import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_cluster/flutter_map_marker_cluster.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/geo/geo_service.dart';
import '../../../data/places/place_dto.dart';
import '../../../data/places/places_repository.dart';
import '../filters/places_filters_controller.dart';
import '../details/place_details_dialog.dart';

class PlacesMap extends StatefulWidget {
  final PlacesRepository repository;
  final PlacesFiltersController filtersController;

  final ValueListenable<PlaceDto?>? focusPlace;

  const PlacesMap({
    super.key,
    required this.repository,
    required this.filtersController,
    this.focusPlace,
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

  /// 🔴 Live invalidation subscription
  late final StreamSubscription<void> _repoInvalidationSub;

  static const double _labelZoomThreshold = 15.8;
  static const int _maxLabeledPlaces = 12;

  static const double _labelMaxWidth = 140;
  static const double _markerHeight = 110;

  static const double _focusZoom = 20.0;
  static const double _userZoom = 16.0;

  final Distance _distance = const Distance();

  Set<String> _visibleLabelIds = <String>{};

  PlaceDto? _pendingFocusPlace;

  @override
  void initState() {
    super.initState();

    /// 🔴 Подписка на live invalidation
    _repoInvalidationSub = widget.repository.invalidations.listen((_) {
      if (_mapReady) {
        _scheduleLoadByViewport();
      }
    });

    widget.focusPlace?.addListener(_onExternalFocusRequested);
    _pendingFocusPlace = widget.focusPlace?.value;
  }

  @override
  void dispose() {
    _repoInvalidationSub.cancel(); // 🔴
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
      );

      if (!mounted) return;

      setState(() {
        _items = items;
        _loading = false;
      });

      _scheduleRecomputeLabels();
    } catch (e) {
      if (kDebugMode) debugPrint('PLACES MAP load error: $e');
      if (!mounted) return;
      setState(() => _loading = false);
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
    return Marker(
      width: 36,
      height: 36,
      point: pos,
      alignment: Alignment.center,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.blueAccent,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 3),
        ),
      ),
    );
  }

  String _emojiForType(String type) {
    switch (type) {
      case 'restaurant':
        return '🍷';
      case 'bar':
        return '🍺';
      case 'nightclub':
        return '💃';
      case 'cinema':
        return '🎬';
      case 'theatre':
        return '🎭';
      default:
        return '📍';
    }
  }

  double _emojiScale() {
    final t = ((_currentZoom - 13) / 5).clamp(0.0, 1.0);
    return lerpDouble(1.0, 1.35, t) ?? 1.1; // увеличили чуть диапазон
  }

  Widget _markerIcon(String emoji) {
    final scale = _emojiScale();

    return Transform.scale(
      scale: scale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            emoji,
            style:
                const TextStyle(fontSize: 26, color: Colors.white), // было 24
          ),
          Text(
            emoji,
            style: const TextStyle(fontSize: 22), // было 20
          ),
        ],
      ),
    );
  }

  Marker _buildMarker(BuildContext context, PlaceDto place) {
    final showLabel =
        _labelsAllowedByZoom && _visibleLabelIds.contains(place.id);

    return Marker(
      width: _labelMaxWidth,
      height: _markerHeight,
      alignment: Alignment.bottomCenter,
      point: LatLng(place.lat, place.lng),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showLabel) _label(context, place),
          const SizedBox(height: 4),
          IgnorePointer(
            child: _markerIcon(_emojiForType(place.type)),
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, PlaceDto place) {
    final titleStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          height: 1.1,
        );

    final secondaryStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Colors.white70,
          fontWeight: FontWeight.w600,
          height: 1.1,
        );

    final double effectiveRating = place.rating ?? 3.0;

    return GestureDetector(
      onTap: () {
        showDialog<void>(
          context: context,
          builder: (_) => PlaceDetailsDialog(
            repository: widget.repository,
            placeId: place.id,
            title: place.title,
            typeLabel: _typeLabel(place.type),
            address:
                place.address.isNotEmpty ? place.address : 'Адрес не указан',
            lat: place.lat,
            lng: place.lng,
            previewMediaUrl: place.previewMediaUrl,
            websiteUrl: place.websiteUrl,
          ),
        );
      },
      child: Container(
        constraints: const BoxConstraints(maxWidth: _labelMaxWidth),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.72),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_typeLabel(place.type), style: secondaryStyle),
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
                const Icon(Icons.star, size: 12, color: Colors.amber),
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
    );
  }

  String _typeLabel(String type) {
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

  @override
  Widget build(BuildContext context) {
    final geo = GeoService.instance.current.value;
    final userPos = geo != null ? LatLng(geo.lat, geo.lng) : null;

    final initialCenter = userPos ?? const LatLng(55.751244, 37.618423);

    final placeMarkers = _items.map((p) => _buildMarker(context, p)).toList();

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: initialCenter,
            initialZoom: geo != null ? 14 : 11,
            minZoom: 3,
            maxZoom: 23.0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              _mapReady = true;

              final cam = _mapController.camera;
              _currentZoom = cam.zoom;
              _currentCenter = cam.center;

              _scheduleLoadByViewport();
              _scheduleRecomputeLabels();

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
