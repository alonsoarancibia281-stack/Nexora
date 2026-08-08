-- Remove implicit PUBLIC/anon execute grants from SECURITY DEFINER functions.
revoke all on function public.is_owner() from public, anon;
revoke all on function public.is_admin() from public, anon;
revoke all on function public.handle_new_user() from public, anon, authenticated;
revoke all on function public.protect_owner_role() from public, anon, authenticated;
revoke all on function public.protect_owner_subscription() from public, anon, authenticated;
revoke all on function public.my_entitlements() from public, anon;
revoke all on function public.admin_dashboard_metrics() from public, anon;
revoke all on function public.admin_list_users(text,int) from public, anon;
revoke all on function public.admin_set_user_suspension(uuid,boolean) from public, anon;
revoke all on function public.admin_set_user_plan(uuid,public.plan_code) from public, anon;
revoke all on function public.admin_set_feature_flag(text,boolean) from public, anon;
revoke all on function public.admin_list_feature_flags() from public, anon;

grant execute on function public.my_entitlements() to authenticated;
grant execute on function public.admin_dashboard_metrics() to authenticated;
grant execute on function public.admin_list_users(text,int) to authenticated;
grant execute on function public.admin_set_user_suspension(uuid,boolean) to authenticated;
grant execute on function public.admin_set_user_plan(uuid,public.plan_code) to authenticated;
grant execute on function public.admin_set_feature_flag(text,boolean) to authenticated;
grant execute on function public.admin_list_feature_flags() to authenticated;

-- RLS policies invoke these internally; direct API access is unnecessary.
revoke all on function public.is_owner() from authenticated;
revoke all on function public.is_admin() from authenticated;
