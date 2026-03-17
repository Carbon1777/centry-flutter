import 'package:supabase_flutter/supabase_flutter.dart';

import 'legal_acceptance_status_dto.dart';
import 'legal_document_dto.dart';
import 'legal_repository.dart';

class LegalRepositoryImpl implements LegalRepository {
  final SupabaseClient _client;

  LegalRepositoryImpl(this._client);

  @override
  Future<List<LegalDocumentDto>> getCurrentDocuments() async {
    final response = await _client.rpc('get_current_legal_documents_v1');
    final list = response as List<dynamic>;
    return list
        .map((e) => LegalDocumentDto.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> acceptDocuments({
    required String appUserId,
    required String termsVersion,
    required String privacyVersion,
    required String bonusRulesVersion,
    required String appVersion,
  }) async {
    await _client.rpc('accept_legal_documents_v1', params: {
      'p_app_user_id':         appUserId,
      'p_terms_version':       termsVersion,
      'p_privacy_version':     privacyVersion,
      'p_bonus_rules_version': bonusRulesVersion,
      'p_user_agent':          'flutter',
      'p_app_version':         appVersion,
    });
  }

  @override
  Future<LegalAcceptanceStatusDto> checkAcceptance({
    required String appUserId,
  }) async {
    final response = await _client.rpc(
      'check_legal_acceptance_v1',
      params: {'p_app_user_id': appUserId},
    );
    return LegalAcceptanceStatusDto.fromJson(
      Map<String, dynamic>.from(response as Map),
    );
  }
}
