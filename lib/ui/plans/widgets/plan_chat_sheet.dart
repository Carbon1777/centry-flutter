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
  });

  @override
  State<PlanChatSheet> createState() => _PlanChatSheetState();
}

class _PlanChatSheetState extends State<PlanChatSheet> {
  static const double _kCollapsedHeight = 76;
  static const double _kHeaderHeight = 72;
  static const Duration _kAnimationDuration = Duration(milliseconds: 240);
  static const Duration _kUnreadDividerLifetime = Duration(seconds: 2);
  static const double _kMinExpandedContentHeight = 120;

  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _unreadDividerKey = GlobalKey();

  late List<PlanChatPresentationMessage> _messages;
  bool _expanded = false;
  int _unreadCount = 0;
  int? _unreadStartIndex;
  double _dragOffsetY = 0;

  bool _showTemporaryUnreadDivider = false;
  int? _temporaryUnreadStartIndex;
  Timer? _unreadDividerTimer;

  final Map<String, GlobalKey> _messageKeys = <String, GlobalKey>{};

  bool get _isServerControlled =>
      widget.presentationItems != null ||
      widget.unreadCountOverride != null ||
      widget.onSendMessage != null;

  @override
  void initState() {
    super.initState();
    _messages = _buildPresentationMessages();
    _syncUnreadStateFromMode(initial: true);
  }

  @override
  void didUpdateWidget(covariant PlanChatSheet oldWidget) {
    super.didUpdateWidget(oldWidget);

    final previousLastMessageId = oldWidget.presentationItems != null &&
            oldWidget.presentationItems!.isNotEmpty
        ? oldWidget.presentationItems!.last.id
        : (_messages.isNotEmpty ? _messages.last.id : null);

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
            !_showTemporaryUnreadDivider;

    if (shouldAutoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_scrollToBottom());
      });
    }
  }

  @override
  void dispose() {
    _unreadDividerTimer?.cancel();
    _composerController.dispose();
    _scrollController.dispose();
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
          left.isMine != right.isMine) {
        return false;
      }
    }
    return true;
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
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_positionChatOnOpen());
    });
  }

  void _handleExpandedClosed() {
    _unreadDividerTimer?.cancel();
    if (_showTemporaryUnreadDivider || _temporaryUnreadStartIndex != null) {
      setState(() {
        _showTemporaryUnreadDivider = false;
        _temporaryUnreadStartIndex = null;
      });
    }
  }

  void _toggleExpanded() {
    final nextExpanded = !_expanded;
    setState(() => _expanded = nextExpanded);
    widget.onExpandedChanged?.call(nextExpanded);
    if (!nextExpanded) {
      _handleExpandedClosed();
      return;
    }
    _handleExpandedOpened();
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    _dragOffsetY = 0;
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    _dragOffsetY += details.delta.dy;

    if (!_expanded && _dragOffsetY <= -10) {
      setState(() => _expanded = true);
      widget.onExpandedChanged?.call(true);
      _dragOffsetY = 0;
      _handleExpandedOpened();
      return;
    }

    final canCollapseFromTop = _expanded &&
        _scrollController.hasClients &&
        _scrollController.offset <= 0.5;
    if (canCollapseFromTop && _dragOffsetY >= 12) {
      setState(() => _expanded = false);
      widget.onExpandedChanged?.call(false);
      _dragOffsetY = 0;
      _handleExpandedClosed();
    }
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    _dragOffsetY = 0;

    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -220) {
      if (!_expanded) {
        setState(() => _expanded = true);
        widget.onExpandedChanged?.call(true);
        _handleExpandedOpened();
      }
      return;
    }
    if (velocity > 220) {
      final canCollapseFromTop = _expanded &&
          _scrollController.hasClients &&
          _scrollController.offset <= 0.5;
      if (canCollapseFromTop) {
        setState(() => _expanded = false);
        widget.onExpandedChanged?.call(false);
        _handleExpandedClosed();
      }
    }
  }

  Future<void> _positionChatOnOpen() async {
    if (_messages.isEmpty) return;

    final unreadIndex =
        _showTemporaryUnreadDivider ? _temporaryUnreadStartIndex : null;

    if (unreadIndex != null &&
        unreadIndex >= 0 &&
        unreadIndex < _messages.length) {
      await _scrollToMessageIndex(unreadIndex);
      return;
    }

    await _scrollToBottom();
  }

  Future<void> _scrollToMessageIndex(int index) async {
    await Future<void>.delayed(const Duration(milliseconds: 40));
    if (!mounted || !_scrollController.hasClients || _messages.isEmpty) return;

    final clampedIndex = index.clamp(0, _messages.length - 1);
    final position = _scrollController.position;
    final denominator = math.max(1, _messages.length - 1);
    final approximateOffset =
        position.maxScrollExtent * (clampedIndex / denominator);

    _scrollController.jumpTo(
      approximateOffset.clamp(0.0, position.maxScrollExtent),
    );

    await Future<void>.delayed(const Duration(milliseconds: 40));
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

  Future<void> _sendPreviewMessage() async {
    final text = _composerController.text.trim();
    if (text.isEmpty) return;

    final currentUserId = widget.currentUserId.trim();
    final currentNickname =
        (widget.nicknamesByUserId[currentUserId] ?? 'Вы').trim().isEmpty
            ? 'Вы'
            : (widget.nicknamesByUserId[currentUserId] ?? 'Вы').trim();

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

    await _scrollToBottom();
  }

  Future<void> _handleSendPressed() async {
    final text = _composerController.text.trim();
    if (text.isEmpty || widget.sending) return;

    final sendMessage = widget.onSendMessage;
    if (sendMessage == null) {
      await _sendPreviewMessage();
      return;
    }

    _composerController.clear();
    setState(() {});

    try {
      await sendMessage(text);
      await _scrollToBottom();
    } catch (_) {
      if (!mounted) return;
      _composerController.text = text;
      _composerController.selection = TextSelection.fromPosition(
        TextPosition(offset: _composerController.text.length),
      );
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragStart: _handleVerticalDragStart,
        onVerticalDragUpdate: _handleVerticalDragUpdate,
        onVerticalDragEnd: _handleVerticalDragEnd,
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
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                _PlanChatComposer(
                                  controller: _composerController,
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
      ),
    );
  }
}

class _PlanChatHeader extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const _PlanChatHeader({
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
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
  final bool sending;
  final VoidCallback onChanged;
  final VoidCallback onSend;
  final VoidCallback onTapInside;

  const _PlanChatComposer({
    required this.controller,
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
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !sending,
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
            SizedBox(
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
          ],
        ),
      ),
    );
  }
}
