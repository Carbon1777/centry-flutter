import '../../../data/local/user_snapshot_storage.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/feed/feed_repository.dart';
import '../../../data/feed/plan_shell_dto.dart';
import '../../profile/user_card_sheet.dart';
import '../../../data/places/place_dto.dart';
import '../../../data/places/places_repository.dart';
import '../../../ui/common/center_toast.dart';
import '../../../ui/places/places_screen.dart';
import '../../profile/profile_email_modal.dart';
import 'add_place_to_plan_modal.dart';

class PlaceDetailsDialog extends StatefulWidget {
  final PlacesRepository repository;

  final String placeId;

  final String title;
  final String typeLabel;
  final String address;
  final double lat;
  final double lng;

  final String? websiteUrl;
  final String? previewMediaUrl;
  final String? previewStorageKey;
  final bool previewIsPlaceholder;
  final String? metroName;
  final int? metroDistanceM;

  /// plan-flow: открыть детали места в контексте конкретного плана
  final String? sourcePlanId;
  final String? sourcePlanTitle;

  /// место уже состоит в текущем плане
  final bool isAlreadyInCurrentPlan;
  final Future<void> Function()? onRemoveFromCurrentPlan;

  /// Feed-specific (optional): агрегаты из ленты
  final int? feedCountPlans;
  final int? feedInterestedCount;
  final int? feedPlannedCount;
  final int? feedVisitedCount;
  final FeedRepository? feedRepository;

  const PlaceDetailsDialog({
    super.key,
    required this.repository,
    required this.placeId,
    required this.title,
    required this.typeLabel,
    required this.address,
    required this.lat,
    required this.lng,
    this.websiteUrl,
    this.previewMediaUrl,
    this.previewStorageKey,
    this.previewIsPlaceholder = false,
    this.metroName,
    this.metroDistanceM,
    this.sourcePlanId,
    this.sourcePlanTitle,
    this.isAlreadyInCurrentPlan = false,
    this.onRemoveFromCurrentPlan,
    this.feedCountPlans,
    this.feedInterestedCount,
    this.feedPlannedCount,
    this.feedVisitedCount,
    this.feedRepository,
  });

  @override
  State<PlaceDetailsDialog> createState() => _PlaceDetailsDialogState();
}

class _PlaceDetailsDialogState extends State<PlaceDetailsDialog> {
  bool _loading = true;
  bool _voting = false;
  bool _hasChanged = false;

  bool _savingSaved = false;
  bool _savedByMe = false;
  bool _addingToPlan = false;

  int _likes = 0;
  int _dislikes = 0;
  int _myVote = 0;
  double? _rating;

  String? _metaCityName;
  String? _metaAreaName;
  String? _metaAddress;
  String? _metaNormalizedAddress;
  String? _metaWebsiteUrl;
  List<String> _metaPhones = const [];
  String? _metaMetroName;
  int? _metaMetroDistanceM;
  String? _metaPreviewStorageKey;
  bool? _metaPreviewIsPlaceholder;

  bool get _isPlanFlow {
    final planId = widget.sourcePlanId?.trim();
    final planTitle = widget.sourcePlanTitle?.trim();
    return planId != null &&
        planId.isNotEmpty &&
        planTitle != null &&
        planTitle.isNotEmpty;
  }

  bool get _showRemoveFromPlanAction => widget.isAlreadyInCurrentPlan;

  String get _planPrimaryButtonLabel {
    if (_showRemoveFromPlanAction) {
      return widget.onRemoveFromCurrentPlan != null
          ? 'Удалить из плана'
          : 'В плане';
    }
    return 'Добавить в план';
  }

  String get _effectiveAddress {
    final n = _metaNormalizedAddress;
    if (n != null && n.trim().isNotEmpty) return n;
    final a = _metaAddress;
    if (a != null && a.trim().isNotEmpty) return a;
    return widget.address;
  }

  String? get _effectiveCityName => _metaCityName;
  String? get _effectiveAreaName => _metaAreaName;

  String? get _effectiveMetroName => _metaMetroName ?? widget.metroName;
  int? get _effectiveMetroDistanceM =>
      _metaMetroDistanceM ?? widget.metroDistanceM;

  String? get _effectiveWebsiteUrl => _metaWebsiteUrl ?? widget.websiteUrl;

  List<String> get _effectivePhones => _metaPhones;

