// ---------------------------------------------------------------------------
// DTO для сессии поддержки
// ---------------------------------------------------------------------------

class SupportSessionDto {
  final String id;
  final String direction;
  final String status;
  final DateTime createdAt;
  final DateTime? lastMessageAt;

  const SupportSessionDto({
    required this.id,
    required this.direction,
    required this.status,
    required this.createdAt,
    this.lastMessageAt,
  });

  factory SupportSessionDto.fromJson(Map<String, dynamic> j) =>
      SupportSessionDto(
        id: j['id'] as String? ?? j['session_id'] as String,
        direction: j['direction'] as String,
        status: j['status'] as String,
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'] as String)
            : DateTime.now(),
        lastMessageAt: j['last_message_at'] != null
            ? DateTime.parse(j['last_message_at'] as String)
            : null,
      );
}

// ---------------------------------------------------------------------------
// DTO для создания сессии (ответ сервера)
// ---------------------------------------------------------------------------

class CreateSessionResultDto {
  final String sessionId;
  final String direction;
  final String status;

  const CreateSessionResultDto({
    required this.sessionId,
    required this.direction,
    required this.status,
  });

  factory CreateSessionResultDto.fromJson(Map<String, dynamic> j) =>
      CreateSessionResultDto(
        sessionId: j['session_id'] as String,
        direction: j['direction'] as String,
        status: j['status'] as String,
      );
}

// ---------------------------------------------------------------------------
// DTO для сообщения в AI-чате
// ---------------------------------------------------------------------------

class SupportQuestionMessageDto {
  final String id;
  final String senderType; // USER | ASSISTANT | SYSTEM
  final String messageText;
  final String? answerStatus; // OK | NO_ANSWER | FALLBACK | ERROR
  final DateTime createdAt;

  const SupportQuestionMessageDto({
    required this.id,
    required this.senderType,
    required this.messageText,
    this.answerStatus,
    required this.createdAt,
  });

  factory SupportQuestionMessageDto.fromJson(Map<String, dynamic> j) =>
      SupportQuestionMessageDto(
        id: j['id'] as String,
        senderType: j['sender_type'] as String,
        messageText: j['message_text'] as String,
        answerStatus: j['answer_status'] as String?,
        createdAt: j['created_at'] != null
            ? DateTime.parse(j['created_at'] as String)
            : DateTime.now(),
      );
}

// ---------------------------------------------------------------------------
// DTO для ответа send_question (Edge Function)
// ---------------------------------------------------------------------------

class SendQuestionResultDto {
  final SupportQuestionMessageDto userMessage;
  final SupportQuestionMessageDto assistantMessage;
  final String sessionStatus;

  const SendQuestionResultDto({
    required this.userMessage,
    required this.assistantMessage,
    required this.sessionStatus,
  });

  factory SendQuestionResultDto.fromJson(Map<String, dynamic> j) =>
      SendQuestionResultDto(
        userMessage: SupportQuestionMessageDto.fromJson(
            j['user_message'] as Map<String, dynamic>),
        assistantMessage: SupportQuestionMessageDto.fromJson(
            j['assistant_message'] as Map<String, dynamic>),
        sessionStatus: j['session_status'] as String,
      );
}

// ---------------------------------------------------------------------------
// DTO для ответа submit suggestion/complaint
// ---------------------------------------------------------------------------

class SubmitFormResultDto {
  final String status;
  final String systemMessage;

  const SubmitFormResultDto({
    required this.status,
    required this.systemMessage,
  });

  factory SubmitFormResultDto.fromJson(Map<String, dynamic> j) =>
      SubmitFormResultDto(
        status: j['status'] as String,
        systemMessage: j['system_message'] as String,
      );
}

// ---------------------------------------------------------------------------
// DTO для полной сессии (get_support_session_v1)
// ---------------------------------------------------------------------------

class SupportSessionDetailDto {
  final String id;
  final String direction;
  final String status;
  final DateTime createdAt;
  final DateTime? lastMessageAt;
  final List<SupportQuestionMessageDto> messages;

  const SupportSessionDetailDto({
    required this.id,
    required this.direction,
    required this.status,
    required this.createdAt,
    this.lastMessageAt,
    this.messages = const [],
  });

  factory SupportSessionDetailDto.fromJson(Map<String, dynamic> j) {
    final rawMessages = j['messages'] as List<dynamic>?;
    return SupportSessionDetailDto(
      id: j['id'] as String,
      direction: j['direction'] as String,
      status: j['status'] as String,
      createdAt: j['created_at'] != null
          ? DateTime.parse(j['created_at'] as String)
          : DateTime.now(),
      lastMessageAt: j['last_message_at'] != null
          ? DateTime.parse(j['last_message_at'] as String)
          : null,
      messages: rawMessages
              ?.map((m) => SupportQuestionMessageDto.fromJson(
                  m as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}
