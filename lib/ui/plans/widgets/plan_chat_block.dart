import 'dart:async';

import 'package:flutter/material.dart';

import '../../../data/plans/plan_chat_dto.dart';
import '../../../data/plans/plan_details_dto.dart';
import '../../../data/plans/plans_repository.dart';
import '../../../features/profile/user_card_sheet.dart';
import 'plan_chat_message_bubble.dart';
import 'plan_chat_sheet.dart';

class PlanChatBlock extends StatefulWidget {
  final List<PlanChatMessageDto> items;
  final String currentUserId;
  final String planId;
  final PlansRepository repository;
  final Map<String, String> nicknamesByUserId;
  final double availableHeight;

  const PlanChatBlock({
    super.key,
    required this.items,
    required this.currentUserId,
    required this.planId,
    required this.repository,
    required this.nicknamesByUserId,
    required this.availableHeight,
  });

  @override
  State<PlanChatBlock> createState() => _PlanChatBlockState();
}

class _PlanChatBlockState extends State<PlanChatBlock> {
  static const int _kSnapshotLimit = 50;
  static const Duration _kExpandedRefreshInterval = Duration(seconds: 2);
  static const Duration _kCollapsedRefreshInterval = Duration(seconds: 4);

  PlanChatSnapshotDto? _snapshot;
  Timer? _expandedRefreshTimer;
  Timer? _collapsedRefreshTimer;
  bool _sending = false;
  bool _expanded = false;
  bool _refreshInFlight = false;
  bool _refreshQueued = false;
  bool _readInFlight = false;
  bool _hasLoadedServerSnapshot = false;
  int _lastMarkedReadRoomSeq = 0;

  Map<String, UserMiniProfile> _profiles = {};
  bool _profilesLoadInFlight = false;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void didUpdateWidget(covariant PlanChatBlock oldWidget) {
    super.didUpdateWidget(oldWidget);

    final planChanged = oldWidget.planId.trim() != widget.planId.trim();
    final userChanged =
        oldWidget.currentUserId.trim() != widget.currentUserId.trim();

    if (planChanged || userChanged) {
      unawaited(_rebind());
      return;
    }

    if (_didItemsChange(oldWidget.items, widget.items) &&
        !_hasLoadedServerSnapshot) {
      _syncSnapshotFromWidgetItems();
      unawaited(_queueRefresh());
    }
  }

  @override
  void dispose() {
    _stopExpandedRefresh();
    _stopCollapsedRefresh();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    _syncSnapshotFromWidgetItems();
    _startClosedStateRefreshIfNeeded();
    await _loadSnapshot();
  }

  Future<void> _rebind() async {
    _stopExpandedRefresh();
    _stopCollapsedRefresh();
    if (!mounted) return;

    setState(() {
      _snapshot = null;
      _sending = false;
      _expanded = false;
      _refreshInFlight = false;
      _refreshQueued = false;
      _readInFlight = false;
      _hasLoadedServerSnapshot = false;
      _lastMarkedReadRoomSeq = 0;
      _profiles = {};
      _profilesLoadInFlight = false;
    });

    await _bootstrap();
  }

  bool _didItemsChange(
    List<PlanChatMessageDto> oldItems,
    List<PlanChatMessageDto> newItems,
  ) {
    if (identical(oldItems, newItems)) return false;
    if (oldItems.length != newItems.length) return true;

    for (var i = 0; i < oldItems.length; i++) {
      final oldItem = oldItems[i];
      final newItem = newItems[i];
      if (oldItem.id != newItem.id ||
          oldItem.authorAppUserId != newItem.authorAppUserId ||
          oldItem.text != newItem.text ||
          oldItem.createdAt != newItem.createdAt) {
        return true;
      }
    }

    return false;
  }

  List<PlanChatSnapshotMessageDto> _mapWidgetItemsToSnapshotMessages() {
    final planId = widget.planId.trim();
    final currentUserId = widget.currentUserId.trim();

    return widget.items.asMap().entries.map((entry) {
      final index = entry.key;
      final item = entry.value;
      final authorUserId = item.authorAppUserId.trim();
      final nickname = widget.nicknamesByUserId[authorUserId]?.trim();

      return PlanChatSnapshotMessageDto(
        id: item.id,
        planId: planId,
        roomSeq: index + 1,
        authorAppUserId: authorUserId,
        authorDisplayName:
            nickname == null || nickname.isEmpty ? 'Участник' : nickname,
        text: item.text,
        createdAt: item.createdAt,
        isMine: authorUserId == currentUserId,
      );
    }).toList();
  }

