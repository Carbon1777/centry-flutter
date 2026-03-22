import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/geo/geo_service.dart';
import '../../data/places/place_dto.dart';
import '../../data/places/places_feed_result.dart';
import '../../data/places/places_repository.dart';
import '../common/category_placeholder.dart';
import '../../data/places/places_repository_impl.dart';
import '../../data/plans/plans_repository_impl.dart';
import 'package:centry/features/places/geo_info/places_geo_info_controller.dart';
import 'package:centry/features/places/geo_info/places_geo_info_dialog.dart';

// ФИЛЬТРЫ
import 'package:centry/features/places/filters/places_filters_controller.dart';
import 'package:centry/features/places/filters/places_filters_dialog.dart'
    show showPlacesFiltersSheet;

// КАРТА
import 'package:centry/features/places/map/places_map.dart';
import 'package:centry/features/places/details/add_place_to_plan_modal.dart';
import 'package:centry/features/places/details/place_details_dialog.dart';
import 'package:centry/features/places/add_place/add_place_dialog.dart';
import 'package:centry/ui/common/center_toast.dart';
import '../plans/plan_details_screen.dart';

enum PlacesViewMode {
  list,
  map,
}

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({
    super.key,
    this.sourcePlanId,
    this.sourcePlanTitle,
    this.currentPlanPlaceIds = const <String>{},
    this.initialViewMode = PlacesViewMode.list,
    this.initialFocusPlace,
  });

  final String? sourcePlanId;
  final String? sourcePlanTitle;
  final Set<String> currentPlanPlaceIds;
  final PlacesViewMode initialViewMode;
  final PlaceDto? initialFocusPlace;

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  late PlacesViewMode _viewMode;

  final _geoInfoController = PlacesGeoInfoController();
  final _filtersController = PlacesFiltersController();
  late final PlacesRepository _repository;

  final ValueNotifier<int> _reloadSignal = ValueNotifier<int>(0);

  /// 🔴 Live invalidation subscription
  late final StreamSubscription<void> _repoInvalidationSub;

  /// UI-сигнал: сфокусировать карту на конкретном месте (из списка).
  final ValueNotifier<PlaceDto?> _mapFocusPlace =
      ValueNotifier<PlaceDto?>(null);

  bool get _isPlanFlow {
    final planId = widget.sourcePlanId?.trim();
    final planTitle = widget.sourcePlanTitle?.trim();
    return planId != null &&
        planId.isNotEmpty &&
        planTitle != null &&
        planTitle.isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    _viewMode = widget.initialViewMode;
    _repository = PlacesRepositoryImpl(Supabase.instance.client);

    if (widget.initialFocusPlace != null) {
      _mapFocusPlace.value = widget.initialFocusPlace;
    }

    /// 🔴 Подписка на live invalidation
    _repoInvalidationSub = _repository.invalidations.listen((_) {
      _reloadSignal.value++;
    });

    // Восстанавливаем сохранённые фильтры; если были активны — перезагружаем список
    _filtersController.init().then((_) {
      if (mounted && _filtersController.state.hasActiveFilters) {
        _reloadSignal.value++;
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowGeoInfo();
    });
  }

  @override
  void dispose() {
    _repoInvalidationSub.cancel(); // 🔴
    _mapFocusPlace.dispose();
    _reloadSignal.dispose();
    super.dispose();
  }

  Future<void> _maybeShowGeoInfo() async {
    final shouldShow = await _geoInfoController.shouldShow();
    if (!shouldShow) return;

    if (!PlacesGeoInfoDialog.canShowThisSession()) return;

    final geo = GeoService.instance.current.value;
    final permission = await Geolocator.checkPermission();

    final permissionGranted = permission != LocationPermission.denied &&
        permission != LocationPermission.deniedForever;

    final hasCurrentPosition = geo != null;

    final state = _geoInfoController.resolveState(
      permissionGranted: permissionGranted,
      hasCurrentPosition: hasCurrentPosition,
    );

    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => PlacesGeoInfoDialog(
        text: _geoInfoController.resolveText(state),
        onNeverShow: _geoInfoController.markNeverShow,
      ),
    );
  }

  Future<void> _openFilters() async {
    final geo = GeoService.instance.current.value;

    if (!mounted) return;

    await showPlacesFiltersSheet(
      context: context,
      controller: _filtersController,
      loadServerState: ({List<String>? cityIds}) => _repository.loadPlacesFiltersState(
        lat: geo?.lat,
        lng: geo?.lng,
        // null = начальная загрузка:
        //   controller пустой → null на сервер → автогео
        //   controller непустой → передаём его города
        // [] = черновик без городов → передаём [] → сервер отдаёт все районы без автогео
        // [...] = конкретный черновой выбор → передаём как есть
        selectedCityIds: cityIds ??
            (_filtersController.state.cityIds.isEmpty
                ? null
                : _filtersController.state.cityIds),
        selectedAreaIds: _filtersController.state.areaIds,
        selectedTypes: _filtersController.state.types,
        minRating: _filtersController.state.minRating,
      ),
    );

    _reloadSignal.value++;
  }

  void _openPlaceOnMap(PlaceDto place) {
    setState(() => _viewMode = PlacesViewMode.map);
    _mapFocusPlace.value = place;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_mapFocusPlace.value == place) {
        _mapFocusPlace.value = null;
      }
    });
  }

  Future<String> _resolveCurrentAppUserId() async {
    const secureStorage = FlutterSecureStorage();
    final rawSnapshot = await secureStorage.read(key: 'user_snapshot');
    if (rawSnapshot != null && rawSnapshot.isNotEmpty) {
      try {
        final json = jsonDecode(rawSnapshot) as Map<String, dynamic>;
        final snapshotUserId = json['id']?.toString();
        if (snapshotUserId != null && snapshotUserId.isNotEmpty) {
          return snapshotUserId;
        }
      } catch (_) {
        // ignore and fallback below
      }
    }

    final authUserId = Supabase.instance.client.auth.currentUser?.id;
    if (authUserId == null || authUserId.isEmpty) {
      throw Exception('Пользователь не найден');
    }

    final row = await Supabase.instance.client
        .from('app_users')
        .select('id')
        .eq('auth_user_id', authUserId)
        .maybeSingle();

    final appUserId = row?['id']?.toString();
    if (appUserId == null || appUserId.isEmpty) {
      throw Exception('Пользователь не найден');
    }

    return appUserId;
  }

  Future<void> _openPlanDetails({required String planId}) async {
    final appUserId = await _resolveCurrentAppUserId();
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlanDetailsScreen(
          appUserId: appUserId,
          planId: planId,
          repository: PlansRepositoryImpl(Supabase.instance.client),
        ),
      ),
    );
  }

  Future<void> _removeFromCurrentPlan(String placeId) async {
    if (!_isPlanFlow) return;

    final appUserId = await _resolveCurrentAppUserId();
    final planId = widget.sourcePlanId!.trim();

    await PlansRepositoryImpl(Supabase.instance.client).removePlanPlace(
      appUserId: appUserId,
      planId: planId,
      placeId: placeId,
      placeSubmissionId: null,
    );
  }

  Future<void> _handlePlaceDialogResult(Object? result) async {
    if (!mounted || result == null) return;

    if (_isPlanFlow) {
      Navigator.of(context).pop(result);
      return;
    }

    if (result is AddPlaceToPlanResult) {
      await _openPlanDetails(planId: result.planId);
      return;
    }

    _reloadSignal.value++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Места'),
        actions: [
          _ViewModeToggle(
            value: _viewMode,
            onChanged: (mode) => setState(() => _viewMode = mode),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _openFilters,
          ),
        ],
      ),
      body: _viewMode == PlacesViewMode.list
          ? _PlacesList(
              repository: _repository,
              filtersController: _filtersController,
              reloadSignal: _reloadSignal,
              onOpenOnMap: _openPlaceOnMap,
              sourcePlanId: widget.sourcePlanId,
              sourcePlanTitle: widget.sourcePlanTitle,
              currentPlanPlaceIds: widget.currentPlanPlaceIds,
              onRemoveFromCurrentPlan:
                  _isPlanFlow ? _removeFromCurrentPlan : null,
              onPlaceDialogResult: _handlePlaceDialogResult,
            )
          : PlacesMap(
              repository: _repository,
              filtersController: _filtersController,
              focusPlace: _mapFocusPlace,
              sourcePlanId: widget.sourcePlanId,
              sourcePlanTitle: widget.sourcePlanTitle,
              currentPlanPlaceIds: widget.currentPlanPlaceIds,
              onRemoveFromCurrentPlan:
                  _isPlanFlow ? _removeFromCurrentPlan : null,
              onPlaceDialogResult: _handlePlaceDialogResult,
            ),
    );
  }
}

