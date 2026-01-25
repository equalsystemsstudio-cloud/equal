-- Bootstrap exec_sql helper to allow executing arbitrary SQL via RPC
-- Run this once in your Supabase project's SQL Editor with service role privileges

-- Create a function that executes a SQL text and returns void
CREATE OR REPLACE FUNCTION public.exec_sql(sql text)
RETURNS void AS $$
BEGIN
  EXECUTE sql;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = public;

-- Grant execute to service_role
GRANT EXECUTE ON FUNCTION public.exec_sql(text) TO service_role;

-- Optionally grant to authenticated if you need (not recommended)
-- GRANT EXECUTE ON FUNCTION public.exec_sql(text) TO authenticated;