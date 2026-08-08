create or replace function public.internal_user_id_by_email(p_email text)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select id from auth.users where lower(email) = lower(trim(p_email)) limit 1
$$;

revoke all on function public.internal_user_id_by_email(text) from public, anon, authenticated;
grant execute on function public.internal_user_id_by_email(text) to service_role;

grant execute on function public.consume_verification_rate_limit(text,text,int,int) to service_role;
