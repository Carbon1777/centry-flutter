import 'dart:convert';

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
  static const _pendingReferralCodeKey = 'pending_referral_code';

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

  // ===== Pending Referral Code =====
  //
  // Постоянная реф-ссылка юзера (см. TZ_referral_program.md). Захватывается
  // при первом запуске из deep link или clipboard, применяется после
  // успешной авторизации в _runPostIdentityFlowsAsync. clear() для
  // user_snapshot этот ключ НЕ трогает — pending данные переживают logout
  // (как pending_plan_invite_token).

  Future<String?> readPendingReferralCode() async {
    final raw = await _storage.read(key: _pendingReferralCodeKey);
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  Future<void> writePendingReferralCode(String code) async {
    if (code.isEmpty) return;
    await _storage.write(
      key: _pendingReferralCodeKey,
      value: code,
    );
  }

  Future<void> clearPendingReferralCode() async {
    await _storage.delete(key: _pendingReferralCodeKey);
  }
}
