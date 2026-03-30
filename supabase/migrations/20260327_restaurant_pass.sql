-- Пароль для входу ресторанів через веб-панель
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS restaurant_pass TEXT;
