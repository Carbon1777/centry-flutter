import 'participant_preview_dto.dart';

class PlanShellDto {
  final String planId;
  final bool isVisible;
  final String? title;
  final int participantsCount;
  final List<ParticipantPreviewDto> participantsPublicPreview;
  final String signalPhase; // "INTERESTED" | "PLANNED" | "VISITED"

  const PlanShellDto({
    required this.planId,
    required this.isVisible,
    required this.title,
    required this.participantsCount,
    required this.participantsPublicPreview,
    required this.signalPhase,
  });

  factory PlanShellDto.fromJson(Map<String, dynamic> json) {
    final rawPreview = json['participants_public_preview'];
    final preview = <ParticipantPreviewDto>[];
    if (rawPreview is List) {
      for (final item in rawPreview) {
        if (item is Map<String, dynamic>) {
          preview.add(ParticipantPreviewDto.fromJson(item));
        }
      }
    }

    return PlanShellDto(
      planId: json['plan_id'] as String,
      isVisible: json['is_visible'] as bool? ?? false,
      title: json['title'] as String?,
      participantsCount: (json['participants_count'] as num?)?.toInt() ?? 0,
      participantsPublicPreview: preview,
      signalPhase: json['signal_phase'] as String? ?? 'INTERESTED',
    );
  }
}
