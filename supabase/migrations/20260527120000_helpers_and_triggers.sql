-- =============================================================================
-- 20260527120000_helpers_and_triggers.sql
-- =============================================================================
-- Foundational utilities every later migration depends on:
--   1. set_updated_at()         — trigger function that stamps updated_at on
--                                 every row mutation.
--   2. auto_enable_rls()        — event trigger that turns RLS on for any new
--                                 table in `public`. Belt + suspenders: even if
--                                 a future migration forgets `ALTER TABLE … ENABLE
--                                 ROW LEVEL SECURITY`, this safety net catches
--                                 it. CLAUDE.md mandates RLS on every table,
--                                 no exceptions.
--
-- Applied BEFORE the schema migration so tables are protected from the moment
-- they exist.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- pgcrypto for gen_random_uuid()
-- -----------------------------------------------------------------------------
create extension if not exists "pgcrypto";

-- -----------------------------------------------------------------------------
-- set_updated_at() — generic BEFORE UPDATE trigger
-- -----------------------------------------------------------------------------
create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

comment on function public.set_updated_at() is
  'BEFORE UPDATE trigger — refreshes updated_at on every row mutation. '
  'Sync engine relies on this column for last-write-wins conflict resolution.';

-- -----------------------------------------------------------------------------
-- auto_enable_rls() — event trigger fired on CREATE TABLE in `public`
-- -----------------------------------------------------------------------------
create or replace function public.auto_enable_rls()
returns event_trigger
language plpgsql
as $$
declare
  obj record;
begin
  for obj in
    select * from pg_event_trigger_ddl_commands()
    where command_tag = 'CREATE TABLE'
      and schema_name = 'public'
  loop
    execute format(
      'alter table %s enable row level security',
      obj.object_identity
    );
    -- Force RLS even for table owners — protects against superuser writes
    -- that would otherwise bypass policies.
    execute format(
      'alter table %s force row level security',
      obj.object_identity
    );
  end loop;
end;
$$;

comment on function public.auto_enable_rls() is
  'Event trigger that turns on (and forces) RLS for every new public table. '
  'Belt-and-suspenders: even if a developer forgets, RLS is never off.';

drop event trigger if exists trg_auto_enable_rls;
create event trigger trg_auto_enable_rls
  on ddl_command_end
  when tag in ('CREATE TABLE')
  execute function public.auto_enable_rls();
