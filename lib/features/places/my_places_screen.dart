
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:centry/data/places/place_dto.dart';
import 'package:centry/data/places/places_repository.dart';
import 'package:centry/features/places/details/place_details_dialog.dart';
import 'package:centry/features/places/map/places_map.dart';
import 'package:centry/features/places/filters/places_filters_controller.dart';
import 'package:centry/ui/places/places_screen.dart'; // PlaceCard / PlaceUiModel

enum MyPlacesViewMode {
  list,
  map,
}

class MyPlacesScreen extends StatefulWidget {
  final PlacesRepository repository;

  const MyPlacesScreen({
    super.key,
    required this.repository,
  });

  @override
  State<MyPlacesScreen> createState() => _MyPlacesScreenState();
}

class _MyPlacesScreenState extends State<MyPlacesScreen> {
  bool _loading = true;
  List<PlaceDto> _places = [];
  StreamSubscription<void>? _sub;

  MyPlacesViewMode _viewMode = MyPlacesViewMode.list;

  final ValueNotifier<PlaceDto?> _mapFocusPlace =
      ValueNotifier<PlaceDto?>(null);

  final PlacesFiltersController _filtersController =
      PlacesFiltersController();

  @override
  void initState() {
    super.initState();

    _sub = widget.repository.invalidations.listen((_) {
      _load();
    });

    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    try {
      final items = await widget.repository.getMyPlaces();
      _places = items;
    } catch (e) {
      debugPrint('[MyPlacesScreen] load error: $e');
      _places = [];
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
    });
  }

  Future<void> _openDetails(PlaceUiModel place) async {
    await showDialog(
      context: context,
      builder: (_) => PlaceDetailsDialog(
        repository: widget.repository,
        placeId: place.dto.id,
        title: place.dto.title,
        typeLabel: place.typeLabel,
        address: place.dto.address,
        lat: place.dto.lat,
        lng: place.dto.lng,
        websiteUrl: place.dto.websiteUrl,
        previewMediaUrl: place.dto.previewMediaUrl,
        previewStorageKey: place.dto.previewStorageKey,
        previewIsPlaceholder: place.dto.previewIsPlaceholder,
        metroName: place.dto.metroName,
        metroDistanceM: place.dto.metroDistanceM,
      ),
    );

    await _load();
  }

  void _openOnMap(PlaceDto place) {
    setState(() {
      _viewMode = MyPlacesViewMode.map;
    });

    _mapFocusPlace.value = place;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_mapFocusPlace.value == place) {
        _mapFocusPlace.value = null;
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _mapFocusPlace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: _viewMode == MyPlacesViewMode.map
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _viewMode = MyPlacesViewMode.list;
                  });
                },
              )
            : null,
        title: const Text('Мои места'),
      ),
      body: _viewMode == MyPlacesViewMode.map
          ? PlacesMap(
              repository: widget.repository,
              filtersController: _filtersController,
              focusPlace: _mapFocusPlace,
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _places.isEmpty
                  ? Center(
                      child: Text(
                        'Пока пусто',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(
                              color: colors.onSurface.withOpacity(0.7),
                            ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _places.length,
                      itemBuilder: (context, index) {
                        final place = _places[index];

                        final uiModel = PlaceUiModel(
                          dto: place,
                          title: place.title,
                          type: place.type,
                          address: place.address,
                          cityName: place.cityName,
                          areaName: place.areaName,
                          distanceM: place.distanceM,
                        );

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: PlaceCard(
                            place: uiModel,
                            onDetailsTap: () => _openDetails(uiModel),
                            onMapTap: () => _openOnMap(place),
                          ),
                        );
                      },
                    ),
    );
  }
}
