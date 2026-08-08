-- Creates profile, default role/plan, and securely promotes configured owner through server metadata.
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.profiles(id,first_name,last_name,country,experience) values(new.id,coalesce(new.raw_user_meta_data->>'first_name',''),coalesce(new.raw_user_meta_data->>'last_name',''),coalesce(new.raw_user_meta_data->>'country',''),coalesce(new.raw_user_meta_data->>'experience','Principiante'));
 insert into public.user_roles(user_id,role) values(new.id,'user');
 insert into public.subscriptions(user_id,plan_code) values(new.id,'free');
 return new;
end; $$;
create trigger on_auth_user_created after insert on auth.users for each row execute procedure public.handle_new_user();

-- Owner assignment is intentionally NOT based on a Flutter condition.
-- Run only from a trusted server function after comparing normalized email to OWNER_EMAIL.
create or replace function public.assign_owner(p_user_id uuid) returns void language plpgsql security definer set search_path='' as $$
begin
 update public.user_roles set role='owner',updated_at=now() where user_id=p_user_id;
 update public.subscriptions set status='replaced',ends_at=now() where user_id=p_user_id and status='active';
 insert into public.subscriptions(user_id,plan_code,status) values(p_user_id,'owner','active');
 insert into public.audit_logs(actor_id,action,target_user_id,metadata) values(null,'owner_assigned',p_user_id,jsonb_build_object('source','trusted_server'));
end; $$;
revoke all on function public.assign_owner(uuid) from public, anon, authenticated;