/* =======================
   LIST
   ======================= */

class _PlacesList extends StatefulWidget {
  const _PlacesList({
    required this.repository,
    required this.filtersController,
    required this.reloadSignal,
    required this.onOpenOnMap,
    required this.currentPlanPlaceIds,
    required this.onPlaceDialogResult,
    this.sourcePlanId,
    this.sourcePlanTitle,
    this.onRemoveFromCurrentPlan,
  });

  final PlacesRepository repository;
  final PlacesFiltersController filtersController;
  final ValueListenable<int> reloadSignal;
  final ValueChanged<PlaceDto> onOpenOnMap;
  final String? sourcePlanId;
  final String? sourcePlanTitle;
  final Set<String> currentPlanPlaceIds;
  final Future<void> Function(String placeId)? onRemoveFromCurrentPlan;
  final Future<void> Function(Object? result) onPlaceDialogResult;

  @override
  State<_PlacesList> createState() => _PlacesListState();
}

class _PlacesListState extends State<_PlacesList> {
  static const int _pageSize = 20;
  static const String _userSnapshotStorageKey = 'user_snapshot';

  final List<PlaceUiModel> _places = [];
  final ScrollController _scrollController = ScrollController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  // SEARCH UI (server-driven)
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  Timer? _searchDebounce;
  bool _searchLoading = false;
  List<String> _suggestions = const [];