  void _syncSnapshotFromWidgetItems() {
    final mappedMessages = _mapWidgetItemsToSnapshotMessages();
    final current = _snapshot;

    if (current == null) {
      if (mappedMessages.isEmpty) return;

      setState(() {
        _snapshot = PlanChatSnapshotDto(
          planId: widget.planId.trim(),
          roomMessageSeq: mappedMessages.length,
          lastReadRoomSeq: mappedMessages.length,
          unreadCount: 0,
          hasMore: false,
          messages: mappedMessages,
        );
      });
      return;
    }

    final nextRoomMessageSeq = current.roomMessageSeq > mappedMessages.length
        ? current.roomMessageSeq
        : mappedMessages.length;

    setState(() {
      _snapshot = PlanChatSnapshotDto(
        planId: current.planId,
        roomMessageSeq: nextRoomMessageSeq,
        lastReadRoomSeq: current.lastReadRoomSeq,
        unreadCount: current.unreadCount,
        hasMore: current.hasMore,
        messages: mappedMessages,
      );
    });
  }

  void _startExpandedRefresh() {
    _expandedRefreshTimer?.cancel();
    _expandedRefreshTimer = Timer.periodic(_kExpandedRefreshInterval, (_) {
      unawaited(_queueRefresh());
    });
  }

  void _stopExpandedRefresh() {
    _expandedRefreshTimer?.cancel();
    _expandedRefreshTimer = null;
  }

  void _startCollapsedRefresh() {
    _collapsedRefreshTimer?.cancel();
    _collapsedRefreshTimer = Timer.periodic(_kCollapsedRefreshInterval, (_) {
      unawaited(_queueRefresh());
    });
  }

  void _stopCollapsedRefresh() {
    _collapsedRefreshTimer?.cancel();
    _collapsedRefreshTimer = null;
  }

  void _startClosedStateRefreshIfNeeded() {
    if (_expanded) return;
    _startCollapsedRefresh();
  }

  Future<void> _queueRefresh() async {
    if (_refreshInFlight) {
      _refreshQueued = true;
      return;
    }

    _refreshInFlight = true;
    try {
      do {
        _refreshQueued = false;
        await _loadSnapshot();
      } while (_refreshQueued);
    } finally {
      _refreshInFlight = false;
    }
  }

  Future<void> _loadSnapshot() async {
    try {
      final snapshot = await widget.repository.getPlanChatSnapshot(
        appUserId: widget.currentUserId,
        planId: widget.planId,
        limit: _kSnapshotLimit,
      );

      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _hasLoadedServerSnapshot = true;
      });

