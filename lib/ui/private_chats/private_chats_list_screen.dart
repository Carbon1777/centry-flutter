import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/private_chats/private_chat_dto.dart';
import '../../data/private_chats/private_chats_repository_impl.dart';
import '../../features/profile/user_card_sheet.dart';
import 'private_chat_screen.dart';

class PrivateChatsListScreen extends StatefulWidget {
  final String appUserId;

  const PrivateChatsListScreen({super.key, required this.appUserId});

  @override
  State<PrivateChatsListScreen> createState() => _PrivateChatsListScreenState();
}

class _PrivateChatsListScreenState extends State<PrivateChatsListScreen>
    with WidgetsBindingObserver {
  late final _repo =
      PrivateChatsRepositoryImpl(Supabase.instance.client);

  static const _kRefreshInterval = Duration(seconds: 5);

  List<PrivateChatListItemDto> _chats = [];
  Map<String, UserMiniProfile> _profiles = {};
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _refreshTimer = Timer.periodic(_kRefreshInterval, (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    try {
      final chats = await _repo.getPrivateChatsList(
          appUserId: widget.appUserId);
      if (!mounted) return;

      final partnerIds = chats.map((c) => c.partnerUserId).toList();
      final profiles = partnerIds.isEmpty
          ? <String, UserMiniProfile>{}
          : await loadUserMiniProfiles(
              userIds: partnerIds, context: 'friends');

      if (!mounted) return;
      setState(() {
        _chats = chats;
        _profiles = profiles;
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
        title: const Text('Приватные чаты'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _chats.isEmpty
              ? Center(
                  child: Text(
                    'У вас пока нет приватных чатов',
                    style: text.bodyMedium
                        ?.copyWith(color: colors.onSurface.withValues(alpha: 0.5)),
                    textAlign: TextAlign.center,
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    itemCount: _chats.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final chat = _chats[i];
                      final profile = _profiles[chat.partnerUserId];
                      return _ChatCard(
                        chat: chat,
                        profile: profile,
                        onTap: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => PrivateChatScreen(
                                appUserId: widget.appUserId,
                                chatId: chat.chatId,
                                partnerUserId: chat.partnerUserId,
                                partnerProfile: profile,
                              ),
                            ),
                          );
                          _load();
                        },
                      );
                    },
                  ),
                ),
    );
  }
}

class _ChatCard extends StatelessWidget {
  final PrivateChatListItemDto chat;
  final UserMiniProfile? profile;
  final VoidCallback onTap;

  const _ChatCard({
    required this.chat,
    required this.profile,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    final nickname = profile?.nickname ?? '...';
    final name = profile?.name;
    final status = buildOnlineStatus(profile?.lastActiveAt);

    return Material(
      color: colors.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Аватар
              UserAvatarWidget(profile: profile, size: 48),
              const SizedBox(width: 12),
              // Ник + имя + превью
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Ник + статус онлайн справа
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            nickname,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: status.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    if (name != null && name.isNotEmpty)
                      Text(
                        name,
                        style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: colors.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    if (chat.lastMessageText != null &&
                        chat.lastMessageText!.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        chat.lastMessageIsMine
                            ? 'Вы: ${chat.lastMessageText!}'
                            : chat.lastMessageText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Красный кружок если есть непрочитанные
              if (chat.hasUnread)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF445A),
                      shape: BoxShape.circle,
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