  /// Exact title constraint applied ONLY after user presses "Найти".
  String? _appliedSearchTitle;

  bool _showScrollToTop = false;
  bool _loading = false;
  bool _hasMore = true;
  int _offset = 0;
  int _loadGeneration = 0;

  bool _creatingPlaceSubmission = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    widget.reloadSignal.addListener(_loadInitial);

    _searchController.addListener(_onSearchTextChanged);
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) {
        if (mounted) setState(() => _suggestions = const []);
      } else {
        _triggerSuggestions(_searchController.text);
      }
    });

    _loadInitial();
  }

  @override
  void dispose() {
    widget.reloadSignal.removeListener(_loadInitial);
    _scrollController.dispose();

    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    _searchFocus.dispose();

    super.dispose();
  }

  void _onScroll() {
    final shouldShow = _scrollController.offset > 700;

    if (shouldShow != _showScrollToTop) {
      setState(() => _showScrollToTop = shouldShow);
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadNext();
    }
  }

  void _onSearchTextChanged() {
    _triggerSuggestions(_searchController.text);
  }

  void _triggerSuggestions(String input) {
    _searchDebounce?.cancel();

    final q = input.trim();
    if (q.isEmpty) {
      if (mounted) {
        setState(() {
          _searchLoading = false;
          _suggestions = const [];
        });
      }
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 220), () async {
      if (!mounted) return;

      setState(() => _searchLoading = true);

      try {
        final items = await widget.repository.loadPlaceSearchSuggestions(
          query: q,
          limit: 25,
        );

        if (!mounted) return;

        if (_searchController.text.trim() != q) {
          setState(() => _searchLoading = false);
          return;
        }

        setState(() {
          _suggestions = items;
          _searchLoading = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _searchLoading = false;
          _suggestions = const [];
        });
      }
    });
  }

  void _applySuggestion(String title) {
    _searchController.text = title;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: title.length),
    );

    setState(() => _suggestions = const []);
    _searchFocus.requestFocus();
  }

  Future<void> _onFindPressed() async {
    final q = _searchController.text.trim();

    setState(() {
      _suggestions = const [];
      _appliedSearchTitle = q.isEmpty ? null : q;
    });

    await _loadInitial();

    if (!mounted) return;
    _searchFocus.unfocus();
  }

  Future<void> _onClearSearch() async {
    _searchController.clear();
    setState(() {
      _suggestions = const [];
      _appliedSearchTitle = null;
    });

    await _loadInitial();
  }

  Future<void> _loadInitial() async {
    // Инвалидируем предыдущий запрос: даже если он ещё в полёте,
    // его результат будет проигнорирован (_loadGeneration не совпадёт).
    _loadGeneration++;
    _places.clear();
    _offset = 0;
    _hasMore = true;
    _loading = false;
    setState(() {});
    await _loadNext();
  }

  Future<void> _loadNext() async {
    if (_loading || !_hasMore) return;

    final gen = _loadGeneration;
    setState(() => _loading = true);

    try {
      final payload = widget.filtersController.buildPayload();

      final PlacesFeedResult result = await widget.repository.loadPlacesFeed(
        cityIds: payload.cityIds,
        areaIds: payload.areaIds,
        types: payload.types,
        minRating: payload.minRating,
        searchTitle: _appliedSearchTitle,
        limit: _pageSize,
        offset: _offset,
      );

      if (!mounted || gen != _loadGeneration) return;

      final uiItems = result.items.map(_mapToUi).toList();

      setState(() {
        _places.addAll(uiItems);
        _hasMore = result.hasMore;
        _offset += uiItems.length;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _loadGeneration) return;
      setState(() {
        _loading = false;
        _hasMore = false;
      });
    }
  }

  Future<String> _resolveCurrentAppUserId() async {
    final rawSnapshot = await _secureStorage.read(key: _userSnapshotStorageKey);
    if (rawSnapshot != null && rawSnapshot.isNotEmpty) {
      try {
        final json = jsonDecode(rawSnapshot) as Map<String, dynamic>;
        final snapshotUserId = json['id']?.toString();

        if (snapshotUserId != null && snapshotUserId.isNotEmpty) {
          return snapshotUserId;
        }
      } catch (e) {
        // ignore and fallback below
      }
    }

    final authUserId = Supabase.instance.client.auth.currentUser?.id;
    if (authUserId != null && authUserId.isNotEmpty) {
      final row = await Supabase.instance.client
          .from('app_users')
          .select('id')
          .eq('auth_user_id', authUserId)
          .maybeSingle();

      final appUserId = row?['id']?.toString();
      if (appUserId != null && appUserId.isNotEmpty) {
        return appUserId;
      }
    }

    throw Exception('Пользователь не найден');
  }

  String _mapDialogTypeToServerCategory(String typeLabel) {
    switch (typeLabel) {
      case 'Бар':
        return 'bar';
      case 'Ночной клуб':
        return 'nightclub';
      case 'Ресторан':
        return 'restaurant';
      case 'Кино':
      case 'Кинотеатр':
        return 'cinema';
      case 'Театр':
        return 'theatre';
      case 'Карaоке':
      case 'Karaoke':
        return 'karaoke';
      case 'Кальянная':
      case 'Кальянные':
        return 'hookah';
      case 'Баня / Сауна':
      case 'Баня и сауна':
      case 'Бани Сауны':
      case 'Баня':
      case 'Сауна':
        return 'bathhouse';
      default:
        throw Exception('Неизвестный тип места');
    }
  }

  String _extractServerErrorMessage(Object error) {
    String combined = '';

    if (error is PostgrestException) {
      combined = [
        error.message,
        error.details,
        error.hint,
        error.code,
      ].whereType<String>().join(' | ');
    } else {
      combined = error.toString();
    }

    final lower = combined.toLowerCase();

    if (lower.contains('такое место уже есть в списке') ||
        lower.contains('already exists in the list') ||
        lower.contains('duplicate') ||
        lower.contains('23505')) {
      return 'Такое место уже есть в списке.';
    }

    if (lower.contains('пользователь не найден') ||
        lower.contains('user not found') ||
        lower.contains('not authenticated') ||
        lower.contains('unauthorized') ||
        lower.contains('jwt') ||
        lower.contains('auth')) {
      return 'Не удалось определить пользователя.';
    }

    if (lower.contains('required') ||
        lower.contains('обязател') ||
        lower.contains('invalid') ||
        lower.contains('неизвестный тип места')) {
      return 'Проверьте заполнение полей.';
    }

    return 'Не удалось добавить место.';
  }

  Future<void> _openAddPlaceDialog() async {
    if (_creatingPlaceSubmission) return;

    final result = await showDialog<AddPlaceDialogResult>(
      context: context,
      builder: (_) => const AddPlaceDialog(),
    );

    if (!mounted || result == null) return;

    setState(() => _creatingPlaceSubmission = true);

    try {
      final appUserId = await _resolveCurrentAppUserId();
      final category = _mapDialogTypeToServerCategory(result.typeLabel);

      await Supabase.instance.client.rpc(
        'create_place_submission_v1',
        params: {
          'p_app_user_id': appUserId,
          'p_title': result.name,
          'p_category': category,
          'p_city': result.city,
          'p_street': result.street,
          'p_house': result.house,
          'p_website': result.website,
        },
      );

      if (!mounted) return;

      await showCenterToast(
        context,
        message: 'Место отправлено на модерацию.',
      );
    } catch (error) {
      if (!mounted) return;

      await showCenterToast(
        context,
        message: _extractServerErrorMessage(error),
        isError: true,
      );
    } finally {
      if (mounted) {
        setState(() => _creatingPlaceSubmission = false);
      }
    }
  }

  PlaceUiModel _mapToUi(PlaceDto dto) {
    return PlaceUiModel(
      dto: dto,
      title: dto.title,
      type: dto.type,
      address: dto.address,
      cityName: dto.cityName,
      areaName: dto.areaName,
      distanceM: dto.distanceM,
    );
  }

  Widget _buildSearchBlock(BuildContext context) {
    final theme = Theme.of(context);
    final borderColor = theme.dividerColor.withValues(alpha: 0.25);

    final canClear = (_searchController.text.trim().isNotEmpty) ||
        (_appliedSearchTitle != null && _appliedSearchTitle!.isNotEmpty);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocus,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _onFindPressed(),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(vertical: 0),
                    border: InputBorder.none,
                    hintText: 'Название места',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity:
                      const VisualDensity(horizontal: -2, vertical: -2),
                ),
                onPressed: _onFindPressed,
                child: const Text('Найти'),
              ),
              if (canClear) ...[
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Очистить',
                  onPressed: _onClearSearch,
                  icon: const Icon(Icons.close),
                ),
              ],
            ],
          ),
        ),
        if (_searchLoading)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(left: 6, top: 6),
              child: Text(
                'Поиск...',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ),
          ),
        if (!_searchLoading && _suggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: borderColor),
            ),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: _suggestions.length,
              separatorBuilder: (_, __) => Divider(
                height: 0.5,
                thickness: 1,
                color: borderColor,
              ),
              itemBuilder: (context, i) {
                final title = _suggestions[i];
                return InkWell(
                  onTap: () => _applySuggestion(title),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              GestureDetector(
                onTap: _creatingPlaceSubmission ? null : _openAddPlaceDialog,
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 150),
                  opacity: _creatingPlaceSubmission ? 0.7 : 1,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainer,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                    child: Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_creatingPlaceSubmission) ...[
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Text(
                            _creatingPlaceSubmission
                                ? 'Отправляем...'
                                : 'Добавить новое место',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _buildSearchBlock(context),
              _ActiveFilterChips(
                controller: widget.filtersController,
                onRemove: (filterId) {
                  widget.filtersController.removeFilter(filterId);
                  _loadInitial();
                },
              ),
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: _places.length + (_loading ? 1 : 0),
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index >= _places.length) {
                      return const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }

                    final place = _places[index];

                    return PlaceCard(
                      place: place,
                      onDetailsTap: () async {
                        final isAlreadyInCurrentPlan =
                            widget.currentPlanPlaceIds.contains(place.dto.id);

                        final result = await showDialog<Object?>(
                          context: context,
                          builder: (_) => PlaceDetailsDialog(
                            repository: widget.repository,
                            placeId: place.dto.id,
                            title: place.dto.title,
                            typeLabel: place.typeLabel,
                            categoryCode: place.dto.categories.isNotEmpty
                                ? place.dto.categories.first
                                : place.dto.type,
                            address: place.dto.address,
                            lat: place.dto.lat,
                            lng: place.dto.lng,
                            previewMediaUrl: place.dto.previewMediaUrl,
                            previewStorageKey: place.dto.previewStorageKey,
                            previewIsPlaceholder:
                                place.dto.previewIsPlaceholder,
                            metroName: place.dto.metroName,
                            metroDistanceM: place.dto.metroDistanceM,
                            websiteUrl: place.dto.websiteUrl,
                            sourcePlanId: widget.sourcePlanId,
                            sourcePlanTitle: widget.sourcePlanTitle,
                            isAlreadyInCurrentPlan: isAlreadyInCurrentPlan,
                            onRemoveFromCurrentPlan: isAlreadyInCurrentPlan &&
                                    widget.onRemoveFromCurrentPlan != null
                                ? () => widget.onRemoveFromCurrentPlan!(
                                      place.dto.id,
                                    )
                                : null,
                          ),
                        );

                        if (!mounted || result == null) return;
                        await widget.onPlaceDialogResult(result);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (_showScrollToTop)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: () => _scrollController.animateTo(
                0,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              ),
              child: const Icon(Icons.arrow_upward),
            ),
          ),
      ],
    );
  }
}

