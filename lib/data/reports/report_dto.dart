// Apple Guideline 1.2 (Safety / UGC) — DTO и enum'ы для жалоб на UGC.
// Серверные значения см. /TZ_apple_ugc_compliance.md разделы 2.1.1, 2.5.

/// Тип объекта, на который подаётся жалоба.
/// Должно совпадать с CHECK constraint на public.content_reports.target_type.
enum ReportTargetType {
  profile('profile'),
  photo('photo'),
  planChatMessage('plan_chat_message'),
  privateChatMessage('private_chat_message'),
  plan('plan'),
  place('place');

  final String code;
  const ReportTargetType(this.code);
}

/// Категория жалобы.
/// Должно совпадать с CHECK constraint на public.content_reports.category.
/// Критичные (csae/violence/self_harm/illegal) маршрутизируются на abuse@.
enum ReportCategory {
  spam('spam', 'Спам или реклама'),
  harassment('harassment', 'Оскорбления или агрессия'),
  hate('hate', 'Ненависть или дискриминация'),
  sexual('sexual', 'Сексуальный контент или нагота'),
  impersonation('impersonation', 'Выдача за другого человека'),
  other('other', 'Другое'),
  csae('csae', 'Угроза безопасности детей (CSAE)'),
  violence('violence', 'Насилие или прямые угрозы'),
  selfHarm('self_harm', 'Самоповреждение или суицид'),
  illegal('illegal', 'Незаконная деятельность');

  final String code;
  final String labelRu;
  const ReportCategory(this.code, this.labelRu);

  /// Критичные категории — обрабатываются приоритетно (отдельный SLA).
  bool get isCritical =>
      this == csae ||
      this == violence ||
      this == selfHarm ||
      this == illegal;
}

/// Причина отказа RPC `submit_content_report_v1`.
enum ReportSubmitError {
  /// Превышен rate-limit (20 жалоб/час).
  rateLimited,

  /// Попытка пожаловаться на собственный контент.
  selfReport,

  /// Юзер не авторизован.
  unauthorized,

  /// Сетевая ошибка / Supabase недоступен.
  network,

  /// Неизвестная ошибка (логируется, юзеру generic toast).
  unknown,
}

class SubmitReportResult {
  /// `report_id` при успехе, `null` при ошибке.
  final String? reportId;
  final ReportSubmitError? error;

  bool get isSuccess => reportId != null && error == null;

  const SubmitReportResult.success(this.reportId) : error = null;
  const SubmitReportResult.failure(this.error) : reportId = null;
}
