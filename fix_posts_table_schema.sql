-- Fix and align posts schema across environments (idempotent)
-- Safe to run multiple times; only adds/adjusts what is missing

begin;

-- Ensure UUID generation function is available
create extension if not exists pgcrypto;

-- Create posts table if missing, using a minimal, stable schema that matches the app
create table if not exists public.posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  type text not null,
  caption text,
  content text not null default '',
  media_url text,
  thumbnail_url text,
  location text,
  hashtags text[] default '{}'::text[],
  mentions text[] default '{}'::text[],
  is_public boolean not null default true,
  allow_comments boolean not null default true,
  views_count integer not null default 0,
  likes_count integer not null default 0,
  comments_count integer not null default 0,
  shares_count integer not null default 0,
  saves_count integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz
);

-- Add any missing columns on existing tables
alter table public.posts add column if not exists caption text;
alter table public.posts add column if not exists content text default '' not null;
alter table public.posts add column if not exists media_url text;
alter table public.posts add column if not exists thumbnail_url text;
alter table public.posts add column if not exists location text;
alter table public.posts add column if not exists hashtags text[] default '{}'::text[];
alter table public.posts add column if not exists mentions text[] default '{}'::text[];
alter table public.posts add column if not exists is_public boolean default true not null;
alter table public.posts add column if not exists allow_comments boolean default true not null;
alter table public.posts add column if not exists views_count integer default 0 not null;
alter table public.posts add column if not exists likes_count integer default 0 not null;
alter table public.posts add column if not exists comments_count integer default 0 not null;
alter table public.posts add column if not exists shares_count integer default 0 not null;
alter table public.posts add column if not exists saves_count integer default 0 not null;
alter table public.posts add column if not exists created_at timestamptz default now() not null;
alter table public.posts add column if not exists updated_at timestamptz;

-- Ensure core constraints/defaults on existing columns (safe checks)
do $$
begin
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='posts' and column_name='user_id') then
    alter table public.posts alter column user_id set not null;
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='posts' and column_name='type') then
    alter table public.posts alter column type set not null;
  end if;
  if exists (select 1 from information_schema.columns where table_schema='public' and table_name='posts' and column_name='content') then
    alter table public.posts alter column content set default '';
    alter table public.posts alter column content set not null;
  end if;
end $$;

-- Helpful indexes
create index if not exists idx_posts_user_id on public.posts(user_id);
create index if not exists idx_posts_created_at on public.posts(created_at);
create index if not exists idx_posts_is_public on public.posts(is_public);

-- Enable RLS and add policies only if they don't exist yet
alter table public.posts enable row level security;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='public' and tablename='posts' and policyname='Allow select public or own posts') then
    create policy "Allow select public or own posts"
      on public.posts
      for select
      using (is_public = true or auth.uid() = user_id);
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='posts' and policyname='Allow insert own posts') then
    create policy "Allow insert own posts"
      on public.posts
      for insert
      with check (auth.uid() = user_id);
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='posts' and policyname='Allow update own posts') then
    create policy "Allow update own posts"
      on public.posts
      for update
      using (auth.uid() = user_id)
      with check (auth.uid() = user_id);
  end if;

  if not exists (select 1 from pg_policies where schemaname='public' and tablename='posts' and policyname='Allow delete own posts') then
    create policy "Allow delete own posts"
      on public.posts
      for delete
      using (auth.uid() = user_id);
  end if;
end $$;

-- updated_at trigger (idempotent)
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $func$
begin
  new.updated_at = now();
  return new;
end
$func$;

do $$
begin
  if not exists (select 1 from pg_trigger where tgname = 'posts_set_updated_at') then
    create trigger posts_set_updated_at
      before update on public.posts
      for each row
      execute procedure public.set_updated_at();
  end if;
end $$;

-- Ensure users table has posts_count and RPC to increment it (used by the app)
alter table public.users add column if not exists posts_count integer not null default 0;

do $$
begin
  if not exists (select 1 from pg_proc where proname='increment_user_posts_count') then
    create function public.increment_user_posts_count(target_user_id uuid)
    returns void
    language sql
    security definer
    set search_path = public
    as $f$
      update public.users
      set posts_count = coalesce(posts_count, 0) + 1
      where id = target_user_id;
    $f$;
    grant execute on function public.increment_user_posts_count(uuid) to authenticated;
  end if;
end $$;

commit;