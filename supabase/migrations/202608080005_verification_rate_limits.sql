create table if not exists public.verification_rate_limits (
  id bigint generated always as identity primary key,
  scope text not null,
  subject_hash text not null,
  created_at timestamptz not null default now()
);

create index if not exists verification_rate_limits_lookup_idx
  on public.verification_rate_limits(scope, subject_hash, created_at desc);

alter table public.verification_rate_limits enable row level security;
-- Deliberately no client policies. Service-role Edge Functions only.

create or replace function public.consume_verification_rate_limit(
  p_scope text,
  p_subject_hash text,
  p_window_seconds int,
  p_max_requests int
) returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  recent_count int;
begin
  delete from public.verification_rate_limits
  where created_at < now() - interval '24 hours';

  select count(*) into recent_count
  from public.verification_rate_limits
  where scope = p_scope
    and subject_hash = p_subject_hash
    and created_at >= now() - make_interval(secs => p_window_seconds);

  if recent_count >= p_max_requests then
    return false;
  end if;

  insert into public.verification_rate_limits(scope, subject_hash)
  values(p_scope, p_subject_hash);
  return true;
end;
$$;

revoke all on function public.consume_verification_rate_limit(text,text,int,int) from public, anon, authenticated;
