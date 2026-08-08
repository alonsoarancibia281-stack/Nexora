-- Owner-only administrative functions. Client access is mediated by SECURITY DEFINER functions
-- that verify the authenticated caller is the immutable owner.

create or replace function public.admin_dashboard_metrics()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if not public.is_owner() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  select jsonb_build_object(
    'total_users', (select count(*) from public.profiles),
    'verified_users', (select count(*) from public.profiles where email_verified),
    'suspended_users', (select count(*) from public.profiles where suspended_at is not null),
    'active_subscriptions', (select count(*) from public.subscriptions where status = 'active'),
    'support_tickets', 0,
    'feature_flags_enabled', (select count(*) from public.feature_flags where enabled),
    'audit_events_24h', (select count(*) from public.audit_logs where created_at >= now() - interval '24 hours')
  ) into result;
  return result;
end;
$$;

create or replace function public.admin_list_users(p_query text default '', p_limit int default 50)
returns table(
  user_id uuid,
  first_name text,
  last_name text,
  email_verified boolean,
  country text,
  experience text,
  suspended_at timestamptz,
  role public.app_role,
  plan public.plan_code,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_owner() then
    raise exception 'forbidden' using errcode = '42501';
  end if;

  return query
  select p.id, p.first_name, p.last_name, p.email_verified, p.country, p.experience,
         p.suspended_at, r.role,
         coalesce((select s.plan_code from public.subscriptions s where s.user_id=p.id and s.status='active' order by s.starts_at desc limit 1), 'free'::public.plan_code),
         p.created_at
  from public.profiles p
  join public.user_roles r on r.user_id = p.id
  where p_query = ''
     or p.first_name ilike '%' || p_query || '%'
     or p.last_name ilike '%' || p_query || '%'
     or p.id::text = p_query
  order by p.created_at desc
  limit least(greatest(p_limit, 1), 100);
end;
$$;

create or replace function public.admin_set_user_suspension(p_user_id uuid, p_suspended boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare target_role public.app_role;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode='42501'; end if;
  select role into target_role from public.user_roles where user_id=p_user_id;
  if target_role = 'owner' then raise exception 'owner_protected' using errcode='42501'; end if;
  update public.profiles set suspended_at = case when p_suspended then now() else null end, updated_at=now() where id=p_user_id;
  insert into public.audit_logs(actor_id,action,target_user_id,metadata)
  values(auth.uid(),case when p_suspended then 'user_suspended' else 'user_unsuspended' end,p_user_id,'{}'::jsonb);
end;
$$;

create or replace function public.admin_set_user_plan(p_user_id uuid, p_plan public.plan_code)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare target_role public.app_role;
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode='42501'; end if;
  select role into target_role from public.user_roles where user_id=p_user_id;
  if target_role = 'owner' or p_plan = 'owner' then raise exception 'owner_protected' using errcode='42501'; end if;
  update public.subscriptions set status='replaced', ends_at=now() where user_id=p_user_id and status='active';
  insert into public.subscriptions(user_id,plan_code,status) values(p_user_id,p_plan,'active');
  insert into public.audit_logs(actor_id,action,target_user_id,metadata)
  values(auth.uid(),'plan_changed',p_user_id,jsonb_build_object('plan',p_plan));
end;
$$;

create or replace function public.admin_set_feature_flag(p_key text, p_enabled boolean)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode='42501'; end if;
  insert into public.feature_flags(key,enabled,updated_at) values(p_key,p_enabled,now())
  on conflict(key) do update set enabled=excluded.enabled, updated_at=now();
  insert into public.audit_logs(actor_id,action,metadata)
  values(auth.uid(),'feature_flag_changed',jsonb_build_object('key',p_key,'enabled',p_enabled));
end;
$$;

create or replace function public.admin_list_feature_flags()
returns setof public.feature_flags
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_owner() then raise exception 'forbidden' using errcode='42501'; end if;
  return query select * from public.feature_flags order by key;
end;
$$;

grant execute on function public.admin_dashboard_metrics() to authenticated;
grant execute on function public.admin_list_users(text,int) to authenticated;
grant execute on function public.admin_set_user_suspension(uuid,boolean) to authenticated;
grant execute on function public.admin_set_user_plan(uuid,public.plan_code) to authenticated;
grant execute on function public.admin_set_feature_flag(text,boolean) to authenticated;
grant execute on function public.admin_list_feature_flags() to authenticated;
