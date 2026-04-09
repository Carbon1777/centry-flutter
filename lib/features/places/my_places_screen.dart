import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:centry/data/places/place_dto.dart';
import 'package:centry/data/places/places_repository.dart';
import 'package:centry/data/plans/plans_repository_impl.dart';
import 'package:centry/features/places/details/add_place_to_plan_modal.dart';
import 'package:centry/features/places/details/place_details_dialog.dart';
import 'package:centry/features/places/map/places_map.dart';
import 'package:centry/features/places/filters/places_filters_controller.dart';
import 'package:centry/ui/common/center_toast.dart';
import 'package:centry/ui/common/category_placeholder.dart';
import 'package:centry/ui/places/places_screen.dart'; // PlaceCard / PlaceUiModel
import 'package:centry/ui/plans/plan_details_screen.dart';

enum MyPlacesViewMode {
  list,
  map,
}

class MyPlacesScreen extends StatefulWidget {
  final PlacesRepository repository;
  final String? sourcePlanId;
  final String? sourcePlanTitle;
  final Set<String> currentPlanPlaceIds;
  final Set<String> currentPlanSubmissionIds;

  const MyPlacesScreen({
    super.key,
    required this.repository,
    this.sourcePlanId,
    this.sourcePlanTitle,
    this.currentPlanPlaceIds = const <String>{},
    this.currentPlanSubmissionIds = const <String>{},
  });

  @override
  State<MyPlacesScreen> createState() => _MyPlacesScreenState();
}

class _MyPlacesScreenState extends State<MyPlacesScreen> {
  static const String _userSnapshotStorageKey = 'user_snapshot';

  bool _loading = true;
  List<PlaceDto> _places = [];
  List<_MyPlaceSubmissionItem> _submissions = [];
  StreamSubscription<void>? _sub;

  final Set<String> _rejectedSeenAckInFlightIds = <String>{};

  MyPlacesViewMode _viewMode = MyPlacesViewMode.list;

  final ValueNotifier<PlaceDto?> _mapFocusPlace =
      ValueNotifier<PlaceDto?>(null);

  final PlacesFiltersController _filtersController = PlacesFiltersController();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final ScrollController _scrollController = ScrollController();

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

    _sub = widget.repository.invalidations.listen((_) {
      _load();
    });

