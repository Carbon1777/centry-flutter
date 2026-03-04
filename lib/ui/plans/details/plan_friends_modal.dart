import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../data/friends/friend_dto.dart';
import '../../../data/friends/friends_repository.dart';
import '../../../data/friends/friends_repository_impl.dart';
import '../../common/center_toast.dart';
import 'plan_friends_picker_sheet.dart';

/// Wrapper for bottom-sheet: loads friends from server and shows PlanFriendsPickerSheet.
class PlanFriendsModal extends StatefulWidget {
  /// current app_user_id (uuid)
  final String appUserId;

  /// Server-first entrypoint: invite into current plan by friend's public_id
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final maxHeight = MediaQuery.of(context).size.height * 0.78;

      return SafeArea(
        child: Container(
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: const BoxDecoration(
            color: Color(0xFF111827),
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    return PlanFriendsPickerSheet(
      friends: _friends,
      onInviteFriendByPublicId: widget.onInviteFriendByPublicId,
    );
  }
}
