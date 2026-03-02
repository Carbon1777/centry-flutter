import 'dart:async';

import 'package:flutter/material.dart';

import '../../data/local/user_snapshot_storage.dart';
import '../../data/friends/friend_dto.dart';
import '../../data/friends/friends_repository.dart';

class FriendsScreen extends StatefulWidget {
  final String appUserId; // доменный app_users.id
  final FriendsRepository repository;
  final UserSnapshotStorage userSnapshotStorage;

  const FriendsScreen({
    super.key,
    required this.appUserId,
    required this.repository,
    required this.userSnapshotStorage,
  });

  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  bool _loading = true;
  List<FriendDto> _friends = const <FriendDto>[];

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final deviceSecret = await widget.userSnapshotStorage.getOrCreateDeviceSecret();
      final friends = await widget.repository.listMyFriends(
        appUserId: widget.appUserId,
        deviceSecret: deviceSecret,
      );
      if (!mounted) return;
      setState(() {
        _friends = friends;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await _showError(context, e);
    }
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
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _friends.isEmpty
              ? _buildEmptyState(context)
              : _buildList(context),
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
              'Добавляй друзей через поиск по Public ID или из списков в продукте.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        itemCount: _friends.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final friend = _friends[index];
          return _FriendCard(
            friend: friend,
            onOpenProfile: () {
              unawaited(_showProfileStub(context));
            },
            onEditNote: () {
              unawaited(_editNote(context, friend));
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
      ),
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

  Future<void> _showProfileStub(BuildContext context) async {
    await _showInDevelopmentModal(
      context,
      title: 'Профиль',
      message: 'В разработке',
    );
  }

  Future<void> _showError(BuildContext context, Object error) async {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Ошибка'),
          content: Text(error.toString()),
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

  Future<bool> _confirmRemove(BuildContext context, String displayName) async {
    final res = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Удалить из друзей?'),
          content: Text('Удалить «$displayName» из друзей?'),
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

  Future<void> _editNote(BuildContext context, FriendDto friend) async {
    final controller = TextEditingController(text: friend.note);

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

    try {
      final deviceSecret = await widget.userSnapshotStorage.getOrCreateDeviceSecret();
      await widget.repository.upsertFriendNote(
        appUserId: widget.appUserId,
        deviceSecret: deviceSecret,
        friendUserId: friend.friendUserId,
        note: saved.trim(),
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      await _showError(context, e);
    }
  }

  Future<void> _removeFriend(BuildContext context, FriendDto friend) async {
    final confirmed = await _confirmRemove(context, friend.displayName);
    if (!confirmed) return;

    try {
      final deviceSecret = await widget.userSnapshotStorage.getOrCreateDeviceSecret();
      await widget.repository.removeFriend(
        appUserId: widget.appUserId,
        deviceSecret: deviceSecret,
        friendUserId: friend.friendUserId,
      );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      await _showError(context, e);
    }
  }
}

class _FriendCard extends StatelessWidget {
  final FriendDto friend;

  final VoidCallback onOpenProfile;
  final VoidCallback onEditNote;
  final VoidCallback onAddToPlan;
  final VoidCallback onRemoveFriend;

  const _FriendCard({
    required this.friend,
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
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 48,
                      height: 48,
                      alignment: Alignment.center,
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.08),
                      child: Text(
                        _initials(friend.displayName),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Ник: ${friend.displayName}', style: titleStyle),
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
                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
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
                      friend.note.isEmpty ? 'Мой комментарий…' : friend.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: friend.note.isEmpty
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
                          color: const Color(0xFFE25B5B),
                        ),
                  ),
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: onAddToPlan,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

  static String _initials(String name) {
    final t = name.trim();
    if (t.isEmpty) return 'U';
    return t.characters.take(1).toString().toUpperCase();
  }
}
