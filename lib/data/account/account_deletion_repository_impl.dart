import 'package:supabase_flutter/supabase_flutter.dart';

import 'account_deletion_repository.dart';

class AccountDeletionRepositoryImpl implements AccountDeletionRepository {
  final SupabaseClient _client;

  AccountDeletionRepositoryImpl(this._client);

  @override
  Future<String> requestDeletion({String? reason}) async {
    final result = await _client.rpc(
      'request_account_deletion_v1',
      params: {'p_reason': reason},
    );

    if (result is! Map) {
      throw StateError('request_account_deletion_v1 returned unexpected payload: $result');
    }

    final status = result['status'] as String?;
    if (status == null) {
      throw StateError('request_account_deletion_v1: missing status field');
    }

    // ok, already_pending — оба допустимы (идемпотентность)
    if (status != 'ok' && status != 'already_pending') {
      throw StateError('request_account_deletion_v1 unexpected status: $status');
    }

    final jobId = result['job_id'];
    if (jobId == null) {
      throw StateError('request_account_deletion_v1: missing job_id');
    }
    return jobId.toString();
  }

  @override
  Future<void> finalizeAuthDeletion() async {
    final session = _client.auth.currentSession;
    if (session == null) {
      throw StateError('No active session — cannot call delete-auth-user');
    }

    final response = await _client.functions.invoke(
      'delete-auth-user',
      method: HttpMethod.post,
    );

    if (response.status != 200) {
      final body = response.data;
      final message = (body is Map ? body['message'] : null) ?? 'unknown error';
      throw StateError('delete-auth-user failed (${response.status}): $message');
    }
  }
}
