-- =============================================================================
-- 20260901160000_tax_calendar_overrides.sql
-- =============================================================================
-- The channel a GİB filing extension reaches installed clients through
-- (1.3.0, Block 4, T10).
--
-- WHY THIS TABLE EXISTS AT ALL
-- The deadline rules live in the client binary (lib/core/market/tax/
-- tr_tax_catalog.dart). GİB moves deadlines by circular, sometimes days before
-- one falls due, and an app store review takes longer than that. Without a
-- server-side channel the only honest options are shipping a build in 48 hours
-- or showing a date we know to be wrong.
--
-- 🚨 WHY IT CARRIES NO user_id AND NO company_id
-- This is the one table in the tax feature that is not the user's data. A
-- filing extension is a fact about the tax authority's calendar, identical for
-- every taxpayer it applies to. Giving it a user_id would mean writing one row
-- per user for a fact none of them authored, and it would drag the table into
-- SyncService — whose push path is per-user and would then try to upload rows
-- the client must never write. It is deliberately outside the
-- `remote_id/user_id/company_id/updated_at/sync_status` convention, and the
-- client reads it through its own narrow datasource rather than through
-- SyncRemoteDataSource. See lib/core/services/tax_override_remote_data_source.dart.
--
-- 🚨 WHY CLIENTS CAN READ IT BUT NOT WRITE IT
-- auto_enable_rls() (20260527120000) enables AND FORCES row level security on
-- every table created in `public`. Forced RLS with no policy is not an error
-- for the caller — it is an empty result set. A channel that silently returns
-- nothing is worse than no channel, because it looks like it works. Hence the
-- explicit `using (true)` SELECT policy below, and a pgTAP assertion that an
-- actual authenticated role sees an actual row: `policies_are` alone would
-- pass on a policy that is present and wrong.
--
-- There are deliberately NO insert/update/delete policies. Rows arrive by
-- migration or from the service role (which carries BYPASSRLS); no client
-- session can author a deadline.
--
-- WHY WITHDRAWAL IS A DELETE
-- The client replaces its whole local copy with what this table returns, so
-- deleting a row here retracts the override everywhere on the next pull. That
-- only works because the client applies overrides while generating rather than
-- writing them into the calendar (D-17): a date written into tax_obligations
-- and then protected from regeneration could never be taken back.
-- =============================================================================

create table public.tax_calendar_overrides (
  id            uuid          primary key default gen_random_uuid(),

  -- ISO-3166-1 alpha-2, uppercase. An override is scoped to the catalog it
  -- corrects; the client filters on its active market and ignores the rest.
  market        text          not null
                              constraint tax_calendar_overrides_market_shape
                              check (market ~ '^[A-Z]{2}$'),

  -- A TaxObligationKind wire value, mirrored from
  -- lib/core/market/tax/tax_obligation_kind.dart. 'custom' is excluded on
  -- purpose: those items are the user's own and no authority has an opinion
  -- about when they are due.
  kind          text          not null
                              constraint tax_calendar_overrides_kind_valid
                              check (kind in (
                                'kdv1', 'kdv2', 'mphb', 'sgk4a', 'bagkur',
                                'gecici', 'yillik_gv', 'kurumlar', 'damga',
                                'basit_usul', 'edefter_berat', 'babs', 'mtv',
                                'emlak'
                              )),

  -- First day of the period the override applies to. Together with kind and
  -- installment_index this addresses exactly one generated item, and matches
  -- the client's generation_key (`kind|period_start|installment`) without the
  -- server having to build that opaque string.
  period_start  date          not null,

  installment_index integer   not null default 0
                              constraint tax_calendar_overrides_installment_range
                              check (installment_index between 0 and 12),

  -- NULL means "this deadline is not overridden", NOT "this deadline is
  -- removed". An extension moves a date; it never deletes an obligation, and
  -- letting this column express deletion would make a typo capable of hiding
  -- a real deadline from every user at once.
  declaration_due_date date   null,
  payment_due_date     date   null,

  constraint tax_calendar_overrides_changes_something
    check (declaration_due_date is not null or payment_due_date is not null),

  -- Required, and not decoration: it is shown to the user next to the date and
  -- it is the only thing that distinguishes this from a number somebody typed.
  -- e.g. 'VUK Sirküleri No: 175'.
  reason        text          not null
                              constraint tax_calendar_overrides_reason_shape
                              check (char_length(reason) between 1 and 300),

  -- Where the reason can be read in full. NULL while the circular has no
  -- stable public URL.
  source_url    text          null
                              constraint tax_calendar_overrides_source_url_length
                              check (source_url is null
                                     or char_length(source_url) <= 500),

  created_at    timestamptz   not null default timezone('utc', now()),
  updated_at    timestamptz   not null default timezone('utc', now()),

  -- One override per addressable item. A second row for the same deadline
  -- would make which date wins depend on row order.
  constraint tax_calendar_overrides_identity_key
    unique (market, kind, period_start, installment_index)
);

create trigger trg_tax_calendar_overrides_updated_at
  before update on public.tax_calendar_overrides
  for each row execute function public.set_updated_at();

comment on table public.tax_calendar_overrides is
  'Server-side corrections to the client''s built-in tax deadline catalog — '
  'the channel a GİB filing extension reaches installed apps through. Global '
  'and read-only to clients: no user_id, no company_id, not part of '
  'SyncService. Deleting a row retracts the override on the next pull.';

comment on column public.tax_calendar_overrides.declaration_due_date is
  'NULL means this deadline is not overridden — never that it is removed. An '
  'override moves a date; it cannot hide an obligation.';

comment on column public.tax_calendar_overrides.reason is
  'Shown to the user beside the date. An override with no stated source is '
  'indistinguishable from a guess, so the column is NOT NULL.';

-- -----------------------------------------------------------------------------
-- RLS — everyone reads, nobody writes.
--
-- Redundant with auto_enable_rls(), and written anyway: this table's whole
-- failure mode is RLS being on with no policy, and a reader of this file
-- should see the posture without having to know about an event trigger three
-- migrations back.
-- -----------------------------------------------------------------------------
alter table public.tax_calendar_overrides enable row level security;
alter table public.tax_calendar_overrides force row level security;

-- Signed-out clients generate a calendar too — the tax feature does not
-- require an account — so `anon` is included deliberately. Nothing here is
-- personal data; it is published regulatory fact.
create policy "tax_calendar_overrides_select_all"
  on public.tax_calendar_overrides for select
  to anon, authenticated
  using (true);
