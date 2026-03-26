import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/geo/geo_service.dart';
import '../../../data/places/place_dto.dart';
import '../../../data/places/places_repository.dart';
import '../filters/places_filters_controller.dart';
import '../details/place_details_dialog.dart';

class PlacesMap extends StatefulWidget {
  final PlacesRepository repository;
  final PlacesFiltersController filtersController;

  final ValueListenable<PlaceDto?>? focusPlace;
  final String? sourcePlanId;
  final String? sourcePlanTitle;
  final Set<String> currentPlanPlaceIds;
  final Future<void> Function(String placeId)? onRemoveFromCurrentPlan;
  final Future<void> Function(Object? result)? onPlaceDialogResult;

  const PlacesMap({
    super.key,
    required this.repository,
    required this.filtersController,
    this.focusPlace,
    this.sourcePlanId,
    this.sourcePlanTitle,
    this.currentPlanPlaceIds = const <String>{},
    this.onRemoveFromCurrentPlan,
    this.onPlaceDialogResult,
  });

  @override
  State<PlacesMap> createState() => _PlacesMapState();
}

class _PlacesMapState extends State<PlacesMap> {
  final MapController _mapController = MapController();

  bool _mapReady = false;
  bool _loading = false;

  List<PlaceDto> _items = const [];

  Timer? _debounceViewport;
  Timer? _debounceLabels;

  double _currentZoom = 14.0;
  LatLng? _currentCenter;

  String? _userAvatarUrl;

  /// 🔴 Live invalidation subscription
  late final StreamSubscription<void> _repoInvalidationSub;

  static const double _labelZoomThreshold = 15.8;
  static const int _maxLabeledPlaces = 12;

  static const double _labelMaxWidth = 100;
  static const double _iconMarkerSize = 40;

  static const double _focusZoom = 17.0;
  static const double _userZoom = 16.0;

  final Distance _distance = const Distance();

  Set<String> _visibleLabelIds = <String>{};

  PlaceDto? _pendingFocusPlace;

  /// Предыдущие cityIds/areaIds для определения смены локации
  List<String> _lastCityIds = const [];
  List<String> _lastAreaIds = const [];

  @override
  void initState() {
    super.initState();

    /// 🔴 Подписка на live invalidation
    _repoInvalidationSub = widget.repository.invalidations.listen((_) {
      if (_mapReady) {
        _scheduleLoadByViewport();
      }
    });

    _loadUserAvatar();
    widget.filtersController.addListener(_onFiltersChanged);
    widget.focusPlace?.addListener(_onExternalFocusRequested);
    _pendingFocusPlace = widget.focusPlace?.value;
  }

  Future<void> _loadUserAvatar() async {
    try {
      final res = await Supabase.instance.client.rpc('current_user');
      if (!mounted || res is! Map) return;
      final url = res['avatar_url'] as String?;
      if (url != null && url.isNotEmpty) {
        setState(() => _userAvatarUrl = url);
      }
    } catch (e) {
      debugPrint('[PlacesMap] loadUserAvatar error: $e');
    }
  }

  void _onFiltersChanged() {
    final payload = widget.filtersController.buildPayload();
    final newCityIds = payload.cityIds ?? const [];
    final newAreaIds = payload.areaIds ?? const [];

    final cityChanged = !_listEquals(_lastCityIds, newCityIds);
    final areaChanged = !_listEquals(_lastAreaIds, newAreaIds);

    // Обновляем всегда — даже если карта ещё не ready,
    // чтобы init() из prefs не вызывал ложный cityChanged
    _lastCityIds = List<String>.from(newCityIds);
    _lastAreaIds = List<String>.from(newAreaIds);

    if (!_mapReady) return;

    if (cityChanged || areaChanged) {
      if (newCityIds.isEmpty && newAreaIds.isEmpty) {
        // Сброс фильтра → возврат к геопозиции (zoom 14, как при первом открытии карты)
        final geo = GeoService.instance.current.value;
        if (geo != null) {
          _mapController.move(LatLng(geo.lat, geo.lng), 14.0);
          final cam = _mapController.camera;
          setState(() {
            _currentZoom = cam.zoom;
            _currentCenter = cam.center;
          });
          _scheduleRecomputeLabels();
        }
        _scheduleLoadByViewport();
        return;
      }

      // Центрируем на районе (если выбран), иначе на городе
      final usedAreaIds = newAreaIds.isNotEmpty ? newAreaIds : null;
      final usedCityIds = newAreaIds.isEmpty ? newCityIds : null;

      widget.repository
          .getCenterForFilter(cityIds: usedCityIds, areaIds: usedAreaIds)
          .then((center) {
        if (!mounted || center == null) return;
        final newCenter = LatLng(center['lat']!, center['lng']!);

        // Если текущая позиция камеры уже близко к новому центру (< 50 км) —
        // не сбрасываем позицию и зум, просто перегружаем маркеры
        final cur = _currentCenter;
        final distToNew =
            cur != null ? _distance(cur, newCenter) : double.infinity;

        if (distToNew > 50000) {
          _mapController.move(newCenter, 12.0);
          final cam = _mapController.camera;
          setState(() {
            _currentZoom = cam.zoom;
            _currentCenter = cam.center;
          });
        }
        _scheduleLoadByViewport();
        _scheduleRecomputeLabels();
      });
    } else {
      // Только тип/рейтинг изменился — остаёмся на месте, перегружаем маркеры
      _scheduleLoadByViewport();
    }
  }

  bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _repoInvalidationSub.cancel(); // 🔴
    widget.filtersController.removeListener(_onFiltersChanged);
    widget.focusPlace?.removeListener(_onExternalFocusRequested);
    _debounceViewport?.cancel();
    _debounceLabels?.cancel();
    super.dispose();
  }

  void _onExternalFocusRequested() {
    final place = widget.focusPlace?.value;
    if (place == null) return;

    if (!_mapReady) {
      _pendingFocusPlace = place;
      return;
    }

    _focusOnPlace(place);
  }

  void _focusOnPlace(PlaceDto place) {
    final targetZoom = _focusZoom.clamp(3.0, 20.5);

    _mapController.move(
      LatLng(place.lat, place.lng),
      targetZoom,
    );

    final cam = _mapController.camera;
    setState(() {
      _currentZoom = cam.zoom;
      _currentCenter = cam.center;
    });

    _scheduleRecomputeLabels();
    _scheduleLoadByViewport();
  }

  void _focusOnUser(LatLng user) {
    _mapController.move(user, _userZoom);

    final cam = _mapController.camera;
    setState(() {
      _currentZoom = cam.zoom;
      _currentCenter = cam.center;
    });

    _scheduleRecomputeLabels();
    _scheduleLoadByViewport();
  }

  void _scheduleLoadByViewport() {
    _debounceViewport?.cancel();
    _debounceViewport =
        Timer(const Duration(milliseconds: 250), _loadByViewport);
  }

  Future<void> _loadByViewport() async {
    if (!_mapReady || _loading) return;

    final bounds = _mapController.camera.visibleBounds;

    setState(() => _loading = true);

    try {
      final payload = widget.filtersController.buildPayload();

      final items = await widget.repository.loadPlacesMap(
        minLat: bounds.south,
        minLng: bounds.west,
        maxLat: bounds.north,
        maxLng: bounds.east,
        cityIds: payload.cityIds,
        areaIds: payload.areaIds,
        types: payload.types,
        minRating: payload.minRating,
      );

      if (!mounted) return;

      setState(() {
        _items = items;
        _loading = false;
      });

      _scheduleRecomputeLabels();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _loading = false;
      });
    }
  }

  bool get _labelsAllowedByZoom => _currentZoom >= _labelZoomThreshold;

  void _scheduleRecomputeLabels() {
    _debounceLabels?.cancel();
    _debounceLabels =
        Timer(const Duration(milliseconds: 120), _recomputeLabels);
  }

  void _recomputeLabels() {
    if (!_labelsAllowedByZoom || _items.isEmpty) {
      setState(() => _visibleLabelIds = <String>{});
      return;
    }

    final center = _currentCenter ?? _mapController.camera.center;

    final sorted = List<PlaceDto>.of(_items)
      ..sort((a, b) {
        final da = _distance.as(
          LengthUnit.Meter,
          center,
          LatLng(a.lat, a.lng),
        );
        final db = _distance.as(
          LengthUnit.Meter,
          center,
          LatLng(b.lat, b.lng),
        );
        return da.compareTo(db);
      });

    final next = <String>{};
    for (var i = 0; i < sorted.length && i < _maxLabeledPlaces; i++) {
      next.add(sorted[i].id);
    }

    setState(() => _visibleLabelIds = next);
  }

  Marker _buildUserMarker(LatLng pos) {
    const double size = 40;
    const double borderW = 3;

    return Marker(
      width: size,
      height: size,
      point: pos,
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Colors.red, width: borderW),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: ClipOval(
          child: _userAvatarUrl != null
              ? CachedNetworkImage(
                  imageUrl: _userAvatarUrl!,
                  width: size - borderW * 2,
                  height: size - borderW * 2,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => _defaultUserIcon(size - borderW * 2),
                  errorWidget: (_, __, ___) => _defaultUserIcon(size - borderW * 2),
                )
              : _defaultUserIcon(size - borderW * 2),
        ),
      ),
    );
  }

  Widget _defaultUserIcon(double s) {
    return Image.asset(
      'assets/images/map_markers/default.png',
      width: s,
      height: s,
      fit: BoxFit.cover,
    );
  }

  static const _markerAssets = <String, String>{
    'restaurant': 'assets/images/map_markers/restaurant.png',
    'bar':        'assets/images/map_markers/bar.png',
    'nightclub':  'assets/images/map_markers/nightclub.png',
    'cinema':     'assets/images/map_markers/cinema.png',
    'theatre':    'assets/images/map_markers/theatre.png',
    'karaoke':    'assets/images/map_markers/karaoke.png',
    'hookah':     'assets/images/map_markers/hookah.png',
    'bathhouse':  'assets/images/map_markers/bathhouse.png',
  };

  static const _defaultMarkerAsset = 'assets/images/map_markers/restaurant.png';

  String _assetForType(String type) =>
      _markerAssets[type] ?? _defaultMarkerAsset;

  double _iconScale() {
    final t = ((_currentZoom - 13) / 5).clamp(0.0, 1.0);
    return lerpDouble(1.0, 1.35, t) ?? 1.1;
  }

  Widget _markerIcon(String assetPath) {
    final size = 28.0 * _iconScale();
    return Image.asset(
      assetPath,
      width: size,
      height: size,
      filterQuality: FilterQuality.medium,
    );
  }

  /// Иконка-маркер места — компактный бокс, center-aligned, без дрейфа.
  Marker _buildMarker(BuildContext context, PlaceDto place) {
    return Marker(
      width: _iconMarkerSize,
      height: _iconMarkerSize,
      alignment: Alignment.center,
      point: LatLng(place.lat, place.lng),
      child: IgnorePointer(
        child: _markerIcon(_assetForType(
          place.categories.isNotEmpty ? place.categories.first : place.type,
        )),
      ),
    );
  }

  /// Лейбл места — отдельный маркер над иконкой.
  /// Geo-точка ниже виджета: нижний край лейбла ~30px выше geo-точки (зазор ~10px от иконки).
  /// offset_bottom = 0.5 * H * (1 - y) → 0.5 * 60 * (1 - 2.0) = -30px (выше geo-точки).
  Marker _buildLabelMarker(BuildContext context, PlaceDto place) {
    return Marker(
      width: 120,
      height: 60,
      alignment: const Alignment(0, -1.7),
      point: LatLng(place.lat, place.lng),
      child: _label(context, place),
    );
  }

  Widget _label(BuildContext context, PlaceDto place) {
    const titleStyle = TextStyle(
      fontSize: 11,
      color: Colors.white,
      fontWeight: FontWeight.w700,
      height: 1.1,
    );

    const secondaryStyle = TextStyle(
      fontSize: 10,
      color: Colors.white70,
      fontWeight: FontWeight.w600,
      height: 1.1,
    );

    final double effectiveRating = place.rating ?? 3.0;
    final isAlreadyInCurrentPlan = widget.currentPlanPlaceIds.contains(place.id);

    return GestureDetector(
      onTap: () async {
        final result = await showDialog<Object?>(
          context: context,
          builder: (_) => PlaceDetailsDialog(
            repository: widget.repository,
            placeId: place.id,
            title: place.title,
            typeLabel: place.categoriesDisplay?.join(' · ') ?? _typeLabel(place.type),
            categoryCode: place.categories.isNotEmpty
                ? place.categories.first
                : place.type,
            address:
                place.address.isNotEmpty ? place.address : 'Адрес не указан',
            lat: place.lat,
            lng: place.lng,
            previewMediaUrl: place.previewMediaUrl,
            previewStorageKey: place.previewStorageKey,
            previewIsPlaceholder: place.previewIsPlaceholder,
            metroName: place.metroName,
            metroDistanceM: place.metroDistanceM,
            websiteUrl: place.websiteUrl,
            sourcePlanId: widget.sourcePlanId,
            sourcePlanTitle: widget.sourcePlanTitle,
            isAlreadyInCurrentPlan: isAlreadyInCurrentPlan,
            onRemoveFromCurrentPlan:
                isAlreadyInCurrentPlan && widget.onRemoveFromCurrentPlan != null
                    ? () => widget.onRemoveFromCurrentPlan!(place.id)
                    : null,
          ),
        );

        if (!mounted) return;

        if (result != null && widget.onPlaceDialogResult != null) {
          await widget.onPlaceDialogResult!(result);
        }
      },
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _labelMaxWidth),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  place.categoriesDisplay?.join(' · ') ?? _typeLabel(place.type),
                  style: secondaryStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 1),
                Text(
                  place.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: titleStyle,
                ),
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star, size: 11, color: Colors.amber),
                    const SizedBox(width: 2),
                    Text(
                      effectiveRating.toStringAsFixed(1),
                      style: secondaryStyle,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _typeLabel(String type) {
    switch (type) {
      case 'restaurant': return 'Ресторан';
      case 'bar':        return 'Бар';
      case 'nightclub':  return 'Ночной клуб';
      case 'cinema':     return 'Кинотеатр';
      case 'theatre':    return 'Театр';
      case 'karaoke':    return 'Карaоке';
      case 'hookah':     return 'Кальянная';
      case 'bathhouse':  return 'Баня / Сауна';
      default:           return 'Место';
    }
  }

  @override
  Widget build(BuildContext context) {
    final geo = GeoService.instance.current.value;
    final userPos = geo != null ? LatLng(geo.lat, geo.lng) : null;

    final initialCenter = userPos ?? const LatLng(55.751244, 37.618423);

    final placeMarkers = _items.map((p) => _buildMarker(context, p)).toList();

    // Лейблы — отдельный слой над кластерами, только для видимых мест
    final labelMarkers = _labelsAllowedByZoom
        ? _items
            .where((p) => _visibleLabelIds.contains(p.id))
            .map((p) => _buildLabelMarker(context, p))
            .toList()
        : <Marker>[];

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: geo != null ? 14 : 11,
            minZoom: 3,
            maxZoom: 22.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _mapReady = true;

              final cam = _mapController.camera;
              _currentZoom = cam.zoom;
              _currentCenter = cam.center;

              // Инициализируем last-состояние фильтров из текущего контроллера,
              // чтобы первый _onFiltersChanged после init() не считал смену города
              // и не двигал карту при применении только типового фильтра.
              final initPayload = widget.filtersController.buildPayload();
              _lastCityIds = initPayload.cityIds ?? const [];
              _lastAreaIds = initPayload.areaIds ?? const [];

              // Всегда немедленно запускаем загрузку маркеров по текущему viewport.
              _scheduleLoadByViewport();
              _scheduleRecomputeLabels();

              // Если при открытии карты уже активен фильтр города/района —
              // дополнительно центрируем камеру на нём (если далеко > 50 км).
              final hasCityFilter =
                  (initPayload.cityIds?.isNotEmpty ?? false) ||
                  (initPayload.areaIds?.isNotEmpty ?? false);

              if (hasCityFilter) {
                final usedAreaIds =
                    initPayload.areaIds?.isNotEmpty == true
                        ? initPayload.areaIds
                        : null;
                final usedCityIds =
                    usedAreaIds == null ? initPayload.cityIds : null;

                widget.repository
                    .getCenterForFilter(
                        cityIds: usedCityIds, areaIds: usedAreaIds)
                    .then((center) {
                  if (!mounted || center == null) return;
                  final newCenter =
                      LatLng(center['lat']!, center['lng']!);
                  final cur = _currentCenter;
                  final dist = cur != null
                      ? _distance(cur, newCenter)
                      : double.infinity;

                  if (dist > 50000) {
                    _mapController.move(newCenter, 12.0);
                    final updatedCam = _mapController.camera;
                    setState(() {
                      _currentZoom = updatedCam.zoom;
                      _currentCenter = updatedCam.center;
                    });
                    // После перемещения перегружаем маркеры для нового viewport
                    _scheduleLoadByViewport();
                  }
                });
              }

              final pending = _pendingFocusPlace;
              _pendingFocusPlace = null;
              if (pending != null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  _focusOnPlace(pending);
                });
              }
            },
            onPositionChanged: (_, __) {
              final cam = _mapController.camera;
              setState(() {
                _currentZoom = cam.zoom;
                _currentCenter = cam.center;
              });
              _scheduleRecomputeLabels();
              _scheduleLoadByViewport();
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.centry.app',
              maxNativeZoom: 19,
              maxZoom: 22,
            ),
            if (userPos != null)
              MarkerLayer(
                markers: [
                  _buildUserMarker(userPos),
                ],
              ),
            MarkerClusterLayerWidget(
              options: MarkerClusterLayerOptions(
                markers: placeMarkers,
                maxClusterRadius: 45,
                disableClusteringAtZoom: 16,
                size: const Size(40, 40),
                builder: (context, markers) {
                  return Container(
                    decoration: const BoxDecoration(
                      color: Colors.black87,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      markers.length.toString(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  );
                },
              ),
            ),
            if (labelMarkers.isNotEmpty)
              MarkerLayer(markers: labelMarkers),
          ],
        ),
        if (userPos != null)
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: () => _focusOnUser(userPos),
              child: const Icon(Icons.my_location),
            ),
          ),
      ],
    );
  }
}
