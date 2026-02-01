-- Create app_config table for dynamic configuration
CREATE TABLE IF NOT EXISTS public.app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  description TEXT,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Enable RLS
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

-- Allow public read access (so the app can fetch config)
-- Use a DO block to check if policy exists to avoid errors on re-runs
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_policies
        WHERE schemaname = 'public'
        AND tablename = 'app_config'
        AND policyname = 'Allow public read access to app_config'
    ) THEN
        CREATE POLICY "Allow public read access to app_config" ON public.app_config
        FOR SELECT USING (true);
    END IF;
END
$$;

-- Insert or Update the Hugging Face API token
-- REPLACE 'hf_YOUR_ACTUAL_TOKEN_HERE' WITH YOUR REAL TOKEN BEFORE RUNNING
INSERT INTO public.app_config (key, value, description)
VALUES 
  ('hugging_face_api_token', 'hf_YOUR_ACTUAL_TOKEN_HERE', 'API token for Hugging Face inference')
ON CONFLICT (key) DO UPDATE 
SET value = EXCLUDED.value;
