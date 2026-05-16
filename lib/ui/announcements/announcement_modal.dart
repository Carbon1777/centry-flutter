import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/announcements/announcement_dto.dart';
import '../common/center_toast.dart';

/// Модальное окно одной серверно-управляемой новости.
///
/// Контент полностью описан сервером в `blocks` (массив type='text|image|video|button').
/// Клиент рендерит их в порядке как пришли. Никаких продуктовых решений
/// (полностью презентационный слой).
///
/// При закрытии — диалог сам не делает markRead(); это решает [AnnouncementsController],
/// который выкручивает очередь непрочитанных. Так модалка остаётся пригодной для
/// push-сценария «открыть конкретную новость» (см. push_notifications.dart).
class AnnouncementModal extends StatelessWidget {
  final AnnouncementDto announcement;

  const AnnouncementModal({super.key, required this.announcement});

  /// Показывает модалку и резолвится после её закрытия.
  static Future<void> show(BuildContext context, AnnouncementDto dto) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => AnnouncementModal(announcement: dto),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaSize = MediaQuery.of(context).size;
    final maxHeight = mediaSize.height * 0.9;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Grab handle для bottom sheet
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 10),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                itemCount: announcement.blocks.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) => _BlockWidget(block: announcement.blocks[i]),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Закрыть'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockWidget extends StatelessWidget {
  final AnnouncementBlock block;
  const _BlockWidget({required this.block});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final b = block;
    if (b is TextBlock) {
      return _TextBlockView(body: b.body, theme: theme);
    }
    if (b is ImageBlock) {
      return _ImageBlockView(url: b.url, alt: b.alt);
    }
    if (b is VideoBlock) {
      return _VideoBlockView(url: b.url, coverUrl: b.coverUrl);
    }
    if (b is ButtonBlock) {
      return _ButtonBlockView(label: b.label, url: b.url);
    }
    return const SizedBox.shrink();
  }
}

class _TextBlockView extends StatelessWidget {
  final String body;
  final ThemeData theme;
  const _TextBlockView({required this.body, required this.theme});

  @override
  Widget build(BuildContext context) {
    final html = _markdownLinksToHtml(body);
    return HtmlWidget(
      html,
      textStyle: theme.textTheme.bodyLarge?.copyWith(
        fontSize: 16,
        height: 1.4,
      ),
      onTapUrl: (url) async {
        await _safeLaunchUrl(context, url);
        return true;
      },
    );
  }
}

class _ImageBlockView extends StatelessWidget {
  final String url;
  final String? alt;
  const _ImageBlockView({required this.url, this.alt});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        width: double.infinity,
        placeholder: (_, __) => Container(
          height: 200,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => Container(
          height: 160,
          alignment: Alignment.center,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image_outlined, size: 40),
        ),
      ),
    );
  }
}

class _VideoBlockView extends StatelessWidget {
  final String url;
  final String? coverUrl;
  const _VideoBlockView({required this.url, this.coverUrl});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCover = coverUrl != null && coverUrl!.trim().isNotEmpty;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _safeLaunchUrl(context, url),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (hasCover)
                CachedNetworkImage(
                  imageUrl: coverUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: 200,
                  placeholder: (_, __) => Container(
                    height: 200,
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 200,
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                )
              else
                Container(
                  height: 160,
                  width: double.infinity,
                  alignment: Alignment.center,
                  color: theme.colorScheme.surfaceContainerHighest,
                  child: Text(
                    'Смотреть видео',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              if (hasCover)
                Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(14),
                  child: const Icon(
                    Icons.play_arrow,
                    size: 36,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ButtonBlockView extends StatelessWidget {
  final String label;
  final String url;
  const _ButtonBlockView({required this.label, required this.url});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.tonal(
        onPressed: () => _safeLaunchUrl(context, url),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(label),
        ),
      ),
    );
  }
}

Future<void> _safeLaunchUrl(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    if (context.mounted) {
      showCenterToast(context, message: 'Не удалось открыть ссылку', isError: true);
    }
    return;
  }
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      showCenterToast(context, message: 'Не удалось открыть ссылку', isError: true);
    }
  } catch (e) {
    debugPrint('[Announcements] launchUrl error: $e');
    if (context.mounted) {
      showCenterToast(context, message: 'Не удалось открыть ссылку', isError: true);
    }
  }
}

/// Минимальный конвертер: экранирует HTML спецсимволы, превращает
/// `[label](url)` в `<a href="url">label</a>`, переводы строк — в `<br>`.
/// Никаких **bold** / *italic* — только то, что нужно для базовых анонсов.
String _markdownLinksToHtml(String input) {
  // 1. HTML-экранирование (защита от инъекций, кто бы ни писал блоки в БД)
  var escaped = input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');

  // 2. [label](url) → <a href="url">label</a>
  // Регексп ищет нерекурсивные ссылки. URL ограничен символами без скобок.
  final linkRe = RegExp(r'\[([^\]\n]+)\]\(([^)\s]+)\)');
  escaped = escaped.replaceAllMapped(linkRe, (m) {
    final label = m.group(1) ?? '';
    final url = m.group(2) ?? '';
    return '<a href="$url">$label</a>';
  });

  // 3. Переводы строк → <br>
  escaped = escaped.replaceAll('\n', '<br>');

  return escaped;
}
