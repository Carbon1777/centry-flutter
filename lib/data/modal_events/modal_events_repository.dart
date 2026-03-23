import 'modal_event_dto.dart';

abstract class ModalEventsRepository {
  Future<List<ModalEventDto>> getPendingEvents({required String appUserId});

  /// Returns [true] if the event should be silently skipped (e.g. expired invite).
  Future<bool> consumeEvent({
    required String appUserId,
    required String eventId,
  });
}