/* =======================
   PLACE CARD
   ======================= */

class PlaceCard extends StatelessWidget {
  final PlaceUiModel place;
  final VoidCallback onDetailsTap;

  const PlaceCard({
    super.key,
    required this.place,
    required this.onDetailsTap,
  });

  @override
  Widget build(BuildContext context) {
    final cardRadius = BorderRadius.circular(16);

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: cardRadius,
      child: InkWell(
        borderRadius: cardRadius,
        onTap: onDetailsTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 72,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Builder(
                            builder: (_) {
                              final category =
                                  place.dto.categories.isNotEmpty
                                      ? place.dto.categories.first
                                      : place.dto.type;
                              final catUrl = categoryPlaceholderUrl(
                                  category, place.dto.id);

                              Widget fallback() => catUrl != null
                                  ? Image.network(
                                      catUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          Image.asset(
                                        'assets/images/place_placeholder.png',
                                        fit: BoxFit.cover,
                                      ),
                                    )
                                  : Image.asset(
                                      'assets/images/place_placeholder.png',
                                      fit: BoxFit.cover,
                                    );

                              final url = place.dto.previewMediaUrl;
                              if (url != null && url.isNotEmpty) {
                                return Image.network(
                                  url,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => fallback(),
                                );
                              }

                              final key = place.dto.previewStorageKey;
                              if (key != null && key.isNotEmpty) {
                                final publicUrl = Supabase
                                    .instance.client.storage
                                    .from('brand-media')
                                    .getPublicUrl(key);
                                return Image.network(
                                  publicUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => fallback(),
                                );
                              }

                              return fallback();
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      if (place.dto.rating != null)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              place.dto.rating!.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        place.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (place.distanceLabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          place.distanceLabel!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: place.distanceColor,
                            height: 1.0,
                          ),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        place.typeLabel,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        place.areaName != null
                            ? '${place.cityName} · ${place.areaName}'
                            : place.cityName,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey.shade500),
                      ),
                      if (place.metroName != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          'м.${place.metroName}'
                          '${place.metroDistanceM != null ? " · ${place.metroDistanceM} м" : ""}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey.shade500),
                        ),
                      ],
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

/* =======================
   VIEW MODE TOGGLE
   ======================= */

class _ViewModeToggle extends StatelessWidget {
  final PlacesViewMode value;
  final ValueChanged<PlacesViewMode> onChanged;

  const _ViewModeToggle({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: SegmentedButton<PlacesViewMode>(
        segments: const [
          ButtonSegment(
            value: PlacesViewMode.list,
            icon: Icon(Icons.list),
          ),
          ButtonSegment(
            value: PlacesViewMode.map,
            icon: Icon(Icons.map),
          ),
        ],
        selected: {value},
        onSelectionChanged: (set) => onChanged(set.first),
      ),
    );
  }
}

/* =======================
   ACTIVE FILTER CHIPS
   ======================= */

class _ActiveFilterChips extends StatefulWidget {
  final PlacesFiltersController controller;
  final void Function(String filterId) onRemove;

  const _ActiveFilterChips({
    required this.controller,
    required this.onRemove,
  });

  @override
  State<_ActiveFilterChips> createState() => _ActiveFilterChipsState();
}

class _ActiveFilterChipsState extends State<_ActiveFilterChips> {
  final _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollController.position;
    final left = pos.pixels > 0;
    final right = pos.pixels < pos.maxScrollExtent;
    if (left != _canScrollLeft || right != _canScrollRight) {
      setState(() {
        _canScrollLeft = left;
        _canScrollRight = right;
      });
    }
  }

  // После рендера проверяем нужны ли стрелки вообще
  void _checkAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final pos = _scrollController.position;
      final right = pos.maxScrollExtent > 0;
      if (right != _canScrollRight) {
        setState(() => _canScrollRight = right);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final filters = widget.controller.activeFilters;
        if (filters.isEmpty) return const SizedBox.shrink();

        _checkAfterBuild();

        final colors = Theme.of(context).colorScheme;
        final arrowColor = colors.primary;
        const arrowSize = 24.0;
        const fadeWidth = 32.0;

        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: SizedBox(
            height: 36,
            child: Stack(
              children: [
                ListView.separated(
                  controller: _scrollController,
                  scrollDirection: Axis.horizontal,
                  itemCount: filters.length,
                  padding: EdgeInsets.only(
                    left: _canScrollLeft ? fadeWidth : 0,
                    right: _canScrollRight ? fadeWidth : 0,
                  ),
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, i) {
                    final f = filters[i];
                    return InputChip(
                      label: Text(f.title),
                      onDeleted: () => widget.onRemove(f.id),
                      visualDensity: VisualDensity.compact,
                    );
                  },
                ),

                // Левая стрелка + фейд
                if (_canScrollLeft)
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: fadeWidth,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colors.surface,
                              colors.surface.withValues(alpha: 0),
                            ],
                          ),
                        ),
                        alignment: Alignment.centerLeft,
                        child: Icon(Icons.chevron_left,
                            size: arrowSize, color: arrowColor),
                      ),
                    ),
                  ),

                // Правая стрелка + фейд
                if (_canScrollRight)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: fadeWidth,
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              colors.surface.withValues(alpha: 0),
                              colors.surface,
                            ],
                          ),
                        ),
                        alignment: Alignment.centerRight,
                        child: Icon(Icons.chevron_right,
                            size: arrowSize, color: arrowColor),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/* =======================
   UI MODEL
   ======================= */

