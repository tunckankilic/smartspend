-- =============================================================================
-- 20260630120000_apple_credentials.sql
-- =============================================================================
-- Stores each user's "Sign in with Apple" refresh token so the delete-account
-- Edge Function can revoke the Apple grant when the account is deleted —
-- required by App Store Review Guideline 5.1.1(v) for apps offering Sign in
-- with Apple.
--
-- Trust model:
--   • Written ONLY by the apple-register Edge Function (service_role), after it
--     exchanges the native authorizationCode for a refresh token.
--   • Read ONLY by the delete-account Edge Function (service_role) at deletion.
--   • The client NEVER touches this table. RLS is enabled + forced (via the
--     trg_auto_enable_rls event trigger) with NO policies, so every
--     non-privileged role is denied; service_role bypasses RLS.
--   • The row is removed automatically when the user is deleted (FK cascade).
-- =============================================================================

create table if not exists public.apple_credentials (
  user_id       uuid primary key
                  references auth.users (id) on delete cascade,
  refresh_token text        not null,
  created_at    timestamptz not null default timezone('utc', now()),
  updated_at    timestamptz not null default timezone('utc', now())
);

-- RLS is enabled + forced automatically by trg_auto_enable_rls; assert it
-- explicitly too so the migration is self-contained and intent is obvious.
alter table public.apple_credentials enable row level security;

-- Intentionally NO policies: service_role (bypassrls) is the only caller.

-- Refresh updated_at on every mutation (token is re-stored on each sign-in).
drop trigger if exists set_apple_credentials_updated_at
  on public.apple_credentials;
create trigger set_apple_credentials_updated_at
  before update on public.apple_credentials
  for each row execute function public.set_updated_at();

comment on table public.apple_credentials is
  'Apple Sign in refresh tokens, used to revoke the Apple grant on account '
  'deletion (Guideline 5.1.1(v)). Service-role only; RLS-locked, no policies.';
