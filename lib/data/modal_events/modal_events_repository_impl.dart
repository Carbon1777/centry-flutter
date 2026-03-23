import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'modal_event_dto.dart';
import 'modal_events_repository.dart';

class ModalEventsRepositoryImpl implements ModalEventsRepository {
  final SupabaseClient _client;

  ModalEventsRepositoryImpl(this._client);

  /// Parses the RPC response which is RETURNS jsonb (a JSON array).
  /// postgrest-dart may return List, String (raw JSON), or other shapes
  /// depending on version/configuration — handle all gracefully.
  List<dynamic> _parseArrayResponse(dynamic response) {
    if (response is List) return response;
    if (response is String) {
      final decoded = jsonDecode(response);
      if (decoded is List) return decoded;
    }
    return [];
  }

  @override
  Future<List<ModalEventDto>> getPendingEvents(
      {required String appUserId}) async {
    final response = await _client.rpc(
      'get_pending_modal_events_v1',
      params: {'p_user_id': appUserId},
    );
    debugPrint('[ModalEvents] getPendingEvents response type=${response.runtimeType}, '
        'value=${response is List ? '(List len=${response.length})' : '$response'}');
    final list = _parseArrayResponse(response);
    if (list.isEmpty) return [];
    return list
        .map((e) => ModalEventDto.fromJson(
              e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e as Map),
            ))
        .toList();
  }

  @override
  Future<bool> consumeEvent({
    required String appUserId,
    required String eventId,
  }) async {
    final response = await _client.rpc(
      'consume_modal_event_v1',
      params: {'p_user_id': appUserId, 'p_event_id': eventId},
    );
    debugPrint('[ModalEvents] consumeEvent response type=${response.runtimeType}, value=$response');
    // Server returns jsonb {consumed: true, skip: true/false}.
    // skip=true means the event should not be shown (e.g. invite expired).
    if (response is Map) {
      return response['skip'] == true;
    }
    // Handle string response
    if (response is String) {
      try {
        final decoded = jsonDecode(response);
        if (decoded is Map) return decoded['skip'] == true;
      } catch (_) {}
    }
    return false;
  }
}
