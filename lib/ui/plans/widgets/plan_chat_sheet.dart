import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import '../../../data/plans/plan_details_dto.dart';
import 'plan_chat_message_bubble.dart';

class PlanChatSheet extends StatefulWidget {
  final List<PlanChatMessageDto> items;
  final String currentUserId;
  final Map<String, String> nicknamesByUserId;
  final double availableHeight;

  /// Server-controlled presentation messages.
  ///
  /// If passed, the sheet does not build local preview messages and renders
  /// exactly these items, preserving the approved visual layout.
  final List<PlanChatPresentationMessage>? presentationItems;

  /// Server-controlled unread count for the collapsed header.
  /// In expanded mode the badge is always hidden.
  final int? unreadCountOverride;

  /// Server-controlled send callback. If absent, legacy local preview send is used.
  final Future<void> Function(String text)? onSendMessage;

  /// Notifies parent when sheet expands/collapses.
  final ValueChanged<bool>? onExpandedChanged;

  /// Disable the local unread divider in server-first mode.
  final bool showUnreadDivider;

  /// Disable fake preview generation when there are no messages.
  final bool usePreviewWhenEmpty;

  /// Disable composer while server send is in-flight.
  final bool sending;

  /// Callback для удаления сообщения только у себя.
  final Future<void> Function(String messageId)? onDeleteMessageForMe;

  /// Callback для редактирования сообщения.
  final Future<void> Function(String messageId, String text)? onEditMessage;

  /// Callback для удаления сообщения у всех (tombstone).
  final Future<void> Function(String messageId)? onDeleteMessageForAll;

  const PlanChatSheet({
    super.key,
    required this.items,
    required this.currentUserId,
    required this.nicknamesByUserId,
    required this.availableHeight,
    this.presentationItems,
    this.unreadCountOverride,
    this.onSendMessage,
    this.onExpandedChanged,
    this.showUnreadDivider = true,
    this.usePreviewWhenEmpty = true,
    this.sending = false,
    this.onDeleteMessageForMe,
    this.onEditMessage,
    this.onDeleteMessageForAll,
  });

  @override
  State<PlanChatSheet> createState() => _PlanChatSheetState();
}

