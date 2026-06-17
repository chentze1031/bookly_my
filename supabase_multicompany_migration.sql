-- ════════════════════════════════════════════════════════════════════════════
-- Bookly MY — Multi-company (Phase 4 #24) cloud schema migration
-- Run in: Supabase Dashboard → SQL Editor, project dgquwkdzmufnrnwquvci
--
-- What it does:
--   • Adds a `company_id` column (default 'default') to every synced table.
--   • Replaces the old per-user uniqueness with per-(user, company) uniqueness
--     so each company is isolated in the cloud.
--   • Idempotent — safe to run more than once. No data is deleted; existing
--     rows become company_id = 'default' (your current single company).
-- ════════════════════════════════════════════════════════════════════════════

-- 1) Add company_id to every synced table (skips tables that don't exist) -----
do $$
declare t text;
begin
  foreach t in array array['transactions','customers','employees',
                           'inventory','stock_movements','user_data','user_settings'] loop
    if to_regclass('public.'||t) is not null then
      execute format(
        'alter table public.%I add column if not exists company_id text not null default ''default''', t);
    end if;
  end loop;
end $$;

-- 2) Drop the old uniqueness (per-user) so the same id can exist per company --
--    Matches any unique/PK constraint OR unique index whose columns are exactly
--    the old key set, regardless of its name.
do $$
declare
  rec  record;
  p    text[];
  tbl  text;
  want text[];
  pairs text[] := array[
    array['transactions','id,user_id'],
    array['customers',   'id,user_id'],
    array['employees',   'id,user_id'],
    array['user_data',   'user_id'],
    array['user_settings','user_id']
  ];
begin
  foreach p slice 1 in array pairs loop
    tbl  := p[1];
    if to_regclass('public.'||tbl) is null then continue; end if;
    want := (select array_agg(x order by x) from unnest(string_to_array(p[2], ',')) x);

    -- 2a) constraints (unique or primary key)
    for rec in
      select c.conname
      from pg_constraint c
      where c.conrelid = ('public.'||tbl)::regclass
        and c.contype in ('u','p')
        and (select array_agg(a.attname order by a.attname)
             from unnest(c.conkey) k
             join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k) = want
    loop
      execute format('alter table public.%I drop constraint %I', tbl, rec.conname);
    end loop;

    -- 2b) standalone unique indexes
    for rec in
      select i.relname as idxname
      from pg_index ix
      join pg_class i on i.oid = ix.indexrelid
      where ix.indrelid = ('public.'||tbl)::regclass
        and ix.indisunique and not ix.indisprimary
        and (select array_agg(a.attname order by a.attname)
             from unnest(ix.indkey) k
             join pg_attribute a on a.attrelid = ix.indrelid and a.attnum = k) = want
    loop
      execute format('drop index if exists public.%I', rec.idxname);
    end loop;
  end loop;
end $$;

-- 3) New company-scoped uniqueness (matches the app's onConflict targets) -----
create unique index if not exists transactions_user_company_id_key
  on public.transactions (user_id, company_id, id);
create unique index if not exists customers_user_company_id_key
  on public.customers    (user_id, company_id, id);
create unique index if not exists employees_user_company_id_key
  on public.employees    (user_id, company_id, id);
create unique index if not exists user_data_user_company_key
  on public.user_data    (user_id, company_id);
create unique index if not exists user_settings_user_company_key
  on public.user_settings(user_id, company_id);

-- 4) Helpful (non-unique) indexes for company-scoped reads --------------------
create index if not exists inventory_company_idx       on public.inventory       (company_id);
create index if not exists stock_movements_company_idx on public.stock_movements (company_id);

-- ════════════════════════════════════════════════════════════════════════════
-- Done. RLS policies (which scope by user_id = auth.uid()) are unaffected —
-- company_id is an extra in-row filter, not a security boundary.
-- ════════════════════════════════════════════════════════════════════════════
