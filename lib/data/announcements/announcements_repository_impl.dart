import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'announcement_dto.dart';
import 'announcements_repository.dart';

class AnnouncementsRepositoryImpl implements AnnouncementsRepository {
  final SupabaseClient _client;

  AnnouncementsRepositoryImpl(this._client);

  List<dynamic> _parseArrayResponse(dynamic response) {
    if (response is List) return response;
    if (response is String) {
      try {
        final decoded = jsonDecode(response);
        if (decoded is List) return decoded;
      } catch (_) {
        // non-critical
      }
    }
    return const [];
  }

  Map<String, dynamic>? _parseObjectResponse(dynamic response) {
    if (response == null) return null;
    if (response is Map) return Map<String, dynamic>.from(response);
    if (response is String) {
      try {
        final decoded = jsonDecode(response);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        // non-critical
      }
    }
    return null;
  }

  @override
  Future<List<AnnouncementDto>> fetchUnread() async {
    final response = await _client
        .rpc('get_unread_announcements_v1')
        .timeout(const Duration(seconds: 15));
    debugPrint('[Announcements] fetchUnread response type=${response.runtimeType}, '
        'value=${response is List ? '(List len=${response.length})' : '$response'}');
    final list = _parseArrayResponse(response);
    if (list.isEmpty) return [];
    final result = <AnnouncementDto>[];
    for (final raw in list) {
      try {
        if (raw is Map) {
          result.add(AnnouncementDto.fromJson(Map<String, dynamic>.from(raw)));
        }
      } catch (e) {
        debugPrint('[Announcements] fetchUnread skip bad item: $e');
      }
    }
    return result;
  }

  @override
  Future<void> markRead(String announcementId) async {
    await _client.rpc(
      'mark_announcement_read_v1',
      params: {'p_announcement_id': announcementId},
    ).timeout(const Duration(seconds: 15));
  }

  @override
  Future<AnnouncementDto?> fetchById(String announcementId) async {
    final response = await _client.rpc(
      'get_announcement_by_id_v1',
      params: {'p_id': announcementId},
    ).timeout(const Duration(seconds: 15));
    debugPrint('[Announcements] fetchById($announcementId) response=$response');
    final obj = _parseObjectResponse(response);
    if (obj == null) return null;
    try {
      return AnnouncementDto.fromJson(obj);
    } catch (e) {
      debugPrint('[Announcements] fetchById parse error: $e');
      return null;
    }
  }
}
