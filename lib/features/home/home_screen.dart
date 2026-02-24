import 'dart:async';

import 'package:flutter/material.dart';

import '../../ui/activity_feed/activity_feed_screen.dart';

class HomeScreen extends StatefulWidget {
  final String userId;
  final String nickname;
  final String publicId;
  final String? email;

  // If not null: open plan details after welcome (deep link UX).
  final String? initialPlanIdToOpen;

  // Called when HomeScreen/Feed starts opening the initial plan to avoid re-opening on rebuild.
  final VoidCallback? onInitialPlanOpened;

  const HomeScreen({
    super.key,
    required this.userId,
    required this.nickname,
    required this.publicId,
    required this.email,
    this.initialPlanIdToOpen,
    this.onInitialPlanOpened,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  late final Animation<double> _titleOpacity;
  late final Animation<double> _handRotation;
  late final Animation<double> _nicknameOpacity;
  late final Animation<double> _textOpacity;

  // Plan to open (invite flow). May arrive after initState via didUpdateWidget.
  String? _pendingInvitePlanId;

  bool _welcomeCompleted = false;
  bool _navigationCommitted = false;

  @override
  void initState() {
    super.initState();

    _pendingInvitePlanId = _normalizePlanId(widget.initialPlanIdToOpen);

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    );

    _titleOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.16, curve: Curves.easeOut),
    );

    _handRotation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 0.35)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.35, end: -0.25)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.25, end: 0.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 1,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.16, 0.40),
      ),
    );

    _nicknameOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.40, 0.52, curve: Curves.easeOut),
    );

    _textOpacity = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.52, 0.84, curve: Curves.easeOut),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _welcomeCompleted = true;
        unawaited(_commitNavigationAfterWelcome());
      }
    });

    _controller.forward();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    final newId = _normalizePlanId(widget.initialPlanIdToOpen);
    final oldId = _normalizePlanId(oldWidget.initialPlanIdToOpen);

    // Invite plan id may arrive after initState; keep it.
    if (newId != null && newId.isNotEmpty && newId != oldId) {
      _pendingInvitePlanId = newId;

      // If welcome already finished and we haven't navigated yet, commit now.
      if (_welcomeCompleted && !_navigationCommitted) {
        unawaited(_commitNavigationAfterWelcome());
      }
    }
  }

  String? _normalizePlanId(String? value) {
    final v = value?.trim();
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> _commitNavigationAfterWelcome() async {
    if (_navigationCommitted || !mounted) return;
    _navigationCommitted = true;

    // ✅ Канон:
    // - HomeScreen (Welcome) НИКОГДА не строит сложную цепочку.
    // - Он просто заменяет себя на Feed.
    // - Если есть инвайт planId — прокидываем его в Feed, и уже Feed строит:
    //   Feed -> Plans -> PlanDetails.
    final planId = _pendingInvitePlanId;

    await _replaceWithFeed(initialPlanIdToOpen: planId);
  }

  Future<void> _replaceWithFeed({required String? initialPlanIdToOpen}) async {
    if (!mounted) return;

    await Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ActivityFeedScreen(
          userId: widget.userId,
          nickname: widget.nickname,
          publicId: widget.publicId,
          email: widget.email,
          initialPlanIdToOpen: initialPlanIdToOpen,
          onInitialPlanOpened: widget.onInitialPlanOpened,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Align(
          alignment: const Alignment(0, -0.25),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: _titleOpacity.value,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Добро пожаловать',
                          style: TextStyle(
                            fontSize: 29,
                            fontWeight: FontWeight.w600,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Transform.rotate(
                          angle: _handRotation.value,
                          child: const Text(
                            '👋',
                            style: TextStyle(fontSize: 30),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  if (widget.nickname.trim().isNotEmpty)
                    Opacity(
                      opacity: _nicknameOpacity.value,
                      child: Text(
                        widget.nickname,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w500,
                          height: 1.05,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  Opacity(
                    opacity: _textOpacity.value,
                    child: Text(
                      'Посмотрим, что сегодня интересного…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        height: 1.1,
                        color: colors.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
