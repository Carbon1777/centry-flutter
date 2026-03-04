import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/friends/friend_dto.dart';
import '../../../data/friends/friends_repository.dart';
import '../../../data/friends/friends_repository_impl.dart';
import '../common/center_toast.dart';

/// Bottom-sheet content: выбор друга для приглашения в план.
///
/// Показывается через showModalBottomSheet (свайп вниз для закрытия).
///
/// Сейчас UX:
/// - грузим список друзей
/// - при тапе: optimistic "Отправлено приглашение" + disabled
/// - зовём существующий server-first механизм инвайта в план через callback
class PlanFriendsModal extends StatefulWidget {
  /// текущий app_user_id (public.app_users.id)
  final String appUserId;

  /// server-first entrypoint: инвайт в текущий план по friend's public_id
  /// (это существующий механизм инвайта в план; мы просто новая точка входа)
  final Future<void> Function(String friendPublicId) onInviteFriendByPublicId;

  const PlanFriendsModal({
    super.key,
    required this.appUserId,
    required this.onInviteFriendByPublicId,
  });

  @override
  State<PlanFriendsModal> createState() => _PlanFriendsModalState();
}

class _PlanFriendsModalState extends State<PlanFriendsModal> {
  late final FriendsRepository _friendsRepository;

  bool _loading = true;
  List<FriendDto> _friends = const [];

  /// optimistic pending by friend_user_id
  final Set<String> _pending = <String>{};

  /// in-flight guard by friend_user_id
  final Set<String> _inFlight = <String>{};

  @override
  void initState() {
    super.initState();
    _friendsRepository = FriendsRepositoryImpl(Supabase.instance.client);
    unawaited(_loadFriends());
  }

  Future<void> _loadFriends() async {
    if (!mounted) return;

    final appUserId = widget.appUserId.trim();
    if (appUserId.isEmpty) {
      setState(() => _loading = false);
      await showCenterToast(
        context,
        message: 'Не удалось определить текущего пользователя',
        isError: true,
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final list = await _friendsRepository.listMyFriends(appUserId: appUserId);
      if (!mounted) return;
      setState(() {
        _friends = list;
      });
    } catch (e) {
      if (!mounted) return;
      await showCenterToast(
        context,
        message: 'Ошибка загрузки друзей: $e',
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _isDisabled(FriendDto f) =>
      _pending.contains(f.friendUserId) || _inFlight.contains(f.friendUserId);

  Future<void> _invite(FriendDto f) async {
    if (!mounted) return;
    if (_isDisabled(f)) return;

    final publicId = f.publicId.trim();
    if (publicId.isEmpty) {
      await showCenterToast(
        context,
        message: 'Не найден public_id друга',
        isError: true,
      );
      return;
    }

    setState(() {
      _inFlight.add(f.friendUserId);
      _pending.add(f.friendUserId);
    });

    try {
      await widget.onInviteFriendByPublicId(publicId);
      if (!mounted) return;

      await showCenterToast(context, message: 'Приглашение отправлено');
    } catch (e) {
      if (!mounted) return;

      // rollback optimistic pending on error
      setState(() {
        _pending.remove(f.friendUserId);
      });

      await showCenterToast(
        context,
        message: 'Ошибка отправки приглашения: $e',
        isError: true,
      );
    } finally {
      if (!mounted) return;
      setState(() {
        _inFlight.remove(f.friendUserId);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.78;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        decoration: const BoxDecoration(
          color: Color(0xFF111827),
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 10),
            _Header(
              title: 'Список друзей',
              subtitle: 'Выберите друга для добавления в план.',
              onClose: () => Navigator.of(context).pop(false),
            ),
            const Divider(height: 1, thickness: 1),
            Expanded(
              child: _loading
                  ? const Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_friends.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Друзей пока нет',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                          itemCount: _friends.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, index) {
                            final f = _friends[index];
                            final disabled = _isDisabled(f);
                            return _FriendPickCard(
                              friend: f,
                              disabled: disabled,
                              showSentLabel: _pending.contains(f.friendUserId),
                              onTap: () => unawaited(_invite(f)),
                            );
                          },
                        )),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onClose;

  const _Header({
    required this.title,
    required this.subtitle,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 10, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Colors.white54,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, color: Colors.white70),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _FriendPickCard extends StatelessWidget {
  final FriendDto friend;
  final bool disabled;
  final bool showSentLabel;
  final VoidCallback onTap;

  const _FriendPickCard({
    required this.friend,
    required this.disabled,
    required this.showSentLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = Colors.white.withOpacity(0.10);
    final bg = Colors.white.withOpacity(0.06);
    final titleColor = disabled ? Colors.white38 : Colors.white;
    final subtitleColor = disabled ? Colors.white30 : Colors.white54;

    // FriendDto даёт displayName + note.
    // Под твой макет:
    // - Ник: displayName
    // - Имя: пока "не указано" (если нужно строго как на скрине — добавим server-first поле позже)
    // - Комментарий: note
    final nick =
        friend.displayName.trim().isEmpty ? '—' : friend.displayName.trim();
    final name = 'не указано';
    final note = friend.note.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: disabled ? null : onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.10), width: 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ник: $nick',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Имя: $name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: subtitleColor),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.08), width: 1),
                      ),
                      child: Text(
                        note.isEmpty ? 'Мой комментарий...' : note,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: note.isEmpty ? Colors.white24 : Colors.white54,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              if (showSentLabel)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: Colors.white.withOpacity(0.12), width: 1),
                  ),
                  child: const Text(
                    'Отправлено приглашение',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
