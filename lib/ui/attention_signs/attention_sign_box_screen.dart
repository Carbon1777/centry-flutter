import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/attention_signs/attention_sign_dto.dart';
import '../../data/attention_signs/attention_signs_repository_impl.dart';
import '../../ui/common/center_toast.dart';
import 'attention_signs_bus.dart';

class AttentionSignBoxScreen extends StatefulWidget {
  final String appUserId;

  const AttentionSignBoxScreen({super.key, required this.appUserId});

  @override
  State<AttentionSignBoxScreen> createState() => _AttentionSignBoxScreenState();
}

class _AttentionSignBoxScreenState extends State<AttentionSignBoxScreen> {
  late final _repo = AttentionSignsRepositoryImpl(Supabase.instance.client);

  AttentionSignBoxDto? _box;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Сбрасываем бейдж в следующем фрейме, чтобы не менять notifier во время build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AttentionSignsBus.instance.setHasIncoming(false);
    });
    _load();
  }

  Future<void> _load() async {
    try {
      final box = await _repo.getMyBox(appUserId: widget.appUserId);
      if (!mounted) return;
      setState(() {
        _box = box;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _handleAccept(String submissionId) async {
    final ok = await _repo.acceptSign(
        appUserId: widget.appUserId, submissionId: submissionId);
    if (!mounted) return;
    if (ok) {
      showCenterToast(context, message: 'Знак принят');
      _load();
    }
  }

  Future<void> _handleDecline(String submissionId) async {
    final ok = await _repo.declineSign(
        appUserId: widget.appUserId, submissionId: submissionId);
    if (!mounted) return;
    if (ok) {
      showCenterToast(context, message: 'Знак отклонён');
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подарки'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _BoxContent(
              box: _box!,
              onAccept: _handleAccept,
              onDecline: _handleDecline,
            ),
    );
  }
}

// ─── Layout constants ────────────────────────────────────────────────────────
const int _kColumnsPerRow = 3;
const double _kCellSpacing = 12;
const double _kGridStickerSize = 86;

// =======================
// Контент — Column без общего скролла
// =======================

class _BoxContent extends StatelessWidget {
  final AttentionSignBoxDto box;
  final void Function(String) onAccept;
  final void Function(String) onDecline;

  const _BoxContent({
    required this.box,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Блок 1: Накопления ─────────────
          const _SectionHeader(title: 'Накопления'),
          const SizedBox(height: 8),
          Expanded(
            flex: 3,
            child: box.collection.isEmpty
                ? const _EmptyHint(text: 'Принятых знаков пока нет')
                : _CollectionGrid(items: box.collection),
          ),

          const SizedBox(height: 8),

          // ─── Блок 2: На рассмотрении ────────
          const _SectionHeader(title: 'На рассмотрении'),
          const SizedBox(height: 8),
          Expanded(
            flex: 3,
            child: box.incoming.isEmpty
                ? const _EmptyHint(text: 'Знаков внимания на рассмотрении нет')
                : _IncomingGrid(
                    items: box.incoming,
                    onAccept: onAccept,
                    onDecline: onDecline,
                  ),
          ),

          const SizedBox(height: 8),

          // ─── Блок 3: Мой знак ─
          const _SectionHeader(title: 'Мой знак внимания'),
          const SizedBox(height: 4),
          Expanded(
            flex: 4,
            child: box.mySign == null
                ? const _EmptyHint(
                    text: 'Сегодня свободных знаков не осталось. Ждите следующий знак.')
                : _MySignCard(sign: box.mySign!),
          ),
        ],
      ),
    );
  }
}

// =======================
// Заголовок секции
// =======================

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context)
          .textTheme
          .titleSmall
          ?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context)
              .colorScheme
              .onSurface
              .withValues(alpha: 0.45)),
    );
  }
}

// =======================
// Блок накоплений — сетка 3 в ряд, внутренний скролл
// =======================

class _CollectionGrid extends StatelessWidget {
  final List<CollectedAttentionSignDto> items;
  const _CollectionGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cellW = (constraints.maxWidth - _kCellSpacing * (_kColumnsPerRow - 1)) / _kColumnsPerRow;
      return SingleChildScrollView(
        child: Wrap(
          spacing: _kCellSpacing,
          runSpacing: _kCellSpacing,
          alignment: WrapAlignment.center,
          children: items
              .map((item) => SizedBox(
                    width: cellW,
                    child: _CollectionItem(item: item),
                  ))
              .toList(),
        ),
      );
    });
  }
}

class _CollectionItem extends StatelessWidget {
  final CollectedAttentionSignDto item;
  const _CollectionItem({required this.item});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _SignSticker(url: item.stickerUrl, size: _kGridStickerSize),
        const SizedBox(height: 2),
        Text(
          '\u00d7${item.count}',
          style: Theme.of(context)
              .textTheme
              .labelMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

// =======================
// На рассмотрении — сетка 3 в ряд, внутренний скролл
// =======================

class _IncomingGrid extends StatelessWidget {
  final List<IncomingAttentionSignDto> items;
  final void Function(String) onAccept;
  final void Function(String) onDecline;

  const _IncomingGrid({
    required this.items,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final cellW = (constraints.maxWidth - _kCellSpacing * (_kColumnsPerRow - 1)) / _kColumnsPerRow;
      return SingleChildScrollView(
        child: Wrap(
          spacing: _kCellSpacing,
          runSpacing: _kCellSpacing,
          alignment: WrapAlignment.center,
          children: items
              .map((s) => SizedBox(
                    width: cellW,
                    child: _IncomingItem(
                      sign: s,
                      onAccept: () => onAccept(s.submissionId),
                      onDecline: () => onDecline(s.submissionId),
                    ),
                  ))
              .toList(),
        ),
      );
    });
  }
}

class _IncomingItem extends StatelessWidget {
  final IncomingAttentionSignDto sign;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _IncomingItem({
    required this.sign,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final nick = sign.fromNickname ?? '—';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          'От «$nick»',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 2),
        _SignSticker(url: sign.stickerUrl, size: _kGridStickerSize),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: onAccept,
              child: const Icon(Icons.check_circle, color: Colors.green, size: 32),
            ),
            const SizedBox(width: 24),
            GestureDetector(
              onTap: onDecline,
              child: const Icon(Icons.cancel, color: Colors.red, size: 32),
            ),
          ],
        ),
      ],
    );
  }
}

// =======================
// Мой знак — центрируется в оставшемся пространстве
// =======================

class _MySignCard extends StatelessWidget {
  final MyDailyAttentionSignDto sign;
  const _MySignCard({required this.sign});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: CachedNetworkImage(
              imageUrl: sign.stickerUrl,
              width: 200,
              fit: BoxFit.fitWidth,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Знак внимания',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Пропадет в 00:00',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.45),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// =======================
// Стикер знака (без фона, без рамки)
// =======================

class _SignSticker extends StatelessWidget {
  final String url;
  final double size;

  const _SignSticker({required this.url, required this.size});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorWidget: (_, __, ___) => SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.star_outline,
            size: size * 0.6,
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3)),
      ),
    );
  }
}
