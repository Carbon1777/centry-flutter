-- ============================================================================
-- app_users.install_store — атрибуция магазина установки приложения
-- ============================================================================
--
-- Цель: закрыть слепое пятно «не знаем, с какого стора пришёл юзер».
-- Клиент через store_checker определяет источник установки и записывает
-- в эту колонку при первой авторизации после установки нового билда.
--
-- ВАЖНО: в Centry эквивалент стандартного `profiles` — это `app_users`
-- (server-first архитектура, app_user_id вместо auth.uid()). install_store
-- хранится здесь, потому что это атрибут самого юзера, а не профиля.
--
-- Аддитивно и идемпотентно:
--   • IF NOT EXISTS на колонку, индекс и тест на констрейнт
--   • NULL у всех существующих юзеров — это ожидаемо, install source
--     ретроспективно не восстановить
--   • текущая выпущенная версия клиента не сломается (поле не обязательно)
-- ============================================================================

ALTER TABLE public.app_users
  ADD COLUMN IF NOT EXISTS install_store text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'app_users_install_store_check'
      AND conrelid = 'public.app_users'::regclass
  ) THEN
    ALTER TABLE public.app_users
      ADD CONSTRAINT app_users_install_store_check
      CHECK (install_store IS NULL OR install_store IN (
        'app_store',
        'google_play',
        'rustore',
        'huawei',
        'samsung',
        'amazon',
        'sideload',
        'unknown'
      ));
  END IF;
END$$;

CREATE INDEX IF NOT EXISTS idx_app_users_install_store
  ON public.app_users(install_store)
  WHERE install_store IS NOT NULL;

COMMENT ON COLUMN public.app_users.install_store IS
  'Магазин установки приложения. Определяется клиентом (package store_checker) при первом запуске и записывается один раз при auth. NULL = неизвестно (старые билды/existing юзеры).';
