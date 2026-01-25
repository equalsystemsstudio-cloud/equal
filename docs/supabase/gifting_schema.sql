-- Equal App: Live Stream Gifting Schema (Supabase)
-- Phase 1: Earnable coins only (no cash-out). Run this in Supabase SQL.

-- gifts_catalog: configurable virtual gifts
create table if not exists public.gifts_catalog (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  icon_key text not null, -- e.g., 'gift', 'star', 'fire', 'heart'
  cost_coins integer not null check (cost_coins > 0),
  is_active boolean not null default true,
  created_at timestamp with time zone not null default now()
);

-- user_wallets: per-user coin balances
create table if not exists public.user_wallets (
  user_id uuid primary key,
  coins integer not null default 0,
  updated_at timestamp with time zone not null default now()
);

-- gift_transactions: immutable log of gifts sent during a stream
create table if not exists public.gift_transactions (
  id uuid primary key default gen_random_uuid(),
  stream_id uuid not null references public.live_streams(id) on delete cascade,
  sender_user_id uuid not null,
  gift_id uuid not null references public.gifts_catalog(id),
  gift_name text not null,
  coins_spent integer not null check (coins_spent > 0),
  created_at timestamp with time zone not null default now()
);

create index if not exists gift_transactions_stream_idx on public.gift_transactions(stream_id);
create index if not exists gift_transactions_sender_idx on public.gift_transactions(sender_user_id);

-- Recommended RLS policies (adjust to your project’s auth schema):
-- NOTE: Enable RLS after validating queries work.
-- alter table public.user_wallets enable row level security;
-- alter table public.gift_transactions enable row level security;
-- alter table public.gifts_catalog enable row level security;

-- Example policies:
-- Wallets: owner can read and update their own balance
-- create policy "wallet read own" on public.user_wallets
--   for select using (auth.uid() = user_id);
-- create policy "wallet update own" on public.user_wallets
--   for update using (auth.uid() = user_id);

-- Gifts catalog: readable by all authenticated users
-- create policy "gifts read all" on public.gifts_catalog
--   for select using (auth.role() = 'authenticated');

-- Gift transactions: insert by authenticated users; select by all for a stream
-- create policy "gift tx insert" on public.gift_transactions
--   for insert with check (auth.uid() = sender_user_id);
-- create policy "gift tx read" on public.gift_transactions
--   for select using (true);

-- Seed: Basic gift catalog (optional)
insert into public.gifts_catalog (name, icon_key, cost_coins)
select * from (
  values
    ('Gift Box', 'gift', 20),
    ('Star', 'star', 10),
    ('Fire', 'fire', 15),
    ('Heart', 'heart', 12)
) as v(name, icon_key, cost_coins)
where not exists (
  select 1 from public.gifts_catalog gc
  where gc.name = v.name and gc.icon_key = v.icon_key and gc.cost_coins = v.cost_coins
);

