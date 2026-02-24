import '../../../data/local/user_snapshot_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/places/places_repository.dart';
import '../../profile/profile_email_modal.dart';

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
  });

  @override
  State<PlaceDetailsDialog> createState() => _PlaceDetailsDialogState();
}

class _PlaceDetailsDialogState extends State<PlaceDetailsDialog> {
  bool _loading = true;
  bool _voting = false;
  bool _hasChanged = false; // ✅ добавлено

  bool _savingSaved = false;
  bool _savedByMe = false;

  int _likes = 0;
  int _dislikes = 0;
  int _myVote = 0;
  double? _rating;

  // ==========================
  // META (content only)
  // ==========================
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

    if (kDebugMode) {
      debugPrint('[PlaceDetailsDialog] initState placeId=${widget.placeId}');
    }

    // 🔎 DEBUG SNAPSHOT
    Future.microtask(() async {
      final snapshot = await UserSnapshotStorage().read();
      debugPrint(
        'SNAPSHOT DEBUG (initState) → id=${snapshot?.id}, state=${snapshot?.state}',
      );
    });

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

      // Snapshot is required to bootstrap the upgrade flow (Guest → User).
      final s = snapshot;
      if (s == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Не удалось открыть регистрацию: нет snapshot')),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => ProfileEmailModal(
          bootstrapResult: {
            'id': s.id,
            'public_id': s.publicId,
            'nickname': s.nickname,
          },
          onUpgradeSuccess: () {
            // Do not mutate business state here.
            // We will re-read snapshot after the modal closes and then proceed.
          },
        ),
      );

      final updated = await UserSnapshotStorage().read();
      if (!mounted) return;

      if (updated == null || updated.state != 'USER') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Регистрация не завершена')),
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

      // Canonical refetch of details (server is the source of truth).
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
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[PlaceDetailsDialog] toggleSavedPlace failed: $e');
        debugPrint('$st');
      }
      if (!mounted) return;
      setState(() {
        _savingSaved = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Не удалось сохранить место')),
      );
    }
  }

  Future<void> _ensureSavedAfterUpgrade() async {
    // After magic-link upgrade we must refetch canonical details and ensure "saved" is applied once.
    await _loadDetails();
    if (!mounted) return;

    // If already saved (e.g. previous attempt succeeded) — do nothing.
    if (_savedByMe) return;

    await _toggleSavedCanonical();
  }

  Future<void> _loadDetails() async {
    try {
      final result = await widget.repository.getPlaceDetails(
        placeId: widget.placeId,
      );

      debugPrint('DETAILS RESULT → $result');

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

      dynamic asString(dynamic v) => v == null ? null : v.toString();
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
        // tolerate shapes like {items:[...]} or {phones:[...]}
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

      // photos: take first as preview if present
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
      // meta load failed
      if (kDebugMode) {
        debugPrint('[PlaceDetailsDialog] meta load failed: $e');
      }
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
        _hasChanged = true; // ✅ фиксируем изменение
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _voting = false;
      });
    }
  }

  bool get _canTapVote => !_loading && !_voting;

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

  void _copyAddress() {
    Clipboard.setData(ClipboardData(text: _effectiveAddress));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Адрес скопирован')),
    );
  }

  void _close() {
    Navigator.of(context).pop(_hasChanged); // ✅ возвращаем флаг
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

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
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.9,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(20)),
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
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
                                  horizontal: 8, vertical: 4),
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
                  fit: FlexFit.loose,
                  child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: SingleChildScrollView(
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
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              minimumSize: const Size(160, 36),
                            ),
                            child: _savingSaved
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Text(
                                    _savedByMe
                                        ? 'Удалить из Моих мест'
                                        : 'Добавить в Мои места',
                                  ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),

                      // ==========================
                      // INFO (contract order)
                      // City → Area → Metro → Address → Website → Phone → Rating
                      // ==========================
                      if (_effectiveCityName != null &&
                          _effectiveCityName!.trim().isNotEmpty) ...[
                        Text(
                          _effectiveCityName!,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                      ],

                      if (_effectiveAreaName != null &&
                          _effectiveAreaName!.trim().isNotEmpty) ...[
                        Text(
                          _effectiveAreaName!,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                      ],

                      if (_effectiveMetroName != null &&
                          _effectiveMetroName!.trim().isNotEmpty) ...[
                        Text(
                          'м. ${_effectiveMetroName}${_effectiveMetroDistanceM != null ? " · ${_effectiveMetroDistanceM} м" : ""}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
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
                            icon: const Icon(Icons.copy_rounded, size: 18),
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
                                    final uri = Uri(scheme: 'tel', path: tel);
                                    await launchUrl(
                                      uri,
                                      mode: LaunchMode.externalApplication,
                                    );
                                  },
                                  child: Text(p),
                                ),
                              ),
                          ],
                        ),
                      ],

                      const SizedBox(height: 6),
                      Text(
                        'Рейтинг',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _rating != null ? _rating!.toStringAsFixed(1) : '—',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _Vote(
                            icon: Icons.thumb_up_alt_rounded,
                            count: _likes,
                            active: _myVote == 1,
                            activeColor: Colors.green,
                            onTap: _canTapVote
                                ? () => _vote(_myVote == 1 ? 0 : 1)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          _Vote(
                            icon: Icons.thumb_down_alt_rounded,
                            count: _dislikes,
                            active: _myVote == -1,
                            activeColor: Colors.redAccent,
                            onTap: _canTapVote
                                ? () => _vote(_myVote == -1 ? 0 : -1)
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2DD4BF),
                            foregroundColor: Colors.black,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Добавить в план',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
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
                onPressed: _close, // ✅ изменено
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
