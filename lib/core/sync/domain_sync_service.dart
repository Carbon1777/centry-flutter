import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'domain_event.dart';

class DomainSyncService {
  final SupabaseClient _client;

  final StreamController<DomainEvent> _events =
      StreamController<DomainEvent>.broadcast(sync: true);

  RealtimeChannel? _usersChannel;
  String? _userId;

  DomainSyncService(this._client);

  Stream<DomainEvent> get events => _events.stream;

  Future<void> start({required String userId}) async {
    if (_userId == userId && _usersChannel != null) return;

    await stop();
    _userId = userId;

    _usersChannel = _client.channel('domain-sync-users-$userId');

    _usersChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'users',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: userId,
          ),
          callback: (payload) {
            _handleUserPayload(userId, payload);
          },
        )
        .subscribe();
  }

  Future<void> stop() async {
    if (_usersChannel != null) {
      await _client.removeChannel(_usersChannel!);
      _usersChannel = null;
    }
    _userId = null;
  }

  Future<void> dispose() async {
    await stop();
    await _events.close();
  }

  void _handleUserPayload(String userId, PostgresChangePayload payload) {
    final receivedAt = DateTime.now();
    final raw = _rawPayload(payload);
    final changeType = _mapChangeType(payload.eventType);

    if (payload.eventType == PostgresChangeEvent.delete) {
      _emit(
        UserDeleted(
          userId: userId,
          receivedAt: receivedAt,
          raw: raw,
          oldRow: payload.oldRecord,
        ),
      );
      return;
    }

    if (payload.eventType == PostgresChangeEvent.insert ||
        payload.eventType == PostgresChangeEvent.update) {
      _emit(
        UserUpserted(
          userId: userId,
          changeType: changeType,
          receivedAt: receivedAt,
          raw: raw,
          userRow: payload.newRecord,
        ),
      );
    }
  }

  void _emit(DomainEvent event) {
    if (_events.isClosed) return;
    _events.add(event);
  }

  DomainChangeType _mapChangeType(PostgresChangeEvent eventType) {
    switch (eventType) {
      case PostgresChangeEvent.insert:
        return DomainChangeType.insert;
      case PostgresChangeEvent.update:
        return DomainChangeType.update;
      case PostgresChangeEvent.delete:
        return DomainChangeType.delete;
      case PostgresChangeEvent.all:
        return DomainChangeType.unknown;
    }
  }

  Map<String, dynamic> _rawPayload(PostgresChangePayload payload) {
    return {
      'schema': payload.schema,
      'table': payload.table,
      'eventType': payload.eventType.name,
      'commitTimestamp': payload.commitTimestamp, // ← ИСПРАВЛЕНО
      'newRecord': payload.newRecord,
      'oldRecord': payload.oldRecord,
      'errors': payload.errors,
    };
  }
}
