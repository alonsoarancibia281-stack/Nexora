create index if not exists audit_logs_actor_id_idx on public.audit_logs(actor_id);
create index if not exists audit_logs_target_user_id_idx on public.audit_logs(target_user_id);
create index if not exists subscriptions_user_id_idx on public.subscriptions(user_id);
create index if not exists subscriptions_plan_code_idx on public.subscriptions(plan_code);
create index if not exists user_consents_user_id_idx on public.user_consents(user_id);

alter policy profiles_read on public.profiles using (id=(select auth.uid()) or public.is_admin());
alter policy profiles_update on public.profiles using (id=(select auth.uid())) with check(id=(select auth.uid()));
alter policy roles_read on public.user_roles using(user_id=(select auth.uid()) or public.is_admin());
alter policy subscriptions_read on public.subscriptions using(user_id=(select auth.uid()) or public.is_admin());
alter policy consents_read on public.user_consents using(user_id=(select auth.uid()) or public.is_admin());
alter policy devices_read on public.user_devices using(user_id=(select auth.uid()) or public.is_admin());
alter policy devices_self_insert on public.user_devices with check (user_id=(select auth.uid()));
alter policy devices_self_update on public.user_devices using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
alter policy devices_self_delete on public.user_devices using (user_id=(select auth.uid()));