class PlaceUiModel {
  final PlaceDto dto;

  final String title;
  final String type;
  final String address;
  final String cityName;
  final String? areaName;
  final double? distanceM;

  String? get metroName => dto.metroName;
  int? get metroDistanceM => dto.metroDistanceM;

  PlaceUiModel({
    required this.dto,
    required this.title,
    required this.type,
    required this.address,
    required this.cityName,
    required this.areaName,
    required this.distanceM,
  });

  String get typeLabel {
    final displays = dto.categoriesDisplay;
    if (displays != null && displays.isNotEmpty) {
      return displays.join(' · ');
    }
    if (dto.typeDisplay != null && dto.typeDisplay!.isNotEmpty) {
      return dto.typeDisplay!;
    }
    switch (type) {
      case 'restaurant':  return 'Ресторан';
      case 'bar':         return 'Бар';
      case 'nightclub':   return 'Ночной клуб';
      case 'cinema':      return 'Кинотеатр';
      case 'theatre':     return 'Театр';
      case 'karaoke':     return 'Карaоке';
      case 'hookah':      return 'Кальянная';
      case 'bathhouse':   return 'Баня / Сауна';
      default:            return 'Место';
    }
  }

  String? get distanceLabel {
    if (distanceM == null) return null;

    if (distanceM! < 1000) {
      return '${distanceM!.round()} м от вас';
    }

    final km = distanceM! / 1000;
    final digits = km < 10 ? 2 : 1;
    return '${km.toStringAsFixed(digits)} км от вас';
  }

  Color get distanceColor {
    if (distanceM == null) return Colors.transparent;

    if (distanceM! < 1000) {
      return const Color(0xFF2E7D32);
    } else if (distanceM! < 5000) {
      return const Color.fromARGB(255, 241, 241, 8);
    } else if (distanceM! < 10000) {
      return const Color(0xFFEF6C00);
    } else {
      return const Color(0xFFC62828);
    }
  }
}
