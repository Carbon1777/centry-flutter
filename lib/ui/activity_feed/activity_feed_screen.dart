import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/geo/geo_service.dart';
import '../../data/feed/feed_place_dto.dart';
import '../../data/feed/feed_repository.dart';
import '../../data/feed/feed_repository_impl.dart';
import '../../data/places/places_repository_impl.dart' as places_impl;
import '../../data/plans/plans_repository.dart';
import '../../data/plans/plans_repository_impl.dart';
import '../../data/friends/friends_repository_impl.dart';
import '../../data/private_chats/private_chats_repository_impl.dart';
import '../places/places_screen.dart';
import '../plans/plans_screen.dart';
import '../plans/plan_details_screen.dart';
import '../friends/friends_screen.dart';
import '../private_chats/private_chats_list_screen.dart';
import '../profile/profile_screen.dart';
import 'widgets/feed_geo_dialog.dart';
import 'widgets/feed_place_card.dart';
import 'widgets/feed_place_detail_sheet.dart';

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
  final ValueNotifier<int> _feedReloadSignal = ValueNotifier(0);

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
    _feedReloadSignal.dispose();
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
        final outlineWhite = Colors.white.withValues(alpha: 0.75);

        // ✅ Feed is the first real working screen after welcome.
        _notifyAppShellReadyAfterBuild();

        // ✅ Only after user is loaded, trigger invite navigation (once).
        _maybeOpenInitialPlanAfterBuild();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Лента'),
            automaticallyImplyLeading: false,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width / 2,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    overlayColor: WidgetStateProperty.resolveWith<Color?>(
                      (states) {
                        if (states.contains(WidgetState.pressed)) {
                          return accentBlue.withValues(alpha: 0.18);
                        }
                        if (states.contains(WidgetState.hovered) ||
                            states.contains(WidgetState.focused)) {
                          return accentBlue.withValues(alpha: 0.10);
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
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: outlineWhite),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 22,
                            color: accentBlue,
                          ),
                          const SizedBox(width: 7),
                          Flexible(
                            child: Text(
                              user.nickname.isNotEmpty
                                  ? user.nickname
                                  : 'Профиль',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.labelLarge?.copyWith(
                                color: accentBlue,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: accentBlue,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          body: _FeedBody(
            appUserId: widget.userId,
            reloadSignal: _feedReloadSignal,
          ),
          bottomNavigationBar: _BottomNavigationBar(
            appUserId: widget.userId,
            onNavigatedBack: () => _feedReloadSignal.value++,
          ),
        );
      },
    );
  }
}

// =======================
// Feed body
// =======================

class _FeedBody extends StatefulWidget {
  final String appUserId;
  final ValueListenable<int> reloadSignal;

  const _FeedBody({
    required this.appUserId,
    required this.reloadSignal,
  });

  @override
  State<_FeedBody> createState() => _FeedBodyState();
}

class _FeedBodyState extends State<_FeedBody> {
  final FeedRepository _feedRepo =
      FeedRepositoryImpl(Supabase.instance.client);
  final _placesRepo =
      places_impl.PlacesRepositoryImpl(Supabase.instance.client);

  List<FeedPlaceDto>? _places;
  bool _loading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load();
    widget.reloadSignal.addListener(_load);
  }

  @override
  void dispose() {
    widget.reloadSignal.removeListener(_load);
    super.dispose();
  }

  Future<void> _maybeShowFeedGeoDialog() async {
    final shouldShow = await FeedGeoDialog.shouldShow();
    if (!shouldShow) return;

    if (!FeedGeoDialog.canShowThisSession()) return;

    final permission = await Geolocator.checkPermission();
    final isDenied = permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever;
    if (!isDenied) return;

    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => FeedGeoDialog(
        onPermissionGranted: _load,
        onNeverShow: FeedGeoDialog.markNeverShow,
      ),
    );
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _hasError = false;
    });

    try {
      await GeoService.instance.ensureInitialized();
      final geo = GeoService.instance.current.value;

      final places = await _feedRepo.getFeedNearby(
        lat: geo?.lat,
        lng: geo?.lng,
      );

      if (!mounted) return;
      setState(() {
        _places = places;
        _loading = false;
      });

      // Задержка 1 сек после загрузки ленты — показываем гео-диалог если нужно
      Future.delayed(const Duration(seconds: 1), () {
        if (mounted) _maybeShowFeedGeoDialog();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Готовим для вас самое лучшее'),
          ],
        ),
      );
    }

    if (_hasError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Не удалось загрузить ленту'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
    }

    final places = _places ?? [];

    if (places.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.place_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Мест поблизости не найдено'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _load,
              child: const Text('Обновить'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        physics: const ClampingScrollPhysics(),
        itemCount: places.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final place = places[index];
          return FeedPlaceCard(
            place: place,
            onTap: () => showFeedPlaceDetailSheet(
              context: context,
              place: place,
              placesRepository: _placesRepo,
              feedRepository: _feedRepo,
              appUserId: widget.appUserId,
            ),
          );
        },
      ),
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

