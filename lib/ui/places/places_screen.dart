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
import '../../data/places/places_repository_impl.dart';
import 'package:centry/features/places/geo_info/places_geo_info_controller.dart';
import 'package:centry/features/places/geo_info/places_geo_info_dialog.dart';

// ФИЛЬТРЫ
import 'package:centry/features/places/filters/places_filters_controller.dart';
import 'package:centry/features/places/filters/places_filters_dialog.dart';

// КАРТА
import 'package:centry/features/places/map/places_map.dart';
import 'package:centry/features/places/details/place_details_dialog.dart';
import 'package:centry/features/places/add_place/add_place_dialog.dart';
import 'package:centry/ui/common/center_toast.dart';

enum PlacesViewMode {
  list,
  map,
}

class PlacesScreen extends StatefulWidget {
  const PlacesScreen({super.key});

  @override
  State<PlacesScreen> createState() => _PlacesScreenState();
}

class _PlacesScreenState extends State<PlacesScreen> {
  PlacesViewMode _viewMode = PlacesViewMode.list;

  final _geoInfoController = PlacesGeoInfoController();
  final _filtersController = PlacesFiltersController();
  late final PlacesRepository _repository;

  final ValueNotifier<int> _reloadSignal = ValueNotifier<int>(0);

  /// 🔴 Live invalidation subscription
  late final StreamSubscription<void> _repoInvalidationSub;

  /// UI-сигнал: сфокусировать карту на конкретном месте (из списка).
  final ValueNotifier<PlaceDto?> _mapFocusPlace =
      ValueNotifier<PlaceDto?>(null);

  @override
  void initState() {
    super.initState();
    _repository = PlacesRepositoryImpl(Supabase.instance.client);

    /// 🔴 Подписка на live invalidation
    _repoInvalidationSub = _repository.invalidations.listen((_) {
      _reloadSignal.value++;
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

    Future<Map<String, dynamic>> loadServerState() {
      return _repository.loadPlacesFiltersState(
        lat: geo?.lat,
        lng: geo?.lng,
        selectedCityIds: _filtersController.state.cityIds,
        selectedAreaIds: _filtersController.state.areaIds,
        selectedTypes: _filtersController.state.types,
      );
    }

    final serverState = await loadServerState();
    _filtersController.applyServerState(serverState);

    final available = serverState['available'] as Map<String, dynamic>? ?? {};
    final citiesJson = available['cities'] as List? ?? const [];
    final typesJson = available['types'] as List? ?? const [];
    final areasJson = available['areas'] as List? ?? const [];

    final initialCities = citiesJson
        .whereType<Map>()
        .map((e) => PlacesFilterItem(
              id: e['id'].toString(),
              title: e['title'].toString(),
            ))
        .toList();

    final initialTypes = typesJson
        .whereType<Map>()
        .map((e) => PlacesFilterItem(
              id: e['type'].toString(),
              title: e['type'].toString(),
            ))
        .toList();

    final initialAreas = areasJson
        .whereType<Map>()
        .map((e) => PlacesFilterItem(
              id: e['id'].toString(),
              title: e['title'].toString(),
            ))
        .toList();

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => PlacesFiltersDialog(
        controller: _filtersController,
        initialCities: initialCities,
        initialTypes: initialTypes,
        initialAreas: initialAreas,
        loadServerState: loadServerState,
      ),
    );

    final normalized = await loadServerState();
    _filtersController.applyServerState(normalized);

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
            )
          : PlacesMap(
              repository: _repository,
              filtersController: _filtersController,
              focusPlace: _mapFocusPlace,
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
  });

  final PlacesRepository repository;
  final PlacesFiltersController filtersController;
  final ValueListenable<int> reloadSignal;
  final ValueChanged<PlaceDto> onOpenOnMap;

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
        if (kDebugMode) debugPrint('PLACES suggestions error: $e');
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
    _places.clear();
    _offset = 0;
    _hasMore = true;
    setState(() {});
    await _loadNext();
  }

  Future<void> _loadNext() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);

    try {
      final payload = widget.filtersController.buildPayload();

      final PlacesFeedResult result = await widget.repository.loadPlacesFeed(
        cityIds: payload.cityIds,
        areaIds: payload.areaIds,
        types: payload.types,
        searchTitle: _appliedSearchTitle,
        limit: _pageSize,
        offset: _offset,
      );

      final uiItems = result.items.map(_mapToUi).toList();

      setState(() {
        _places.addAll(uiItems);
        _hasMore = result.hasMore;
        _offset += uiItems.length;
        _loading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('PLACES loadNext error: $e');
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
        if (kDebugMode) {
          debugPrint('PLACES user_snapshot parse error: $e');
        }
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
        return 'cinema';
      case 'Театр':
        return 'theatre';
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
      if (kDebugMode) {
        debugPrint('PLACE SUBMISSION create error: $error');
      }

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
    final borderColor = theme.dividerColor.withOpacity(0.25);

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
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  controller: _scrollController,
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
                      onDetailsTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (_) => PlaceDetailsDialog(
                            repository: widget.repository,
                            placeId: place.dto.id,
                            title: place.dto.title,
                            typeLabel: place.typeLabel,
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
                          ),
                        );
                      },
                      onMapTap: () {
                        widget.onOpenOnMap(place.dto);
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
  final VoidCallback onMapTap;

  const PlaceCard({
    super.key,
    required this.place,
    required this.onDetailsTap,
    required this.onMapTap,
  });

  @override
  Widget build(BuildContext context) {
    final compactTextButtonStyle = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    );

    final linkStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
          height: 1.05,
        );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 96),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
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
                          final url = place.dto.previewMediaUrl;

                          if (url != null && url.isNotEmpty) {
                            return Image.network(
                              url,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Image.asset(
                                  'assets/images/place_placeholder.png',
                                  fit: BoxFit.cover,
                                );
                              },
                            );
                          }

                          final key = place.dto.previewStorageKey;
                          if (key != null && key.isNotEmpty) {
                            final publicUrl = Supabase.instance.client.storage
                                .from('brand-media')
                                .getPublicUrl(key);

                            return Image.network(
                              publicUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Image.asset(
                                  'assets/images/place_placeholder.png',
                                  fit: BoxFit.cover,
                                );
                              },
                            );
                          }

                          return Image.asset(
                            'assets/images/place_placeholder.png',
                            fit: BoxFit.cover,
                          );
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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          place.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      TextButton(
                        style: compactTextButtonStyle,
                        onPressed: onMapTap,
                        child: Text(
                          'Посмотреть\nна карте',
                          textAlign: TextAlign.right,
                          style: linkStyle,
                        ),
                      ),
                    ],
                  ),
                  if (place.distanceLabel != null)
                    Text(
                      place.distanceLabel!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: place.distanceColor,
                        height: 1.0,
                      ),
                    ),
                  const SizedBox(height: 2),
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
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: place.metroName != null
                            ? Text(
                                'м.${place.metroName}'
                                '${place.metroDistanceM != null ? " · ${place.metroDistanceM} м" : ""}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: Colors.grey.shade500),
                              )
                            : const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: compactTextButtonStyle,
                        onPressed: onDetailsTap,
                        child: const Text('Подробнее'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
    switch (type) {
      case 'restaurant':
        return 'Ресторан';
      case 'bar':
        return 'Бар';
      case 'nightclub':
        return 'Ночной клуб';
      case 'cinema':
        return 'Кинотеатр';
      case 'theatre':
        return 'Театр';
      default:
        return 'Место';
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