    _load();
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
      _places = [];
      _submissions = [];
    }

    if (!mounted) return;

    setState(() {
      _loading = false;
    });
  }

  Future<void> _loadPreservingScroll() async {
    final savedOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;

    await _load();

    if (savedOffset > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(
            savedOffset.clamp(0.0, _scrollController.position.maxScrollExtent),
          );
        }
      });
    }
  }

  Future<void> _ackRejectedSubmissionSeen(
    _MyPlaceSubmissionItem submission,
  ) async {
    if (!submission.shouldAckRejectedSeen) return;
    if (_rejectedSeenAckInFlightIds.contains(submission.submissionId)) return;

    _rejectedSeenAckInFlightIds.add(submission.submissionId);

    try {
      final appUserId = await _resolveCurrentAppUserId();

      final raw = await Supabase.instance.client.rpc(
        'ack_rejected_place_submission_seen_v1',
        params: {
          'p_app_user_id': appUserId,
          'p_submission_id': submission.submissionId,
        },
      );

      final map =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};

      final rejectedSeenAt = map['rejected_seen_at']?.toString();
      final rejectedDeleteAfterAt = map['rejected_delete_after_at']?.toString();

      if (!mounted) return;

      setState(() {
        _submissions = _submissions.map((item) {
          if (item.submissionId != submission.submissionId) {
            return item;
          }

          return item.copyWith(
            rejectedSeenAt: rejectedSeenAt ?? item.rejectedSeenAt,
            rejectedDeleteAfterAt:
                rejectedDeleteAfterAt ?? item.rejectedDeleteAfterAt,
          );
        }).toList();
      });
    } catch (e) {
      // ignore
    } finally {
      _rejectedSeenAckInFlightIds.remove(submission.submissionId);
    }
  }

  Future<void> _openPlanDetails({
    required String planId,
  }) async {
    try {
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
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось открыть план')),
      );
    }
  }

  Future<void> _removeCorePlaceFromCurrentPlan(String placeId) async {
    if (!_isPlanFlow) return;

    final appUserId = await _resolveCurrentAppUserId();
    await PlansRepositoryImpl(Supabase.instance.client).removePlanPlace(
      appUserId: appUserId,
      planId: widget.sourcePlanId!.trim(),
      placeId: placeId,
      placeSubmissionId: null,
    );
  }

  Future<void> _removeSubmissionFromCurrentPlan(String submissionId) async {
    if (!_isPlanFlow) return;

    final appUserId = await _resolveCurrentAppUserId();
    await PlansRepositoryImpl(Supabase.instance.client).removePlanPlace(
      appUserId: appUserId,
      planId: widget.sourcePlanId!.trim(),
      placeId: null,
      placeSubmissionId: submissionId,
    );
  }

  Future<void> _handleDialogResult(Object? result) async {
    if (!mounted || result == null) return;

    if (_isPlanFlow) {
      Navigator.of(context).pop(result);
      return;
    }

    if (result is AddPlaceToPlanResult) {
      await _openPlanDetails(planId: result.planId);
      return;
    }

    await _loadPreservingScroll();
  }

  Future<void> _openDetails(PlaceUiModel place) async {
    final isAlreadyInCurrentPlan =
        widget.currentPlanPlaceIds.contains(place.dto.id);

    final result = await showDialog<Object?>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.75),
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
        websiteUrl: place.dto.websiteUrl,
        previewMediaUrl: place.dto.previewMediaUrl,
        previewStorageKey: place.dto.previewStorageKey,
        previewIsPlaceholder: place.dto.previewIsPlaceholder,
        metroName: place.dto.metroName,
        metroDistanceM: place.dto.metroDistanceM,
        sourcePlanId: widget.sourcePlanId,
        sourcePlanTitle: widget.sourcePlanTitle,
        isAlreadyInCurrentPlan: isAlreadyInCurrentPlan,
        onRemoveFromCurrentPlan: isAlreadyInCurrentPlan
            ? () => _removeCorePlaceFromCurrentPlan(place.dto.id)
            : null,
      ),
    );

    if (!mounted) return;
    await _handleDialogResult(result);
  }

  Future<void> _openSubmissionDetails(_MyPlaceSubmissionItem submission) async {
    final isAlreadyInCurrentPlan =
        widget.currentPlanSubmissionIds.contains(submission.submissionId);

    final result = await showDialog<Object?>(
      context: context,
      builder: (_) => _MyPlaceSubmissionDetailsDialog(
        submission: submission,
        resolveCurrentAppUserId: _resolveCurrentAppUserId,
        sourcePlanId: widget.sourcePlanId,
        sourcePlanTitle: widget.sourcePlanTitle,
        isAlreadyInCurrentPlan: isAlreadyInCurrentPlan,
        onRemoveFromCurrentPlan: isAlreadyInCurrentPlan
            ? () => _removeSubmissionFromCurrentPlan(submission.submissionId)
            : null,
      ),
    );

    if (!mounted) return;
    await _handleDialogResult(result);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _mapFocusPlace.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final scaffoldBackground = theme.scaffoldBackgroundColor;
    final totalItems = _submissions.length + _places.length;

    return Scaffold(
      backgroundColor: scaffoldBackground,
      appBar: AppBar(
        backgroundColor: scaffoldBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
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
      body: ColoredBox(
        color: scaffoldBackground,
        child: _viewMode == MyPlacesViewMode.map
            ? PlacesMap(
                repository: widget.repository,
                filtersController: _filtersController,
                focusPlace: _mapFocusPlace,
                sourcePlanId: widget.sourcePlanId,
                sourcePlanTitle: widget.sourcePlanTitle,
                currentPlanPlaceIds: widget.currentPlanPlaceIds,
                onRemoveFromCurrentPlan:
                    _isPlanFlow ? _removeCorePlaceFromCurrentPlan : null,
                onPlaceDialogResult: _handleDialogResult,
              )
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : totalItems == 0
                    ? Center(
                        child: Text(
                          'Пока пусто',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        physics: const ClampingScrollPhysics(),
                        itemCount: totalItems,
                        itemBuilder: (context, index) {
                          if (index < _submissions.length) {
                            final submission = _submissions[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _MyPlaceSubmissionCard(
                                key: ValueKey(submission.submissionId),
                                submission: submission,
                                onDetailsTap: () =>
                                    _openSubmissionDetails(submission),
                                onRejectedShown:
                                    submission.shouldAckRejectedSeen
                                        ? () => _ackRejectedSubmissionSeen(
                                              submission,
                                            )
                                        : null,
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
                            ),
                          );
                        },
                      ),
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
    this.rejectedSeenAt,
    this.rejectedDeleteAfterAt,
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
      rejectedSeenAt: json['rejected_seen_at']?.toString(),
      rejectedDeleteAfterAt: json['rejected_delete_after_at']?.toString(),
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
  final String? rejectedSeenAt;
  final String? rejectedDeleteAfterAt;

  _MyPlaceSubmissionItem copyWith({
    String? rejectedSeenAt,
    String? rejectedDeleteAfterAt,
  }) {
    return _MyPlaceSubmissionItem(
      submissionId: submissionId,
      title: title,
      type: type,
      city: city,
      street: street,
      house: house,
      address: address,
      websiteUrl: websiteUrl,
      status: status,
      approvedCorePlaceId: approvedCorePlaceId,
      createdAt: createdAt,
      updatedAt: updatedAt,
      reviewedAt: reviewedAt,
      rejectedSeenAt: rejectedSeenAt ?? this.rejectedSeenAt,
      rejectedDeleteAfterAt:
          rejectedDeleteAfterAt ?? this.rejectedDeleteAfterAt,
    );
  }

  bool get shouldAckRejectedSeen =>
      status == 'REJECTED' &&
      (rejectedSeenAt == null || rejectedSeenAt!.trim().isEmpty);

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
      case 'karaoke':
        return 'Карaоке';
      case 'hookah':
        return 'Кальянная';
      case 'bathhouse':
        return 'Баня / Сауна';
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
        return Colors.amber.withValues(alpha: 0.14);
      case 'REJECTED':
        return Theme.of(context).colorScheme.error.withValues(alpha: 0.12);
      case 'APPROVED':
        return Colors.green.withValues(alpha: 0.12);
      default:
        return Theme.of(context).colorScheme.primary.withValues(alpha: 0.12);
    }
  }
}

class _MyPlaceSubmissionCard extends StatefulWidget {
  const _MyPlaceSubmissionCard({
    super.key,
    required this.submission,
    required this.onDetailsTap,
    this.onRejectedShown,
  });

  final _MyPlaceSubmissionItem submission;
  final VoidCallback onDetailsTap;
  final VoidCallback? onRejectedShown;

  @override
  State<_MyPlaceSubmissionCard> createState() => _MyPlaceSubmissionCardState();
}

class _MyPlaceSubmissionCardState extends State<_MyPlaceSubmissionCard> {
  bool _rejectedShownReported = false;

  @override
  Widget build(BuildContext context) {
    if (widget.submission.shouldAckRejectedSeen &&
        !_rejectedShownReported &&
        widget.onRejectedShown != null) {
      _rejectedShownReported = true;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        widget.onRejectedShown!.call();
      });
    }

    final statusColor = widget.submission.statusColor(context);
    final statusBgColor = widget.submission.statusBackgroundColor(context);
    final cardRadius = BorderRadius.circular(16);

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: cardRadius,
      child: InkWell(
        borderRadius: cardRadius,
        onTap: widget.onDetailsTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 96),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 88,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: Builder(builder: (_) {
                            final catUrl = categoryPlaceholderUrl(
                              widget.submission.type,
                              widget.submission.submissionId,
                            );
                            if (catUrl != null) {
                              return Image.network(
                                catUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Image.asset(
                                  'assets/images/place_placeholder.png',
                                  fit: BoxFit.cover,
                                ),
                              );
                            }
                            return Image.asset(
                              'assets/images/place_placeholder.png',
                              fit: BoxFit.cover,
                            );
                          }),
                        ),
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
                              widget.submission.title,
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
                              widget.submission.statusLabel,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.submission.typeLabel,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.submission.city,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey.shade500),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.submission.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.grey.shade500),
                      ),
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

