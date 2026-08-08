insert into public.plan_features values
('free','backtesting','false'),('free','reports','false'),('free','admin','false'),
('essential','backtesting','false'),('essential','reports','false'),('essential','admin','false'),
('pro','backtesting','false'),('pro','reports','true'),('pro','admin','false'),
('elite','backtesting','true'),('elite','reports','true'),('elite','admin','false'),
('owner','backtesting','true'),('owner','reports','true')
on conflict (plan_code,feature_key) do update set value=excluded.value;

create or replace function public.my_entitlements() returns jsonb
language sql stable security definer set search_path=''
as $$
  with role_cte as (
    select role::text as role_name from public.user_roles where user_id=auth.uid()
  ), plan_cte as (
    select plan_code::text as plan_name
    from public.subscriptions
    where user_id=auth.uid() and status='active'
    order by starts_at desc limit 1
  ), feature_cte as (
    select pf.feature_key, pf.value
    from public.plan_features pf
    join plan_cte pc on pf.plan_code::text=pc.plan_name
  )
  select jsonb_build_object(
    'role', coalesce((select role_name from role_cte),'user'),
    'plan', coalesce((select plan_name from plan_cte),'free'),
    'daily_analyses', coalesce((select (value#>>'{}')::int from feature_cte where feature_key='daily_analyses'),0),
    'active_alerts', coalesce((select (value#>>'{}')::int from feature_cte where feature_key='active_alerts'),0),
    'ai', coalesce((select (value#>>'{}')::boolean from feature_cte where feature_key='ai'),false),
    'backtesting', coalesce((select (value#>>'{}')::boolean from feature_cte where feature_key='backtesting'),false),
    'reports', coalesce((select (value#>>'{}')::boolean from feature_cte where feature_key='reports'),false),
    'admin', coalesce((select (value#>>'{}')::boolean from feature_cte where feature_key='admin'),false) or coalesce((select role_name in ('admin','owner') from role_cte),false)
  );
$$;
grant execute on function public.my_entitlements() to authenticated;

create or replace function public.protect_owner_role() returns trigger
language plpgsql security definer set search_path=''
as $$
begin
  if old.role='owner' and new.role<>'owner' then
    raise exception 'owner role cannot be downgraded';
  end if;
  return new;
end;
$$;
create trigger protect_owner_role_before_update before update on public.user_roles for each row execute function public.protect_owner_role();

create or replace function public.protect_owner_subscription() returns trigger
language plpgsql security definer set search_path=''
as $$
begin
  if old.plan_code='owner' and (new.plan_code<>'owner' or new.status<>'active') then
    raise exception 'owner subscription cannot be downgraded';
  end if;
  return new;
end;
$$;
create trigger protect_owner_subscription_before_update before update on public.subscriptions for each row execute function public.protect_owner_subscription();
