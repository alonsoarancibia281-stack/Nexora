-- Phase 1 administrative security contract checks.
-- Run against staging after migrations.

begin;

-- Owner-sensitive helpers must not be executable by anon/authenticated directly.
select has_function_privilege('anon', 'public.assign_owner(uuid)', 'EXECUTE') = false as anon_cannot_assign_owner;
select has_function_privilege('authenticated', 'public.assign_owner(uuid)', 'EXECUTE') = false as user_cannot_assign_owner;
select has_function_privilege('anon', 'public.internal_user_id_by_email(text)', 'EXECUTE') = false as anon_cannot_lookup_auth_email;
select has_function_privilege('authenticated', 'public.internal_user_id_by_email(text)', 'EXECUTE') = false as user_cannot_lookup_auth_email;
select has_function_privilege('anon', 'public.consume_verification_rate_limit(text,text,int,int)', 'EXECUTE') = false as anon_cannot_consume_internal_limit;
select has_function_privilege('authenticated', 'public.consume_verification_rate_limit(text,text,int,int)', 'EXECUTE') = false as user_cannot_consume_internal_limit;

-- Admin RPCs are callable by authenticated users but enforce owner authorization internally.
select has_function_privilege('authenticated', 'public.admin_dashboard_metrics()', 'EXECUTE') = true as admin_rpc_exposed_to_authenticated;
select has_function_privilege('authenticated', 'public.admin_set_user_suspension(uuid,boolean)', 'EXECUTE') = true as suspension_rpc_exposed;
select has_function_privilege('authenticated', 'public.admin_set_feature_flag(text,boolean)', 'EXECUTE') = true as flags_rpc_exposed;

rollback;
