import 'legal_acceptance_status_dto.dart';
import 'legal_document_dto.dart';

abstract interface class LegalRepository {
  Future<List<LegalDocumentDto>> getCurrentDocuments();

  Future<void> acceptDocuments({
    required String appUserId,
    required String termsVersion,
    required String privacyVersion,
    required String bonusRulesVersion,
    required String appVersion,
  });

  Future<LegalAcceptanceStatusDto> checkAcceptance({
    required String appUserId,
  });
}
