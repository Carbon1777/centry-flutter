import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  // Server-first note:
  // This screen is UI-only v0. The source of truth for friends + notes must be on the server.
  // Later we will replace the local list with an RPC-backed repository and persist notes via RPC.
  late final List<_FriendCardVm> _friends = _initialFriends();

  // Local (temporary) note cache for UX iteration. Will be replaced by server storage.
  final Map<String, String> _notesByUserId = <String, String>{};

  List<_FriendCardVm> _initialFriends() {
    // In release, show empty list until server contract is ready.
    if (!kDebugMode) return <_FriendCardVm>[];

    // Dev/demo data so the UI is visible during iteration.
    return const <_FriendCardVm>[
      _FriendCardVm(
        userId: 'demo-1',
        nickname: 'rewader',
        publicId: 'A1B2C3',
      ),
      _FriendCardVm(
        userId: 'demo-2',
        nickname: 't1',
        publicId: 'X7Y8Z9',
      ),
      _FriendCardVm(
        userId: 'demo-3',
        nickname: 'alex',
        publicId: 'P0Q1R2',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Друзья'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: OutlinedButton.icon(
              onPressed: () {
                unawaited(
                  _showInDevelopmentModal(
                    context,
                    title: 'Добавить в друзья',
                    message: 'В разработке',
                  ),
                );
              },
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const StadiumBorder(),
              ),
              icon: const Icon(Icons.person_add_alt_1, size: 18),
              label: const Text('Добавить в друзья'),
            ),
          ),
        ],
      ),
      body: _friends.isEmpty ? _buildEmptyState(context) : _buildList(context),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.people_outline, size: 44),
            const SizedBox(height: 14),
            Text(
              'Пока нет друзей',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Добавляй друзей из участников плана —\nв деталях плана через иконку “добавить в друзья”.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      itemCount: _friends.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final friend = _friends[index];
        final note = _notesByUserId[friend.userId] ?? '';
        return _FriendCard(
          friend: friend,
          note: note,
          onOpenProfile: () {
            unawaited(_showProfileStub(context, friend));
          },
          onEditNote: () {
            unawaited(_editNote(context, friend, initial: note));
          },
          onAddToPlan: () {
            unawaited(
              _showInDevelopmentModal(
                context,
                title: 'Добавить в план',
                message: 'В разработке',
              ),
            );
          },
          onRemoveFriend: () {
            unawaited(_removeFriend(context, friend));
          },
        );
      },
    );
  }

  Future<void> _showInDevelopmentModal(
    BuildContext context, {
    required String title,
    required String message,
  }) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Закрыть'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmRemove(BuildContext context, String nickname) async {
    final res = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Удалить из друзей?'),
          content: Text('Удалить «$nickname» из друзей?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Удалить'),
            ),
          ],
        );
      },
    );
    return res ?? false;
  }

  Future<void> _showProfileStub(
      BuildContext context, _FriendCardVm friend) async {
    await _showInDevelopmentModal(
      context,
      title: 'Профиль',
      message: 'В разработке',
    );
  }

  Future<void> _editNote(
    BuildContext context,
    _FriendCardVm friend, {
    required String initial,
  }) async {
    final controller = TextEditingController(text: initial);

    final saved = await showDialog<String?>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Мой комментарий'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 280, maxWidth: 420),
            child: TextField(
              controller: controller,
              maxLength: 80,
              maxLines: 2,
              minLines: 1,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'Например: “коллега”, “сосед”, “партнёр”',
                border: OutlineInputBorder(),
                counterText: '',
              ),
              buildCounter: (
                BuildContext context, {
                required int currentLength,
                required bool isFocused,
                required int? maxLength,
              }) {
                final max = maxLength ?? 0;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '$currentLength/$max',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(controller.text),
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (!mounted) return;
    if (saved == null) return;

    final trimmed = saved.trim();
    setState(() {
      if (trimmed.isEmpty) {
        _notesByUserId.remove(friend.userId);
      } else {
        _notesByUserId[friend.userId] = trimmed;
      }
    });
  }

  Future<void> _removeFriend(BuildContext context, _FriendCardVm friend) async {
    final confirmed = await _confirmRemove(context, friend.nickname);
    if (!confirmed) return;
    if (!mounted) return;

    setState(() {
      _friends.removeWhere((f) => f.userId == friend.userId);
      _notesByUserId.remove(friend.userId);
    });
  }
}

class _FriendCardVm {
  final String userId;
  final String nickname;
  final String publicId;

  const _FriendCardVm({
    required this.userId,
    required this.nickname,
    required this.publicId,
  });
}

class _FriendCard extends StatelessWidget {
  final _FriendCardVm friend;
  final String note;

  final VoidCallback onOpenProfile;
  final VoidCallback onEditNote;
  final VoidCallback onAddToPlan;
  final VoidCallback onRemoveFriend;

  const _FriendCard({
    required this.friend,
    required this.note,
    required this.onOpenProfile,
    required this.onEditNote,
    required this.onAddToPlan,
    required this.onRemoveFriend,
  });

  @override
  Widget build(BuildContext context) {
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w700,
        );

    final hintStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.8),
        );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onOpenProfile,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.08),
                    child: Text(
                      _initials(friend.nickname),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ник: ${friend.nickname}', style: titleStyle),
                        const SizedBox(height: 2),
                        Text(
                          'Public ID: ${friend.publicId}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.color
                        ?.withOpacity(0.7),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).dividerColor.withOpacity(0.35),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
                    child: Text(
                      note.isEmpty ? 'Мой комментарий…' : note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: note.isEmpty
                          ? hintStyle
                          : Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onEditNote,
                  tooltip: 'Редактировать',
                  icon: const Icon(Icons.edit, size: 20),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              InkWell(
                onTap: onRemoveFriend,
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Text(
                    'Удалить',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: onAddToPlan,
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Добавить в план'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _initials(String nickname) {
    final t = nickname.trim();
    if (t.isEmpty) return 'U';
    return t.characters.take(1).toString().toUpperCase();
  }
}
