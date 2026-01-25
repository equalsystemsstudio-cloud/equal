-- Add a Safe Mode flag to users for content filtering

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS safe_mode boolean DEFAULT true;

CREATE INDEX IF NOT EXISTS idx_users_safe_mode ON public.users (safe_mode);

