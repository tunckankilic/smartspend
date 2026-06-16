-- =============================================================================
-- 20260527120004_rate_limit_function.sql
-- =============================================================================
-- consume_token(user_id, bucket, max_tokens, refill_per_hour) → boolean
--
-- Token bucket implemented in Postgres so Edge Functions don't need a
-- separate Redis. Returns TRUE when a token was consumed, FALSE when the
-- bucket is empty.
--
-- Usage from `gemini-ocr-fallback`:
--     const { data, error } = await supabase.rpc('consume_token', {
--       p_user_id: user.id,
--       p_bucket: 'gemini-ocr',
--       p_max_tokens: 20,
--       p_refill_per_hour: 1,
--     });
--     if (!data) return new Response('rate limited', { status: 429 });
--
-- Runs SECURITY DEFINER because RLS on `rate_limits` denies all client
-- writes. The function owner (typically `postgres`) bypasses RLS by design.
-- =============================================================================

create or replace function public.consume_token(
  p_user_id            uuid,
  p_bucket             text,
  p_max_tokens         integer,
  p_refill_per_hour    integer
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_now            timestamptz := timezone('utc', now());
  v_tokens         integer;
  v_refilled_at    timestamptz;
  v_elapsed_hours  numeric;
  v_to_refill      integer;
begin
  -- Defensive: avoid silently rate-limiting nobody.
  if p_user_id is null then
    raise exception 'consume_token called with null user_id';
  end if;
  if p_max_tokens <= 0 or p_refill_per_hour <= 0 then
    raise exception 'consume_token: max_tokens and refill_per_hour must be > 0';
  end if;

  -- Ensure a row exists (full bucket on first call).
  insert into public.rate_limits as rl (user_id, bucket, tokens, refilled_at)
  values (p_user_id, p_bucket, p_max_tokens, v_now)
  on conflict (user_id, bucket) do nothing;

  -- Lock and read current state.
  select tokens, refilled_at
    into v_tokens, v_refilled_at
  from public.rate_limits
  where user_id = p_user_id and bucket = p_bucket
  for update;

  -- Refill based on elapsed time.
  v_elapsed_hours := extract(epoch from (v_now - v_refilled_at)) / 3600.0;
  v_to_refill := floor(v_elapsed_hours * p_refill_per_hour)::integer;
  if v_to_refill > 0 then
    v_tokens := least(p_max_tokens, v_tokens + v_to_refill);
    v_refilled_at := v_now;
  end if;

  -- Empty bucket → reject without decrementing.
  if v_tokens <= 0 then
    update public.rate_limits
       set tokens = v_tokens,
           refilled_at = v_refilled_at
     where user_id = p_user_id and bucket = p_bucket;
    return false;
  end if;

  -- Consume one token.
  update public.rate_limits
     set tokens = v_tokens - 1,
         refilled_at = v_refilled_at
   where user_id = p_user_id and bucket = p_bucket;
  return true;
end;
$$;

comment on function public.consume_token(uuid, text, integer, integer) is
  'Atomic token-bucket consume for rate limiting. SECURITY DEFINER so it can '
  'bypass RLS on public.rate_limits. Edge Functions call this via RPC; '
  'clients should never invoke it directly.';

-- Edge Functions invoke via the authenticator role; service_role bypasses RLS
-- automatically. Grant explicit execute so signed-in users (via PostgREST RPC
-- from an Edge Function impersonating them) can call it.
grant execute on function public.consume_token(uuid, text, integer, integer)
  to authenticated, service_role;
