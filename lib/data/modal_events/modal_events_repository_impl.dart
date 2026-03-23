import 'package:supabase_flutter/supabase_flutter.dart';

import 'modal_event_dto.dart';
import 'modal_events_repository.dart';

class ModalEventsRepositoryImpl implements ModalEventsRepository {
  final SupabaseClient _client;

  ModalEventsRepositoryImpl(this._client);

  @override
  Future<List<ModalEventDto>> getPendingEvents(
      {required String appUserId}) async {
    final response = await _client.rpc(
      'get_pending_modal_events_v1',
      params: {'p_user_id': appUserId},
    );
    if (response is List) {
      return response
          .map((e) => ModalEventDto.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    return [];
  }

  @override
  Future<void> consumeEvent({
    required String appUserId,
    required String eventId,
  }) async {
    await _client.rpc(
      'consume_modal_event_v1',
      params: {'p_user_id': appUserId, 'p_event_id': eventId},
    );
  }
}
