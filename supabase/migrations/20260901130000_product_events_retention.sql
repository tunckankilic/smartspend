-- =============================================================================
-- 20260901130000_product_events_retention.sql
-- =============================================================================
-- Retention and anonymisation for product telemetry.
--
-- WHY
-- The previous migration created `product_events` with no retention at all.
-- Rows carrying user_id and device_id would have sat there forever, which
-- KVKK does not permit: personal data may be kept only for as long as the
-- purpose requires (art. 4/2-d), and the purpose here — answering D-2 and
-- watching the scan → save conversion — is measured in weeks, not years.
--
-- THE TWO-LAYER SHAPE
-- 1. Identified rows live 90 days. Long enough to cover a release cycle and
--    to still be able to answer an access request about a recent period;
--    short enough that no identified counter outlives its usefulness.
-- 2. Before deletion they are rolled up into `product_event_daily`, which
--    carries no user_id and no device_id. That table is genuinely anonymous
--    and can be kept indefinitely, so long-term product analytics costs no
--    long-term personal data.
--
-- THE k-THRESHOLD
-- Aggregation alone does not make data anonymous. On a small user base a row
-- like (day, dimension = 'anonim', count = 1) points at one person, and a
-- re-identifiable aggregate is still personal data. So a day/event/dimension
-- combination is only carried across when at least `k` distinct users
-- contributed to it; below the threshold it is dropped rather than kept.
-- Losing a thin statistic is the cheaper mistake.
--
-- SCHEDULING IS AN OPS STEP, NOT A MIGRATION
-- The DO block at the bottom schedules the job only if pg_cron is already
-- installed. On a fresh Supabase project it is not — it is enabled from the
-- dashboard (Database → Extensions), and this migration deliberately does not
-- try to install it: a migration that fails on a missing superuser-only
-- extension would block every later deploy. After enabling pg_cron, run the
-- statement in the block by hand once. Until then `roll_up_product_events()`
-- exists and is callable, but nothing calls it — see the ops note in
-- docs/internal.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- The anonymous long-term table
-- -----------------------------------------------------------------------------
create table public.product_event_daily (
  event_key     text          not null,
  dimension     text          not null,
  day           date          not null,

  -- Sum across every device and every user that contributed that day.
  total_count   bigint        not null,

  -- How many distinct users are behind `total_count`. Kept so the k-threshold
  -- that let the row through stays auditable, and so a later analysis can tell
  -- "20 scans by 20 people" from "20 scans by one person".
  user_count    integer       not null,

  rolled_up_at  timestamptz   not null default timezone('utc', now()),

  primary key (event_key, dimension, day)
);

comment on table public.product_event_daily is
  'Anonymous daily roll-up of product_events. Carries no user_id and no '
  'device_id, and only holds combinations with at least k distinct '
  'contributing users, so it is not re-identifiable and needs no retention '
  'limit. Written solely by roll_up_product_events(); clients have no access.';

-- RLS on, zero policies — same posture as `rate_limits`. No client, on any
-- role, has any business reading or writing this table; only the SECURITY
-- DEFINER function below touches it.
alter table public.product_event_daily enable row level security;

-- -----------------------------------------------------------------------------
-- roll_up_product_events()
-- -----------------------------------------------------------------------------
create or replace function public.roll_up_product_events(
  p_retention_days integer default 90,
  p_min_users      integer default 5
)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cutoff  date;
  v_deleted integer;
begin
  if p_retention_days < 1 then
    raise exception 'retention must be at least one day, got %', p_retention_days;
  end if;

  v_cutoff := (timezone('utc', now()))::date - p_retention_days;

  -- Carry the combinations that clear the k-threshold into the anonymous
  -- table. Re-running is safe: the upsert recomputes rather than accumulates,
  -- so a job that runs twice on the same day does not double the totals.
  insert into public.product_event_daily as d
    (event_key, dimension, day, total_count, user_count, rolled_up_at)
  select
    e.event_key,
    e.dimension,
    e.day,
    sum(e.count)::bigint,
    count(distinct e.user_id)::integer,
    timezone('utc', now())
  from public.product_events e
  where e.day < v_cutoff
  group by e.event_key, e.dimension, e.day
  having count(distinct e.user_id) >= p_min_users
  on conflict (event_key, dimension, day) do update
    set total_count  = excluded.total_count,
        user_count   = excluded.user_count,
        rolled_up_at = excluded.rolled_up_at;

  -- Everything past the window goes, including the combinations that did not
  -- clear the threshold. Deleting a statistic we may not keep is the point,
  -- not a side effect.
  delete from public.product_events where day < v_cutoff;
  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

comment on function public.roll_up_product_events(integer, integer) is
  'Rolls product_events older than p_retention_days into the anonymous '
  'product_event_daily table (only combinations with >= p_min_users distinct '
  'users) and deletes the identified source rows. Idempotent. Intended to run '
  'monthly via pg_cron.';

-- Clients never call this; only the scheduler does.
revoke all on function public.roll_up_product_events(integer, integer)
  from public, anon, authenticated;

-- -----------------------------------------------------------------------------
-- Scheduling — only if pg_cron is already present
-- -----------------------------------------------------------------------------
do $$
begin
  if exists (
    select 1 from pg_extension where extname = 'pg_cron'
  ) then
    perform cron.schedule(
      'roll-up-product-events',
      '0 3 1 * *',
      $cron$ select public.roll_up_product_events(); $cron$
    );
  else
    raise notice
      'pg_cron not installed — roll_up_product_events() will not run on a '
      'schedule until it is enabled and cron.schedule() is called once.';
  end if;
end
$$;