class _PlanChatSheetState extends State<PlanChatSheet>
    with WidgetsBindingObserver {
  static const double _kCollapsedHeight = 76;
  static const double _kHeaderHeight = 72;
  static const Duration _kAnimationDuration = Duration(milliseconds: 240);
  static const Duration _kUnreadDividerLifetime = Duration(seconds: 2);
  static const double _kMinExpandedContentHeight = 120;
  static const double _kBottomAutoScrollThreshold = 72;

  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _composerFocusNode = FocusNode();
  final GlobalKey _unreadDividerKey = GlobalKey();

  late List<PlanChatPresentationMessage> _messages;
  bool _expanded = false;
  int _unreadCount = 0;
  int? _unreadStartIndex;
  double _dragOffsetY = 0;

  bool _showTemporaryUnreadDivider = false;
  int? _temporaryUnreadStartIndex;
  Timer? _unreadDividerTimer;

  bool _pendingOwnMessageAutoScroll = false;
  int _scheduledAutoScrollId = 0;
  int _openPositionRequestId = 0;
  int _keyboardAdjustmentRequestId = 0;
  double _lastKeyboardInsetBottom = 0;

  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};

  PlanChatPresentationMessage? _editingMessage;
  PlanChatPresentationMessage? _replyingTo;
  bool _showEmojiPicker = false;
  bool _openingInProgress = false;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  bool get _isServerControlled =>
      widget.presentationItems != null ||
      widget.unreadCountOverride != null ||
      widget.onSendMessage != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _messages = _buildPresentationMessages();
    _syncUnreadStateFromMode(initial: true);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lastKeyboardInsetBottom = MediaQuery.viewInsetsOf(context).bottom;
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;

    final nextKeyboardInsetBottom = _currentKeyboardInsetBottom();
    final keyboardOpened =
        nextKeyboardInsetBottom > _lastKeyboardInsetBottom + 1;
    final shouldKeepBottomAnchored =
        _expanded &&
        (_composerFocusNode.hasFocus ||
            _isNearBottom(
              threshold: _kBottomAutoScrollThreshold + 56,
            ));

    _lastKeyboardInsetBottom = nextKeyboardInsetBottom;

    if (keyboardOpened) {
      if (_showEmojiPicker) {
        setState(() => _showEmojiPicker = false);
      }
      if (shouldKeepBottomAnchored) {
        _scheduleKeyboardInsetAdjustment();
      }
    }
  }

  @override
  void didUpdateWidget(covariant PlanChatSheet oldWidget) {
    super.didUpdateWidget(oldWidget);

    final previousLastMessageId = oldWidget.presentationItems != null &&
            oldWidget.presentationItems!.isNotEmpty
        ? oldWidget.presentationItems!.last.id
        : (_messages.isNotEmpty ? _messages.last.id : null);
    final previousMaxScrollExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final wasNearBottom = _expanded && _isNearBottom();

    final newMessages = _buildPresentationMessages();
    final newLastMessageId = newMessages.isNotEmpty ? newMessages.last.id : null;
    final messagesChanged = !_sameMessages(_messages, newMessages);

    if (messagesChanged) {
      _messages = newMessages;
      _cleanupMessageKeys();
    }

    _syncUnreadStateFromMode(initial: false);

    final shouldAutoScroll =
        _expanded &&
            messagesChanged &&
            previousLastMessageId != newLastMessageId &&
            !_showTemporaryUnreadDivider &&
            (wasNearBottom || _pendingOwnMessageAutoScroll);

    if (shouldAutoScroll) {
      final forceToBottom = _pendingOwnMessageAutoScroll;
      _pendingOwnMessageAutoScroll = false;
      _scheduleAutoScrollAfterUpdate(
        previousMaxScrollExtent: previousMaxScrollExtent,
        forceToBottom: forceToBottom,
      );
    } else if (messagesChanged && _pendingOwnMessageAutoScroll) {
      _pendingOwnMessageAutoScroll = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unreadDividerTimer?.cancel();
    _composerController.dispose();
    _scrollController.dispose();
    _composerFocusNode.dispose();
    super.dispose();
  }

  bool _sameMessages(
    List<PlanChatPresentationMessage> a,
    List<PlanChatPresentationMessage> b,
  ) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.id != right.id ||
          left.text != right.text ||
          left.createdAt != right.createdAt ||
          left.isMine != right.isMine ||
          left.editedAt != right.editedAt ||
          left.messageKind != right.messageKind ||
          left.deletedAt != right.deletedAt ||
          left.nicknameHidden != right.nicknameHidden ||
          left.avatarHidden != right.avatarHidden ||
          left.avatarUrl != right.avatarUrl ||
          left.authorNickname != right.authorNickname) {
        return false;
      }
    }
    return true;
  }

  double _currentKeyboardInsetBottom() {
    final view = View.of(context);
    return MediaQueryData.fromView(view).viewInsets.bottom;
  }

  bool _isNearBottom({double threshold = _kBottomAutoScrollThreshold}) {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels <= threshold;
  }

  void _scheduleAutoScrollAfterUpdate({
    required double previousMaxScrollExtent,
    required bool forceToBottom,
  }) {
    final requestId = ++_scheduledAutoScrollId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _autoScrollAfterUpdate(
          requestId: requestId,
          previousMaxScrollExtent: previousMaxScrollExtent,
          forceToBottom: forceToBottom,
        ),
      );
    });
  }

  void _scheduleKeyboardInsetAdjustment() {
    final requestId = ++_keyboardAdjustmentRequestId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_adjustForKeyboardInset(requestId: requestId));
    });
  }

  Future<void> _adjustForKeyboardInset({required int requestId}) async {
    for (var i = 0; i < 3; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
      if (!mounted || !_expanded || requestId != _keyboardAdjustmentRequestId) {
        return;
      }
      if (!_scrollController.hasClients) {
        continue;
      }

      final position = _scrollController.position;
      final targetOffset = position.maxScrollExtent;
      if ((targetOffset - position.pixels).abs() < 1.0) {
        continue;
      }
      _scrollController.jumpTo(targetOffset);
    }
  }

  Future<void> _autoScrollAfterUpdate({
    required int requestId,
    required double previousMaxScrollExtent,
    required bool forceToBottom,
  }) async {
    if (!mounted || !_scrollController.hasClients) return;
    if (requestId != _scheduledAutoScrollId) return;

    final position = _scrollController.position;
    final previousPixels = position.pixels;
    final newMaxScrollExtent = position.maxScrollExtent;
    final delta = math.max(0.0, newMaxScrollExtent - previousMaxScrollExtent);

    final targetOffset = forceToBottom
        ? newMaxScrollExtent
        : (previousPixels + delta).clamp(0.0, newMaxScrollExtent);

    if ((targetOffset - previousPixels).abs() < 1.0) return;

    if (forceToBottom) {
      _scrollController.jumpTo(targetOffset);
      return;
    }

    await _scrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

  void _syncUnreadStateFromMode({required bool initial}) {
    if (_isServerControlled) {
      _unreadCount = widget.unreadCountOverride ?? 0;
      _unreadStartIndex = null;
      return;
    }

    if (!initial) return;

    if (_messages.isNotEmpty) {
      _unreadCount =
          _messages.length >= 3 ? 3 : (_messages.length >= 2 ? 2 : 1);
      final unreadStartIndex = _messages.length - _unreadCount;
      _unreadStartIndex = unreadStartIndex < 0 ? 0 : unreadStartIndex;
    }
  }

  List<PlanChatPresentationMessage> _buildPresentationMessages() {
    final controlled = widget.presentationItems;
    if (controlled != null) {
      return List<PlanChatPresentationMessage>.from(controlled);
    }

    if (widget.items.isNotEmpty) {
      return widget.items.map((item) {
        final authorUserId = item.authorAppUserId.trim();
        final authorNickname = widget.nicknamesByUserId[authorUserId]?.trim();
        return PlanChatPresentationMessage(
          id: item.id,
          authorUserId: authorUserId,
          authorNickname: (authorNickname == null || authorNickname.isEmpty)
              ? 'Участник'
              : authorNickname,
          text: item.text,
          createdAt: item.createdAt,
          isMine: authorUserId == widget.currentUserId.trim(),
        );
      }).toList();
    }

    if (!widget.usePreviewWhenEmpty) {
      return const <PlanChatPresentationMessage>[];
    }

    final me = widget.currentUserId.trim();
    final allNames = widget.nicknamesByUserId;
    final myNickname = (allNames[me] ?? 'Вы').trim().isEmpty
        ? 'Вы'
        : (allNames[me] ?? 'Вы').trim();

    String? firstOtherUserId;
    String? secondOtherUserId;
    for (final entry in allNames.entries) {
      final entryUserId = entry.key.trim();
      if (entryUserId.isEmpty || entryUserId == me) continue;

      firstOtherUserId ??= entryUserId;
      if (entryUserId != firstOtherUserId) {
        secondOtherUserId ??= entryUserId;
      }
    }

    firstOtherUserId ??= 'preview_member_1';
    secondOtherUserId ??= 'preview_member_2';

    final firstOtherNickname =
        (allNames[firstOtherUserId] ?? 't1').trim().isEmpty
            ? 't1'
            : (allNames[firstOtherUserId] ?? 't1').trim();
    final secondOtherNickname =
        (allNames[secondOtherUserId] ?? 'alex').trim().isEmpty
            ? 'alex'
            : (allNames[secondOtherUserId] ?? 'alex').trim();

    final now = DateTime.now();
    return <PlanChatPresentationMessage>[
      PlanChatPresentationMessage(
        id: 'preview_1',
        authorUserId: firstOtherUserId,
        authorNickname: firstOtherNickname,
        text: 'Давайте определимся по времени, чтобы всем было удобно.',
        createdAt: now.subtract(const Duration(minutes: 34)),
        isMine: false,
      ),
      PlanChatPresentationMessage(
        id: 'preview_2',
        authorUserId: me,
        authorNickname: myNickname,
        text: 'Мне подходит после 20:00, раньше не успею.',
        createdAt: now.subtract(const Duration(minutes: 28)),
        isMine: true,
      ),
      PlanChatPresentationMessage(
        id: 'preview_3',
        authorUserId: secondOtherUserId,
        authorNickname: secondOtherNickname,
        text: 'Я за Тонгал. По локации он самый удобный.',
        createdAt: now.subtract(const Duration(minutes: 16)),
        isMine: false,
      ),
      PlanChatPresentationMessage(
        id: 'preview_4',
        authorUserId: firstOtherUserId,
        authorNickname: firstOtherNickname,
        text: 'Ок, тогда давайте добьем голосование и зафиксируем итог.',
        createdAt: now.subtract(const Duration(minutes: 7)),
        isMine: false,
      ),
    ];
  }

  void _cleanupMessageKeys() {
    final activeIds = _messages.map((message) => message.id).toSet();
    _messageKeys.removeWhere((key, _) => !activeIds.contains(key));
  }

  GlobalKey _keyForMessage(String messageId) {
    return _messageKeys.putIfAbsent(messageId, GlobalKey.new);
  }

  int _currentUnreadCountForOpen() {
    return _isServerControlled
        ? (widget.unreadCountOverride ?? 0)
        : _unreadCount;
  }

  void _prepareOpenAnchorState() {
    _unreadDividerTimer?.cancel();
    _showTemporaryUnreadDivider = false;
    _temporaryUnreadStartIndex = null;

    if (_messages.isEmpty) return;

    final unreadAtOpen = _currentUnreadCountForOpen();
    final shouldShowTemporaryDivider =
        unreadAtOpen > 0 && (_isServerControlled || widget.showUnreadDivider);

    if (!shouldShowTemporaryDivider) {
      return;
    }

    _temporaryUnreadStartIndex = math.max(0, _messages.length - unreadAtOpen);
    _showTemporaryUnreadDivider = true;

    _unreadDividerTimer = Timer(_kUnreadDividerLifetime, () {
      if (!mounted) return;
      setState(() {
        _showTemporaryUnreadDivider = false;
        _temporaryUnreadStartIndex = null;
      });
    });
  }

  void _handleExpandedOpened() {
    _prepareOpenAnchorState();
    final requestId = ++_openPositionRequestId;
    setState(() => _openingInProgress = true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_positionChatOnOpen(requestId: requestId));
    });
  }

  void _handleExpandedClosed() {
    _openPositionRequestId++;
    _keyboardAdjustmentRequestId++;
    _unreadDividerTimer?.cancel();
    final needsUpdate = _showTemporaryUnreadDivider ||
        _temporaryUnreadStartIndex != null ||
        _selectionMode ||
        _replyingTo != null ||
        _showEmojiPicker ||
        _openingInProgress;
    if (needsUpdate) {
      setState(() {
        _showTemporaryUnreadDivider = false;
        _temporaryUnreadStartIndex = null;
        _selectionMode = false;
        _selectedIds.clear();
        _replyingTo = null;
        _showEmojiPicker = false;
        _openingInProgress = false;
      });
    }
  }

  void _dismissKeyboard() {
    if (!_composerFocusNode.hasFocus) return;
    _composerFocusNode.unfocus();
    FocusScope.of(context).unfocus();
  }

  void _setExpandedState(
    bool value, {
    bool dismissKeyboardOnClose = true,
  }) {
    if (_expanded == value) return;

    setState(() => _expanded = value);
    widget.onExpandedChanged?.call(value);

    if (value) {
      _handleExpandedOpened();
      return;
    }

    if (dismissKeyboardOnClose) {
      _dismissKeyboard();
    }
    _handleExpandedClosed();
  }

  void _toggleExpanded() {
    _setExpandedState(!_expanded);
  }

  void _handleHeaderVerticalDragStart(DragStartDetails details) {
    _dragOffsetY = 0;
  }

  void _handleHeaderVerticalDragUpdate(DragUpdateDetails details) {
    _dragOffsetY += details.delta.dy;

    if (!_expanded && _dragOffsetY <= -10) {
      _dragOffsetY = 0;
      _setExpandedState(true);
      return;
    }

    if (_expanded && _dragOffsetY >= 12) {
      _dragOffsetY = 0;
      _setExpandedState(false, dismissKeyboardOnClose: false);
    }
  }

  void _handleHeaderVerticalDragEnd(DragEndDetails details) {
    _dragOffsetY = 0;

    final velocity = details.primaryVelocity ?? 0;
    if (!_expanded && velocity < -220) {
      _setExpandedState(true);
      return;
    }

    if (_expanded && velocity > 220) {
      _setExpandedState(false, dismissKeyboardOnClose: false);
    }
  }

  Future<void> _positionChatOnOpen({required int requestId}) async {
    // Ждём окончания анимации контейнера — в этот момент контент ещё скрыт
    // (AnimatedOpacity = 0), поэтому пользователь не видит промежуточных позиций.
    await Future<void>.delayed(_kAnimationDuration);

    if (!mounted || !_expanded || requestId != _openPositionRequestId) return;

    // Ждём следующего кадра после задержки анимации — это гарантирует, что
    // AnimatedContainer завершил последний rebuild и layout стабилен.
    // Без этого maxScrollExtent может быть вычислен на одну высоту раньше.
    final frameCompleter = Completer<void>();
    WidgetsBinding.instance.addPostFrameCallback((_) => frameCompleter.complete());
    await frameCompleter.future;

    if (!mounted || !_expanded || requestId != _openPositionRequestId) return;

    if (_messages.isNotEmpty && _scrollController.hasClients) {
      final unreadIndex =
          _showTemporaryUnreadDivider ? _temporaryUnreadStartIndex : null;

      if (unreadIndex != null &&
          unreadIndex >= 0 &&
          unreadIndex < _messages.length) {
        await _scrollToMessageIndex(unreadIndex);
      } else {
        await _scrollToBottom();
      }
    }

    // Показываем контент — он уже в правильной позиции.
    if (mounted) setState(() => _openingInProgress = false);
  }

  /// Мгновенное (без анимации) центрирование на сообщении по индексу.
  /// Используется при открытии чата — контент в этот момент скрыт opacity=0,
  /// поэтому прыжки незаметны пользователю.
  Future<void> _scrollToMessageIndex(int index) async {
    if (!mounted || !_scrollController.hasClients || _messages.isEmpty) return;

    final clampedIndex = index.clamp(0, _messages.length - 1);
    final position = _scrollController.position;
    final denominator = math.max(1, _messages.length - 1);
    final approximateOffset =
        position.maxScrollExtent * (clampedIndex / denominator);

    // Прыжок к приблизительной позиции → виджет оказывается в viewport.
    _scrollController.jumpTo(
      approximateOffset.clamp(0.0, position.maxScrollExtent),
    );

    // Один кадр для пересчёта layout.
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted || !_scrollController.hasClients) return;

    // Точное позиционирование через render-контекст (мгновенно, duration=0).
    final BuildContext? targetContext =
        _unreadDividerKey.currentContext ??
        _keyForMessage(_messages[clampedIndex].id).currentContext;

    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        alignment: 0.5,
        // duration = 0 по умолчанию → jumpTo внутри
      );
      return;
    }

    // Fallback: остаёмся на приблизительной позиции.
    _scrollController.jumpTo(
      approximateOffset.clamp(0.0, position.maxScrollExtent),
    );
  }

  Future<void> _scrollToBottom() async {
    if (!mounted || !_scrollController.hasClients) return;
    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
  }

  void _markUnreadAsRead() {
    if (_isServerControlled) return;
    if (_unreadCount == 0) return;
    setState(() {
      _unreadCount = 0;
      _unreadStartIndex = null;
    });
  }

  void _restoreComposerFocus() {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      FocusScope.of(context).requestFocus(_composerFocusNode);
    });
  }

  Future<void> _sendPreviewMessage() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;

    final currentUserId = widget.currentUserId.trim();
    final currentNickname =
        (widget.nicknamesByUserId[currentUserId] ?? 'Вы').trim().isEmpty
            ? 'Вы'
            : (widget.nicknamesByUserId[currentUserId] ?? 'Вы').trim();
    final previousMaxScrollExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    setState(() {
      _messages = List<PlanChatPresentationMessage>.from(_messages)
        ..add(
          PlanChatPresentationMessage(
            id: 'local_${DateTime.now().microsecondsSinceEpoch}',
            authorUserId: currentUserId,
            authorNickname: currentNickname,
            text: text,
            createdAt: DateTime.now(),
            isMine: true,
          ),
        );
      _composerController.clear();
      _unreadCount = 0;
      _unreadStartIndex = null;
    });

    _restoreComposerFocus();
    _scheduleAutoScrollAfterUpdate(
      previousMaxScrollExtent: previousMaxScrollExtent,
      forceToBottom: true,
    );
  }

  void _enterEditMode(PlanChatPresentationMessage message) {
    setState(() {
      _editingMessage = message;
      _composerController.text = message.text;
      _composerController.selection = TextSelection.fromPosition(
        TextPosition(offset: _composerController.text.length),
      );
    });
    _restoreComposerFocus();
  }

  void _exitEditMode() {
    setState(() {
      _editingMessage = null;
      _composerController.clear();
    });
  }

  void _enterSelectionMode(String firstMessageId) {
    _dismissKeyboard();
    setState(() {
      _editingMessage = null;
      _composerController.clear();
      _selectionMode = true;
      _selectedIds.clear();
      _selectedIds.add(firstMessageId);
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _enterReplyMode(PlanChatPresentationMessage message) {
    setState(() {
      _replyingTo = message;
      _showEmojiPicker = false;
    });
    _restoreComposerFocus();
  }

  void _exitReplyMode() {
    setState(() => _replyingTo = null);
  }

  void _toggleEmojiPicker() {
    setState(() {
      _showEmojiPicker = !_showEmojiPicker;
    });
    if (_showEmojiPicker) {
      _composerFocusNode.unfocus();
      FocusScope.of(context).unfocus();
    } else {
      _restoreComposerFocus();
    }
  }

  void _toggleMessageSelection(String messageId) {
    setState(() {
      if (_selectedIds.contains(messageId)) {
        _selectedIds.remove(messageId);
      } else {
        _selectedIds.add(messageId);
      }
    });
  }

  bool get _canDeleteSelectedForAll {
    if (_selectedIds.isEmpty) return false;
    return _messages
        .where((m) => _selectedIds.contains(m.id))
        .every((m) => m.isMine && !m.isTombstone);
  }

  Future<void> _handleBulkDeleteForMe() async {
    final ids = List<String>.from(_selectedIds);
    _exitSelectionMode();
    final deleteForMe = widget.onDeleteMessageForMe;
    if (deleteForMe == null) return;
    for (final id in ids) {
      await deleteForMe(id);
    }
  }

  Future<void> _handleBulkDeleteForAll() async {
    final ids = List<String>.from(_selectedIds);
    _exitSelectionMode();
    final deleteForAll = widget.onDeleteMessageForAll;
    if (deleteForAll == null) return;
    for (final id in ids) {
      await deleteForAll(id);
    }
  }

  Future<void> _showMessageActions(
    PlanChatPresentationMessage message,
  ) async {
    final deleteForMe = widget.onDeleteMessageForMe;
    if (deleteForMe == null) return;

    final canReply =
        widget.onSendMessage != null && !message.isTombstone;

    final canEdit = widget.onEditMessage != null &&
        message.isMine &&
        !message.isTombstone;

    final canDeleteForAll = widget.onDeleteMessageForAll != null &&
        message.isMine &&
        !message.isTombstone;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _MessageActionSheet(
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
          onCopy: !message.isTombstone
              ? () {
                  Clipboard.setData(ClipboardData(text: message.text));
                  Navigator.of(context).pop();
                }
              : null,
          onDeleteForMe: () async {
            Navigator.of(context).pop();
            await deleteForMe(message.id);
          },
          onDeleteForAll: canDeleteForAll
              ? () async {
                  Navigator.of(context).pop();
                  await widget.onDeleteMessageForAll!(message.id);
                }
              : null,
          onSelectMultiple: message.isTombstone
              ? null
              : () {
                  Navigator.of(context).pop();
                  _enterSelectionMode(message.id);
                },
        );
      },
    );
  }

  Future<void> _handleSendPressed() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || widget.sending) return;

    final editingMessage = _editingMessage;
    if (editingMessage != null) {
      final editMessage = widget.onEditMessage;
      if (editMessage == null) return;

      _exitEditMode();
      try {
        await editMessage(editingMessage.id, text);
      } catch (_) {
        if (!mounted) return;
        _enterEditMode(editingMessage);
      }
      return;
    }

    // Формируем текст с цитатой, если идёт ответ
    final replyingTo = _replyingTo;
    final String finalText;
    if (replyingTo != null) {
      final author = replyingTo.authorNickname;
      // Стрипаем вложенную цитату — берём только тело сообщения
      var raw = replyingTo.text;
      const quoteEnd = ' »\n';
      final qIdx = raw.indexOf(quoteEnd);
      if ((raw.startsWith('« @') || raw.startsWith('« ')) && qIdx != -1) {
        raw = raw.substring(qIdx + quoteEnd.length);
      }
      final quoted = raw.length > 80 ? '${raw.substring(0, 80)}…' : raw;
      finalText = '« @$author: $quoted »\n$text';
    } else {
      finalText = text;
    }

    final sendMessage = widget.onSendMessage;
    if (sendMessage == null) {
      if (replyingTo != null) {
        setState(() => _replyingTo = null);
        _composerController.text = finalText;
      }
      await _sendPreviewMessage();
      return;
    }

    setState(() => _replyingTo = null);
    _pendingOwnMessageAutoScroll = true;
    _composerController.clear();
    setState(() {});
    _restoreComposerFocus();

    try {
      await sendMessage(finalText);
    } catch (_) {
      if (!mounted) return;
      _pendingOwnMessageAutoScroll = false;
      _composerController.text = text;
      _composerController.selection = TextSelection.fromPosition(
        TextPosition(offset: _composerController.text.length),
      );
      _restoreComposerFocus();
      setState(() {});
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = (widget.availableHeight
            .clamp(_kCollapsedHeight, widget.availableHeight) as num)
        .toDouble();
    final targetHeight = _expanded ? maxHeight : _kCollapsedHeight;
    final headerUnreadCount = _expanded
        ? 0
        : (_isServerControlled
            ? (widget.unreadCountOverride ?? 0)
            : _unreadCount);

    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: keyboardInset),
      child: Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: _kAnimationDuration,
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: targetHeight,
        decoration: BoxDecoration(
          color: const Color(0xB8181E27),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withValues(alpha: 0.055),
              Colors.white.withValues(alpha: 0.015),
            ],
          ),
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
            child: Column(
              children: [
                _PlanChatHeader(
                  unreadCount: headerUnreadCount,
                  onTap: _toggleExpanded,
                  onVerticalDragStart: _handleHeaderVerticalDragStart,
                  onVerticalDragUpdate: _handleHeaderVerticalDragUpdate,
                  onVerticalDragEnd: _handleHeaderVerticalDragEnd,
                ),
                if (_expanded)
                  Expanded(
                    child: ClipRect(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxHeight <
                              _kMinExpandedContentHeight) {
                            return const SizedBox.expand();
                          }

                          return AnimatedOpacity(
                            opacity: _openingInProgress ? 0.0 : 1.0,
                            duration: const Duration(milliseconds: 100),
                            child: Column(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.translucent,
                                  onTap: _dismissKeyboard,
                                  child: NotificationListener<ScrollNotification>(
                                    onNotification: (notification) {
                                      if (!_isServerControlled &&
                                          _unreadCount > 0 &&
                                          notification
                                              is ScrollUpdateNotification) {
                                        _markUnreadAsRead();
                                      }
                                      return false;
                                    },
                                    child: ListView.separated(
                                      keyboardDismissBehavior:
                                          ScrollViewKeyboardDismissBehavior
                                              .onDrag,
                                      controller: _scrollController,
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        8,
                                        14,
                                        14,
                                      ),
                                      itemCount: _messages.length,
                                      separatorBuilder: (_, __) =>
                                          const SizedBox(height: 10),
                                      itemBuilder: (context, index) {
                                        final showUnreadDivider =
                                            (_showTemporaryUnreadDivider &&
                                                    _temporaryUnreadStartIndex !=
                                                        null &&
                                                    index ==
                                                        _temporaryUnreadStartIndex) ||
                                                (!_isServerControlled &&
                                                    widget.showUnreadDivider &&
                                                    _unreadStartIndex != null &&
                                                    _unreadCount > 0 &&
                                                    index == _unreadStartIndex);

                                        final message = _messages[index];
                                        return KeyedSubtree(
                                          key: _keyForMessage(message.id),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              if (showUnreadDivider)
                                                KeyedSubtree(
                                                  key: _unreadDividerKey,
                                                  child:
                                                      const _UnreadMessagesDivider(),
                                                ),
                                              if (showUnreadDivider)
                                                const SizedBox(height: 10),
                                              if (_selectionMode &&
                                                  !message.isTombstone)
                                                GestureDetector(
                                                  behavior: HitTestBehavior
                                                      .opaque,
                                                  onTap: () =>
                                                      _toggleMessageSelection(
                                                    message.id,
                                                  ),
                                                  child: Row(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .center,
                                                    children: [
                                                      SizedBox(
                                                        width: 32,
                                                        child: AnimatedScale(
                                                          scale: _selectedIds
                                                                  .contains(
                                                                    message.id,
                                                                  )
                                                              ? 1.0
                                                              : 0.85,
                                                          duration: const Duration(
                                                            milliseconds: 150,
                                                          ),
                                                          child: Checkbox(
                                                            value: _selectedIds
                                                                .contains(
                                                              message.id,
                                                            ),
                                                            onChanged: (_) =>
                                                                _toggleMessageSelection(
                                                              message.id,
                                                            ),
                                                            shape:
                                                                RoundedRectangleBorder(
                                                              borderRadius:
                                                                  BorderRadius
                                                                      .circular(
                                                                6,
                                                              ),
                                                            ),
                                                            side: BorderSide(
                                                              color: Colors
                                                                  .white
                                                                  .withValues(alpha: 
                                                                0.40,
                                                              ),
                                                            ),
                                                            activeColor:
                                                                const Color(
                                                              0xFF3B82F6,
                                                            ),
                                                            checkColor:
                                                                Colors.white,
                                                            materialTapTargetSize:
                                                                MaterialTapTargetSize
                                                                    .shrinkWrap,
                                                            visualDensity:
                                                                VisualDensity
                                                                    .compact,
                                                          ),
                                                        ),
                                                      ),
                                                      Expanded(
                                                        child:
                                                            PlanChatMessageBubble(
                                                          message: message,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              else
                                                PlanChatMessageBubble(
                                                  message: message,
                                                  onLongPress: widget
                                                              .onDeleteMessageForMe !=
                                                          null
                                                      ? () => unawaited(
                                                            _showMessageActions(
                                                              message,
                                                            ),
                                                          )
                                                      : null,
                                                ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                              if (_selectionMode)
                                _SelectionActionBar(
                                  selectedCount: _selectedIds.length,
                                  canDeleteForAll: _canDeleteSelectedForAll,
                                  onCancel: _exitSelectionMode,
                                  onDeleteForMe: _selectedIds.isEmpty
                                      ? null
                                      : () => unawaited(
                                            _handleBulkDeleteForMe(),
                                          ),
                                  onDeleteForAll: _canDeleteSelectedForAll
                                      ? () => unawaited(
                                            _handleBulkDeleteForAll(),
                                          )
                                      : null,
                                )
                              else ...[
                                if (_editingMessage != null)
                                  _PlanChatEditBanner(
                                    onCancel: _exitEditMode,
                                  ),
                                if (_replyingTo != null)
                                  _PlanChatReplyBanner(
                                    message: _replyingTo!,
                                    onCancel: _exitReplyMode,
                                  ),
                                _PlanChatComposer(
                                  controller: _composerController,
                                  focusNode: _composerFocusNode,
                                  sending: widget.sending,
                                  showEmojiPicker: _showEmojiPicker,
                                  onChanged: () => setState(() {}),
                                  onSend: _handleSendPressed,
                                  onTapInside: _markUnreadAsRead,
                                  onEmojiToggle: _toggleEmojiPicker,
                                ),
                                if (_showEmojiPicker)
                                  _ChatEmojiPicker(
                                    controller: _composerController,
                                    onChanged: () => setState(() {}),
                                  ),
                              ],
                            ],
                          ),
                          ); // AnimatedOpacity
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }
}

class _PlanChatHeader extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;

  const _PlanChatHeader({
    required this.unreadCount,
    required this.onTap,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      child: InkWell(
        onTap: onTap,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        customBorder: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SizedBox(
          height: _PlanChatSheetState._kHeaderHeight,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 72,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.40),
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: Center(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Text(
                        'Чат',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 28,
                          letterSpacing: 0.1,
                          color: Colors.white.withValues(alpha: 0.96),
                        ),
                      ),
                      if (unreadCount > 0)
                        Positioned(
                          right: -24,
                          top: -5,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 24,
                              minHeight: 24,
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF445A),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: const Color(0xB8181E27),
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              unreadCount > 99 ? '99+' : unreadCount.toString(),
                              textAlign: TextAlign.center,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                                height: 1.0,
                              ),
                            ),
                          ),
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

class _UnreadMessagesDivider extends StatelessWidget {
  const _UnreadMessagesDivider();

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
                (_) => Container(
                  width: 6,
                  height: 1.2,
                  color: color,
                ),
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

class _PlanChatComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final bool showEmojiPicker;
  final VoidCallback onChanged;
  final VoidCallback onSend;
  final VoidCallback onTapInside;
  final VoidCallback onEmojiToggle;

  const _PlanChatComposer({
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
                  enabled: true,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.newline,
                  onChanged: (_) => onChanged(),
                  onTap: onTapInside,
                  decoration: InputDecoration(
                    hintText: 'Напишите сообщение…',
                    filled: true,
                    fillColor: theme.colorScheme.surface.withValues(alpha: 0.90),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide:
                          BorderSide(color: Colors.white.withValues(alpha: 0.10)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide:
                          BorderSide(color: Colors.white.withValues(alpha: 0.10)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: const BorderSide(color: Color(0xFF3B82F6)),
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
    );
  }
}

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
    final hasReply = onReply != null;
    final hasEdit = onEdit != null;
    final hasDeleteForAll = onDeleteForAll != null;
    final hasSelectMultiple = onSelectMultiple != null;

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
          colors: [
            Color(0xFF252D3D),
            Color(0xFF181E2B),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.13)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: Colors.white.withValues(alpha: 0.04),
            blurRadius: 0,
            spreadRadius: 0,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            if (hasReply) ...[
              _ActionTile(
                icon: Icons.reply_outlined,
                iconColor: const Color(0xFF7FB0FF),
                label: 'Ответить',
                labelColor: Colors.white,
                onTap: onReply!,
              ),
              divider(),
            ],
            if (hasEdit) ...[
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
            if (hasDeleteForAll) ...[
              divider(),
              _ActionTile(
                icon: Icons.delete_outline,
                iconColor: const Color(0xFFFF445A),
                label: 'Удалить у всех',
                labelColor: const Color(0xFFFF445A),
                onTap: onDeleteForAll!,
              ),
            ],
            if (hasSelectMultiple) ...[
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
      child: Row(
        children: [
          TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white.withValues(alpha: 0.70),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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

class _PlanChatEditBanner extends StatelessWidget {
  final VoidCallback onCancel;

  const _PlanChatEditBanner({required this.onCancel});

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
          const Icon(
            Icons.edit_outlined,
            size: 16,
            color: Color(0xFF7FB0FF),
          ),
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
            child: const Icon(
              Icons.close,
              size: 18,
              color: Colors.white54,
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════
// Reply banner
// ══════════════════════════════════════════════════════════

class _PlanChatReplyBanner extends StatelessWidget {
  final PlanChatPresentationMessage message;
  final VoidCallback onCancel;

  const _PlanChatReplyBanner({
    required this.message,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final quoted = message.text.length > 80
        ? '${message.text.substring(0, 80)}…'
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
                  message.authorNickname,
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

// ══════════════════════════════════════════════════════════
// Emoji picker
// ══════════════════════════════════════════════════════════

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

  static const _tabs = ['😀', '👍', '🐶', '🍎', '⚽', '🚗', '💡', '❤️'];
  static const _tabNames = [
    'Смайлики',
    'Жесты',
    'Животные',
    'Еда',
    'Спорт',
    'Транспорт',
    'Предметы',
    'Символы',
  ];

  static const _emojis = [
    // Смайлики
    [
      '😀','😃','😄','😁','😆','😅','🤣','😂','🙂','🙃','😉','😊','😇',
      '🥰','😍','🤩','😘','😗','😚','😙','🥲','😋','😛','😜','🤪','😝',
      '🤑','🤗','🤭','🤫','🤔','🤐','🤨','😐','😑','😶','😏','😒','🙄',
      '😬','🤥','😌','😔','😪','🤤','😴','😷','🤒','🤕','🤢','🤮','🤧',
      '🥵','🥶','🥴','😵','🤯','🤠','🥸','😎','🤓','🧐','😕','😟','🙁',
      '☹️','😮','😯','😲','😳','🥺','😦','😧','😨','😰','😥','😢','😭',
      '😱','😖','😣','😞','😓','😩','😫','🥱','😤','😡','😠','🤬','😈',
      '👿','💀','☠️','💩','🤡','👹','👺','👻','👽','👾','🤖',
    ],
    // Жесты
    [
      '👋','🤚','🖐️','✋','🖖','👌','🤌','🤏','✌️','🤞','🤟','🤘','🤙',
      '👈','👉','👆','👇','☝️','👍','👎','✊','👊','🤛','🤜','👏','🙌',
      '👐','🤲','🤝','🙏','✍️','💅','🤳','💪','🦾','🦵','🦶','👂','👃',
      '👀','👁️','👅','👄','💋','🫀','🫁',
    ],
    // Животные
    [
      '🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷',
      '🐸','🐵','🙈','🙉','🙊','🐒','🐔','🐧','🐦','🐤','🦆','🦅','🦉',
      '🦇','🐺','🐗','🐴','🦄','🐝','🐛','🦋','🐌','🐞','🐜','🦟','🦗',
      '🕷️','🦂','🐢','🐍','🦎','🐙','🦑','🦐','🦞','🦀','🐡','🐟','🐠',
      '🐬','🐳','🐋','🦈','🐊','🐅','🐆','🦓','🦍','🐘','🦏','🦛','🦒',
      '🦘','🐃','🐂','🐄','🐎','🐖','🐏','🐑','🦙','🐐','🦌','🐕','🐩',
      '🐈','🐓','🦃','🦚','🦜','🦢','🦩','🕊️','🐇','🦝','🦨','🦡','🦦',
      '🦥','🐁','🐀','🐿️','🦔',
    ],
    // Еда
    [
      '🍎','🍐','🍊','🍋','🍌','🍉','🍇','🍓','🫐','🍈','🍒','🍑','🥭',
      '🍍','🥥','🥝','🍅','🍆','🥑','🥦','🥬','🥒','🌶️','🫑','🧄','🧅',
      '🥔','🍠','🥐','🥯','🍞','🥖','🥨','🧀','🥚','🍳','🧈','🥞','🧇',
      '🥓','🥩','🍗','🍖','🌭','🍔','🍟','🍕','🥪','🥙','🧆','🌮','🌯',
      '🫔','🥗','🥘','🫕','🥫','🍝','🍜','🍲','🍛','🍣','🍱','🥟','🦪',
      '🍤','🍙','🍚','🍘','🍥','🥮','🍢','🧁','🍰','🎂','🍮','🍭','🍬',
      '🍫','🍿','🍩','🍪','🌰','🥜','🫘','🍯','🧃','🥤','🧋','☕','🫖',
      '🍵','🧉','🍺','🍻','🥂','🍷','🥃','🍸','🍹','🍾','🧊',
    ],
    // Спорт
    [
      '⚽','🏀','🏈','⚾','🥎','🏐','🏉','🥏','🎾','🏸','🏒','🏑','🥍',
      '🏏','🪃','🥊','🥋','🥅','⛳','🏹','🎣','🤿','🥌','🎿','⛷️','🏂',
      '🪂','🏋️','🤼','🤸','⛹️','🤺','🏇','🧘','🏄','🏊','🤽','🚣','🧗',
      '🚵','🚴','🏆','🥇','🥈','🥉','🏅','🎖️','🎗️','🎟️','🎫','🎪',
    ],
    // Транспорт
    [
      '🚗','🚕','🚙','🚌','🚎','🏎️','🚓','🚑','🚒','🚐','🛻','🚚','🚛',
      '🚜','🛴','🚲','🛵','🏍️','🚨','🚔','🚍','🚘','🚖','🚡','🚠','🚟',
      '🚃','🚋','🚞','🚝','🚄','🚅','🚈','🚂','🚆','🚇','🚊','🚉','✈️',
      '🛫','🛬','🛩️','💺','🛰️','🚀','🛸','🚁','🛶','⛵','🚤','🛥️','🛳️',
      '⛴️','🚢','⚓','⛽','🚧','🚦','🚥','🗺️','🗿','🗽','🗼','🏰','🏯',
      '🏟️','🎡','🎢','🎠','⛲','⛺','🌁','🌃','🏙️','🌄','🌅','🌆','🌇',
      '🌉','🌌','🌠','🎇','🎆','🌋','🏔️','⛰️','🗻','🏕️','🏖️','🏜️','🏝️',
      '🏞️',
    ],
    // Предметы
    [
      '💡','🔦','🕯️','🧱','🛏️','🛋️','🪑','🚽','🚿','🛁','🪤','🧴','🧷',
      '🧹','🧺','🧻','🪣','🧼','🧽','🪒','💈','🛒','🚪','🧲','🖼️','🪆',
      '🎎','🎏','🎐','🧧','🎀','🎁','🎈','🎉','🎊','🎋','🎍','🎑','🎃',
      '🎆','🎇','🧨','✨','🎼','🎵','🎶','🎙️','🎤','🎧','📻','🎷','🪗',
      '🎸','🎹','🎺','🎻','🥁','🪘','📱','💻','⌨️','🖥️','🖨️','🖱️','💽',
      '💾','💿','📀','📷','📸','📹','🎥','📽️','📞','☎️','📺','📡','🔋',
      '🪫','🔌','💸','💵','💴','💶','💷','💰','💳','💎','⚖️','🔧','🪛',
      '🔨','⚒️','🛠️','⛏️','🪚','🔩','🧰','🪜','🔮','🪄','🎱','🧿',
    ],
    // Символы
    [
      '❤️','🧡','💛','💚','💙','💜','🖤','🤍','🤎','💔','❣️','💕','💞',
      '💓','💗','💖','💘','💝','💟','☮️','✝️','☪️','🕉️','☸️','✡️','🔯',
      '🕎','☯️','☦️','🛐','⛎','♈','♉','♊','♋','♌','♍','♎','♏','♐',
      '♑','♒','♓','🆔','⚛️','☢️','☣️','📴','📳','🈶','🈚','🈸','🈺',
      '🈷️','✴️','🆚','💮','🉐','㊙️','㊗️','🈴','🈵','🈹','🈲','🅰️','🅱️',
      '🆎','🆑','🅾️','🆘','❌','⭕','🛑','⛔','📛','🚫','💯','💢','♨️',
      '🚷','🚯','🚳','🚱','🔞','📵','🚭','❗','❕','❓','❔','‼️','⁉️',
      '🔅','🔆','〽️','⚠️','🔱','⚜️','🔰','♻️','✅','❇️','✳️','❎','🌐',
      '💠','🌀','💤','🏧','🚾','♿','🅿️','🛗','🛂','🛃','🛄','🛅',
      '🚹','🚺','🚼','🚻','🚮','🎦','📶','🈁','🔣','🔤','🔡','🔠',
      '🆙','🆒','🆕','🆓','🔟','#️⃣','*️⃣','0️⃣','1️⃣','2️⃣','3️⃣',
      '4️⃣','5️⃣','6️⃣','7️⃣','8️⃣','9️⃣',
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
                    child: Text(_tabs[i], style: const TextStyle(fontSize: 20)),
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
                      horizontal: 8,
                      vertical: 4,
                    ),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 9,
                      childAspectRatio: 1,
                    ),
                    itemCount: list.length,
                    itemBuilder: (_, i) => GestureDetector(
                      onTap: () => _insertEmoji(list[i]),
                      child: Center(
                        child: Text(
                          list[i],
                          style: const TextStyle(fontSize: 22),
                        ),
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
