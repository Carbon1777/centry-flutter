class SupabaseConfig {
  /// Supabase Project URL.
  /// Используем reverse-proxy в РФ (api.centryweb.ru) вместо прямого
  /// supabase.co, чтобы обходить замедление Cloudflare у российских
  /// провайдеров. Прокси прозрачен: /rest, /auth, /storage, /realtime,
  /// /functions проксируются на исходный Supabase. См. TZ10_russian_proxy.md.
  static const String url = 'https://api.centryweb.ru';

  /// Supabase publishable (public) key
  static const String anonKey =
      'sb_publishable_YlYQC-Sv2prP2QPmZs48rA_gjSb62aB';
}
