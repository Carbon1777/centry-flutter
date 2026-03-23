import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/private_chats/private_chat_dto.dart';
import '../../data/private_chats/private_chats_repository_impl.dart';
import '../../features/profile/user_card_sheet.dart';
import '../../ui/common/center_toast.dart';

// =======================
// Block (State Management)
// =======================

class PrivateChatBlock extends StatefulWidget {
  final String appUserId;
  final String chatId;
  final String partnerUserId;
  final UserMiniProfile? partnerProfile;
  final Widget Function(
    BuildContext context,
    PrivateChatSnapshotDto? snapshot,
    bool sending,
    void Function(String text) onSend,
    VoidCallback onMarkRead,
    VoidCallback onDeleteChat,
    VoidCallback onDeleteChatAndBlock,
  ) builder;

  const PrivateChatBlock({
    super.key,
    required this.appUserId,
    required this.chatId,
    required this.partnerUserId,
    this.partnerProfile,
    required this.builder,
  });

  @override
  State<PrivateChatBlock> createState() => _PrivateChatBlockState();
}

class _PrivateChatBlockState extends State<PrivateChatBlock>
    with WidgetsBindingObserver {
  late final _repo = PrivateChatsRepositoryImpl(Supabase.instance.client);

  static const _kRefreshInterval = Duration(seconds: 2);

  PrivateChatSnapshotDto? _snapshot;
  bool _sending = false;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _readInFlight = false;
  int _lastMarkedReadSeq = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadSnapshot();
    _refreshTimer = Timer.periodic(_kRefreshInterval, (_) {
      _queueRefresh();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _queueRefresh();
  }

  Future<void> _loadSnapshot() async {
    try {
      final snapshot = await _repo.getPrivateChatSnapshot(
        appUserId: widget.appUserId,
        chatId: widget.chatId,
      );
      if (!mounted || snapshot == null) return;
      setState(() => _snapshot = snapshot);
      _markReadIfNeeded();
    } catch (_) {}
  }

  void _queueRefresh() {
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }
    _doRefresh();
  }

  Future<void> _doRefresh() async {
    if (!mounted) return;
    _refreshInFlight = true;
    try {
      final snapshot = await _repo.getPrivateChatSnapshot(
        appUserId: widget.appUserId,
        chatId: widget.chatId,
      );
      if (!mounted || snapshot == null) return;
      setState(() => _snapshot = snapshot);
      _markReadIfNeeded();
    } catch (_) {
    } finally {
      _refreshInFlight = false;
      if (_refreshQueued) {
        _refreshQueued = false;
        _doRefresh();
      }
    }
  }

  void _markReadIfNeeded() {
    final snap = _snapshot;
    if (snap == null) return;
    if (snap.unreadCount <= 0) return;
    if (_readInFlight) return;
    final seq = snap.roomMessageSeq;
    if (seq <= _lastMarkedReadSeq) return;
    _doMarkRead(seq);
  }

  Future<void> _doMarkRead(int seq) async {
    _readInFlight = true;
    try {
      await _repo.markChatRead(
        appUserId: widget.appUserId,
        chatId: widget.chatId,
        readThroughSeq: seq,
      );
      _lastMarkedReadSeq = seq;
    } catch (_) {
    } finally {
      _readInFlight = false;
    }
  }

  Future<void> _handleSend(String text) async {
    if (text.trim().isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final nonce =
          'pc_${widget.chatId}_${widget.appUserId}_${DateTime.now().microsecondsSinceEpoch}';
      final result = await _repo.sendMessage(
        appUserId: widget.appUserId,
        chatId: widget.chatId,
        text: text.trim(),
        clientNonce: nonce,
      );
      if (!mounted) return;
      if (result.isSuccess) {
        _queueRefresh();
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _handleDeleteChat() async {
    final ok = await _repo.deletePrivateChat(
      appUserId: widget.appUserId,
      chatId: widget.chatId,
    );
    if (!mounted) return;
    if (ok) {
      showCenterToast(context, message: 'Чат удален');
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleDeleteChatAndBlock() async {
    final ok = await _repo.deletePrivateChatAndBlock(
      appUserId: widget.appUserId,
      chatId: widget.chatId,
    );
    if (!mounted) return;
    if (ok) {
      showCenterToast(context, message: 'Пользователь заблокирован, чат удален');
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      _snapshot,
      _sending,
      _handleSend,
      _markReadIfNeeded,
      _handleDeleteChat,
      _handleDeleteChatAndBlock,
    );
  }
}

// =======================
// Screen (UI)
// =======================

class PrivateChatScreen extends StatelessWidget {
  final String appUserId;
  final String chatId;
  final String partnerUserId;
  final UserMiniProfile? partnerProfile;

  const PrivateChatScreen({
    super.key,
    required this.appUserId,
    required this.chatId,
    required this.partnerUserId,
    this.partnerProfile,
  });

  @override
  Widget build(BuildContext context) {
    return PrivateChatBlock(
      appUserId: appUserId,
      chatId: chatId,
      partnerUserId: partnerUserId,
      partnerProfile: partnerProfile,
      builder: (context, snapshot, sending, onSend, onMarkRead,
          onDeleteChat, onDeleteChatAndBlock) {
        return _PrivateChatView(
          appUserId: appUserId,
          chatId: chatId,
          partnerProfile: partnerProfile,
          snapshot: snapshot,
          sending: sending,
          onSend: onSend,
          onDeleteChat: onDeleteChat,
          onDeleteChatAndBlock: onDeleteChatAndBlock,
        );
      },
    );
  }
}

// =======================
// View (внутренний виджет)
// =======================

class _PrivateChatView extends StatefulWidget {
  final String appUserId;
  final String chatId;
  final UserMiniProfile? partnerProfile;
  final PrivateChatSnapshotDto? snapshot;
  final bool sending;
  final void Function(String) onSend;
  final VoidCallback onDeleteChat;
  final VoidCallback onDeleteChatAndBlock;

  const _PrivateChatView({
    required this.appUserId,
    required this.chatId,
    required this.partnerProfile,
    required this.snapshot,
    required this.sending,
    required this.onSend,
    required this.onDeleteChat,
    required this.onDeleteChatAndBlock,
  });

  @override
  State<_PrivateChatView> createState() => _PrivateChatViewState();
}

class _PrivateChatViewState extends State<_PrivateChatView> {
  final _scrollController = ScrollController();
  final _composerController = TextEditingController();
  final _composerFocusNode = FocusNode();

  @override
  void dispose() {
    _scrollController.dispose();
    _composerController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_PrivateChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) {
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSendPressed() {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;
    _composerController.clear();
    widget.onSend(text);
  }

  void _showDeleteOptions() {
    showModalBottomSheet(
      context: context,
      builder: (_) => _DeleteOptionsSheet(
        onDeleteChat: () {
          Navigator.of(context).pop();
          _confirmDeleteChat();
        },
        onDeleteChatAndBlock: () {
          Navigator.of(context).pop();
          _confirmDeleteChatAndBlock();
        },
      ),
    );
  }

  void _confirmDeleteChat() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить чат?'),
        content:
            const Text('Чат и история сообщений будут удалены у обоих участников.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDeleteChat();
            },
            child: const Text('Удалить',
                style: TextStyle(color: Color(0xFFFF445A))),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteChatAndBlock() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Удалить чат и заблокировать?'),
        content: const Text(
            'Чат, история и дружба будут удалены. Пользователь будет заблокирован.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onDeleteChatAndBlock();
            },
            child: const Text('Заблокировать',
                style: TextStyle(color: Color(0xFFFF445A))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = widget.partnerProfile;
    final nickname = profile?.nickname ?? '...';
    final name = profile?.name;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            UserAvatarWidget(profile: profile, size: 36),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nickname,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
                if (name != null && name.isNotEmpty)
                  Text(
                    name,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: colors.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: _showDeleteOptions,
          ),
        ],
      ),
      body: Column(
        children: [
          // Список сообщений
          Expanded(
            child: _MessagesList(
              appUserId: widget.appUserId,
              snapshot: widget.snapshot,
              scrollController: _scrollController,
            ),
          ),
          // Composer
          _Composer(
            controller: _composerController,
            focusNode: _composerFocusNode,
            sending: widget.sending,
            onSend: _handleSendPressed,
          ),
        ],
      ),
    );
  }
}

// =======================
// Список сообщений
// =======================

class _MessagesList extends StatelessWidget {
  final String appUserId;
  final PrivateChatSnapshotDto? snapshot;
  final ScrollController scrollController;

  const _MessagesList({
    required this.appUserId,
    required this.snapshot,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final messages = snapshot?.messages ?? [];

    if (messages.isEmpty) {
      return Center(
        child: Text(
          'Начните общение',
          style: TextStyle(
            color: Theme.of(context)
                .colorScheme
                .onSurface
                .withValues(alpha: 0.4),
          ),
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: messages.length,
      itemBuilder: (context, i) {
        final msg = messages[i];
        return _MessageBubble(message: msg);
      },
    );
  }
}

// =======================
// Пузырь сообщения
// =======================

class _MessageBubble extends StatelessWidget {
  final PrivateChatMessageDto message;

  const _MessageBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isMine = message.isMine;
    final isDeleted = message.isTombstone;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.72,
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isDeleted
                  ? colors.surface.withValues(alpha: 0.4)
                  : isMine
                      ? colors.primary.withValues(alpha: 0.85)
                      : colors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: Radius.circular(isMine ? 16 : 4),
                bottomRight: Radius.circular(isMine ? 4 : 16),
              ),
            ),
            child: isDeleted
                ? Text(
                    'Сообщение удалено',
                    style: TextStyle(
                      fontSize: 14,
                      fontStyle: FontStyle.italic,
                      color: colors.onSurface.withValues(alpha: 0.38),
                    ),
                  )
                : Text(
                    message.text,
                    style: TextStyle(
                      fontSize: 14,
                      color: isMine ? colors.onPrimary : colors.onSurface,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

// =======================
// Composer (поле ввода)
// =======================

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        8,
        12,
        8 + MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          top: BorderSide(
            color: colors.onSurface.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Сообщение...',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: colors.onSurface.withValues(alpha: 0.06),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            sending
                ? const SizedBox(
                    width: 40,
                    height: 40,
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.arrow_upward_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF3B82F6),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(40, 40),
                    ),
                    onPressed: onSend,
                  ),
          ],
        ),
      ),
    );
  }
}

// =======================
// Шторка действий (удалить чат)
// =======================

class _DeleteOptionsSheet extends StatelessWidget {
  final VoidCallback onDeleteChat;
  final VoidCallback onDeleteChatAndBlock;

  const _DeleteOptionsSheet({
    required this.onDeleteChat,
    required this.onDeleteChatAndBlock,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.delete_outline,
                  color: colors.onSurface.withValues(alpha: 0.7)),
              title: const Text('Удалить чат'),
              onTap: onDeleteChat,
            ),
            ListTile(
              leading: const Icon(Icons.block, color: Color(0xFFFF445A)),
              title: const Text(
                'Удалить чат и заблокировать пользователя',
                style: TextStyle(color: Color(0xFFFF445A)),
              ),
              onTap: onDeleteChatAndBlock,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
