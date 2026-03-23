import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/attention_signs/attention_sign_dto.dart';
import '../../data/attention_signs/attention_signs_repository_impl.dart';
import '../../ui/common/center_toast.dart';

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
    final ok =
        await _repo.acceptSign(appUserId: widget.appUserId, submissionId: submissionId);
    if (!mounted) return;
    if (ok) {
      showCenterToast(context, message: 'Знак принят');
      _load();
    }
  }

  Future<void> _handleDecline(String submissionId) async {
    final ok =
        await _repo.declineSign(appUserId: widget.appUserId, submissionId: submissionId);
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
        title: const Text('Коробка'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _BoxContent(
                box: _box!,
                onAccept: _handleAccept,
                onDecline: _handleDecline,
              ),
            ),
    );
  }
}

// =======================
// Контент коробки
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
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // ─── Блок 1: Накопления ─────────────────────────
        _SectionHeader(title: 'Накопления'),
        const SizedBox(height: 8),
        if (box.collection.isEmpty)
          _EmptyHint(text: 'Принятых знаков пока нет')
        else
          _CollectionBlock(items: box.collection),

        const SizedBox(height: 20),

        // ─── Блок 2: На рассмотрении ────────────────────
        _SectionHeader(title: 'На рассмотрении'),
        const SizedBox(height: 8),
        if (box.incoming.isEmpty)
          _EmptyHint(text: 'Знаков внимания на рассмотрении нет')
        else
          ...box.incoming.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _IncomingSignCard(
                  sign: s,
                  onAccept: () => onAccept(s.submissionId),
                  onDecline: () => onDecline(s.submissionId),
                ),
              )),

        const SizedBox(height: 20),

        // ─── Блок 3: Мой знак ───────────────────────────
        _SectionHeader(title: 'Мой знак внимания'),
        const SizedBox(height: 2),
        if (box.mySign == null)
          _EmptyHint(
              text: 'Сегодня свободных знаков не осталось. Ждите следующий знак.')
        else
          _MySignCard(sign: box.mySign!),

        const SizedBox(height: 24),
      ],
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
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

// =======================
// Блок накоплений
// =======================

class _CollectionBlock extends StatelessWidget {
  final List<CollectedAttentionSignDto> items;
  const _CollectionBlock({required this.items});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 16,
          runSpacing: 12,
          children: items
              .map((item) => _CollectionItem(item: item))
              .toList(),
        ),
      ),
    );
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
        _SignSticker(url: item.stickerUrl, size: 56),
        const SizedBox(height: 4),
        Text(
          '×${item.count}',
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
// Входящий знак
// =======================

class _IncomingSignCard extends StatelessWidget {
  final IncomingAttentionSignDto sign;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _IncomingSignCard({
    required this.sign,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            _SignSticker(url: sign.stickerUrl, size: 52),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sign.fromNickname ?? '—',
                    style: text.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    'прислал(а) знак внимания',
                    style: text.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.5)),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: onAccept,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(72, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('Принять'),
                ),
                TextButton(
                  onPressed: onDecline,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(72, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    foregroundColor:
                        colors.onSurface.withValues(alpha: 0.5),
                  ),
                  child: const Text('Отклонить'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// =======================
// Мой знак
// =======================

class _MySignCard extends StatelessWidget {
  final MyDailyAttentionSignDto sign;
  const _MySignCard({required this.sign});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.topCenter,
          heightFactor: 0.72,
          child: CachedNetworkImage(
            imageUrl: sign.stickerUrl,
            width: 224,
            fit: BoxFit.fitWidth,
          ),
        ),
        const SizedBox(height: 4),
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
    );
  }
}

// =======================
// Стикер знака
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
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.3)),
      ),
    );
  }
}