  String? get _effectivePreviewMediaUrl => widget.previewMediaUrl;
  String? get _effectivePreviewStorageKey =>
      _metaPreviewStorageKey ?? widget.previewStorageKey;
  bool get _effectivePreviewIsPlaceholder =>
      (_metaPreviewIsPlaceholder ?? widget.previewIsPlaceholder);

  @override
  void initState() {
    super.initState();

    _loadDetails();
    _loadMeta();
  }

  bool _asBool(dynamic value) {
    if (value == true) return true;
    if (value == false) return false;
    if (value is String) {
      final v = value.toLowerCase();
      if (v == 'true') return true;
      if (v == 'false') return false;
    }
    if (value is num) return value != 0;
    return false;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int _voteFromDetails(Map<String, dynamic> result) {
    final likedByMe = _asBool(result['liked_by_me']);
    final dislikedByMe = _asBool(result['disliked_by_me']);
    if (likedByMe) return 1;
    if (dislikedByMe) return -1;
    return 0;
  }

  Future<void> _onSavedPressed() async {
    if (_loading || _savingSaved) return;

    final snapshot = await UserSnapshotStorage().read();
    if (!mounted) return;

    if (snapshot == null || snapshot.state != 'USER') {
      final goRegister = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Требуется регистрация'),
          content: const Text(
            'Добавление в Мои места доступно только зарегистрированным пользователям.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Зарегистрироваться'),
            ),
          ],
        ),
      );

      if (goRegister != true) return;

      final s = snapshot;
      if (s == null) {
        if (!mounted) return;
        await showCenterToast(
          context,
          message: 'Не удалось открыть регистрацию: нет snapshot',
          isError: true,
        );
        return;
      }

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ProfileEmailModal(
          bootstrapResult: {
            'id': s.id,
            'public_id': s.publicId,
            'nickname': s.nickname,
          },
          onUpgradeSuccess: () {},
        ),
      );

      final updated = await UserSnapshotStorage().read();
      if (!mounted) return;

      if (updated == null || updated.state != 'USER') {
        await showCenterToast(
          context,
          message: 'Регистрация не завершена',
          isError: true,
        );
        return;
      }

      await _ensureSavedAfterUpgrade();
      return;
    }

    await _toggleSavedCanonical();
  }

  Future<void> _toggleSavedCanonical() async {
    setState(() {
      _savingSaved = true;
    });

    try {
      await widget.repository.toggleSavedPlace(widget.placeId);

      final result = await widget.repository.getPlaceDetails(
        placeId: widget.placeId,
      );

      if (!mounted) return;

      setState(() {
        _likes = _asInt(result['likes_count'], fallback: 0);
        _dislikes = _asInt(result['dislikes_count'], fallback: 0);
        _myVote = _voteFromDetails(result);
        _rating = _asDouble(result['rating']);
        _savedByMe = _asBool(result['saved_by_me']);
        _savingSaved = false;
        _hasChanged = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savingSaved = false;
      });
      await showCenterToast(
        context,
        message: 'Не удалось сохранить место',
        isError: true,
      );
    }
  }

  Future<void> _ensureSavedAfterUpgrade() async {
    await _loadDetails();
    if (!mounted) return;

    if (_savedByMe) return;

    await _toggleSavedCanonical();
  }

  Future<void> _loadDetails() async {
    try {
      final result = await widget.repository.getPlaceDetails(
        placeId: widget.placeId,
      );

      if (!mounted) return;

      setState(() {
        _likes = _asInt(result['likes_count'], fallback: 0);
        _dislikes = _asInt(result['dislikes_count'], fallback: 0);
        _myVote = _voteFromDetails(result);
        _rating = _asDouble(result['rating']);
        _savedByMe = _asBool(result['saved_by_me']);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMeta() async {
    try {
      final meta = await widget.repository.getPlaceDetailsMeta(
        placeId: widget.placeId,
      );

      if (!mounted) return;

      dynamic asString(dynamic v) => v?.toString();

      int? asIntNullable(dynamic v) {
        if (v == null) return null;
        if (v is int) return v;
        if (v is num) return v.toInt();
        return int.tryParse(v.toString());
      }

      final phonesRaw = meta['phones'];
      final phones = <String>[];
      if (phonesRaw is List) {
        for (final e in phonesRaw) {
          final s = e?.toString().trim();
          if (s != null && s.isNotEmpty) phones.add(s);
        }
      } else if (phonesRaw is Map) {
        final items = phonesRaw['items'] ?? phonesRaw['phones'];
        if (items is List) {
          for (final e in items) {
            final s = e?.toString().trim();
            if (s != null && s.isNotEmpty) phones.add(s);
          }
        }
      }

      final metroRaw = meta['metro'];
      String? metroName;
      if (metroRaw is Map) {
        metroName = asString(metroRaw['name']);
      }

      String? previewKey;
      bool? previewPlaceholder;
      final photosRaw = meta['photos'];
      if (photosRaw is List && photosRaw.isNotEmpty) {
        final first = photosRaw.first;
        if (first is Map) {
          previewKey = asString(first['storage_key']);
          final ph = first['is_placeholder'];
          if (ph is bool) {
            previewPlaceholder = ph;
          } else if (ph != null) {
            previewPlaceholder = ph.toString().toLowerCase() == 'true';
          }
        }
      }

      setState(() {
        _metaCityName = asString(meta['city_name']);
        _metaAreaName = asString(meta['area_name']);
        _metaAddress = asString(meta['address']);
        _metaNormalizedAddress = asString(meta['normalized_address']);
        _metaWebsiteUrl = asString(meta['website_url']);
        _metaPhones = phones;
        _metaMetroName = metroName;
        _metaMetroDistanceM = asIntNullable(meta['metro_distance_m']);

        if (previewKey != null && previewKey.isNotEmpty) {
          _metaPreviewStorageKey = previewKey;
        }
        if (previewPlaceholder != null) {
          _metaPreviewIsPlaceholder = previewPlaceholder;
        }
      });
    } catch (e) {
      if (!mounted) return;
    }
  }

  Future<void> _vote(int value) async {
    if (_voting || _loading) return;

    setState(() {
      _voting = true;
    });

    try {
      await widget.repository.votePlace(
        placeId: widget.placeId,
        value: value,
      );

      final result = await widget.repository.getPlaceDetails(
        placeId: widget.placeId,
      );

      if (!mounted) return;

      setState(() {
        _likes = _asInt(result['likes_count'], fallback: 0);
        _dislikes = _asInt(result['dislikes_count'], fallback: 0);
        _myVote = _voteFromDetails(result);
        _rating = _asDouble(result['rating']);
        _savedByMe = _asBool(result['saved_by_me']);
        _voting = false;
        _hasChanged = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _voting = false;
      });
    }
  }

  bool get _canTapVote => !_loading && !_voting;

  String _canonicalTypeFromLabel(String label) {
    switch (label.trim()) {
      case 'Ресторан':
        return 'restaurant';
      case 'Бар':
        return 'bar';
      case 'Ночной клуб':
        return 'nightclub';
      case 'Кинотеатр':
      case 'Кино':
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
        return 'bar';
    }
  }

  PlaceDto _buildMapFocusPlace() {
    return PlaceDto(
      id: widget.placeId,
      title: widget.title,
      type: _canonicalTypeFromLabel(widget.typeLabel),
      address: _effectiveAddress,
      cityId: '',
      cityName: _effectiveCityName ?? '',
      areaId: null,
      areaName: _effectiveAreaName,
      lat: widget.lat,
      lng: widget.lng,
      distanceM: null,
      previewMediaUrl: _effectivePreviewMediaUrl,
      previewStorageKey: _effectivePreviewStorageKey,
      previewIsPlaceholder: _effectivePreviewIsPlaceholder,
      metroName: _effectiveMetroName,
      metroDistanceM: _effectiveMetroDistanceM,
      typeDisplay: null,
      categories: [_canonicalTypeFromLabel(widget.typeLabel)],
      rating: _rating,
      likesCount: _likes,
      dislikesCount: _dislikes,
      websiteUrl: _effectiveWebsiteUrl,
    );
  }

  Future<void> _openOnMapInApp() async {
    final focusPlace = _buildMapFocusPlace();

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PlacesScreen(
          sourcePlanId: widget.sourcePlanId,
          sourcePlanTitle: widget.sourcePlanTitle,
          currentPlanPlaceIds: widget.isAlreadyInCurrentPlan
              ? <String>{widget.placeId}
              : const <String>{},
          initialViewMode: PlacesViewMode.map,
          initialFocusPlace: focusPlace,
        ),
      ),
    );
  }

  Future<void> _openRoute() async {
    final uri = Uri.parse(
      'https://yandex.ru/maps/?rtext=~${widget.lat},${widget.lng}&rtt=auto',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openWebsite() async {
    final url = _effectiveWebsiteUrl;
    if (url == null || url.trim().isEmpty) return;
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyAddress() async {
    await Clipboard.setData(ClipboardData(text: _effectiveAddress));
    if (!mounted) return;
    await showCenterToast(context, message: 'Адрес скопирован');
  }

  Future<String> _resolveCurrentAppUserId() async {
    final snapshot = await UserSnapshotStorage().read();
    if (snapshot != null && snapshot.id.trim().isNotEmpty) {
      return snapshot.id;
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

  String _humanizeAddToPlanError(Object e) {
    if (e is PostgrestException) {
      final combined = [
        e.message,
        e.details,
        e.hint,
        e.code,
      ]
          .where((v) => v != null && v.toString().trim().isNotEmpty)
          .join(' ')
          .toLowerCase();

      if (combined.contains('place already added to plan')) {
        return 'Место уже добавлено';
      }

      if (combined.contains('already added')) {
        return 'Место уже добавлено';
      }

      if (combined.contains('plan already has 5 places')) {
        return 'В плане уже 5 мест';
      }

      if (combined.contains('max') && combined.contains('5')) {
        return 'В плане уже 5 мест';
      }

      if (combined.contains('limit') && combined.contains('5')) {
        return 'В плане уже 5 мест';
      }

      if (combined.contains('rejected')) {
        return 'Отклонённое место нельзя добавить в новый план';
      }

      if (combined.contains('access denied') ||
          combined.contains('not a member') ||
          combined.contains('banned')) {
        return 'План недоступен';
      }

      if (combined.contains('open')) {
        return 'Добавлять места можно только в открытый план';
      }
    }

    return 'Не удалось добавить место в план';
  }

  Future<bool> _confirmAddToSourcePlan() async {
    final planTitle = widget.sourcePlanTitle?.trim();
    if (planTitle == null || planTitle.isEmpty) return false;

    final confirmed = await showDialog<bool>(
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

    return confirmed == true;
  }

  Future<void> _addToSourcePlanDirectly() async {
    final planId = widget.sourcePlanId?.trim();
    final planTitle = widget.sourcePlanTitle?.trim();
    if (planId == null ||
        planId.isEmpty ||
        planTitle == null ||
        planTitle.isEmpty) {
      return;
    }

    final confirmed = await _confirmAddToSourcePlan();
    if (!confirmed) return;

    setState(() {
      _addingToPlan = true;
    });

    try {
      final appUserId = await _resolveCurrentAppUserId();

      await Supabase.instance.client.rpc(
        'add_plan_place_v2',
        params: {
          'p_app_user_id': appUserId,
          'p_plan_id': planId,
          'p_place_id': widget.placeId,
          'p_place_submission_id': null,
        },
      );

      if (!mounted) return;

      _hasChanged = true;
      setState(() {
        _addingToPlan = false;
      });

      Navigator.of(context).pop(
        AddPlaceToPlanResult(
          planId: planId,
          planTitle: planTitle,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _addingToPlan = false;
      });

      await showCenterToast(
        context,
        message: _humanizeAddToPlanError(e),
        isError: true,
      );
    }
  }

  Future<void> _onAddToPlanPressed() async {
    if (_loading || _addingToPlan) return;

    if (_showRemoveFromPlanAction) {
      if (widget.onRemoveFromCurrentPlan == null) return;

      setState(() {
        _addingToPlan = true;
      });

      try {
        await widget.onRemoveFromCurrentPlan!.call();

        if (!mounted) return;

        _hasChanged = true;
        setState(() {
          _addingToPlan = false;
        });

        Navigator.of(context).pop(true);
      } catch (e) {
        if (!mounted) return;

        setState(() {
          _addingToPlan = false;
        });

        await showCenterToast(
          context,
          message: 'Не удалось удалить место из плана',
          isError: true,
        );
      }
      return;
    }

    if (_isPlanFlow) {
      await _addToSourcePlanDirectly();
      return;
    }

    setState(() {
      _addingToPlan = true;
    });

    try {
      final result = await AddPlaceToPlanModal.show(
        context,
        placeId: widget.placeId,
      );

      if (!mounted) return;

      if (result == null) {
        setState(() {
          _addingToPlan = false;
        });
        return;
      }

      _hasChanged = true;
      setState(() {
        _addingToPlan = false;
      });

      Navigator.of(context).pop(result);
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _addingToPlan = false;
      });
    }
  }

  void _close() {
    Navigator.of(context).pop(_hasChanged);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    final outlinedActionStyle = OutlinedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      minimumSize: const Size(0, 36),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    );

    final screenHeight = MediaQuery.of(context).size.height;
    final dialogMaxHeight = screenHeight - MediaQuery.of(context).viewInsets.bottom - 80;
    final imageHeight = (screenHeight * 0.22).clamp(120.0, 200.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Stack(
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: dialogMaxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(20)),
                    child: SizedBox(
                      height: imageHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (_effectivePreviewMediaUrl != null)
                            Image.network(
                              _effectivePreviewMediaUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Image.asset(
                                  'assets/images/place_placeholder.png',
                                  fit: BoxFit.cover,
                                );
                              },
                            )
                          else if (_effectivePreviewStorageKey != null)
                            Image.network(
                              Supabase.instance.client.storage
                                  .from('brand-media')
                                  .getPublicUrl(_effectivePreviewStorageKey!),
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) {
                                return Image.asset(
                                  'assets/images/place_placeholder.png',
                                  fit: BoxFit.cover,
                                );
                              },
                            )
                          else
                            Image.asset(
                              'assets/images/place_placeholder.png',
                              fit: BoxFit.cover,
                            ),
                          if (_effectivePreviewIsPlaceholder)
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black54,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Плейсхолдер. Актуальные фото добавятся позже',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  Flexible(
                    child: SingleChildScrollView(
                      physics: const ClampingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(
                              widget.typeLabel,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    widget.title,
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                OutlinedButton(
                                  onPressed: (_loading || _savingSaved)
                                      ? null
                                      : _onSavedPressed,
                                  style: outlinedActionStyle,
                                  child: _savingSaved
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Text(
                                          _savedByMe
                                              ? 'Удалить из Моих мест'
                                              : 'Добавить в Мои места',
                                        ),
                                ),
                              ],
                            ),
                            // Feed-specific: сигналы + планы — сразу под названием
                            if (widget.feedCountPlans != null) ...[
                              const SizedBox(height: 6),
                              const Divider(height: 1),
                              const SizedBox(height: 6),
                              _FeedSignalsRow(
                                interestedCount: widget.feedInterestedCount ?? 0,
                                plannedCount: widget.feedPlannedCount ?? 0,
                                visitedCount: widget.feedVisitedCount ?? 0,
                              ),
                              const SizedBox(height: 6),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: widget.feedCountPlans! > 0 &&
                                          widget.feedRepository != null
                                      ? () {
                                          showDialog<void>(
                                            context: context,
                                            builder: (_) =>
                                                _FeedPlanShellsDialog(
                                              placeId: widget.placeId,
                                              feedRepository:
                                                  widget.feedRepository!,
                                            ),
                                          );
                                        }
                                      : null,
                                  icon: const Icon(Icons.event_note_outlined,
                                      size: 18),
                                  label: Text(
                                      'Планов — ${widget.feedCountPlans}'),
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Divider(height: 1),
                            ],
                            const SizedBox(height: 4),
                            if (_effectiveCityName != null &&
                                _effectiveCityName!.trim().isNotEmpty) ...[
                              Text(
                                _effectiveCityName!,
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 2),
                            ],
                            if (_effectiveAreaName != null &&
                                _effectiveAreaName!.trim().isNotEmpty) ...[
                              Text(
                                _effectiveAreaName!,
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 2),
                            ],
                            if (_effectiveMetroName != null &&
                                _effectiveMetroName!.trim().isNotEmpty) ...[
                              Text(
                                'м. $_effectiveMetroName${_effectiveMetroDistanceM != null ? " · $_effectiveMetroDistanceM м" : ""}',
                                style: theme.textTheme.bodySmall,
                              ),
                              const SizedBox(height: 2),
                            ],
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _effectiveAddress,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                IconButton(
                                  icon:
                                      const Icon(Icons.copy_rounded, size: 18),
                                  onPressed: _copyAddress,
                                ),
                              ],
                            ),
                            if (_effectiveWebsiteUrl != null &&
                                _effectiveWebsiteUrl!.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              OutlinedButton(
                                onPressed: _openWebsite,
                                child: const Text('Сайт'),
                              ),
                            ],
                            if (_effectivePhones.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final p in _effectivePhones)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: OutlinedButton(
                                        onPressed: () async {
                                          final tel = p.trim();
                                          if (tel.isEmpty) return;
                                          final uri = Uri(
                                            scheme: 'tel',
                                            path: tel,
                                          );
                                          await launchUrl(
                                            uri,
                                            mode:
                                                LaunchMode.externalApplication,
                                          );
                                        },
                                        child: Text(p),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 4),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Рейтинг',
                                        style: theme.textTheme.bodySmall,
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _rating != null
                                            ? _rating!.toStringAsFixed(1)
                                            : '—',
                                        style: theme.textTheme.titleSmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          _Vote(
                                            icon: Icons.thumb_up_alt_rounded,
                                            count: _likes,
                                            active: _myVote == 1,
                                            activeColor: Colors.green,
                                            onTap: _canTapVote
                                                ? () =>
                                                    _vote(_myVote == 1 ? 0 : 1)
                                                : null,
                                          ),
                                          const SizedBox(width: 16),
                                          _Vote(
                                            icon: Icons.thumb_down_alt_rounded,
                                            count: _dislikes,
                                            active: _myVote == -1,
                                            activeColor: Colors.redAccent,
                                            onTap: _canTapVote
                                                ? () => _vote(
                                                      _myVote == -1 ? 0 : -1,
                                                    )
                                                : null,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                OutlinedButton(
                                  onPressed: _openOnMapInApp,
                                  style: outlinedActionStyle,
                                  child: const Text('Посмотреть на карте'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: (_loading || _addingToPlan)
                                    ? null
                                    : (_showRemoveFromPlanAction &&
                                            widget.onRemoveFromCurrentPlan ==
                                                null)
                                        ? null
                                        : _onAddToPlanPressed,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF2DD4BF),
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 10,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: _addingToPlan
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.black,
                                        ),
                                      )
                                    : Text(
                                        _planPrimaryButtonLabel,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: _openRoute,
                                    child: const Text('Маршрут'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black45,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close),
                color: Colors.white,
                onPressed: _close,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Vote extends StatelessWidget {
  final IconData icon;
  final int count;
  final bool active;
  final Color activeColor;
  final VoidCallback? onTap;

  const _Vote({
    required this.icon,
    required this.count,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = active ? activeColor : Colors.grey;
    final effectiveOnTap = onTap;

    return InkWell(
      onTap: effectiveOnTap,
      borderRadius: BorderRadius.circular(6),
      child: Opacity(
        opacity: effectiveOnTap == null ? 0.45 : 1.0,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 4),
            Text(
              count.toString(),
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Feed: строка сигналов
// ──────────────────────────────────────────────

class _FeedSignalsRow extends StatelessWidget {
  final int interestedCount;
  final int plannedCount;
  final int visitedCount;

  const _FeedSignalsRow({
    required this.interestedCount,
    required this.plannedCount,
    required this.visitedCount,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(
            child: _SignalColumn(
              icon: Icons.visibility_outlined,
              color: const Color(0xFF7986CB), // индиго светлее
              count: interestedCount,
              label: 'Интересуются',
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).dividerColor,
          ),
          Expanded(
            child: _SignalColumn(
              icon: Icons.directions_walk,
              color: const Color(0xFF43A047), // зелёный ярче
              count: plannedCount,
              label: 'Идут',
            ),
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: Theme.of(context).dividerColor,
          ),
          Expanded(
            child: _SignalColumn(
              icon: Icons.check_circle_outline,
              color: const Color(0xFF78909C), // серо-синий
              count: visitedCount,
              label: 'Были',
            ),
          ),
        ],
      ),
    );
  }
}

class _SignalColumn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final int count;
  final String label;

  const _SignalColumn({
    required this.icon,
    required this.color,
    required this.count,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 22, color: color),
        const SizedBox(height: 2),
        Text(
          '$count',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: count > 0 ? color : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.35),
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────
// Feed: модалка оболочек планов
// ──────────────────────────────────────────────

class _FeedPlanShellsDialog extends StatefulWidget {
  final String placeId;
  final FeedRepository feedRepository;

  const _FeedPlanShellsDialog({
    required this.placeId,
    required this.feedRepository,
  });

  @override
  State<_FeedPlanShellsDialog> createState() => _FeedPlanShellsDialogState();
}

class _FeedPlanShellsDialogState extends State<_FeedPlanShellsDialog> {
  late Future<List<PlanShellDto>> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.feedRepository.getPlanShells(widget.placeId);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Планы на это место',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: FutureBuilder<List<PlanShellDto>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Нет активных планов')),
                    );
                  }
                  final shells = snap.data!;
                  return ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: shells.length,
                    itemBuilder: (context, i) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: i < shells.length - 1 ? 10 : 0),
                        child: _PlanShellTile(shell: shells[i]),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanShellTile extends StatelessWidget {
  final PlanShellDto shell;

  const _PlanShellTile({required this.shell});

  String _participantsLabel(int count) {
    if (count % 10 == 1 && count % 100 != 11) return '$count участник';
    if (count % 10 >= 2 && count % 10 <= 4 && (count % 100 < 10 || count % 100 >= 20)) {
      return '$count участника';
    }
    return '$count участников';
  }

  Color get _phaseColor {
    switch (shell.signalPhase) {
      case 'PLANNED':
        return const Color(0xFF43A047);
      case 'VISITED':
        return const Color(0xFF78909C);
      default:
        return const Color(0xFF7986CB);
    }
  }

  void _openParticipants(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => _FeedPlanParticipantsDialog(shell: shell),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isHidden = !shell.isVisible;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isHidden ? null : () => _openParticipants(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isHidden
                  ? colors.outline.withValues(alpha: 0.25)
                  : colors.outline.withValues(alpha: 0.5),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Цветная точка — фаза сигнала
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isHidden ? Colors.grey.shade600 : _phaseColor,
                ),
              ),
              // Название + участники
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHidden ? 'Закрытый план' : (shell.title ?? 'Без названия'),
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isHidden ? colors.onSurface.withValues(alpha: 0.4) : null,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _participantsLabel(shell.participantsCount),
                      style: textTheme.bodySmall?.copyWith(
                        color: isHidden
                            ? colors.onSurface.withValues(alpha: 0.3)
                            : colors.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              // Стрелка — только для видимых
              if (!isHidden) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  size: 20,
                  color: colors.onSurface.withValues(alpha: 0.4),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────
// Feed: модалка участников плана
// ──────────────────────────────────────────────

class _FeedPlanParticipantsDialog extends StatefulWidget {
  final PlanShellDto shell;

  const _FeedPlanParticipantsDialog({required this.shell});

  @override
  State<_FeedPlanParticipantsDialog> createState() =>
      _FeedPlanParticipantsDialogState();
}

class _FeedPlanParticipantsDialogState
    extends State<_FeedPlanParticipantsDialog> {
  String? _currentAppUserId;

  @override
  void initState() {
    super.initState();
    UserSnapshotStorage().read().then((snapshot) {
      if (mounted && snapshot != null) {
        setState(() => _currentAppUserId = snapshot.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final preview = widget.shell.participantsPublicPreview;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.shell.title ?? 'Участники',
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: preview.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('Нет участников')),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                      itemCount: preview.length,
                      itemBuilder: (context, i) {
                        final p = preview[i];
                        final isMe = _currentAppUserId != null &&
                            p.userId == _currentAppUserId;
                        final miniProfile = p.userId != null
                            ? UserMiniProfile(
                                userId: p.userId!,
                                nickname: p.nickname,
                                avatarUrl: p.avatarUrl,
                              )
                            : null;

                        final colors = Theme.of(context).colorScheme;
                        final borderColor = isMe
                            ? colors.primary
                            : Colors.white.withValues(alpha: 0.18);
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: borderColor,
                                width: isMe ? 1.5 : 1.0),
                          ),
                          child: ListTile(
                            leading: UserAvatarWidget(
                              profile: miniProfile,
                              size: 40,
                              borderRadius:
                                  const BorderRadius.all(Radius.circular(10)),
                            ),
                            title: Text(
                              p.nickname?.isNotEmpty == true
                                  ? p.nickname!
                                  : '—',
                              style: TextStyle(
                                fontWeight: isMe
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                              ),
                            ),
                            onTap: p.userId != null
                                ? () => UserCardSheet.show(
                                      context,
                                      targetUserId: p.userId!,
                                      cardContext: 'in_feed',
                                    )
                                : null,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
