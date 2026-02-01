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
CREATE POLICY "Allow public read access to app_config" ON public.app_config
  FOR SELECT USING (true);

-- Insert the Hugging Face API token (placeholder)
-- You should update this value in your Supabase dashboard
INSERT INTO public.app_config (key, value, description)
VALUES 
  ('hugging_face_api_token', 'hf_YOUR_ACTUAL_TOKEN_HERE', 'API token for Hugging Face inference')
ON CONFLICT (key) DO UPDATE 
SET value = EXCLUDED.value;
