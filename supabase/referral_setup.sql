-- ════════════════════════════════════════════════════════════════════════════
-- Bookly MY — Referral system schema
-- Run once in Supabase → SQL Editor.
-- ════════════════════════════════════════════════════════════════════════════

-- One row per user: their invite code, who referred them, activity + reward tier.
create table if not exists referral_profiles (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  code         text unique not null,
  referred_by  uuid references auth.users(id),
  active       boolean not null default false,   -- referee counts only when active
  granted_tier int not null default 0,           -- highest tier already rewarded (0/1/5/10/20)
  created_at   timestamptz not null default now()
);

alter table referral_profiles enable row level security;

-- Users may read their own profile. All writes go through the Edge Function
-- (service role, which bypasses RLS) — never directly from the client.
drop policy if exists "referral own read" on referral_profiles;
create policy "referral own read" on referral_profiles
  for select using (auth.uid() = user_id);

-- Fast lookup of a referrer's referees.
create index if not exists referral_referred_by_idx on referral_profiles(referred_by);
