import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class UserSnapshot {
  final String id;
  final String publicId;
  final String nickname;
  final String state; // GUEST | USER

  const UserSnapshot({
    required this.id,
    required this.publicId,
    required this.nickname,
    required this.state,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'public_id': publicId,
        'nickname': nickname,
        'state': state,
      };

  static UserSnapshot fromJson(Map<String, dynamic> json) {
    return UserSnapshot(
      id: json['id'] as String,
      publicId: json['public_id'] as String,
      nickname: json['nickname'] as String,
      state: json['state'] as String,
    );
  }
}

class UserSnapshotStorage {
  static const _key = 'user_snapshot';

  // Pending deep links (foundation for invites; later deferred provider will write here too)
  static const _pendingPlanInviteTokenKey = 'pending_plan_invite_token';

  // Friends guest-proof secret (server-first).
  // IMPORTANT: this is NOT an auth/email requirement.
  // It is a per-install secret used to prove "who is calling" when the user is a guest.
  static const _deviceSecretKey = 'device_secret_v1';

  final _storage = const FlutterSecureStorage();

  Future<UserSnapshot?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;

    final json = jsonDecode(raw) as Map<String, dynamic>;
    return UserSnapshot.fromJson(json);
  }

  Future<void> save(UserSnapshot snapshot) async {
    await _storage.write(
      key: _key,
      value: jsonEncode(snapshot.toJson()),
    );
  }

  Future<void> clear() async {
    await _storage.delete(key: _key);
  }

  // ===== Device Secret (Friends) =====

  /// Returns an existing device secret or generates a new one and stores it.
  /// This secret is used with Friends RPC as (app_user_id + device_secret).
  Future<String> getOrCreateDeviceSecret() async {
    final existing = await readDeviceSecret();
    if (existing != null && existing.isNotEmpty) return existing;

    final generated = _generateDeviceSecret();
    await _storage.write(key: _deviceSecretKey, value: generated);
    return generated;
  }

  Future<String?> readDeviceSecret() async {
    final raw = await _storage.read(key: _deviceSecretKey);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Future<void> clearDeviceSecret() async {
    await _storage.delete(key: _deviceSecretKey);
  }

  String _generateDeviceSecret() {
    // 32 bytes -> base64url string (no padding). Length ~43 chars.
    final rnd = Random.secure();
    final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  // ===== Pending Plan Invite Token =====

  Future<String?> readPendingPlanInviteToken() async {
    final raw = await _storage.read(key: _pendingPlanInviteTokenKey);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Future<void> writePendingPlanInviteToken(String token) async {
    if (token.isEmpty) return;
    await _storage.write(
      key: _pendingPlanInviteTokenKey,
      value: token,
    );
  }

  Future<void> clearPendingPlanInviteToken() async {
    await _storage.delete(key: _pendingPlanInviteTokenKey);
  }
}
