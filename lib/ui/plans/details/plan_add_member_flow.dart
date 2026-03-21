import 'package:flutter/material.dart';

import 'plan_add_by_id_modal.dart';
import 'plan_friends_modal.dart';
import 'plan_invite_modal.dart';

/// 1) Первый экран: выбор способа добавления участника (3 опции).
///
/// ВАЖНО: client = dumb.
/// - Никаких вычислений прав/ролей/статусов.
/// - Только рендер по server flags.
/// - Любые действия -> callbacks (RPC снаружи)
class PlanAddMemberModal extends StatelessWidget {
  /// ✅ Каноничный userId для server-first RPC (тот же, что используется в планах).
  final String appUserId;

  final bool canInvite;
  final bool canAddFromFriends;
  final bool canAddById;

  /// current plan id (uuid)
  final String planId;

  /// server-first: create invite (returns token/payload)
  final Future<String> Function() onCreateInvite;

  /// server-first: add member by public_id
  final Future<void> Function(String publicId) onAddByPublicId;

  const PlanAddMemberModal({
    super.key,
    required this.appUserId,
    required this.canInvite,
    required this.canAddFromFriends,
    required this.canAddById,
    required this.planId,
    required this.onCreateInvite,
    required this.onAddByPublicId,
  });

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.8;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(
                title: 'Выберите способ',
                onClose: () => Navigator.of(context).pop(false),
              ),
              const Divider(height: 1, thickness: 1),
              Flexible(
                child: SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      _ActionCard(
                        title: 'Добавить по инвайту',
                        enabled: canInvite,
                        onTap: () async {
                          if (!canInvite) return;

                          await showDialog<void>(
                            context: context,
                            barrierDismissible: true,
                            builder: (_) => PlanInviteModal(
                              onCreateInvite: onCreateInvite,
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      _ActionCard(
                        title: 'Добавить из списка друзей',
                        enabled: canAddFromFriends,
                        onTap: () async {
                          if (!canAddFromFriends) return;

                          // Bottom-sheet, swipe-down to close
                          var didInvite = false;
                          await showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            barrierColor: Colors.black.withValues(alpha: 0.55),
                            builder: (_) => PlanFriendsModal(
                              appUserId: appUserId, // ✅ FIX: каноничный userId
                              planId: planId,
                              onInviteFriendByPublicId: onAddByPublicId,
                              onInviteSent: () => didInvite = true,
                            ),
                          );

                          if (!context.mounted) return;

                          // Если внутри bottom-sheet реально отправили хотя бы одно приглашение —
                          // закрываем этот диалог с true (родитель обновит детали/участников).
                          if (didInvite) {
                            Navigator.of(context).pop(true);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      _ActionCard(
                        title: 'Добавить по ID',
                        enabled: canAddById,
                        onTap: () async {
                          if (!canAddById) return;

                          final ok = await showDialog<bool>(
                            context: context,
                            barrierDismissible: true,
                            builder: (_) => PlanAddByIdModal(
                              onAddByPublicId: onAddByPublicId,
                            ),
                          );

                          if (!context.mounted) return;

                          // ✅ IMPORTANT: propagate success to parent modal
                          if (ok == true) {
                            Navigator.of(context).pop(true);
                          }
                        },
                      ),
                    ],
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

class _Header extends StatelessWidget {
  final String title;
  final VoidCallback onClose;

  const _Header({
    required this.title,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 12, 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final bool enabled;
  final VoidCallback onTap;

  const _ActionCard({
    required this.title,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = enabled ? Colors.white70 : Colors.white24;
    final titleColor =
        enabled ? const Color.fromARGB(226, 78, 113, 239) : Colors.white38;
    final chevronColor = enabled ? Colors.white70 : Colors.white24;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled ? onTap : null,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: titleColor,
                  ),
                ),
              ),
              Icon(Icons.chevron_right, color: chevronColor),
            ],
          ),
        ),
      ),
    );
  }
}
