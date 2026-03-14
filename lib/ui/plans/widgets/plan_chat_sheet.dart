import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

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

    if (keyboardOpened && shouldKeepBottomAnchored) {
      _scheduleKeyboardInsetAdjustment();
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
          left.deletedAt != right.deletedAt) {
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
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_positionChatOnOpen(requestId: requestId));
    });
  }

  void _handleExpandedClosed() {
    _openPositionRequestId++;
    _keyboardAdjustmentRequestId++;
    _unreadDividerTimer?.cancel();
    if (_showTemporaryUnreadDivider || _temporaryUnreadStartIndex != null) {
      setState(() {
        _showTemporaryUnreadDivider = false;
        _temporaryUnreadStartIndex = null;
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
    if (_messages.isEmpty) return;

    final unreadIndex =
        _showTemporaryUnreadDivider ? _temporaryUnreadStartIndex : null;

    if (unreadIndex != null &&
        unreadIndex >= 0 &&
        unreadIndex < _messages.length) {
      await Future<void>.delayed(_kAnimationDuration);
      if (!mounted || !_expanded || requestId != _openPositionRequestId) {
        return;
      }
      await _scrollToMessageIndex(unreadIndex);
      return;
    }

    await _scrollToBottom();
  }

  Future<void> _scrollToMessageIndex(int index) async {
    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted || !_scrollController.hasClients || _messages.isEmpty) return;

    final clampedIndex = index.clamp(0, _messages.length - 1);
    final position = _scrollController.position;
    final denominator = math.max(1, _messages.length - 1);
    final approximateOffset =
        position.maxScrollExtent * (clampedIndex / denominator);

    _scrollController.jumpTo(
      approximateOffset.clamp(0.0, position.maxScrollExtent),
    );

    await Future<void>.delayed(const Duration(milliseconds: 16));
    if (!mounted || !_scrollController.hasClients) return;

    final BuildContext? targetContext =
        _unreadDividerKey.currentContext ??
        _keyForMessage(_messages[clampedIndex].id).currentContext;

    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.5,
      );
      return;
    }

    await _scrollController.animateTo(
      approximateOffset.clamp(0.0, position.maxScrollExtent),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _scrollToBottom() async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted || !_scrollController.hasClients) return;
    await _scrollController.animateTo(
      _scrollController.position.maxScrollExtent,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
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

  Future<void> _showMessageActions(
    PlanChatPresentationMessage message,
  ) async {
    final deleteForMe = widget.onDeleteMessageForMe;
    if (deleteForMe == null) return;

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
          onEdit: canEdit
              ? () {
                  Navigator.of(context).pop();
                  _enterEditMode(message);
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

    final sendMessage = widget.onSendMessage;
    if (sendMessage == null) {
      await _sendPreviewMessage();
      return;
    }

    _pendingOwnMessageAutoScroll = true;
    _composerController.clear();
    setState(() {});
    _restoreComposerFocus();

    try {
      await sendMessage(text);
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

    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedContainer(
        duration: _kAnimationDuration,
        curve: Curves.easeOutCubic,
        width: double.infinity,
        height: targetHeight,
        decoration: BoxDecoration(
          color: const Color(0xB8181E27),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white.withOpacity(0.055),
              Colors.white.withOpacity(0.015),
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

                          return Column(
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
                              if (_editingMessage != null)
                                _PlanChatEditBanner(
                                  onCancel: _exitEditMode,
                                ),
                              _PlanChatComposer(
                                controller: _composerController,
                                focusNode: _composerFocusNode,
                                sending: widget.sending,
                                onChanged: () => setState(() {}),
                                onSend: _handleSendPressed,
                                onTapInside: _markUnreadAsRead,
                              ),
                            ],
                          );
                        },
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
                    color: Colors.white.withOpacity(0.40),
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
                          color: Colors.white.withOpacity(0.96),
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
    final color = Colors.white.withOpacity(0.26);
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
  final VoidCallback onChanged;
  final VoidCallback onSend;
  final VoidCallback onTapInside;

  const _PlanChatComposer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onChanged,
    required this.onSend,
    required this.onTapInside,
  });

  @override
  Widget build(BuildContext context) {
    final canSend = !sending && controller.text.trim().isNotEmpty;
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.08),
          border: Border(
            top: BorderSide(color: Colors.white.withOpacity(0.08)),
          ),
        ),
        child: TextFieldTapRegion(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
                    fillColor: theme.colorScheme.surface.withOpacity(0.90),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.10)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide:
                          BorderSide(color: Colors.white.withOpacity(0.10)),
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
  final VoidCallback? onEdit;
  final Future<void> Function() onDeleteForMe;
  final Future<void> Function()? onDeleteForAll;

  const _MessageActionSheet({
    required this.onDeleteForMe,
    this.onEdit,
    this.onDeleteForAll,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF1C2333),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          if (onEdit != null)
            ListTile(
              leading: const Icon(
                Icons.edit_outlined,
                color: Colors.white70,
              ),
              title: Text(
                'Редактировать',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: Colors.white,
                ),
              ),
              onTap: onEdit,
            ),
          ListTile(
            leading: const Icon(
              Icons.visibility_off_outlined,
              color: Colors.white70,
            ),
            title: Text(
              'Удалить у себя',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: Colors.white,
              ),
            ),
            onTap: onDeleteForMe,
          ),
          if (onDeleteForAll != null)
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                color: Color(0xFFFF445A),
              ),
              title: Text(
                'Удалить у всех',
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: const Color(0xFFFF445A),
                ),
              ),
              onTap: onDeleteForAll,
            ),
          const SizedBox(height: 8),
        ],
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
        color: Colors.black.withOpacity(0.12),
        border: Border(
          top: BorderSide(color: Colors.white.withOpacity(0.08)),
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