class _MyPlaceSubmissionDetailsDialog extends StatefulWidget {
  const _MyPlaceSubmissionDetailsDialog({
    required this.submission,
    required this.resolveCurrentAppUserId,
    this.sourcePlanId,
    this.sourcePlanTitle,
    this.isAlreadyInCurrentPlan = false,
    this.onRemoveFromCurrentPlan,
  });

  final _MyPlaceSubmissionItem submission;
  final Future<String> Function() resolveCurrentAppUserId;
  final String? sourcePlanId;
  final String? sourcePlanTitle;
  final bool isAlreadyInCurrentPlan;
  final Future<void> Function()? onRemoveFromCurrentPlan;

  @override
  State<_MyPlaceSubmissionDetailsDialog> createState() =>
      _MyPlaceSubmissionDetailsDialogState();
}

class _MyPlaceSubmissionDetailsDialogState
    extends State<_MyPlaceSubmissionDetailsDialog> {
  bool _addingToPlan = false;

  bool get _isPlanFlow {
    final planId = widget.sourcePlanId?.trim();
    final planTitle = widget.sourcePlanTitle?.trim();
    return planId != null &&
        planId.isNotEmpty &&
        planTitle != null &&
        planTitle.isNotEmpty;
  }

  bool get _canAddToPlan => widget.submission.status != 'REJECTED';

  bool get _showRemoveFromPlanAction => widget.isAlreadyInCurrentPlan;

  String get _primaryActionLabel {
    if (_showRemoveFromPlanAction) {
      return widget.onRemoveFromCurrentPlan != null
          ? 'Удалить из плана'
          : 'В плане';
    }
    return 'Добавить в план';
  }

  String _mapPlanPlaceAddError(String message) {
    switch (message) {
      case 'Place already added to plan':
        return 'Место уже добавлено';
      case 'Plan already has 5 places':
        return 'В плане уже 5 мест';
      case 'Plan is not open':
        return 'План закрыт';
      case 'Not a member of plan':
        return 'Нет доступа к плану';
      case 'Rejected place cannot be added to new plan':
        return 'Отклонённое место нельзя добавить в новый план';
      case 'Place not found':
      case 'Place submission not found':
        return 'Место не найдено';
      default:
        return message.isEmpty ? 'Не удалось добавить место в план' : message;
    }
  }

  Future<bool> _confirmAddToPlan() async {
    final planTitle = widget.sourcePlanTitle?.trim() ?? '';

    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Подтверждение добавления в план'),
        content: Text(
          'Подтвердите, что хотите добавить место в план "$planTitle"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отменить'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Добавить'),
          ),
        ],
      ),
    );

    return result == true;
  }

  Future<void> _onAddToPlanPressed() async {
    if (_addingToPlan) return;
    if (!_showRemoveFromPlanAction && !_canAddToPlan) return;

    if (_showRemoveFromPlanAction) {
      if (widget.onRemoveFromCurrentPlan == null) return;

      setState(() => _addingToPlan = true);

      try {
        await widget.onRemoveFromCurrentPlan!.call();

        if (!mounted) return;
        Navigator.of(context).pop(true);
      } catch (e) {
        if (!mounted) return;

        setState(() => _addingToPlan = false);

        await showCenterToast(
          context,
          message: 'Не удалось удалить место из плана',
          isError: true,
        );
      }
      return;
    }

    setState(() => _addingToPlan = true);

    try {
      if (_isPlanFlow) {
        final confirmed = await _confirmAddToPlan();
        if (!mounted) return;

        if (!confirmed) {
          setState(() => _addingToPlan = false);
          return;
        }

        final appUserId = await widget.resolveCurrentAppUserId();
        final planId = widget.sourcePlanId!.trim();
        final planTitle = widget.sourcePlanTitle!.trim();

        await Supabase.instance.client.rpc(
          'add_plan_place_v2',
          params: {
            'p_app_user_id': appUserId,
            'p_plan_id': planId,
            'p_place_id': null,
            'p_place_submission_id': widget.submission.submissionId,
          },
        );

        if (!mounted) return;

        Navigator.of(context).pop(
          AddPlaceToPlanResult(
            planId: planId,
            planTitle: planTitle,
          ),
        );
        return;
      }

      final result = await AddPlaceToPlanModal.show(
        context,
        placeSubmissionId: widget.submission.submissionId,
      );

      if (!mounted) return;

      if (result == null) {
        setState(() => _addingToPlan = false);
        return;
      }

      Navigator.of(context).pop(result);
    } catch (e) {
      if (!mounted) return;

      final message = e is PostgrestException
          ? e.message.toString().trim()
          : e.toString().replaceFirst('Exception: ', '').trim();

      setState(() => _addingToPlan = false);

      await showCenterToast(
        context,
        message: _mapPlanPlaceAddError(message),
        isError: true,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = widget.submission.statusColor(context);
    final statusBgColor = widget.submission.statusBackgroundColor(context);

    const addToPlanFillColor = Color(0xFF19D3C5);
    const addToPlanTextColor = Color(0xFF081217);
    final secondaryButtonBorderColor = Colors.white.withValues(alpha: 0.82);
    const secondaryButtonTextColor = Color(0xFF4E8DFF);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: theme.colorScheme.surface,
          child: Stack(
            children: [
              SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AspectRatio(
                      aspectRatio: 1.35,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          Builder(builder: (_) {
                            final catUrl = categoryPlaceholderUrl(
                              widget.submission.type,
                              widget.submission.submissionId,
                            );
                            if (catUrl != null) {
                              return Image.network(
                                catUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Image.asset(
                                  'assets/images/place_placeholder.png',
                                  fit: BoxFit.cover,
                                ),
                              );
                            }
                            return Image.asset(
                              'assets/images/place_placeholder.png',
                              fit: BoxFit.cover,
                            );
                          }),
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.55),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                'Плейсхолдер. Фото добавятся позже',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.submission.typeLabel,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: theme.colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  widget.submission.title,
                                  style:
                                      theme.textTheme.headlineSmall?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: statusBgColor,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  widget.submission.statusLabel,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: statusColor,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            widget.submission.city,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.submission.address,
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.grey.shade400,
                            ),
                          ),
                          if (widget.submission.websiteUrl != null &&
                              widget.submission.websiteUrl!
                                  .trim()
                                  .isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Text(
                              widget.submission.websiteUrl!,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'Статус',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: Colors.grey.shade400,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.submission.statusLabel,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 22),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton(
                              onPressed: (_addingToPlan || !_canAddToPlan)
                                  ? null
                                  : _onAddToPlanPressed,
                              style: FilledButton.styleFrom(
                                elevation: 0,
                                backgroundColor: addToPlanFillColor,
                                foregroundColor: addToPlanTextColor,
                                disabledBackgroundColor:
                                    addToPlanFillColor.withValues(alpha: 0.45),
                                disabledForegroundColor:
                                    addToPlanTextColor.withValues(alpha: 0.75),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: _addingToPlan
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: addToPlanTextColor,
                                      ),
                                    )
                                  : Text(
                                      _primaryActionLabel,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16,
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: secondaryButtonTextColor,
                                side: BorderSide(
                                  color: secondaryButtonBorderColor,
                                  width: 1.4,
                                ),
                                backgroundColor: Colors.transparent,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 16),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: const Text(
                                'Закрыть',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.black45,
                  shape: const CircleBorder(),
                  child: IconButton(
                    icon: const Icon(Icons.close),
                    color: Colors.white,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
