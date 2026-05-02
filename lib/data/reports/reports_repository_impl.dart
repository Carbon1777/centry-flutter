import 'package:supabase_flutter/supabase_flutter.dart';

import 'report_dto.dart';
import 'reports_repository.dart';

class ReportsRepositoryImpl implements ReportsRepository {
  final SupabaseClient _client;

  ReportsRepositoryImpl(this._client);

  @override
  Future<SubmitReportResult> submit({
    required ReportTargetType targetType,
    required String targetId,
    required ReportCategory category,
    String? comment,
  }) async {
    try {
      final response = await _client.rpc(
        'submit_content_report_v1',
        params: {
          'p_target_type': targetType.code,
          'p_target_id': targetId,
          'p_category': category.code,
          if (comment != null && comment.trim().isNotEmpty)
            'p_comment': comment.trim(),
        },
      );

      // RPC возвращает uuid жалобы (или существующей при дедупликации)
      if (response is String && response.isNotEmpty) {
        return SubmitReportResult.success(response);
      }
      return const SubmitReportResult.failure(ReportSubmitError.unknown);
    } on PostgrestException catch (e) {
      return SubmitReportResult.failure(_mapError(e));
    } catch (_) {
      // Сетевые / неизвестные клиентские ошибки.
      return const SubmitReportResult.failure(ReportSubmitError.network);
    }
  }

  /// Маппинг серверных кодов ошибок на enum.
  /// См. submit_content_report_v1 в /TZ_apple_ugc_compliance.md.
  ReportSubmitError _mapError(PostgrestException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('rate_limited')) return ReportSubmitError.rateLimited;
    if (msg.contains('self_report')) return ReportSubmitError.selfReport;
    if (msg.contains('unauthorized') || e.code == '28000') {
      return ReportSubmitError.unauthorized;
    }
    return ReportSubmitError.unknown;
  }
}
