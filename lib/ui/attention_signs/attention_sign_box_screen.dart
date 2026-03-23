import 'dart:ui';

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
const double _kCollectionStickerSize = 110;
const double _kBoxHeight = 163;
const double _kIncomingStickerSize = 73;

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ─── Блок 1: Накопления ─────────────
          const _SectionHeader(title: 'Накопления'),
          const SizedBox(height: 8),
          _GlassContainer(
            height: _kBoxHeight,
            child: box.collection.isEmpty
                ? const _EmptyHint(text: 'Принятых знаков пока нет')
                : _CollectionStrip(items: box.collection),
          ),

          const SizedBox(height: 12),

          // ─── Блок 2: На рассмотрении ────────
          const _SectionHeader(title: 'На рассмотрении'),
          const SizedBox(height: 8),
          _GlassContainer(
            height: _kBoxHeight,
            child: box.incoming.isEmpty
                ? const _EmptyHint(text: 'Знаков внимания на рассмотрении нет')
                : _IncomingStrip(
                    items: box.incoming,
                    onAccept: onAccept,
                    onDecline: onDecline,
                  ),
          ),

          const SizedBox(height: 12),

          // ─── Блок 3: Мой знак ─
          const _SectionHeader(title: 'Мой знак внимания'),
          const SizedBox(height: 4),
          if (box.mySign == null)
            const Padding(
              padding: EdgeInsets.only(top: 16),
              child: _NoSignHint(),
            )
          else
            Expanded(
              child: _MySignCard(sign: box.mySign!),
            ),
        ],
      ),
    );
  }
}

// =======================
// Стеклянная подложка (frosted glass)
// =======================

class _GlassContainer extends StatelessWidget {
  final double height;
  final Widget child;

  const _GlassContainer({required this.height, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.12),
                Colors.blueGrey.withValues(alpha: 0.08),
                Colors.white.withValues(alpha: 0.05),
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 0.8,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: child,
        ),
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
    return Center(
      child: Text(
        text,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.45)),
      ),
    );
  }
}

class _NoSignHint extends StatelessWidget {
  const _NoSignHint();

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context)
        .colorScheme
        .onSurface
        .withValues(alpha: 0.45);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'У вас не осталось на сегодня знаков внимания.\nЖдите новый знак.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Знаки внимания выдаются в 00:00 ежедневно.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: muted,
                ),
          ),
        ],
      ),
    );
  }
}

// =======================
// Горизонтальная лента со стрелочками
// =======================

class _ScrollableStrip extends StatefulWidget {
  final int itemCount;
  final double itemWidth;
  final double itemSpacing;
  final IndexedWidgetBuilder itemBuilder;

  const _ScrollableStrip({
    required this.itemCount,
    required this.itemWidth,
    required this.itemSpacing,
    required this.itemBuilder,
  });

  @override
  State<_ScrollableStrip> createState() => _ScrollableStripState();
}

class _ScrollableStripState extends State<_ScrollableStrip> {
  final _controller = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_updateArrows);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateArrows());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _updateArrows() {
    if (!_controller.hasClients) return;
    final pos = _controller.position;
    final left = pos.pixels > 0;
    final right = pos.pixels < pos.maxScrollExtent - 1;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        ListView.separated(
          controller: _controller,
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
          itemCount: widget.itemCount,
          separatorBuilder: (_, __) => SizedBox(width: widget.itemSpacing),
          itemBuilder: widget.itemBuilder,
        ),
        if (_canScrollLeft)
          const Positioned(
            left: 2,
            child: _ScrollArrow(icon: Icons.chevron_left),
          ),
        if (_canScrollRight)
          const Positioned(
            right: 2,
            child: _ScrollArrow(icon: Icons.chevron_right),
          ),
      ],
    );
  }
}

class _ScrollArrow extends StatelessWidget {
  final IconData icon;
  const _ScrollArrow({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(4),
      child: Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: 22),
    );
  }
}

// =======================
// Блок накоплений — горизонтальная лента
// =======================

class _CollectionStrip extends StatelessWidget {
  final List<CollectedAttentionSignDto> items;
  const _CollectionStrip({required this.items});

  @override
  Widget build(BuildContext context) {
    return _ScrollableStrip(
      itemCount: items.length,
      itemWidth: _kCollectionStickerSize,
      itemSpacing: 16,
      itemBuilder: (context, index) => _CollectionItem(item: items[index]),
    );
  }
}

class _CollectionItem extends StatelessWidget {
  final CollectedAttentionSignDto item;
  const _CollectionItem({required this.item});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kCollectionStickerSize,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _SignSticker(url: item.stickerUrl, size: _kCollectionStickerSize),
          const SizedBox(height: 4),
          Text(
            '\u00d7${item.count}',
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

// =======================
// На рассмотрении — горизонтальная лента
// =======================

class _IncomingStrip extends StatelessWidget {
  final List<IncomingAttentionSignDto> items;
  final void Function(String) onAccept;
  final void Function(String) onDecline;

  const _IncomingStrip({
    required this.items,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return _ScrollableStrip(
      itemCount: items.length,
      itemWidth: _kIncomingStickerSize + 20,
      itemSpacing: 16,
      itemBuilder: (context, index) {
        final s = items[index];
        return _IncomingItem(
          sign: s,
          onAccept: () => onAccept(s.submissionId),
          onDecline: () => onDecline(s.submissionId),
        );
      },
    );
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
    return SizedBox(
      width: _kIncomingStickerSize + 20,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'От «$nick»',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          _SignSticker(url: sign.stickerUrl, size: _kIncomingStickerSize),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onAccept,
                child: const Icon(Icons.check_circle,
                    color: Colors.green, size: 32),
              ),
              const SizedBox(width: 24),
              GestureDetector(
                onTap: onDecline,
                child:
                    const Icon(Icons.cancel, color: Colors.red, size: 32),
              ),
            ],
          ),
        ],
      ),
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
