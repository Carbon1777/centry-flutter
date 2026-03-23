import 'modal_event_dto.dart';

abstract class ModalEventsRepository {
  Future<List<ModalEventDto>> getPendingEvents({required String appUserId});

  Future<void> consumeEvent({
    required String appUserId,
    required String eventId,
  });
}
