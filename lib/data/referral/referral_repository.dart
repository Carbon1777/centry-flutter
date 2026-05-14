import 'referral_code_dto.dart';

abstract class ReferralRepository {
  /// Ленивая идемпотентная генерация реф-кода: первый вызов создаёт код,
  /// повторные возвращают тот же.
  Future<ReferralCodeDto> getOrCreateMyCode();
}
