import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/announcements/announcement_dto.dart';
import '../common/center_toast.dart';

/// Модальное окно одной серверно-управляемой новости.
///
/// Центральная брендовая модалка в стиле остальных Centry-диалогов
/// (см. `lib/ui/common/modal_events_checker.dart`):
/// - `showDialog` с `barrierDismissible: false` и `useRootNavigator: true`
/// - `AlertDialog` с insetPadding/titlePadding/contentPadding/actionsPadding
/// - Размер адаптивный: mainAxisSize.min + maxWidth 360 + maxHeight 80% экрана.
///   Если контента мало — диалог компактный. Много — растёт до максимума,
///   дальше внутренний скрол.
///
/// Контент полностью описан сервером в `blocks` (массив type='text|image|video|button').
/// При закрытии — диалог сам не делает markRead(); это решает [AnnouncementsController].
class AnnouncementModal extends StatelessWidget {
  final AnnouncementDto announcement;

  const AnnouncementModal({super.key, required this.announcement});

  /// Показывает модалку и резолвится после её закрытия.
  static Future<void> show(BuildContext context, AnnouncementDto dto) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (ctx) => AnnouncementModal(announcement: dto),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final media = MediaQuery.of(context);
    // Контент адаптивный: минимум 280, максимум 360 по ширине.
    // По высоте — растёт по контенту до 80% экрана, дальше внутренний скрол.
    final maxContentHeight = media.size.height * 0.8;

    return AlertDialog(
      // Тонкая обводка всего окна — канон place_details_dialog.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: colors.primary.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
      titlePadding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
      contentPadding: const EdgeInsets.fromLTRB(22, 0, 22, 14),
      actionsPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      title: Text(
        'Новость от Centry',
        textAlign: TextAlign.center,
        style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: 280,
          maxWidth: 360,
          maxHeight: maxContentHeight,
        ),
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (int i = 0; i < announcement.blocks.length; i++) ...[
                if (i > 0) const SizedBox(height: 14),
                _BlockWidget(block: announcement.blocks[i]),
              ],
            ],
          ),
        ),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
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
    // Тонкая рамка как в plan_details / place_details — единый стиль Centry.
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: HtmlWidget(
        html,
        textStyle: theme.textTheme.bodyLarge?.copyWith(
          fontSize: 16,
          height: 1.4,
        ),
        onTapUrl: (url) async {
          await _safeLaunchUrl(context, url);
          return true;
        },
      ),
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
          height: 160,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        errorWidget: (_, __, ___) => Container(
          height: 120,
          alignment: Alignment.center,
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: const Icon(Icons.broken_image_outlined, size: 36),
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
                  height: 160,
                  placeholder: (_, __) => Container(
                    height: 160,
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (_, __, ___) => Container(
                    height: 160,
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                )
              else
                Container(
                  height: 120,
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
                  padding: const EdgeInsets.all(12),
                  child: const Icon(
                    Icons.play_arrow,
                    size: 32,
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
