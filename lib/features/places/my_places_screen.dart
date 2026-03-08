import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
  List<_MyPlaceSubmissionItem> _submissions = [];
  StreamSubscription<void>? _sub;

  MyPlacesViewMode _viewMode = MyPlacesViewMode.list;

  final ValueNotifier<PlaceDto?> _mapFocusPlace =
      ValueNotifier<PlaceDto?>(null);

  final PlacesFiltersController _filtersController = PlacesFiltersController();

  @override
  void initState() {
    super.initState();

    _sub = widget.repository.invalidations.listen((_) {
      _load();
    });

    _load();
  }

  Future<String> _resolveCurrentAppUserId() async {
    final authUserId = Supabase.instance.client.auth.currentUser?.id;
    if (authUserId == null || authUserId.isEmpty) {
      throw Exception('Вы не авторизованы');
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

  Future<List<_MyPlaceSubmissionItem>> _loadMyPlaceSubmissions() async {
    final appUserId = await _resolveCurrentAppUserId();

    final raw = await Supabase.instance.client.rpc(
      'get_my_place_submissions_v1',
      params: {
        'p_app_user_id': appUserId,
      },
    );

    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final items = map['items'];

    if (items is! List) {
      return [];
    }

    return items
        .whereType<Map>()
        .map((e) =>
            _MyPlaceSubmissionItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });

    try {
      final places = await widget.repository.getMyPlaces();
      final submissions = await _loadMyPlaceSubmissions();

      _places = places;
      _submissions = submissions;
    } catch (e) {
      debugPrint('[MyPlacesScreen] load error: $e');
      _places = [];
      _submissions = [];
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

  Future<void> _openSubmissionDetails(_MyPlaceSubmissionItem submission) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(submission.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Тип: ${submission.typeLabel}'),
            const SizedBox(height: 8),
            Text('Город: ${submission.city}'),
            const SizedBox(height: 4),
            Text('Адрес: ${submission.address}'),
            if (submission.websiteUrl != null &&
                submission.websiteUrl!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Сайт: ${submission.websiteUrl}'),
            ],
            const SizedBox(height: 12),
            Text('Статус: ${submission.statusLabel}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
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
    final totalItems = _submissions.length + _places.length;

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
              : totalItems == 0
                  ? Center(
                      child: Text(
                        'Пока пусто',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.onSurface.withOpacity(0.7),
                            ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: totalItems,
                      itemBuilder: (context, index) {
                        if (index < _submissions.length) {
                          final submission = _submissions[index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _MyPlaceSubmissionCard(
                              submission: submission,
                              onDetailsTap: () =>
                                  _openSubmissionDetails(submission),
                            ),
                          );
                        }

                        final place = _places[index - _submissions.length];

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

class _MyPlaceSubmissionItem {
  const _MyPlaceSubmissionItem({
    required this.submissionId,
    required this.title,
    required this.type,
    required this.city,
    required this.street,
    required this.house,
    required this.address,
    required this.status,
    required this.createdAt,
    this.websiteUrl,
    this.approvedCorePlaceId,
    this.updatedAt,
    this.reviewedAt,
  });

  factory _MyPlaceSubmissionItem.fromJson(Map<String, dynamic> json) {
    return _MyPlaceSubmissionItem(
      submissionId: json['submission_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      city: json['city']?.toString() ?? '',
      street: json['street']?.toString() ?? '',
      house: json['house']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      websiteUrl: json['website_url']?.toString(),
      status: json['status']?.toString() ?? 'PENDING',
      approvedCorePlaceId: json['approved_core_place_id']?.toString(),
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString(),
      reviewedAt: json['reviewed_at']?.toString(),
    );
  }

  final String submissionId;
  final String title;
  final String type;
  final String city;
  final String street;
  final String house;
  final String address;
  final String? websiteUrl;
  final String status;
  final String? approvedCorePlaceId;
  final String createdAt;
  final String? updatedAt;
  final String? reviewedAt;

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
        return type.isEmpty ? 'Место' : type;
    }
  }

  String get statusLabel {
    switch (status) {
      case 'PENDING':
        return 'На модерации';
      case 'REJECTED':
        return 'Отклонено';
      case 'APPROVED':
        return 'Подтверждено';
      default:
        return status;
    }
  }

  Color statusColor(BuildContext context) {
    switch (status) {
      case 'PENDING':
        return Colors.amber.shade700;
      case 'REJECTED':
        return Theme.of(context).colorScheme.error;
      case 'APPROVED':
        return Colors.green.shade700;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Color statusBackgroundColor(BuildContext context) {
    switch (status) {
      case 'PENDING':
        return Colors.amber.withOpacity(0.14);
      case 'REJECTED':
        return Theme.of(context).colorScheme.error.withOpacity(0.12);
      case 'APPROVED':
        return Colors.green.withOpacity(0.12);
      default:
        return Theme.of(context).colorScheme.primary.withOpacity(0.12);
    }
  }
}

class _MyPlaceSubmissionCard extends StatelessWidget {
  const _MyPlaceSubmissionCard({
    required this.submission,
    required this.onDetailsTap,
  });

  final _MyPlaceSubmissionItem submission;
  final VoidCallback onDetailsTap;

  @override
  Widget build(BuildContext context) {
    final compactTextButtonStyle = TextButton.styleFrom(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
    );

    final statusColor = submission.statusColor(context);
    final statusBgColor = submission.statusBackgroundColor(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.place_outlined,
              size: 32,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        submission.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: statusBgColor,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        submission.statusLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  submission.typeLabel,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  submission.city,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey.shade500),
                ),
                const SizedBox(height: 2),
                Text(
                  submission.address,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey.shade500),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    style: compactTextButtonStyle,
                    onPressed: onDetailsTap,
                    child: const Text('Подробнее'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
