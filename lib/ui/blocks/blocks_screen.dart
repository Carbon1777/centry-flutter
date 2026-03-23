import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/blocks/block_dto.dart';
import '../../data/blocks/blocks_repository_impl.dart';
import '../../features/profile/user_card_sheet.dart';

class BlocksScreen extends StatefulWidget {
  final String appUserId;

  const BlocksScreen({super.key, required this.appUserId});

  @override
  State<BlocksScreen> createState() => _BlocksScreenState();
}

class _BlocksScreenState extends State<BlocksScreen> {
  late final _repo = BlocksRepositoryImpl(Supabase.instance.client);

  List<BlockedUserDto> _blocks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final blocks = await _repo.getMyBlocks(appUserId: widget.appUserId);
      if (!mounted) return;
      setState(() {
        _blocks = blocks;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Блокировка'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _blocks.isEmpty
              ? Center(
                  child: Text(
                    'Заблокированных пользователей нет',
                    style: text.bodyMedium?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.5)),
                    textAlign: TextAlign.center,
                  ),
                )
              : ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  itemCount: _blocks.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _BlockCard(block: _blocks[i]),
                ),
    );
  }
}

class _BlockCard extends StatelessWidget {
  final BlockedUserDto block;

  const _BlockCard({required this.block});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final d = block.blockedAt.toLocal();
    final dateStr =
        '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    final profile = UserMiniProfile(
      userId: block.blockedUserId,
      nickname: block.nickname,
      avatarUrl: block.avatarUrl,
    );

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            UserAvatarWidget(profile: profile, size: 44),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    block.nickname ?? '—',
                    style: text.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Заблокирован $dateStr',
                    style: text.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: 0.45)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
