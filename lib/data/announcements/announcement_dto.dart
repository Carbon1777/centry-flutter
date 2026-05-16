/// DTO для серверно-управляемых новостных модалок.
///
/// Модель строится вокруг гибкого массива блоков (`blocks`):
/// сервер описывает контент новости как последовательность строительных
/// элементов (текст / картинка / видео / кнопка), клиент рендерит их в порядке.
///
/// Это позволяет менять контент без релиза клиента — только insert в БД.
class AnnouncementDto {
  final String id;
  final List<AnnouncementBlock> blocks;
  final int priority;
  final DateTime startsAt;
  final DateTime? endsAt;

  const AnnouncementDto({
    required this.id,
    required this.blocks,
    required this.priority,
    required this.startsAt,
    this.endsAt,
  });

  factory AnnouncementDto.fromJson(Map<String, dynamic> j) {
    final rawBlocks = j['blocks'];
    final blocksList = <AnnouncementBlock>[];
    if (rawBlocks is List) {
      for (final raw in rawBlocks) {
        if (raw is Map) {
          final block = AnnouncementBlock.tryFromJson(
            Map<String, dynamic>.from(raw),
          );
          if (block != null) blocksList.add(block);
        }
      }
    }
    return AnnouncementDto(
      id: j['id'] as String,
      blocks: blocksList,
      priority: (j['priority'] as num?)?.toInt() ?? 0,
      startsAt: DateTime.parse(j['starts_at'] as String),
      endsAt:
          j['ends_at'] == null ? null : DateTime.parse(j['ends_at'] as String),
    );
  }
}

/// Базовый тип блока. Конкретные подклассы определяют рендер.
///
/// Поле `type` в jsonb — дискриминатор:
/// - `text` → [TextBlock]
/// - `image` → [ImageBlock]
/// - `video` → [VideoBlock]
/// - `button` → [ButtonBlock]
sealed class AnnouncementBlock {
  const AnnouncementBlock();

  static AnnouncementBlock? tryFromJson(Map<String, dynamic> j) {
    final type = (j['type'] ?? '').toString().trim().toLowerCase();
    switch (type) {
      case 'text':
        final body = (j['body'] ?? '').toString();
        if (body.isEmpty) return null;
        return TextBlock(body: body);
      case 'image':
        final url = (j['url'] ?? '').toString().trim();
        if (url.isEmpty) return null;
        final alt = (j['alt'] as String?)?.trim();
        return ImageBlock(url: url, alt: alt == null || alt.isEmpty ? null : alt);
      case 'video':
        final url = (j['url'] ?? '').toString().trim();
        if (url.isEmpty) return null;
        final cover = (j['cover_url'] as String?)?.trim();
        return VideoBlock(
          url: url,
          coverUrl: cover == null || cover.isEmpty ? null : cover,
        );
      case 'button':
        final label = (j['label'] ?? '').toString().trim();
        final url = (j['url'] ?? '').toString().trim();
        if (label.isEmpty || url.isEmpty) return null;
        return ButtonBlock(label: label, url: url);
      default:
        return null;
    }
  }
}

class TextBlock extends AnnouncementBlock {
  final String body;
  const TextBlock({required this.body});
}

class ImageBlock extends AnnouncementBlock {
  final String url;
  final String? alt;
  const ImageBlock({required this.url, this.alt});
}

class VideoBlock extends AnnouncementBlock {
  final String url;
  final String? coverUrl;
  const VideoBlock({required this.url, this.coverUrl});
}

class ButtonBlock extends AnnouncementBlock {
  final String label;
  final String url;
  const ButtonBlock({required this.label, required this.url});
}