class _BottomNavigationBar extends StatefulWidget {
  final String appUserId;
  final VoidCallback onNavigatedBack;

  const _BottomNavigationBar({
    required this.appUserId,
    required this.onNavigatedBack,
  });

  @override
  State<_BottomNavigationBar> createState() => _BottomNavigationBarState();
}

class _BottomNavigationBarState extends State<_BottomNavigationBar>
    with WidgetsBindingObserver {
  final PlansRepository _plansRepository =
      PlansRepositoryImpl(Supabase.instance.client);
  final _privateChatsRepository =
      PrivateChatsRepositoryImpl(Supabase.instance.client);

  Timer? _refreshTimer;
  bool _hasUnreadPlanChats = false;
  bool _hasUnreadPrivateChats = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBadges();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      unawaited(_loadBadges());
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
    if (state == AppLifecycleState.resumed) {
      unawaited(_loadBadges());
    }
  }

  Future<void> _loadBadges() async {
    if (!mounted || _loading) return;
    _loading = true;
    try {
      final results = await Future.wait([
        _plansRepository.getMyPlanChatBadges(
          appUserId: widget.appUserId,
          includeArchived: true,
        ),
        _privateChatsRepository.getPrivateChatBadges(
          appUserId: widget.appUserId,
        ),
      ]);

      if (!mounted) return;
      final planBadges = results[0] as dynamic;
      final privateBadges = results[1] as dynamic;
      setState(() {
        _hasUnreadPlanChats =
            planBadges.hasAnyUnread || planBadges.unreadPlansCount > 0;
        _hasUnreadPrivateChats = privateBadges.hasUnread as bool;
      });
    } catch (e) {
      // ignore
    } finally {
      _loading = false;
    }
  }

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
                color: Colors.white.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 6),
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
                    ).then((_) => widget.onNavigatedBack());
                  },
                ),
                _NavItem(
                  icon: Icons.event_note_outlined,
                  label: 'Мои планы',
                  showDot: _hasUnreadPlanChats,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlansScreen(
                          appUserId: widget.appUserId,
                        ),
                      ),
                    ).then((_) => widget.onNavigatedBack());
                  },
                ),
                _NavItem(
                  icon: Icons.group_outlined,
                  label: 'Друзья',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) {
                          final repo =
                              FriendsRepositoryImpl(Supabase.instance.client);
                          return FriendsScreen(
                            appUserId: widget.appUserId,
                            repository: repo,
                          );
                        },
                      ),
                    ).then((_) => widget.onNavigatedBack());
                  },
                ),
                _NavItem(
                  icon: Icons.chat_bubble_outline,
                  label: 'Чаты',
                  showDot: _hasUnreadPrivateChats,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PrivateChatsListScreen(
                          appUserId: widget.appUserId,
                        ),
                      ),
                    ).then((_) {
                      unawaited(_loadBadges());
                      widget.onNavigatedBack();
                    });
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
  final bool showDot;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
    this.showDot = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 23),
                if (showDot)
                  const Positioned(
                    right: -2,
                    top: -1,
                    child: _UnreadDot(),
                  ),
              ],
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      decoration: const BoxDecoration(
        color: Color(0xFFEF4444),
        shape: BoxShape.circle,
      ),
    );
  }
}
