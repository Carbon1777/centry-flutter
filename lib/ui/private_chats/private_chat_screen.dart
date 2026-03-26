import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/private_chats/private_chat_dto.dart';
import '../../data/private_chats/private_chats_repository_impl.dart';
import '../../features/profile/user_card_sheet.dart';
import '../../ui/common/center_toast.dart';

// ═══════════════════════════════════════════════════════════
// Block (State Management)
// ═══════════════════════════════════════════════════════════

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
    Future<void> Function(String messageId, String text) onEditMessage,
    Future<void> Function(String messageId) onDeleteMessageForAll,
    Future<void> Function(String messageId) onDeleteMessageForMe,
    Future<void> Function(List<String> messageIds, String mode)
        onDeleteMessagesBulk,
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
    } catch (e) {
      debugPrint('[PrivateChat] loadSnapshot error: $e');
    }
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
    } catch (e) {
      debugPrint('[PrivateChat] doRefresh error: $e');
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
    } catch (e) {
      debugPrint('[PrivateChat] markRead error: $e');
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
    } catch (e) {
      debugPrint('[PrivateChat] sendMessage error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _handleDeleteChat() async {
    _refreshTimer?.cancel();
    await _repo.deletePrivateChat(
      appUserId: widget.appUserId,
      chatId: widget.chatId,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    showCenterToast(context, message: 'Чат удален');
  }

  Future<void> _handleDeleteChatAndBlock() async {
    _refreshTimer?.cancel();
    await _repo.deletePrivateChatAndBlock(
      appUserId: widget.appUserId,
      chatId: widget.chatId,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    showCenterToast(context, message: 'Пользователь заблокирован, чат удален');
  }

  Future<void> _handleEditMessage(String messageId, String text) async {
    try {
      await _repo.editMessage(
        appUserId: widget.appUserId,
        chatId: widget.chatId,
        messageId: messageId,
        text: text,
      );
      _queueRefresh();
    } catch (e) {
      debugPrint('[PrivateChat] editMessage error: $e');
    }
  }

  Future<void> _handleDeleteMessageForAll(String messageId) async {
    try {
      await _repo.deleteMessageForAll(
        appUserId: widget.appUserId,
        chatId: widget.chatId,
        messageId: messageId,
      );
      _queueRefresh();
    } catch (e) {
      debugPrint('[PrivateChat] deleteMessageForAll error: $e');
    }
  }

  Future<void> _handleDeleteMessageForMe(String messageId) async {
    try {
      await _repo.deleteMessageForMe(
        appUserId: widget.appUserId,
        chatId: widget.chatId,
        messageId: messageId,
      );
      _queueRefresh();
    } catch (e) {
      debugPrint('[PrivateChat] deleteMessageForMe error: $e');
    }
  }

  Future<void> _handleDeleteMessagesBulk(
      List<String> messageIds, String mode) async {
    try {
      await _repo.deleteMessagesBulk(
        appUserId: widget.appUserId,
        chatId: widget.chatId,
        messageIds: messageIds,
        mode: mode,
      );
      _queueRefresh();
    } catch (e) {
      debugPrint('[PrivateChat] deleteMessagesBulk error: $e');
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
      _handleEditMessage,
      _handleDeleteMessageForAll,
      _handleDeleteMessageForMe,
      _handleDeleteMessagesBulk,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Screen (entry point)
// ═══════════════════════════════════════════════════════════

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
      builder: (context, snapshot, sending, onSend, onMarkRead, onDeleteChat,
          onDeleteChatAndBlock, onEditMessage, onDeleteMessageForAll,
          onDeleteMessageForMe, onDeleteMessagesBulk) {
        return _PrivateChatView(
          appUserId: appUserId,
          chatId: chatId,
          partnerProfile: partnerProfile,
          snapshot: snapshot,
          sending: sending,
          onSend: onSend,
          onDeleteChat: onDeleteChat,
          onDeleteChatAndBlock: onDeleteChatAndBlock,
          onEditMessage: onEditMessage,
          onDeleteMessageForAll: onDeleteMessageForAll,
          onDeleteMessageForMe: onDeleteMessageForMe,
          onDeleteMessagesBulk: onDeleteMessagesBulk,
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════
// View
// ═══════════════════════════════════════════════════════════

class _PrivateChatView extends StatefulWidget {
  final String appUserId;
  final String chatId;
  final UserMiniProfile? partnerProfile;
  final PrivateChatSnapshotDto? snapshot;
  final bool sending;
  final void Function(String) onSend;
  final VoidCallback onDeleteChat;
  final VoidCallback onDeleteChatAndBlock;
  final Future<void> Function(String messageId, String text) onEditMessage;
  final Future<void> Function(String messageId) onDeleteMessageForAll;
  final Future<void> Function(String messageId) onDeleteMessageForMe;
  final Future<void> Function(List<String> messageIds, String mode)
      onDeleteMessagesBulk;

  const _PrivateChatView({
    required this.appUserId,
    required this.chatId,
    required this.partnerProfile,
    required this.snapshot,
    required this.sending,
    required this.onSend,
    required this.onDeleteChat,
    required this.onDeleteChatAndBlock,
    required this.onEditMessage,
    required this.onDeleteMessageForAll,
    required this.onDeleteMessageForMe,
    required this.onDeleteMessagesBulk,
  });

  @override
  State<_PrivateChatView> createState() => _PrivateChatViewState();
}

// ---------------------------------------------------------------------------
// Статус онлайн-активности
// ---------------------------------------------------------------------------

class OnlineStatus {
  final Color color;
  final String label;
  const OnlineStatus(this.color, this.label);
}

OnlineStatus buildOnlineStatus(DateTime? lastActiveAt) {
  if (lastActiveAt == null) {
    return const OnlineStatus(Color(0xFFFF445A), 'Был давно');
  }
  final diff = DateTime.now().toUtc().difference(lastActiveAt.toUtc());
  if (diff.inMinutes <= 5) {
    return const OnlineStatus(Color(0xFF4CAF50), 'В сети');
  } else if (diff.inDays < 7) {
    return const OnlineStatus(Color(0xFFFFC107), 'Был недавно');
  } else {
    return const OnlineStatus(Color(0xFFFF445A), 'Был давно');
  }
}

class _PrivateChatViewState extends State<_PrivateChatView>
    with WidgetsBindingObserver {
  static const double _kBottomAutoScrollThreshold = 72;
  static const Duration _kUnreadDividerLifetime = Duration(seconds: 2);

  final _scrollController = ScrollController();
  final _composerController = TextEditingController();
  final _composerFocusNode = FocusNode();

  PrivateChatMessageDto? _editingMessage;
  PrivateChatMessageDto? _replyingTo;
  bool _showEmojiPicker = false;
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  bool _initialScrollDone = false;
  bool _pendingOwnMessageAutoScroll = false;
  double _lastKeyboardInsetBottom = 0;
  final GlobalKey _unreadDividerKey = GlobalKey();

  // Разделитель непрочитанных — временный, скрывается через 2 сек
  bool _showUnreadDivider = false;
  int? _unreadDividerInsertIndex;
  Timer? _unreadDividerTimer;

  // Периодическое обновление профиля партнёра (для статуса онлайн)
  UserMiniProfile? _livePartnerProfile;
  Timer? _profileRefreshTimer;
  bool _profileRefreshedOnce = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _livePartnerProfile = widget.partnerProfile;
    _profileRefreshTimer =
        Timer.periodic(const Duration(seconds: 30), (_) => _refreshPartnerProfile());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lastKeyboardInsetBottom = MediaQuery.viewInsetsOf(context).bottom;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unreadDividerTimer?.cancel();
    _profileRefreshTimer?.cancel();
    _scrollController.dispose();
    _composerController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  Future<void> _refreshPartnerProfile() async {
    final snapshot = widget.snapshot;
    if (snapshot == null) return;
    try {
      final profiles = await loadUserMiniProfiles(
        userIds: [snapshot.partnerUserId],
        context: 'friends',
      );
      if (!mounted) return;
      _profileRefreshedOnce = true;
      final updated = profiles[snapshot.partnerUserId];
      if (updated != null) {
        setState(() => _livePartnerProfile = updated);
      }
    } catch (e) {
      debugPrint('[PrivateChat] refreshPartnerProfile error: $e');
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;

    final nextKeyboardBottom = _currentKeyboardInsetBottom();
    final keyboardOpened = nextKeyboardBottom > _lastKeyboardInsetBottom + 1;
    final keyboardClosed = nextKeyboardBottom < _lastKeyboardInsetBottom - 1;
    final shouldKeepBottomAnchored = _composerFocusNode.hasFocus ||
        _isNearBottom(threshold: _kBottomAutoScrollThreshold + 56);

    _lastKeyboardInsetBottom = nextKeyboardBottom;

    if (keyboardOpened) {
      if (_showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
      if (shouldKeepBottomAnchored) {
        _scheduleKeyboardAdjustment();
      }
    } else if (keyboardClosed && shouldKeepBottomAnchored) {
      _scheduleKeyboardAdjustment();
    }
  }

  double _currentKeyboardInsetBottom() {
    final view = View.of(context);
    return MediaQueryData.fromView(view).viewInsets.bottom;
  }

  bool _isNearBottom({double threshold = _kBottomAutoScrollThreshold}) {
    if (!_scrollController.hasClients) return true;
    final pos = _scrollController.position;
    return pos.maxScrollExtent - pos.pixels <= threshold;
  }

  int _keyboardAdjustmentRequestId = 0;

  void _scheduleKeyboardAdjustment() {
    final requestId = ++_keyboardAdjustmentRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _adjustForKeyboardInset(requestId: requestId);
    });
  }

  Future<void> _adjustForKeyboardInset({required int requestId}) async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted || requestId != _keyboardAdjustmentRequestId) return;
      if (!_scrollController.hasClients) continue;

      final position = _scrollController.position;
      final targetOffset = position.maxScrollExtent;
      if ((targetOffset - position.pixels).abs() < 1.0) continue;
      _scrollController.jumpTo(targetOffset);
    }
  }

  @override
  void didUpdateWidget(_PrivateChatView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldSnap = oldWidget.snapshot;
    final newSnap = widget.snapshot;
    if (oldSnap == newSnap || newSnap == null) return;

    // При первом snapshot — загрузить актуальный профиль партнёра
    if (oldSnap == null && !_profileRefreshedOnce) {
      _refreshPartnerProfile();
    }

    if (!_initialScrollDone) {
      _initialScrollDone = true;
      _setupUnreadDivider(newSnap);
      _scrollToUnreadOrBottom(newSnap);
      return;
    }

    // Проверяем: появились ли новые сообщения?
    final oldLastId = oldSnap != null && oldSnap.messages.isNotEmpty
        ? oldSnap.messages.last.id
        : null;
    final newLastId =
        newSnap.messages.isNotEmpty ? newSnap.messages.last.id : null;
    final hasNewMessages = oldLastId != newLastId;

    if (hasNewMessages &&
        !_showUnreadDivider &&
        (_isNearBottom() || _pendingOwnMessageAutoScroll)) {
      final forceToBottom = _pendingOwnMessageAutoScroll;
      _pendingOwnMessageAutoScroll = false;
      _scheduleAutoScroll(forceToBottom: forceToBottom);
    } else if (_pendingOwnMessageAutoScroll) {
      _pendingOwnMessageAutoScroll = false;
    }
  }

  void _setupUnreadDivider(PrivateChatSnapshotDto snapshot) {
    _unreadDividerTimer?.cancel();
    _showUnreadDivider = false;
    _unreadDividerInsertIndex = null;

    final firstUnreadSeq = snapshot.firstUnreadRoomSeq;
    if (firstUnreadSeq == null || snapshot.unreadCount <= 0) return;

    // Находим индекс первого непрочитанного
    for (int i = 0; i < snapshot.messages.length; i++) {
      if (snapshot.messages[i].roomSeq >= firstUnreadSeq) {
        _unreadDividerInsertIndex = i;
        break;
      }
    }

    if (_unreadDividerInsertIndex == null) return;

    _showUnreadDivider = true;
    _unreadDividerTimer = Timer(_kUnreadDividerLifetime, () {
      if (mounted) {
        setState(() {
          _showUnreadDivider = false;
          _unreadDividerInsertIndex = null;
        });
      }
    });
  }

  void _scrollToUnreadOrBottom(PrivateChatSnapshotDto snapshot) {
    if (_showUnreadDivider && _unreadDividerInsertIndex != null) {
      _scrollToUnreadDivider();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      });
    }
  }

  void _scrollToUnreadDivider() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scrollController.hasClients) return;

      // Шаг 1: приблизительный скролл к области разделителя
      final dividerIndex = _unreadDividerInsertIndex!;
      final messages = widget.snapshot?.messages ?? [];
      final totalCount = messages.length + 1; // +1 для самого разделителя
      final pos = _scrollController.position;
      final approxOffset =
          (pos.maxScrollExtent * dividerIndex / totalCount)
              .clamp(0.0, pos.maxScrollExtent);
      _scrollController.jumpTo(approxOffset);

      // Шаг 2: ждём layout
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted) return;

      // Шаг 3: точное позиционирование через ensureVisible (по центру)
      if (!mounted) return;
      final dividerContext = _unreadDividerKey.currentContext;
      if (dividerContext != null) {
        Scrollable.ensureVisible(
          dividerContext,
          alignment: 0.4,
          duration: Duration.zero,
        );
      }
    });
  }

  void _scheduleAutoScroll({required bool forceToBottom}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      if (forceToBottom) {
        _scrollController.jumpTo(pos.maxScrollExtent);
      } else {
        _scrollController.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  // ── Send ──

  void _handleSendPressed() {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;

    final editing = _editingMessage;
    if (editing != null) {
      _composerController.clear();
      setState(() => _editingMessage = null);
      widget.onEditMessage(editing.id, text);
      return;
    }

    // Формируем текст с цитатой
    final replyTo = _replyingTo;
    final String finalText;
    if (replyTo != null) {
      final nick = replyTo.isMine
          ? 'Вы'
          : (widget.partnerProfile?.nickname ?? '...');
      var raw = replyTo.text;
      const quoteEnd = ' \u00bb\n';
      final qIdx = raw.indexOf(quoteEnd);
      if ((raw.startsWith('\u00ab @') || raw.startsWith('\u00ab ')) &&
          qIdx != -1) {
        raw = raw.substring(qIdx + quoteEnd.length);
      }
      final quoted = raw.length > 80 ? '${raw.substring(0, 80)}\u2026' : raw;
      finalText = '\u00ab @$nick: $quoted \u00bb\n$text';
      setState(() => _replyingTo = null);
    } else {
      finalText = text;
    }

    _composerController.clear();
    _pendingOwnMessageAutoScroll = true;
    setState(() {});
    widget.onSend(finalText);
  }

  // ── Edit / Reply / Selection modes ──

  void _enterEditMode(PrivateChatMessageDto message) {
    setState(() {
      _editingMessage = message;
      _replyingTo = null;
      _selectionMode = false;
      _selectedIds.clear();
      _composerController.text = message.text;
      _composerController.selection = TextSelection.fromPosition(
        TextPosition(offset: _composerController.text.length),
      );
    });
    _composerFocusNode.requestFocus();
  }

  void _exitEditMode() {
    setState(() {
      _editingMessage = null;
      _composerController.clear();
    });
  }

  void _enterReplyMode(PrivateChatMessageDto message) {
    setState(() {
      _replyingTo = message;
      _editingMessage = null;
      _showEmojiPicker = false;
    });
    _composerFocusNode.requestFocus();
  }

  void _exitReplyMode() {
    setState(() => _replyingTo = null);
  }

  void _enterSelectionMode(String firstId) {
    _composerFocusNode.unfocus();
    setState(() {
      _editingMessage = null;
      _replyingTo = null;
      _composerController.clear();
      _selectionMode = true;
      _selectedIds.clear();
      _selectedIds.add(firstId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _toggleEmojiPicker() {
    setState(() => _showEmojiPicker = !_showEmojiPicker);
    if (_showEmojiPicker) {
      _composerFocusNode.unfocus();
      FocusScope.of(context).unfocus();
    } else {
      _composerFocusNode.requestFocus();
    }
  }

  bool get _canDeleteSelectedForAll {
    if (_selectedIds.isEmpty) return false;
    final messages = widget.snapshot?.messages ?? [];
    return messages
        .where((m) => _selectedIds.contains(m.id))
        .every((m) => m.isMine && !m.isTombstone);
  }

  Future<void> _handleBulkDeleteForMe() async {
    final ids = List<String>.from(_selectedIds);
    _exitSelectionMode();
    await widget.onDeleteMessagesBulk(ids, 'for_me');
  }

  Future<void> _handleBulkDeleteForAll() async {
    final ids = List<String>.from(_selectedIds);
    _exitSelectionMode();
    await widget.onDeleteMessagesBulk(ids, 'for_all');
  }

  // ── Action sheet ──

  void _showMessageActions(PrivateChatMessageDto message) {
    final canReply = !message.isTombstone;
    final canEdit = message.isMine && !message.isTombstone;
    final canDeleteForAll = message.isMine && !message.isTombstone;
    final canCopy = !message.isTombstone;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MessageActionSheet(
        onReply: canReply
            ? () {
                Navigator.of(context).pop();
                _enterReplyMode(message);
              }
            : null,
        onEdit: canEdit
            ? () {
                Navigator.of(context).pop();
                _enterEditMode(message);
              }
            : null,
        onCopy: canCopy
            ? () {
                Clipboard.setData(ClipboardData(text: message.text));
                Navigator.of(context).pop();
                showCenterToast(context, message: 'Скопировано');
              }
            : null,
        onDeleteForMe: () async {
          Navigator.of(context).pop();
          await widget.onDeleteMessageForMe(message.id);
        },
        onDeleteForAll: canDeleteForAll
            ? () async {
                Navigator.of(context).pop();
                await widget.onDeleteMessageForAll(message.id);
              }
            : null,
        onSelectMultiple: !message.isTombstone
            ? () {
                Navigator.of(context).pop();
                _enterSelectionMode(message.id);
              }
            : null,
      ),
    );
  }

  // ── Chat delete options (existing) ──

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
        content: const Text(
            'Чат и история сообщений будут удалены у обоих участников.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // закрыть диалог
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

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final profile = _livePartnerProfile ?? widget.partnerProfile;
    final nickname = profile?.nickname ?? '...';
    final messages = widget.snapshot?.messages ?? [];

    // Статус активности партнёра
    final statusInfo = buildOnlineStatus(profile?.lastActiveAt);

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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    nickname,
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: statusInfo.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        statusInfo.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w400,
                          color: colors.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
            child: messages.isEmpty
                ? Center(
                    child: Text(
                      'Начните общение',
                      style: TextStyle(
                        color: colors.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : _buildMessageList(messages),
          ),
          // Edit / Reply banners
          if (_editingMessage != null)
            _EditBanner(onCancel: _exitEditMode),
          if (_replyingTo != null)
            _ReplyBanner(
              message: _replyingTo!,
              partnerNickname:
                  widget.partnerProfile?.nickname ?? '...',
              onCancel: _exitReplyMode,
            ),
          // Composer / Selection bar
          if (_selectionMode)
            _SelectionActionBar(
              selectedCount: _selectedIds.length,
              canDeleteForAll: _canDeleteSelectedForAll,
              onCancel: _exitSelectionMode,
              onDeleteForMe:
                  _selectedIds.isNotEmpty ? _handleBulkDeleteForMe : null,
              onDeleteForAll: _canDeleteSelectedForAll
                  ? _handleBulkDeleteForAll
                  : null,
            )
          else
            _PrivateChatComposer(
              controller: _composerController,
              focusNode: _composerFocusNode,
              sending: widget.sending,
              showEmojiPicker: _showEmojiPicker,
              onChanged: () => setState(() {}),
              onSend: _handleSendPressed,
              onTapInside: () {
                if (_showEmojiPicker) {
                  setState(() => _showEmojiPicker = false);
                }
              },
              onEmojiToggle: _toggleEmojiPicker,
            ),
          // Emoji picker
          if (_showEmojiPicker)
            _ChatEmojiPicker(
              controller: _composerController,
              onChanged: () => setState(() {}),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageList(
    List<PrivateChatMessageDto> messages,
  ) {
    final unreadInsertIndex =
        _showUnreadDivider ? _unreadDividerInsertIndex : null;

    final totalCount =
        messages.length + (unreadInsertIndex != null ? 1 : 0);

    return GestureDetector(
      onTap: () {
        _composerFocusNode.unfocus();
        FocusScope.of(context).unfocus();
      },
      child: ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: totalCount,
      itemBuilder: (context, index) {
        // Вставляем разделитель непрочитанных
        if (unreadInsertIndex != null && index == unreadInsertIndex) {
          return Padding(
            key: _unreadDividerKey,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: const _UnreadDivider(),
          );
        }

        final msgIndex = unreadInsertIndex != null && index > unreadInsertIndex
            ? index - 1
            : index;
        final msg = messages[msgIndex];

        return _buildMessageRow(msg);
      },
    ),
    );
  }

  Widget _buildMessageRow(PrivateChatMessageDto msg) {
    final bubble = _MessageBubble(
      message: msg,
      partnerProfile: widget.partnerProfile,
      onLongPress: () => _showMessageActions(msg),
    );

    if (_selectionMode) {
      final selected = _selectedIds.contains(msg.id);
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: GestureDetector(
          onTap: () => _toggleSelection(msg.id),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: selected ? 1.0 : 0.85,
                duration: const Duration(milliseconds: 150),
                child: Checkbox(
                  value: selected,
                  onChanged: (_) => _toggleSelection(msg.id),
                  activeColor: const Color(0xFF3B82F6),
                  side: BorderSide(
                    color: Colors.white.withValues(alpha: 0.40),
                  ),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              Expanded(child: bubble),
            ],
          ),
        ),
      );
    }

    // Swipe to reply
    if (!msg.isTombstone) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Dismissible(
          key: ValueKey('swipe_${msg.id}'),
          direction: DismissDirection.startToEnd,
          confirmDismiss: (_) async {
            _enterReplyMode(msg);
            return false;
          },
          background: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Icon(
                Icons.reply_outlined,
                color: Colors.white.withValues(alpha: 0.40),
              ),
            ),
          ),
          child: bubble,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: bubble,
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Message Bubble
// ═══════════════════════════════════════════════════════════

class _ParsedMessage {
  final String? quotedNickname;
  final String? quotedText;
  final String body;

  const _ParsedMessage({
    this.quotedNickname,
    this.quotedText,
    required this.body,
  });

  bool get hasQuote => quotedNickname != null;
}

_ParsedMessage _parseMessage(String raw) {
  const start = '\u00ab @';
  const end = ' \u00bb\n';
  if (!raw.startsWith(start)) return _ParsedMessage(body: raw);
  final endIdx = raw.indexOf(end);
  if (endIdx == -1) return _ParsedMessage(body: raw);

  final quoteContent = raw.substring(start.length, endIdx);
  final body = raw.substring(endIdx + end.length);

  final colonIdx = quoteContent.indexOf(': ');
  if (colonIdx == -1) return _ParsedMessage(body: raw);

  final nick = quoteContent.substring(0, colonIdx);
  final quoted = quoteContent.substring(colonIdx + 2);
  return _ParsedMessage(quotedNickname: nick, quotedText: quoted, body: body);
}

class _MessageBubble extends StatelessWidget {
  final PrivateChatMessageDto message;
  final UserMiniProfile? partnerProfile;
  final VoidCallback? onLongPress;

  const _MessageBubble({
    required this.message,
    this.partnerProfile,
    this.onLongPress,
  });

  String _formatDateTime(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)} ${two(value.hour)}:${two(value.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isMine = message.isMine;
    final isTombstone = message.isTombstone;
    final isEdited = message.isEdited;
    final parsed = isTombstone ? null : _parseMessage(message.text);

    final bubbleColor = isTombstone
        ? theme.colorScheme.surface.withValues(alpha: 0.40)
        : (isMine
            ? const Color(0xFF10233F)
            : theme.colorScheme.surface.withValues(alpha: 0.94));
    final borderColor = isTombstone
        ? Colors.white.withValues(alpha: 0.08)
        : (isMine
            ? const Color(0xFF2A62C7).withValues(alpha: 0.50)
            : Colors.white.withValues(alpha: 0.14));
    final nicknameColor =
        isMine ? const Color(0xFF7FB0FF) : const Color(0xFF8BE4D4);

    final nicknameText = isMine
        ? 'Вы'
        : (partnerProfile?.nickname ?? '...');

    // Аватар для чужих сообщений
    Widget? avatar;
    if (!isMine) {
      avatar = _ChatAvatar(
        userId: message.authorAppUserId,
        nickname: partnerProfile?.nickname ?? '?',
        avatarUrl: partnerProfile?.avatarUrl,
        size: 34,
      );
    }

    final bubbleContent = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Никнейм + время
          Row(
            children: [
              Expanded(
                child: Text(
                  nicknameText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isTombstone
                        ? Colors.white.withValues(alpha: 0.35)
                        : nicknameColor,
                    height: 1.0,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDateTime(message.createdAt),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(
                    alpha: isTombstone ? 0.35 : 0.68,
                  ),
                  fontWeight: FontWeight.w500,
                  height: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Содержимое
          if (isTombstone)
            Text(
              'Сообщение удалено',
              style: theme.textTheme.bodyLarge?.copyWith(
                height: 1.35,
                fontSize: 15.5,
                color: Colors.white.withValues(alpha: 0.38),
                fontStyle: FontStyle.italic,
              ),
            )
          else ...[
            if (parsed != null && parsed.hasQuote) ...[
              _QuoteBlock(
                nickname: parsed.quotedNickname!,
                text: parsed.quotedText ?? '',
                isMine: isMine,
              ),
              const SizedBox(height: 6),
              Text(
                parsed.body,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.35,
                  fontSize: 15.5,
                ),
              ),
            ] else
              Text(
                message.text,
                style: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.35,
                  fontSize: 15.5,
                ),
              ),
            if (isEdited)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  'Изменено',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontWeight: FontWeight.w500,
                    height: 1.0,
                  ),
                ),
              ),
          ],
        ],
      ),
    );

    return GestureDetector(
      onLongPress: onLongPress,
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.82,
          ),
          child: isMine
              ? bubbleContent
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Opacity(
                      opacity: isTombstone ? 0.35 : 1.0,
                      child: avatar!,
                    ),
                    const SizedBox(width: 8),
                    Flexible(child: bubbleContent),
                  ],
                ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Quote Block
// ═══════════════════════════════════════════════════════════

class _QuoteBlock extends StatelessWidget {
  final String nickname;
  final String text;
  final bool isMine;

  const _QuoteBlock({
    required this.nickname,
    required this.text,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: isMine ? 0.25 : 0.15),
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(8),
          bottomRight: Radius.circular(8),
        ),
        border: const Border(
          left: BorderSide(color: Color(0xFF3B82F6), width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            nickname,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontStyle: FontStyle.italic,
              color: Colors.white.withValues(alpha: 0.50),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withValues(alpha: 0.55),
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Chat Avatar
// ═══════════════════════════════════════════════════════════

class _ChatAvatar extends StatelessWidget {
  final String userId;
  final String nickname;
  final String? avatarUrl;
  final double size;

  const _ChatAvatar({
    required this.userId,
    required this.nickname,
    this.avatarUrl,
    this.size = 34,
  });

  static const List<Color> _palette = <Color>[
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFF0F766E),
    Color(0xFF15803D),
    Color(0xFFB45309),
    Color(0xFFBE123C),
    Color(0xFF4F46E5),
    Color(0xFF9333EA),
    Color(0xFF1D4ED8),
    Color(0xFF047857),
    Color(0xFFC2410C),
  ];

  String get _initial {
    final trimmed = nickname.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.substring(0, 1).toUpperCase();
  }

  Color _backgroundColor() {
    final source = userId.trim().isEmpty ? nickname.trim() : userId.trim();
    final hash = source.hashCode.abs();
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(12);

    if (avatarUrl != null && avatarUrl!.isNotEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: Image.network(
          avatarUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _initials(context, radius),
        ),
      );
    }
    return _initials(context, radius);
  }

  Widget _initials(BuildContext context, BorderRadius radius) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _backgroundColor(),
        borderRadius: radius,
      ),
      child: Text(
        _initial,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Composer
// ═══════════════════════════════════════════════════════════

class _PrivateChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool showEmojiPicker;
  final VoidCallback onChanged;
  final VoidCallback onSend;
  final VoidCallback onTapInside;
  final VoidCallback onEmojiToggle;

  const _PrivateChatComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.showEmojiPicker,
    required this.onChanged,
    required this.onSend,
    required this.onTapInside,
    required this.onEmojiToggle,
  });

  @override
  Widget build(BuildContext context) {
    final canSend = !sending && controller.text.trim().isNotEmpty;
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 10, 14, 14),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.08),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: SafeArea(
          top: false,
          child: TextFieldTapRegion(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Focus(
                  canRequestFocus: false,
                  descendantsAreFocusable: false,
                  child: IconButton(
                    onPressed: onEmojiToggle,
                    padding: const EdgeInsets.only(bottom: 4),
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 48),
                    icon: Icon(
                      showEmojiPicker
                          ? Icons.keyboard_alt_outlined
                          : Icons.emoji_emotions_outlined,
                      color: showEmojiPicker
                          ? const Color(0xFF3B82F6)
                          : Colors.white.withValues(alpha: 0.55),
                      size: 22,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    minLines: 1,
                    maxLines: 5,
                    textInputAction: TextInputAction.newline,
                    onChanged: (_) => onChanged(),
                    onTap: onTapInside,
                    decoration: InputDecoration(
                      hintText: 'Напишите сообщение\u2026',
                      filled: true,
                      fillColor:
                          theme.colorScheme.surface.withValues(alpha: 0.90),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.10)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                            color: Colors.white.withValues(alpha: 0.10)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide:
                            const BorderSide(color: Color(0xFF3B82F6)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Focus(
                  canRequestFocus: false,
                  descendantsAreFocusable: false,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: FilledButton(
                      onPressed: canSend ? onSend : null,
                      style: FilledButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Icon(Icons.arrow_upward_rounded),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Edit Banner
// ═══════════════════════════════════════════════════════════

class _EditBanner extends StatelessWidget {
  final VoidCallback onCancel;

  const _EditBanner({required this.onCancel});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.edit_outlined, size: 16, color: Color(0xFF7FB0FF)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Редактирование сообщения',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF7FB0FF),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: onCancel,
            child: const Icon(Icons.close, size: 18, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Reply Banner
// ═══════════════════════════════════════════════════════════

class _ReplyBanner extends StatelessWidget {
  final PrivateChatMessageDto message;
  final String partnerNickname;
  final VoidCallback onCancel;

  const _ReplyBanner({
    required this.message,
    required this.partnerNickname,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final nick = message.isMine ? 'Вы' : partnerNickname;
    final quoted = message.text.length > 80
        ? '${message.text.substring(0, 80)}\u2026'
        : message.text;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nick,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: const Color(0xFF7FB0FF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  quoted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white.withValues(alpha: 0.60),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onCancel,
            child: const Icon(Icons.close, size: 18, color: Colors.white54),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Message Action Sheet
// ═══════════════════════════════════════════════════════════

class _MessageActionSheet extends StatelessWidget {
  final VoidCallback? onReply;
  final VoidCallback? onEdit;
  final VoidCallback? onCopy;
  final Future<void> Function() onDeleteForMe;
  final Future<void> Function()? onDeleteForAll;
  final VoidCallback? onSelectMultiple;

  const _MessageActionSheet({
    required this.onDeleteForMe,
    this.onReply,
    this.onEdit,
    this.onCopy,
    this.onDeleteForAll,
    this.onSelectMultiple,
  });

  @override
  Widget build(BuildContext context) {
    Divider divider() => Divider(
          height: 1,
          thickness: 1,
          indent: 16,
          endIndent: 16,
          color: Colors.white.withValues(alpha: 0.07),
        );

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF252D3D), Color(0xFF181E2B)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            if (onReply != null) ...[
              _ActionTile(
                icon: Icons.reply_outlined,
                iconColor: const Color(0xFF7FB0FF),
                label: 'Ответить',
                labelColor: Colors.white,
                onTap: onReply!,
              ),
              divider(),
            ],
            if (onEdit != null) ...[
              _ActionTile(
                icon: Icons.edit_outlined,
                iconColor: Colors.white.withValues(alpha: 0.80),
                label: 'Редактировать',
                labelColor: Colors.white,
                onTap: onEdit!,
              ),
              divider(),
            ],
            if (onCopy != null) ...[
              _ActionTile(
                icon: Icons.copy_outlined,
                iconColor: Colors.white.withValues(alpha: 0.60),
                label: 'Скопировать текст',
                labelColor: Colors.white.withValues(alpha: 0.90),
                onTap: onCopy!,
              ),
              divider(),
            ],
            _ActionTile(
              icon: Icons.visibility_off_outlined,
              iconColor: Colors.white.withValues(alpha: 0.60),
              label: 'Удалить у себя',
              labelColor: Colors.white.withValues(alpha: 0.90),
              onTap: onDeleteForMe,
            ),
            if (onDeleteForAll != null) ...[
              divider(),
              _ActionTile(
                icon: Icons.delete_outline,
                iconColor: const Color(0xFFFF445A),
                label: 'Удалить у всех',
                labelColor: const Color(0xFFFF445A),
                onTap: onDeleteForAll!,
              ),
            ],
            if (onSelectMultiple != null) ...[
              divider(),
              _ActionTile(
                icon: Icons.checklist_rounded,
                iconColor: Colors.white.withValues(alpha: 0.60),
                label: 'Выбрать несколько',
                labelColor: Colors.white.withValues(alpha: 0.90),
                onTap: onSelectMultiple!,
              ),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final Color labelColor;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.labelColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 14),
            Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: labelColor,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Selection Action Bar
// ═══════════════════════════════════════════════════════════

class _SelectionActionBar extends StatelessWidget {
  final int selectedCount;
  final bool canDeleteForAll;
  final VoidCallback onCancel;
  final VoidCallback? onDeleteForMe;
  final VoidCallback? onDeleteForAll;

  const _SelectionActionBar({
    required this.selectedCount,
    required this.canDeleteForAll,
    required this.onCancel,
    this.onDeleteForMe,
    this.onDeleteForAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white.withValues(alpha: 0.70),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              child: Text(
                'Отмена',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Expanded(
              child: Text(
                selectedCount == 0
                    ? 'Выберите сообщения'
                    : 'Выбрано: $selectedCount',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.60),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (canDeleteForAll)
              IconButton(
                onPressed: onDeleteForAll,
                tooltip: 'Удалить у всех',
                icon: const Icon(
                  Icons.delete_forever_outlined,
                  color: Color(0xFFFF445A),
                ),
              ),
            IconButton(
              onPressed: onDeleteForMe,
              tooltip: 'Удалить у себя',
              icon: Icon(
                Icons.visibility_off_outlined,
                color: onDeleteForMe != null
                    ? Colors.white.withValues(alpha: 0.75)
                    : Colors.white.withValues(alpha: 0.25),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Unread Divider
// ═══════════════════════════════════════════════════════════

class _UnreadDivider extends StatelessWidget {
  const _UnreadDivider();

  @override
  Widget build(BuildContext context) {
    final color = Colors.white.withValues(alpha: 0.26);
    final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFFFB7185),
          fontWeight: FontWeight.w800,
        );

    Widget dash() {
      return Expanded(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = (constraints.maxWidth / 10).floor().clamp(1, 1000);
            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(
                count,
                (_) => Container(width: 6, height: 1.2, color: color),
              ),
            );
          },
        ),
      );
    }

    return Row(
      children: [
        dash(),
        const SizedBox(width: 10),
        Text('Новые сообщения', style: labelStyle),
        const SizedBox(width: 10),
        dash(),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Emoji Picker
// ═══════════════════════════════════════════════════════════

class _ChatEmojiPicker extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback onChanged;

  const _ChatEmojiPicker({
    required this.controller,
    required this.onChanged,
  });

  @override
  State<_ChatEmojiPicker> createState() => _ChatEmojiPickerState();
}

class _ChatEmojiPickerState extends State<_ChatEmojiPicker>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  static const _tabs = ['\u{1F600}', '\u{1F44D}', '\u{1F436}', '\u{1F34E}', '\u26BD', '\u{1F697}', '\u{1F4A1}', '\u2764\uFE0F'];
  static const _tabNames = [
    'Смайлики', 'Жесты', 'Животные', 'Еда',
    'Спорт', 'Транспорт', 'Предметы', 'Символы',
  ];

  static const _emojis = [
    // Смайлики
    [
      '\u{1F600}','\u{1F603}','\u{1F604}','\u{1F601}','\u{1F606}','\u{1F605}','\u{1F923}','\u{1F602}','\u{1F642}','\u{1F643}','\u{1F609}','\u{1F60A}','\u{1F607}',
      '\u{1F970}','\u{1F60D}','\u{1F929}','\u{1F618}','\u{1F617}','\u{1F61A}','\u{1F619}','\u{1F972}','\u{1F60B}','\u{1F61B}','\u{1F61C}','\u{1F92A}','\u{1F61D}',
      '\u{1F911}','\u{1F917}','\u{1F92D}','\u{1F92B}','\u{1F914}','\u{1F910}','\u{1F928}','\u{1F610}','\u{1F611}','\u{1F636}','\u{1F60F}','\u{1F612}','\u{1F644}',
      '\u{1F62C}','\u{1F925}','\u{1F60C}','\u{1F614}','\u{1F62A}','\u{1F924}','\u{1F634}','\u{1F637}','\u{1F912}','\u{1F915}','\u{1F922}','\u{1F92E}','\u{1F927}',
      '\u{1F975}','\u{1F976}','\u{1F974}','\u{1F635}','\u{1F92F}','\u{1F920}','\u{1F978}','\u{1F60E}','\u{1F913}','\u{1F9D0}','\u{1F615}','\u{1F61F}','\u{1F641}',
      '\u2639\uFE0F','\u{1F62E}','\u{1F62F}','\u{1F632}','\u{1F633}','\u{1F97A}','\u{1F626}','\u{1F627}','\u{1F628}','\u{1F630}','\u{1F625}','\u{1F622}','\u{1F62D}',
      '\u{1F631}','\u{1F616}','\u{1F623}','\u{1F61E}','\u{1F613}','\u{1F629}','\u{1F62B}','\u{1F971}','\u{1F624}','\u{1F621}','\u{1F620}','\u{1F92C}','\u{1F608}',
      '\u{1F47F}','\u{1F480}','\u2620\uFE0F','\u{1F4A9}','\u{1F921}','\u{1F479}','\u{1F47A}','\u{1F47B}','\u{1F47D}','\u{1F47E}','\u{1F916}',
    ],
    // Жесты
    [
      '\u{1F44B}','\u{1F91A}','\u{1F590}\uFE0F','\u270B','\u{1F596}','\u{1F44C}','\u{1F90C}','\u{1F90F}','\u270C\uFE0F','\u{1F91E}','\u{1F91F}','\u{1F918}','\u{1F919}',
      '\u{1F448}','\u{1F449}','\u{1F446}','\u{1F447}','\u261D\uFE0F','\u{1F44D}','\u{1F44E}','\u270A','\u{1F44A}','\u{1F91B}','\u{1F91C}','\u{1F44F}','\u{1F64C}',
      '\u{1F450}','\u{1F932}','\u{1F91D}','\u{1F64F}','\u270D\uFE0F','\u{1F485}','\u{1F933}','\u{1F4AA}',
    ],
    // Животные
    [
      '\u{1F436}','\u{1F431}','\u{1F42D}','\u{1F439}','\u{1F430}','\u{1F98A}','\u{1F43B}','\u{1F43C}','\u{1F428}','\u{1F42F}','\u{1F981}','\u{1F42E}','\u{1F437}',
      '\u{1F438}','\u{1F435}','\u{1F648}','\u{1F649}','\u{1F64A}','\u{1F412}','\u{1F414}','\u{1F427}','\u{1F426}','\u{1F424}','\u{1F986}','\u{1F985}','\u{1F989}',
      '\u{1F987}','\u{1F43A}','\u{1F417}','\u{1F434}','\u{1F984}','\u{1F41D}','\u{1F41B}','\u{1F98B}','\u{1F40C}','\u{1F41E}','\u{1F41C}',
    ],
    // Еда
    [
      '\u{1F34E}','\u{1F350}','\u{1F34A}','\u{1F34B}','\u{1F34C}','\u{1F349}','\u{1F347}','\u{1F353}','\u{1F348}','\u{1F352}','\u{1F351}','\u{1F96D}',
      '\u{1F34D}','\u{1F95D}','\u{1F345}','\u{1F346}','\u{1F951}','\u{1F966}','\u{1F952}','\u{1F336}\uFE0F',
      '\u{1F354}','\u{1F355}','\u{1F32D}','\u{1F35F}','\u{1F969}','\u{1F357}','\u{1F356}',
      '\u{1F370}','\u{1F382}','\u{1F36D}','\u{1F36C}','\u{1F36B}','\u{1F37F}','\u{1F369}','\u{1F36A}',
      '\u2615','\u{1F37A}','\u{1F37B}','\u{1F942}','\u{1F377}','\u{1F378}','\u{1F379}','\u{1F37E}',
    ],
    // Спорт
    [
      '\u26BD','\u{1F3C0}','\u{1F3C8}','\u26BE','\u{1F3BE}','\u{1F3D0}','\u{1F3C9}','\u{1F94F}',
      '\u{1F3B1}','\u{1F3C6}','\u{1F947}','\u{1F948}','\u{1F949}','\u{1F3C5}',
      '\u{1F6B4}','\u{1F3CA}','\u{1F3C4}','\u{1F3BF}','\u26F7\uFE0F','\u{1F3CB}\uFE0F',
    ],
    // Транспорт
    [
      '\u{1F697}','\u{1F695}','\u{1F699}','\u{1F68C}','\u{1F3CE}\uFE0F','\u{1F693}','\u{1F691}','\u{1F692}',
      '\u{1F6B2}','\u{1F6F5}','\u{1F3CD}\uFE0F','\u{1F680}','\u2708\uFE0F','\u{1F6F8}','\u{1F681}',
      '\u{1F6A2}','\u26F5','\u{1F6A4}','\u{1F6A8}',
    ],
    // Предметы
    [
      '\u{1F4A1}','\u{1F526}','\u{1F6CF}\uFE0F','\u{1F6CB}\uFE0F',
      '\u{1F381}','\u{1F388}','\u{1F389}','\u{1F38A}',
      '\u{1F3B5}','\u{1F3B6}','\u{1F3A4}','\u{1F3A7}','\u{1F3B7}','\u{1F3B8}','\u{1F3B9}','\u{1F3BA}','\u{1F3BB}','\u{1F941}',
      '\u{1F4F1}','\u{1F4BB}','\u{1F5A5}\uFE0F','\u{1F4F7}','\u{1F4F9}','\u{1F4FA}',
      '\u{1F4B8}','\u{1F4B0}','\u{1F4B3}','\u{1F48E}','\u{1F52E}',
    ],
    // Символы
    [
      '\u2764\uFE0F','\u{1F9E1}','\u{1F49B}','\u{1F49A}','\u{1F499}','\u{1F49C}','\u{1F5A4}','\u{1F90D}','\u{1F90E}','\u{1F494}','\u2763\uFE0F','\u{1F495}','\u{1F49E}',
      '\u{1F493}','\u{1F497}','\u{1F496}','\u{1F498}','\u{1F49D}','\u{1F49F}',
      '\u2714\uFE0F','\u274C','\u2B55','\u{1F6D1}','\u26D4','\u{1F4AF}','\u2757','\u2753','\u203C\uFE0F','\u2049\uFE0F',
      '\u267B\uFE0F','\u2705','\u2728','\u{1F525}','\u{1F4A4}',
    ],
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _insertEmoji(String emoji) {
    final ctrl = widget.controller;
    final text = ctrl.text;
    final sel = ctrl.selection;
    final start = sel.baseOffset < 0 ? text.length : sel.baseOffset;
    final end = sel.extentOffset < 0 ? text.length : sel.extentOffset;
    final newText = text.substring(0, start) + emoji + text.substring(end);
    ctrl.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 260,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF181E2B),
          border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              indicatorColor: const Color(0xFF3B82F6),
              indicatorSize: TabBarIndicatorSize.label,
              dividerColor: Colors.transparent,
              tabs: List.generate(
                _tabs.length,
                (i) => Tooltip(
                  message: _tabNames[i],
                  child: Tab(
                    height: 40,
                    child:
                        Text(_tabs[i], style: const TextStyle(fontSize: 20)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: List.generate(_emojis.length, (catIndex) {
                  final list = _emojis[catIndex];
                  return GridView.builder(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 9,
                      childAspectRatio: 1,
                    ),
                    itemCount: list.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _insertEmoji(list[i]),
                      child: Center(
                        child: Text(list[i],
                            style: const TextStyle(fontSize: 22)),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// Delete Options Sheet (existing - untouched)
// ═══════════════════════════════════════════════════════════

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
