import 'package:supabase_flutter/supabase_flutter.dart';

/// Тонкая обёртка над Supabase Auth.
/// Все методы возвращают человекочитаемые ошибки через [AuthFlowException].
class AuthService {
  AuthService(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  Session? get currentSession => _auth.currentSession;
  User? get currentUser => _auth.currentUser;

  /// Проверить, свободен ли email (true = можно регистрироваться).
  /// RPC проверяет `app_users` и `auth.users`. Используется ДО signUp,
  /// чтобы не упереться в тихий `user_repeated_signup` (когда Supabase
  /// возвращает 200 OK, но письмо не шлёт по соображениям приватности).
  Future<bool> checkEmailAvailable(String email) async {
    final dynamic res = await _client.rpc(
      'check_email_available',
      params: {'p_email': email.trim()},
    );
    return res == true;
  }

  /// Создать аккаунт. После signUp Supabase сразу шлёт письмо с OTP-кодом
  /// (так настроен Confirm signup template).
  /// Сессия НЕ выдаётся, пока не пройден verifyOtp.
  Future<void> signUp({required String email, required String password}) async {
    try {
      await _auth.signUp(email: email.trim(), password: password);
    } on AuthException catch (e) {
      throw AuthFlowException(_mapAuthError(e));
    }
  }

  /// Войти по email+password. Сессия выдаётся сразу.
  Future<Session> signInWithPassword({
    required String email,
    required String password,
  }) async {
    try {
      final res = await _auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
      final session = res.session;
      if (session == null) {
        throw AuthFlowException('Не удалось войти');
      }
      return session;
    } on AuthException catch (e) {
      throw AuthFlowException(_mapAuthError(e));
    }
  }

  /// Подтвердить email 6-значным кодом (OTP) после signUp.
  /// При успехе Supabase ставит email_confirmed_at и выдаёт сессию.
  Future<Session> verifySignupOtp({
    required String email,
    required String token,
  }) async {
    try {
      final res = await _auth.verifyOTP(
        email: email.trim(),
        token: token,
        type: OtpType.signup,
      );
      final session = res.session;
      if (session == null) {
        throw AuthFlowException('Неверный код или истёк срок действия');
      }
      return session;
    } on AuthException catch (e) {
      throw AuthFlowException(_mapAuthError(e));
    }
  }

  /// Запросить письмо с OTP-кодом для сброса пароля.
  Future<void> requestPasswordReset({required String email}) async {
    try {
      await _auth.resetPasswordForEmail(email.trim());
    } on AuthException catch (e) {
      throw AuthFlowException(_mapAuthError(e));
    }
  }

  /// Подтвердить OTP-код сброса пароля. Возвращает временную сессию,
  /// в которой можно вызвать [updatePassword].
  Future<Session> verifyRecoveryOtp({
    required String email,
    required String token,
  }) async {
    try {
      final res = await _auth.verifyOTP(
        email: email.trim(),
        token: token,
        type: OtpType.recovery,
      );
      final session = res.session;
      if (session == null) {
        throw AuthFlowException('Неверный код или истёк срок действия');
      }
      return session;
    } on AuthException catch (e) {
      throw AuthFlowException(_mapAuthError(e));
    }
  }

  /// Установить новый пароль. Требует активную сессию (после verifyRecoveryOtp
  /// или для авторизованного пользователя).
  Future<void> updatePassword(String newPassword) async {
    try {
      await _auth.updateUser(UserAttributes(password: newPassword));
    } on AuthException catch (e) {
      throw AuthFlowException(_mapAuthError(e));
    }
  }

  /// Повторно отправить OTP-код подтверждения регистрации.
  Future<void> resendSignupOtp({required String email}) async {
    try {
      await _auth.resend(type: OtpType.signup, email: email.trim());
    } on AuthException catch (e) {
      throw AuthFlowException(_mapAuthError(e));
    }
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on AuthException catch (e) {
      throw AuthFlowException(_mapAuthError(e));
    }
  }

  String _mapAuthError(AuthException e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('invalid login credentials') ||
        msg.contains('invalid_credentials')) {
      return 'Неверный email или пароль';
    }
    if (msg.contains('user already registered') ||
        msg.contains('already registered') ||
        msg.contains('user_already_exists')) {
      return 'Этот email уже зарегистрирован';
    }
    if (msg.contains('email not confirmed')) {
      return 'Email не подтверждён';
    }
    if (msg.contains('token has expired') ||
        msg.contains('otp_expired') ||
        msg.contains('expired')) {
      return 'Срок действия кода истёк';
    }
    if (msg.contains('invalid token') || msg.contains('token_hash')) {
      return 'Неверный код';
    }
    if (msg.contains('rate limit') || msg.contains('over_email_send_rate_limit')) {
      return 'Слишком много попыток. Попробуйте позже';
    }
    if (msg.contains('different from the old password') ||
        msg.contains('same_password') ||
        msg.contains('same password')) {
      return 'Новый пароль должен отличаться от старого';
    }
    if (msg.contains('weak password') ||
        msg.contains('password should be at least')) {
      return 'Пароль слишком простой';
    }
    return 'Ошибка авторизации';
  }
}

class AuthFlowException implements Exception {
  AuthFlowException(this.message);
  final String message;
  @override
  String toString() => message;
}
