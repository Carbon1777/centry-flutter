import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';

/// Canonical GPS-only geo service for Centry.
///
/// Fixed product rules:
/// - GPS only (not IP/operator; VPN must not affect result)
/// - refresh on app cold start + app resume
/// - if GPS fetch fails -> use last known position from local storage
/// - NO business logic here. Only signal acquisition + persistence.
class GeoService {
  GeoService._();

  static final GeoService instance = GeoService._();

  static const _keyLat = 'geo_last_lat';
  static const _keyLng = 'geo_last_lng';
  static const _keyTs = 'geo_last_ts_ms';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  /// Latest known position (GPS if available; otherwise persisted last-known).
  final ValueNotifier<GeoPosition?> current = ValueNotifier<GeoPosition?>(null);

  /// Increments each time we *attempt* a refresh due to app start/resume.
  /// UI will later use this to show the "geo applied" dialog once per session.
  final ValueNotifier<int> refreshTick = ValueNotifier<int>(0);

  bool _initialized = false;
  Future<void>? _initFuture;

  /// Must be called once at app start. Safe to call multiple times.
  Future<void> ensureInitialized() {
    if (_initialized) return Future.value();
    _initFuture ??= _ensureInitializedImpl();
    return _initFuture!;
  }

  Future<void> _ensureInitializedImpl() async {
    // Load last-known first (so app has a signal even before GPS completes).
    final last = await _readLastKnown();
    if (last != null) {
      current.value = last;
    }
    _initialized = true;
  }

  /// Refresh GPS position (attempt). If fails, keeps/loads last-known.
  ///
  /// NOTE: This does NOT request permissions. Permissions flow is handled
  /// in onboarding (PermissionsScreen). If permission is not granted, we fall
  /// back to last-known.
  Future<void> refresh() async {
    await ensureInitialized();

    refreshTick.value = refreshTick.value + 1;

    GeoPosition? next;

    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        next = await _readLastKnown();
      } else {
        // GPS-only: request high accuracy.
        final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        );

        next = GeoPosition(
          lat: pos.latitude,
          lng: pos.longitude,
          tsMs: DateTime.now().millisecondsSinceEpoch,
        );

        await _writeLastKnown(next);
      }
    } catch (_) {
      next = await _readLastKnown();
    }

    if (next != null) {
      current.value = next;
    }
  }

  Future<GeoPosition?> _readLastKnown() async {
    final latRaw = await _storage.read(key: _keyLat);
    final lngRaw = await _storage.read(key: _keyLng);
    final tsRaw = await _storage.read(key: _keyTs);

    if (latRaw == null || lngRaw == null) return null;

    final lat = double.tryParse(latRaw);
    final lng = double.tryParse(lngRaw);
    final tsMs = int.tryParse(tsRaw ?? '');

    if (lat == null || lng == null) return null;

    return GeoPosition(
      lat: lat,
      lng: lng,
      tsMs: tsMs,
    );
  }

  Future<void> _writeLastKnown(GeoPosition pos) async {
    await _storage.write(key: _keyLat, value: pos.lat.toString());
    await _storage.write(key: _keyLng, value: pos.lng.toString());
    await _storage.write(
      key: _keyTs,
      value: (pos.tsMs ?? DateTime.now().millisecondsSinceEpoch).toString(),
    );
  }
}

class GeoPosition {
  final double lat;
  final double lng;

  /// Timestamp in ms when the position was obtained (optional).
  final int? tsMs;

  const GeoPosition({
    required this.lat,
    required this.lng,
    required this.tsMs,
  });
}
