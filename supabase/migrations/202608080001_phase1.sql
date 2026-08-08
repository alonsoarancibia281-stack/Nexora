create extension if not exists pgcrypto;
create type public.app_role as enum ('user','support','analyst','admin','owner');
create type public.plan_code as enum ('free','essential','pro','elite','owner');

create table public.profiles (id uuid primary key references auth.users(id) on delete cascade,first_name text not null,last_name text not null,country text not null,experience text not null check(experience in ('Principiante','Intermedio','Avanzado')),email_verified boolean not null default false,suspended_at timestamptz,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.user_roles (user_id uuid primary key references auth.users(id) on delete cascade,role public.app_role not null default 'user',updated_at timestamptz not null default now());
create table public.subscription_plans (code public.plan_code primary key,name text not null,monthly_usd numeric(10,2) not null,active boolean not null default true);
create table public.subscriptions (id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,plan_code public.plan_code not null references public.subscription_plans(code),status text not null default 'active',starts_at timestamptz not null default now(),ends_at timestamptz,created_at timestamptz not null default now());
create table public.plan_features (plan_code public.plan_code references public.subscription_plans(code) on delete cascade,feature_key text not null,value jsonb not null,primary key(plan_code,feature_key));
create table public.verification_codes (id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,code_hash text not null,expires_at timestamptz not null,used_at timestamptz,attempts int not null default 0 check(attempts between 0 and 5),blocked_until timestamptz,created_at timestamptz not null default now());
create index verification_codes_user_created_idx on public.verification_codes(user_id,created_at desc);
create table public.user_consents (id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,terms_version text not null,privacy_version text not null,marketing boolean not null default false,country text,ip_hash text,accepted_at timestamptz not null default now());
create table public.audit_logs (id bigint generated always as identity primary key,actor_id uuid references auth.users(id),action text not null,target_user_id uuid references auth.users(id),metadata jsonb not null default '{}'::jsonb,created_at timestamptz not null default now());
create table public.feature_flags (key text primary key,enabled boolean not null default false,description text,updated_at timestamptz not null default now());
create table public.user_devices (id uuid primary key default gen_random_uuid(),user_id uuid not null references auth.users(id) on delete cascade,device_hash text not null,platform text,last_seen_at timestamptz not null default now(),revoked_at timestamptz,unique(user_id,device_hash));

insert into public.subscription_plans values ('free','Free',0,true),('essential','Essential',9.99,true),('pro','Pro Trader',29.99,true),('elite','Elite AI',79.99,true),('owner','Owner',0,true);
insert into public.plan_features values ('free','daily_analyses','3'),('free','active_alerts','1'),('free','ai','false'),('essential','daily_analyses','25'),('essential','active_alerts','20'),('essential','ai','false'),('pro','daily_analyses','100'),('pro','active_alerts','-1'),('pro','ai','true'),('elite','daily_analyses','-1'),('elite','active_alerts','-1'),('elite','ai','true'),('owner','daily_analyses','-1'),('owner','active_alerts','-1'),('owner','ai','true'),('owner','admin','true');

create or replace function public.is_owner() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.user_roles where user_id=auth.uid() and role='owner')$$;
create or replace function public.is_admin() returns boolean language sql stable security definer set search_path='' as $$select exists(select 1 from public.user_roles where user_id=auth.uid() and role in ('admin','owner'))$$;

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$begin insert into public.profiles(id,first_name,last_name,country,experience) values(new.id,coalesce(new.raw_user_meta_data->>'first_name',''),coalesce(new.raw_user_meta_data->>'last_name',''),coalesce(new.raw_user_meta_data->>'country',''),coalesce(new.raw_user_meta_data->>'experience','Principiante'));insert into public.user_roles(user_id,role) values(new.id,'user');insert into public.subscriptions(user_id,plan_code) values(new.id,'free');return new;end$$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.assign_owner(p_user_id uuid) returns void language plpgsql security definer set search_path='' as $$begin update public.user_roles set role='owner',updated_at=now() where user_id=p_user_id;update public.subscriptions set status='replaced',ends_at=now() where user_id=p_user_id and status='active';insert into public.subscriptions(user_id,plan_code,status) values(p_user_id,'owner','active');insert into public.audit_logs(actor_id,action,target_user_id,metadata) values(null,'owner_assigned',p_user_id,jsonb_build_object('source','trusted_server'));end$$;
revoke all on function public.assign_owner(uuid) from public,anon,authenticated;

alter table public.profiles enable row level security;alter table public.user_roles enable row level security;alter table public.subscription_plans enable row level security;alter table public.subscriptions enable row level security;alter table public.plan_features enable row level security;alter table public.verification_codes enable row level security;alter table public.user_consents enable row level security;alter table public.audit_logs enable row level security;alter table public.feature_flags enable row level security;alter table public.user_devices enable row level security;
create policy profiles_read on public.profiles for select using(id=auth.uid() or public.is_admin());
create policy profiles_update on public.profiles for update using(id=auth.uid()) with check(id=auth.uid());
create policy roles_read on public.user_roles for select using(user_id=auth.uid() or public.is_admin());
create policy subscriptions_read on public.subscriptions for select using(user_id=auth.uid() or public.is_admin());
create policy plans_read on public.subscription_plans for select to authenticated using(true);
create policy features_read on public.plan_features for select to authenticated using(true);
create policy consents_read on public.user_consents for select using(user_id=auth.uid() or public.is_admin());
create policy devices_read on public.user_devices for select using(user_id=auth.uid() or public.is_admin());
create policy flags_read on public.feature_flags for select to authenticated using(true);
create policy audit_owner_read on public.audit_logs for select using(public.is_owner());