      unawaited(_markReadIfNeeded());
      unawaited(_loadProfiles(snapshot.messages));
    } catch (e) {
      debugPrint('[PlanChatBlock] loadSnapshot error: $e');
    }
  }

  Future<void> _loadProfiles(List<PlanChatSnapshotMessageDto> messages) async {
    if (_profilesLoadInFlight) return;

    final ids = messages
        .map((m) => m.authorAppUserId.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    if (ids.isEmpty) return;

    _profilesLoadInFlight = true;
    try {
      final profiles = await loadUserMiniProfiles(
        userIds: ids,
        context: 'in_plans',
      );
      if (!mounted) return;
      setState(() {
        _profiles = profiles;
      });
    } catch (e) {
      debugPrint('[PlanChatBlock] loadProfiles error: $e');
    } finally {
      _profilesLoadInFlight = false;
    }
  }

  Future<void> _handleExpandedChanged(bool expanded) async {
    if (!mounted) return;
    setState(() => _expanded = expanded);

    if (expanded) {
      _stopCollapsedRefresh();
      _startExpandedRefresh();
      await _queueRefresh();
      await _markReadIfNeeded();
      return;
    }

    _stopExpandedRefresh();
    _startClosedStateRefreshIfNeeded();
    await _queueRefresh();
  }

  Future<void> _markReadIfNeeded() async {
    final snapshot = _snapshot;
    if (!_expanded || snapshot == null) return;
    if (snapshot.unreadCount <= 0) return;
    if (_readInFlight) return;
    if (snapshot.roomMessageSeq <= _lastMarkedReadRoomSeq) return;

    _readInFlight = true;
    final readThroughRoomSeq = snapshot.roomMessageSeq;

    try {
      await widget.repository.markPlanChatRead(
        appUserId: widget.currentUserId,
        planId: widget.planId,
        readThroughRoomSeq: readThroughRoomSeq,
      );

      if (!mounted) return;

      _lastMarkedReadRoomSeq = readThroughRoomSeq;
      final current = _snapshot;
      if (current != null) {
        setState(() {
          _snapshot = PlanChatSnapshotDto(
            planId: current.planId,
            roomMessageSeq: current.roomMessageSeq,
            lastReadRoomSeq: readThroughRoomSeq,
            unreadCount: 0,
            hasMore: current.hasMore,
            messages: current.messages,
          );
        });
      }
    } catch (e) {
      debugPrint('[PlanChatBlock] markRead error: $e');
    } finally {
      _readInFlight = false;
    }
  }

  Future<void> _handleEditMessage(String messageId, String text) async {
    try {
      await widget.repository.editPlanChatMessage(
        appUserId: widget.currentUserId,
        planId: widget.planId,
        messageId: messageId,
        text: text,
      );
    } catch (e) {
      debugPrint('[PlanChatBlock] editMessage error: $e');
      rethrow;
    }
    unawaited(_queueRefresh());
  }

  Future<void> _handleDeleteForAll(String messageId) async {
    try {
      await widget.repository.deletePlanChatMessageForAll(
        appUserId: widget.currentUserId,
        planId: widget.planId,
        messageId: messageId,
      );
    } catch (e) {
      debugPrint('[PlanChatBlock] deleteForAll error: $e');
      return;
    }
    unawaited(_queueRefresh());
  }

  Future<void> _handleDeleteForMe(String messageId) async {
    try {
      await widget.repository.deletePlanChatMessageForMe(
        appUserId: widget.currentUserId,
        planId: widget.planId,
        messageId: messageId,
      );
    } catch (e) {
      debugPrint('[PlanChatBlock] deleteForMe error: $e');
      return;
    }
    unawaited(_queueRefresh());
  }

  Future<void> _handleSendMessage(String text) async {
    if (_sending) return;

    setState(() => _sending = true);
    try {
      final clientNonce =
          'chat_${widget.planId}_${widget.currentUserId}_${DateTime.now().microsecondsSinceEpoch}';

      final sentMessage = await widget.repository.sendPlanChatMessage(
        appUserId: widget.currentUserId,
        planId: widget.planId,
        text: text,
        clientNonce: clientNonce,
      );

      if (!mounted) return;

      final current = _snapshot;
      if (current != null) {
        final alreadyExists =
            current.messages.any((message) => message.id == sentMessage.id);
        final nextMessages = alreadyExists
            ? current.messages
            : <PlanChatSnapshotMessageDto>[
                ...current.messages,
                sentMessage,
              ];

        final nextRoomSeq = current.roomMessageSeq > sentMessage.roomSeq
            ? current.roomMessageSeq
            : sentMessage.roomSeq;

        _snapshot = PlanChatSnapshotDto(
          planId: current.planId,
          roomMessageSeq: nextRoomSeq,
          lastReadRoomSeq: _expanded ? nextRoomSeq : current.lastReadRoomSeq,
          unreadCount: _expanded ? 0 : current.unreadCount,
          hasMore: current.hasMore,
          messages: nextMessages,
        );
      }

      setState(() {});

      unawaited(_queueRefresh());
      unawaited(_markReadIfNeeded());
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  List<PlanChatPresentationMessage> _buildPresentationMessages() {
    final snapshot = _snapshot;
    if (snapshot != null) {
      return snapshot.messages.map(_mapSnapshotMessage).toList();
    }

    return widget.items.map((item) {
      final authorUserId = item.authorAppUserId.trim();
      final nickname = widget.nicknamesByUserId[authorUserId]?.trim();
      return PlanChatPresentationMessage(
        id: item.id,
        authorUserId: authorUserId,
        authorNickname:
            nickname == null || nickname.isEmpty ? 'Участник' : nickname,
        text: item.text,
        createdAt: item.createdAt,
        isMine: authorUserId == widget.currentUserId.trim(),
      );
    }).toList();
  }

  PlanChatPresentationMessage _mapSnapshotMessage(
    PlanChatSnapshotMessageDto message,
  ) {
    final authorUserId = message.authorAppUserId.trim();
    final profile = _profiles[authorUserId];

    // Всегда резолвим реальный никнейм — независимо от флага скрытия.
    // Приоритет: профиль → nicknamesByUserId → authorDisplayName → 'Участник'
    final profileNick = profile?.nickname?.trim() ?? '';
    final fallbackNick = widget.nicknamesByUserId[authorUserId]?.trim() ?? '';
    final displayName = message.authorDisplayName.trim();

    final effectiveNickname = profileNick.isNotEmpty
        ? profileNick
        : fallbackNick.isNotEmpty
            ? fallbackNick
            : displayName.isNotEmpty
                ? displayName
                : 'Участник';

    return PlanChatPresentationMessage(
      id: message.id,
      authorUserId: authorUserId,
      authorNickname: effectiveNickname,
      nicknameHidden: profile?.nicknameHidden ?? false,
      avatarUrl: profile?.avatarUrl,
      avatarHidden: profile?.avatarHidden ?? false,
      text: message.text,
      createdAt: message.createdAt,
      isMine: message.isMine,
      editedAt: message.editedAt,
      messageKind: message.messageKind,
      deletedAt: message.deletedAt,
    );
  }

  @override
  
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final presentationItems = _buildPresentationMessages();
    final unreadCount = snapshot?.unreadCount ?? 0;

    return PlanChatSheet(
      items: widget.items,
      currentUserId: widget.currentUserId,
      nicknamesByUserId: widget.nicknamesByUserId,
      availableHeight: widget.availableHeight,
      presentationItems: presentationItems,
      unreadCountOverride: unreadCount,
      onSendMessage: _handleSendMessage,
      onEditMessage: _handleEditMessage,
      onDeleteMessageForMe: _handleDeleteForMe,
      onDeleteMessageForAll: _handleDeleteForAll,
      onExpandedChanged: _handleExpandedChanged,
      showUnreadDivider: false,
      usePreviewWhenEmpty: false,
      sending: _sending,
    );
  }
}
