import '../../data/legal/legal_document_dto.dart';

/// In-memory state, который держит данные между экранами онбординга
/// (Agreement → Auth → Otp → Nickname). Очищается при перезапуске процесса —
/// это ОК, в таком случае юзер начинает онбординг с Agreement заново.
class OnboardingFlowState {
  OnboardingFlowState._();
  static final OnboardingFlowState instance = OnboardingFlowState._();

  /// Принятые версии документов (фиксируется на AgreementScreen, применяется
  /// в NicknameScreen через accept_legal_documents_v1 после bootstrap_guest).
  List<LegalDocumentDto> acceptedLegalDocuments = const [];

  /// Email, на который ушёл OTP-код (передаётся между AuthScreen и OtpVerifyScreen).
  String? pendingEmail;

  void reset() {
    acceptedLegalDocuments = const [];
    pendingEmail = null;
  }
}
