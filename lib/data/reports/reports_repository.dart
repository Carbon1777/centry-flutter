import 'report_dto.dart';

abstract class ReportsRepository {
  /// Подать жалобу на UGC.
  ///
  /// Возвращает [SubmitReportResult] с `reportId` или `error`.
  /// Никогда не бросает исключений — все известные ошибки маппятся в [ReportSubmitError].
  Future<SubmitReportResult> submit({
    required ReportTargetType targetType,
    required String targetId,
    required ReportCategory category,
    String? comment,
  });
}
