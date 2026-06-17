-- ════════════════════════════════════════════════════════════════════════════
-- Bookly MY — MyInvois (Phase 4 #28) cloud schema migration
-- Run in: Supabase Dashboard → SQL Editor, project dgquwkdzmufnrnwquvci
-- Idempotent. Safe to run more than once.
-- ════════════════════════════════════════════════════════════════════════════

-- 1) Per-user MyInvois API credentials (read only by their owner) -------------
create table if not exists public.myinvois_credentials (
  user_id       uuid primary key references auth.users(id) on delete cascade,
  client_id     text not null default '',
  client_secret text not null default '',
  env           text not null default 'sandbox',   -- 'sandbox' | 'prod'
  updated_at    timestamptz default now()
);

alter table public.myinvois_credentials enable row level security;

do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public' and tablename = 'myinvois_credentials'
      and policyname = 'own_myinvois_creds'
  ) then
    create policy "own_myinvois_creds" on public.myinvois_credentials
      for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
  end if;
end $$;

-- 2) Buyer TIN on customers (matches the app's Customer.tin field) -------------
do $$
begin
  if to_regclass('public.customers') is not null then
    alter table public.customers add column if not exists tin text not null default '';
  end if;
end $$;

-- ════════════════════════════════════════════════════════════════════════════
-- Done. The Edge Function (supabase/functions/myinvois) reads this table with
-- the caller's JWT, so RLS keeps each user limited to their own credentials.
-- ════════════════════════════════════════════════════════════════════════════
