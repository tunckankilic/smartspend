-- =============================================================================
-- 20260901150000_tax_obligations.sql
-- =============================================================================
-- Generated calendar items and the user's marks on them (1.3.0, Block 4).
--
-- WHY TWO DUE DATES AND NOT ONE
-- Filing and payment are separate deadlines, and in the Turkish catalog they
-- often differ. Several obligations have only one of them: Bağ-Kur premiums
-- are assessed and never declared; Form Ba/Bs and the e-ledger berat are
-- declared and never paid. Collapsing them into a single "due date" would
-- make roughly a third of the calendar say something untrue.
--
-- Both are NULLABLE, and that is not laxness. The catalog ships with every
-- deadline rule unconfirmed (see lib/core/market/tax/tr_tax_catalog.dart): an
-- item whose rule has not been verified against GİB has no date, and the app
-- says so instead of showing a plausible guess.
--
-- WHY TWO TIMESTAMPS
-- declared_at and paid_at are separate acts, usually days apart. "I filed it"
-- must not mark it paid.
--
-- 🚨 WHY THERE IS NO `overdue` COLUMN
-- Because it is a function of a due date and the current time, both already
-- present. Stored, it would be computed by whichever device happened to write
-- last — including one with a wrong clock or one that had not synced for a
-- week — and last-write-wins would then propagate that verdict to every other
-- device. The user would be told they missed a deadline they did not miss.
-- Derived state stays derived; a client test pins the column's absence and so
-- does the assertion in supabase/tests/rls_test.sql.
--
-- 🚨 WHY `amount_source` HAS NO `computed` VALUE
-- SmartSpend does not calculate tax. There is no line-item VAT breakdown
-- before 1.6.0, no knowledge of the user's deductions, and no licence to
-- practise accountancy — and a number this app produced would be read as an
-- amount to pay. Every amount here was typed by a person, the accountant or
-- the user. The CHECK is what makes "the app worked it out" unrepresentable
-- rather than merely discouraged, and a pgTAP assertion pins it.
--
-- WHY generation_key EXISTS
-- Generation is deterministic: the same profile and catalog produce the same
-- items on every device. Without a shared identity, a phone and a tablet that
-- both generated August's VAT return would push two rows and the user would
-- see the same deadline twice. UNIQUE (user_id, generation_key) is that
-- identity, and it is the client's ON CONFLICT target — a locally generated
-- row has no server id to conflict on.
--
-- Conventions match 20260901140000_tax_profiles.sql.
-- =============================================================================

create table public.tax_obligations (
  id            uuid          primary key default gen_random_uuid(),
  user_id       uuid          not null references auth.users(id) on delete cascade,

  -- Nullable and FK-less until 1.4.0 ships the companies table.
  company_id    uuid          null,

  -- `kind|period_start|installment` for generated rows, a random id for
  -- user-created ones. Length-capped; it is an identity, not a note.
  generation_key text         not null
                              constraint tax_obligations_generation_key_shape
                              check (char_length(generation_key) between 1 and 128),

  -- A TaxObligationKind wire value. Closed vocabulary, mirrored from
  -- lib/core/market/tax/tax_obligation_kind.dart.
  kind          text          not null
                              constraint tax_obligations_kind_valid
                              check (kind in (
                                'kdv1', 'kdv2', 'mphb', 'sgk4a', 'bagkur',
                                'gecici', 'yillik_gv', 'kurumlar', 'damga',
                                'basit_usul', 'edefter_berat', 'babs', 'mtv',
                                'emlak', 'custom'
                              )),

  period_kind   text          not null
                              constraint tax_obligations_period_kind_valid
                              check (period_kind in (
                                'monthly', 'quarterly', 'annual', 'one_off'
                              )),

  period_start  date          not null,
  period_end    date          not null
                              constraint tax_obligations_period_ordered
                              check (period_end >= period_start),

  -- 0 for a single payment; 1, 2, … for an obligation paid in installments.
  installment_index integer   not null default 0
                              constraint tax_obligations_installment_range
                              check (installment_index between 0 and 12),

  -- Nullable: no filing step, or no confirmed rule yet. See the header.
  declaration_due_date date   null,
  payment_due_date     date   null,

  due_date_source text        not null default 'catalog'
                              constraint tax_obligations_due_source_valid
                              check (due_date_source in (
                                'catalog', 'override', 'user'
                              )),

  -- Smallest currency unit (kuruş). Never a float, and never written by the
  -- app itself.
  amount_minor  bigint        null
                              constraint tax_obligations_amount_nonneg
                              check (amount_minor is null or amount_minor >= 0),

  -- No 'computed'. See the header.
  amount_source text          not null default 'unknown'
                              constraint tax_obligations_amount_source_valid
                              check (amount_source in (
                                'accountant', 'user', 'unknown'
                              )),

  declared_at   timestamptz   null,
  paid_at       timestamptz   null,
  dismissed_at  timestamptz   null,

  note          text          null
                              constraint tax_obligations_note_length
                              check (note is null or char_length(note) <= 2000),

  title         text          null
                              constraint tax_obligations_title_length
                              check (title is null or char_length(title) <= 200),

  is_user_defined boolean     not null default false,

  created_at    timestamptz   not null default timezone('utc', now()),
  updated_at    timestamptz   not null default timezone('utc', now()),

  -- The ON CONFLICT target for a device pushing an item it generated itself.
  constraint tax_obligations_identity_key unique (user_id, generation_key)
);

-- The calendar screen's query: this user, ordered by when things are due.
create index tax_obligations_user_period_idx
  on public.tax_obligations(user_id, period_start);

create trigger trg_tax_obligations_updated_at
  before update on public.tax_obligations
  for each row execute function public.set_updated_at();

comment on table public.tax_obligations is
  'One instance of one tax obligation. Filing and payment are separate '
  'deadlines and separate timestamps; several obligations have only one of '
  'the two. No overdue column — it is derived from the due date and the '
  'current time, and a stored verdict from a device with a wrong clock would '
  'propagate under last-write-wins.';

comment on column public.tax_obligations.generation_key is
  'Stable identity of the item within the user''s calendar. Two devices '
  'generating the same calendar produce the same key, which is what stops '
  'the same deadline appearing twice.';

comment on column public.tax_obligations.amount_source is
  'accountant | user | unknown. Deliberately no "computed": SmartSpend does '
  'not calculate tax, and a number it produced would be read as an amount to '
  'pay.';

comment on column public.tax_obligations.declaration_due_date is
  'NULL where the obligation has no filing step, and also where the catalog '
  'rule is not confirmed against GİB yet. Showing nothing beats showing a '
  'guess.';

-- -----------------------------------------------------------------------------
-- RLS — owner-only, same posture as tax_profiles. DELETE is granted: a
-- user-created item is theirs to remove, and KVKK erasure has to reach these
-- rows without going through support.
-- -----------------------------------------------------------------------------
alter table public.tax_obligations enable row level security;
alter table public.tax_obligations force row level security;

create policy "tax_obligations_select_own"
  on public.tax_obligations for select
  using (auth.uid() = user_id);
create policy "tax_obligations_insert_own"
  on public.tax_obligations for insert
  with check (auth.uid() = user_id);
create policy "tax_obligations_update_own"
  on public.tax_obligations for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
create policy "tax_obligations_delete_own"
  on public.tax_obligations for delete
  using (auth.uid() = user_id);
