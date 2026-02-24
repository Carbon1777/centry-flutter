import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/plans/plans_repository.dart';
import '../../data/plans/plans_repository_impl.dart';
import '../places/places_screen.dart';
import '../plans/plans_screen.dart';
import '../plans/plan_details_screen.dart';
import '../friends/friends_screen.dart';
import '../profile/profile_screen.dart';

class ActivityFeedScreen extends StatefulWidget {
  final String userId; // ← доменный app_user_id
  final String nickname;
  final String publicId;
  final String? email;

  // ✅ If not null: open Plans -> PlanDetails immediately (deep link UX),
  // while keeping the normal back-stack: Feed -> Plans -> Details.
  final String? initialPlanIdToOpen;

  // Called when Feed starts opening the initial plan to avoid re-opening on rebuild.
  final VoidCallback? onInitialPlanOpened;

  // Called once when Feed is actually visible and ready (app shell ready).
  final VoidCallback? onAppShellReady;

  const ActivityFeedScreen({
    super.key,
    required this.userId,
    required this.nickname,
    required this.publicId,
    required this.email,
    this.initialPlanIdToOpen,
    this.onInitialPlanOpened,
    this.onAppShellReady,
  });

  @override
  State<ActivityFeedScreen> createState() => _ActivityFeedScreenState();
}

class _ActivityFeedScreenState extends State<ActivityFeedScreen> {
  late Future<_FeedUserState> _future;
  StreamSubscription<AuthState>? _authSub;

  bool _handledInitialPlanNav = false;
  bool _appShellReadyNotified = false;

  @override
  void initState() {
    super.initState();

    _future = _loadFromAuthoritativeSource();

    final auth = Supabase.instance.client.auth;
    _authSub = auth.onAuthStateChange.listen((data) {
      if (!mounted) return;
      if (data.session != null) {
        setState(() {
          _future = _loadFromAuthoritativeSource();
        });
      }
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<_FeedUserState> _loadFromAuthoritativeSource() async {
    final client = Supabase.instance.client;

    if (client.auth.currentSession == null) {
      return _guestFromSnapshot();
    }

    return _loadFromServer();
  }

  _FeedUserState _guestFromSnapshot() {
    return _FeedUserState(
      nickname: widget.nickname,
      publicId: widget.publicId,
      email: null,
      isGuest: true,
    );
  }

  Future<_FeedUserState> _loadFromServer() async {
    final res = Supabase.instance.client.rpc('current_user');

    final resolved = await res;

    if (resolved is! Map) {
      throw StateError('current_user must return Map, got: $resolved');
    }

    final row = Map<String, dynamic>.from(resolved);

    final nickname = (row['nickname'] as String?) ?? '';
    final publicId = row['public_id'] as String?;
    final email = row['email'] as String?;

    if (publicId == null || publicId.isEmpty) {
      throw StateError('current_user missing public_id: $row');
    }

    final isGuest = email == null || email.trim().isEmpty;

    return _FeedUserState(
      nickname: nickname,
      publicId: publicId,
      email: email,
      isGuest: isGuest,
    );
  }

  void _retry() {
    setState(() {
      _future = _loadFromAuthoritativeSource();
    });
  }

  void _notifyAppShellReadyAfterBuild() {
    if (_appShellReadyNotified) return;
    _appShellReadyNotified = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onAppShellReady?.call();
    });
  }

  void _maybeOpenInitialPlanAfterBuild() {
    // ignore: avoid_print
    print(
      'INVITE NAV: initialPlanIdToOpen="${widget.initialPlanIdToOpen}" handled=$_handledInitialPlanNav',
    );

    if (_handledInitialPlanNav) return;

    final planId = widget.initialPlanIdToOpen?.trim();
    if (planId == null || planId.isEmpty) return;

    _handledInitialPlanNav = true;

    // ✅ ВАЖНО:
    // НИЧЕГО не вызываем, что может привести к setState() родителя, во время build.
    // Всё (включая onInitialPlanOpened) переносим в post-frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // Mark as handled in parent (BootstrapGate/Home) so it won't be re-triggered on rebuilds.
      // Теперь это точно происходит ПОСЛЕ build → без "setState during build".
      widget.onInitialPlanOpened?.call();

      // ✅ Canonical back stack: Feed -> Plans -> Details

      // 1) Push Plans (НЕ await, иначе Future завершится только на pop)
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => PlansScreen(appUserId: widget.userId),
        ),
      );

      // 2) On next frame push Details on top of Plans
      WidgetsBinding.instance.addPostFrameCallback((__) async {
        if (!mounted) return;

        final PlansRepository repo =
            PlansRepositoryImpl(Supabase.instance.client);

        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PlanDetailsScreen(
              appUserId: widget.userId,
              planId: planId,
              repository: repo,
            ),
          ),
        );
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return FutureBuilder<_FeedUserState>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (snap.hasError) {
          return Scaffold(
            appBar: AppBar(
              title: const Text('Лента'),
              automaticallyImplyLeading: false,
            ),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Ошибка загрузки пользователя'),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _retry,
                    child: const Text('Повторить'),
                  ),
                ],
              ),
            ),
          );
        }

        final user = snap.data!;
        final accentBlue = colors.primary;
        final outlineWhite = Colors.white.withOpacity(0.75);

        // ✅ Feed is the first real working screen after welcome.
        _notifyAppShellReadyAfterBuild();

        // ✅ Only after user is loaded, trigger invite navigation (once).
        _maybeOpenInitialPlanAfterBuild();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Лента'),
            automaticallyImplyLeading: false,
            actions: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (user.nickname.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          'Ник: ${user.nickname}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelLarge?.copyWith(
                            color: const Color.fromARGB(221, 232, 232, 232),
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      overlayColor: MaterialStateProperty.resolveWith<Color?>(
                        (states) {
                          if (states.contains(MaterialState.pressed)) {
                            return accentBlue.withOpacity(0.18);
                          }
                          if (states.contains(MaterialState.hovered) ||
                              states.contains(MaterialState.focused)) {
                            return accentBlue.withOpacity(0.10);
                          }
                          return null;
                        },
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ProfileScreen(
                              userId: widget.userId,
                              nickname: user.nickname,
                              publicId: user.publicId,
                              email: user.email,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: outlineWhite),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_outline,
                              size: 20,
                              color: accentBlue,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Профиль',
                              style: textTheme.labelLarge?.copyWith(
                                color: accentBlue,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(24),
            children: const [],
          ),
          bottomNavigationBar: _BottomNavigationBar(
            appUserId: widget.userId,
          ),
        );
      },
    );
  }
}

// =======================
// UI-only model
// =======================

class _FeedUserState {
  final String nickname;
  final String publicId;
  final String? email;
  final bool isGuest;

  _FeedUserState({
    required this.nickname,
    required this.publicId,
    required this.email,
    required this.isGuest,
  });
}

// =======================
// Bottom navigation
// =======================

class _BottomNavigationBar extends StatelessWidget {
  final String appUserId;

  const _BottomNavigationBar({
    required this.appUserId,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Material(
          borderRadius: BorderRadius.circular(16),
          color: Theme.of(context).colorScheme.surface,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.place_outlined,
                  label: 'Места',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PlacesScreen(),
                      ),
                    );
                  },
                ),
                _NavItem(
                  icon: Icons.event_note_outlined,
                  label: 'Мои планы',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlansScreen(
                          appUserId: appUserId,
                        ),
                      ),
                    );
                  },
                ),
                _NavItem(
                  icon: Icons.group_outlined,
                  label: 'Друзья',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const FriendsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon),
            const SizedBox(height: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}
