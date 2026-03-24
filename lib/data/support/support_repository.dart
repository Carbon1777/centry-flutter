import 'support_dto.dart';

abstract class SupportRepository {
  Future<CreateSessionResultDto> createSession({required String direction});

  Future<SupportSessionDetailDto> getSession({required String sessionId});

  Future<SendQuestionResultDto> sendQuestion({
    required String sessionId,
    required String messageText,
  });

  Future<SubmitFormResultDto> submitSuggestion({
    required String sessionId,
    required String text,
  });

  Future<SubmitFormResultDto> submitComplaint({
    required String sessionId,
    required String text,
  });
}
