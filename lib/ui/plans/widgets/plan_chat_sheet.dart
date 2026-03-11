import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/plans/plan_details_dto.dart';
import 'plan_chat_message_bubble.dart';

class PlanChatSheet extends StatefulWidget {
  final List<PlanChatMessageDto> items;
  final String currentUserId;
  final Map<String, String> nicknamesByUserId;
  final double availableHeight;

  const PlanChatSheet({
    super.key,
    required this.items,
    required this.currentUserId,
    required this.nicknamesByUserId,
    required this.availableHeight,
  });

  @override
  State<PlanChatSheet> createState() => _PlanChatSheetState();
}

class _PlanChatSheetState extends State<PlanChatSheet> {
  static const double _kCollapsedHeight = 76;
  static const double _kHeaderHeight = 72;
  static const Duration _kAnimationDuration = Duration(milliseconds: 240);

  final TextEditingController _composerController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  late List<PlanChatPresentationMessage> _messages;
  bool _expanded = false;
  int _unreadCount = 0;
  int? _unreadStartIndex;

  @override
  void initState() {
    super.initState();
    _messages = _buildInitialMessages();
    if (_messages.isNotEmpty) {
      _unreadCount =
          _messages.length >= 3 ? 3 : (_messages.length >= 2 ? 2 : 1);
      final unreadStartIndex = _messages.length - _unreadCount;
      _unreadStartIndex = unreadStartIndex < 0 ? 0 : unreadStartIndex;
    }
  }

  @override
  void dispose() {
    _composerController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  List<PlanChatPresentationMessage> _buildInitialMessages() {
    if (widget.items.isNotEmpty) {
      return widget.items.map((item) {
        final authorUserId = item.authorAppUserId.trim();
        final authorNickname = widget.nicknamesByUserId[authorUserId]?.trim();
        return PlanChatPresentationMessage(
          id: '${authorUserId}_${item.createdAt.toIso8601String()}_${item.text.hashCode}',
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

  void _toggleExpanded() {
    setState(() => _expanded = !_expanded);
    if (!_expanded) return;
    unawaited(_scrollToBottom());
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -220) {
      if (!_expanded) {
        setState(() => _expanded = true);
        unawaited(_scrollToBottom());
      }
      return;
    }
    if (velocity > 220) {
      if (_expanded) {
        setState(() => _expanded = false);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    final maxHeight = ((widget.availableHeight - 6)
            .clamp(_kCollapsedHeight, widget.availableHeight) as num)
        .toDouble();
    final targetHeight = _expanded ? maxHeight : _kCollapsedHeight;

    return Align(
      alignment: Alignment.bottomCenter,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragEnd: _handleVerticalDragEnd,
        child: AnimatedContainer(
          duration: _kAnimationDuration,
          curve: Curves.easeOutCubic,
          width: double.infinity,
          height: targetHeight,
          decoration: BoxDecoration(
            color: const Color(0xFF1A1F27),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: Colors.white.withOpacity(0.07)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.34),
                blurRadius: 26,
                offset: const Offset(0, -8),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: Column(
              children: [
                _PlanChatHeader(
                  unreadCount: _unreadCount,
                  onTap: _toggleExpanded,
                ),
                if (_expanded)
                  Expanded(
                    child: Column(
                      children: [
                        Expanded(
                          child: NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification is ScrollUpdateNotification ||
                                  notification is UserScrollNotification) {
                                _markUnreadAsRead();
                              }
                              return false;
                            },
                            child: ListView.separated(
                              controller: _scrollController,
                              padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                              itemCount: _messages.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final showUnreadDivider =
                                    _unreadStartIndex != null &&
                                        _unreadCount > 0 &&
                                        index == _unreadStartIndex;
                                final message = _messages[index];
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (showUnreadDivider)
                                      const _UnreadMessagesDivider(),
                                    if (showUnreadDivider)
                                      const SizedBox(height: 10),
                                    PlanChatMessageBubble(message: message),
                                  ],
                                );
                              },
                            ),
                          ),
                        ),
                        _PlanChatComposer(
                          controller: _composerController,
                          onChanged: () => setState(() {}),
                          onSend: _sendPreviewMessage,
                          onTapInside: _markUnreadAsRead,
                        ),
                      ],
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
                  color: Colors.white.withOpacity(0.38),
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 34,
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (unreadCount > 0) ...[
                      Container(
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: const Color(0xFF1A1F27),
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          unreadCount > 99 ? '99+' : unreadCount.toString(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      'Чат',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: 0.1,
                        color: Colors.white.withOpacity(0.95),
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
  final VoidCallback onChanged;
  final VoidCallback onSend;
  final VoidCallback onTapInside;

  const _PlanChatComposer({
    required this.controller,
    required this.onChanged,
    required this.onSend,
    required this.onTapInside,
  });

  @override
  Widget build(BuildContext context) {
    final canSend = controller.text.trim().isNotEmpty;
    final theme = Theme.of(context);

    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.10),
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
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                onChanged: (_) => onChanged(),
                onTap: onTapInside,
                decoration: InputDecoration(
                  hintText: 'Напишите сообщение…',
                  filled: true,
                  fillColor: theme.colorScheme.surface.withOpacity(0.92),
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
