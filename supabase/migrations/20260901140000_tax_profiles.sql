-- =============================================================================
-- 20260901140000_tax_profiles.sql
-- =============================================================================
-- The taxpayer's eight profile answers (1.3.0, Block 4).
--
-- WHY THIS TABLE EXISTS
-- The tax calendar is generated, not stored: profile × market catalog →
-- deadlines. This row is the entire input. Nothing else about the user's
-- finances reaches the generator, and no document, amount or line item is
-- involved in producing a calendar.
--
-- WHAT IT HOLDS, AND WHY THAT IS SENSITIVE
-- Legal form, whether they employ anyone, whether they own a vehicle or
-- property. None of it is special-category data under KVKK art. 6, but taken
-- together it is a fairly precise description of a person's business, so it
-- is owner-only, it cascades on account deletion, and the client wipes it at
-- sign-out rather than leaving it for the next account on the device.
--
-- WHY EVERY ANSWER IS A CONSTRAINED TEXT AND NOT AN ENUM TYPE
-- Postgres enums are painful to extend from a migration and worse to roll
-- back. A text column with a CHECK against a closed list gives the same
-- guarantee — the vocabulary cannot drift into free text — while staying
-- alterable. The lists mirror the Dart enums in
-- lib/core/market/tax/taxpayer_profile.dart one for one.
--
-- WHY EVERY ANSWER HAS AN "UNKNOWN" VALUE AND A DEFAULT
-- The wizard is skippable, on purpose: it is also the instrument that answers
-- D-2, and a form that will not advance without an answer measures only who
-- tolerates forms. An unanswered question has to be storable, and it has to
-- be distinguishable from "no" — "I have no staff" and "I did not say"
-- produce different calendars.
--
-- WHY UNIQUE (user_id) RATHER THAN (user_id, company_id)
-- company_id is NULL for every row in 1.3.0 (the company model lands in
-- 1.4.0), and Postgres treats NULLs as distinct, so a composite key would let
-- the same user insert an unlimited number of profiles. The 1.4.0 migration
-- that backfills company_id replaces this constraint with the composite one.
-- Until then this is both the correct invariant and the client's ON CONFLICT
-- target — a second device that filled the wizard offline has no shared `id`
-- to conflict on, so without a named unique constraint its push would either
-- duplicate the profile or fail forever.
--
-- Conventions match 20260901120000_product_events.sql.
-- =============================================================================

create table public.tax_profiles (
  id            uuid          primary key default gen_random_uuid(),
  user_id       uuid          not null references auth.users(id) on delete cascade,

  -- Nullable and FK-less until 1.4.0 ships the companies table — same
  -- reasoning as product_events.company_id.
  company_id    uuid          null,

  -- Q1 — legal form. Mirrors TaxpayerLegalForm and, deliberately, the
  -- telemetry dimension vocabulary: the D-2 measurement counts this answer,
  -- and two lists that could drift apart would corrupt it quietly.
  legal_form    text          not null default 'belirtilmedi'
                              constraint tax_profiles_legal_form_valid
                              check (legal_form in (
                                'sahis_sirketi', 'limited', 'anonim',
                                'serbest_meslek', 'basit_usul', 'diger',
                                'belirtilmedi'
                              )),

  -- Q2 — VAT liability. Carries the filing frequency, because that is what
  -- decides whether the KDV items recur monthly or quarterly.
  vat_liability text          not null default 'unknown'
                              constraint tax_profiles_vat_liability_valid
                              check (vat_liability in (
                                'monthly', 'quarterly', 'none', 'unknown'
                              )),

  -- Q3 — withholding liability, same shape as Q2.
  withholding_liability text  not null default 'unknown'
                              constraint tax_profiles_withholding_valid
                              check (withholding_liability in (
                                'monthly', 'quarterly', 'none', 'unknown'
                              )),

  -- Q4..Q8 — yes / no / unknown.
  employs_staff   text        not null default 'unknown'
                              constraint tax_profiles_employs_staff_valid
                              check (employs_staff in ('yes', 'no', 'unknown')),
  bagkur_insured  text        not null default 'unknown'
                              constraint tax_profiles_bagkur_valid
                              check (bagkur_insured in ('yes', 'no', 'unknown')),
  uses_e_ledger   text        not null default 'unknown'
                              constraint tax_profiles_e_ledger_valid
                              check (uses_e_ledger in ('yes', 'no', 'unknown')),
  owns_vehicle    text        not null default 'unknown'
                              constraint tax_profiles_vehicle_valid
                              check (owns_vehicle in ('yes', 'no', 'unknown')),
  owns_real_estate text       not null default 'unknown'
                              constraint tax_profiles_real_estate_valid
                              check (owns_real_estate in ('yes', 'no', 'unknown')),

  created_at    timestamptz   not null default timezone('utc', now()),
  updated_at    timestamptz   not null default timezone('utc', now()),

  -- One profile per user for 1.3.0. Also the client's ON CONFLICT target.
  constraint tax_profiles_one_per_user unique (user_id)
);

create trigger trg_tax_profiles_updated_at
  before update on public.tax_profiles
  for each row execute function public.set_updated_at();

comment on table public.tax_profiles is
  'The taxpayer profile the tax calendar is generated from: eight answers, '
  'each with an explicit "unknown" value because the wizard is skippable. '
  'One row per user in 1.3.0 (unique on user_id); the constraint becomes '
  '(user_id, company_id) when 1.4.0 backfills company_id. Owner-only.';

comment on column public.tax_profiles.company_id is
  'Nullable and FK-less until 1.4.0 ships the companies table. Carried now so '
  'the 1.4.0 backfill has a column to write into.';

comment on column public.tax_profiles.legal_form is
  'Mirrors TaxpayerLegalForm and the product_events dimension vocabulary. '
  'The D-2 measurement counts this answer, so the two lists must not drift.';

-- -----------------------------------------------------------------------------
-- RLS — enable + force (the auto_enable_rls() event trigger already does this;
-- repeated here so the migration is self-contained) plus the owner-only policy
-- set.
--
-- Scoped on user_id = auth.uid() for this release; the
-- is_company_member(company_id) form lands in 1.4.0 with the companies table,
-- following the transitional pattern in CLAUDE.md.
--
-- DELETE is granted: this is the user's own data and KVKK's erasure right has
-- to reach it without going through support.
-- -----------------------------------------------------------------------------
alter table public.tax_profiles enable row level security;
alter table public.tax_profiles force row level security;

create policy "tax_profiles_select_own"
  on public.tax_profiles for select
  using (auth.uid() = user_id);
create policy "tax_profiles_insert_own"
  on public.tax_profiles for insert
  with check (auth.uid() = user_id);
create policy "tax_profiles_update_own"
  on public.tax_profiles for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "tax_profiles_delete_own"
  on public.tax_profiles for delete
  using (auth.uid() = user_id);
