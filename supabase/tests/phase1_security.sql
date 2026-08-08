begin;

-- Owner entitlement invariants.
do $$
declare v jsonb;
begin
  select value into v from public.plan_features where plan_code='owner' and feature_key='admin';
  if v is distinct from 'true'::jsonb then
    raise exception 'Owner must have admin entitlement';
  end if;
end $$;

-- Sensitive owner promotion must never be callable by normal clients.
do $$
begin
  if has_function_privilege('anon','public.assign_owner(uuid)','EXECUTE') then
    raise exception 'anon can execute assign_owner';
  end if;
  if has_function_privilege('authenticated','public.assign_owner(uuid)','EXECUTE') then
    raise exception 'authenticated can execute assign_owner';
  end if;
end $$;

-- OTP storage must not expose client-side RLS policies.
do $$
declare c int;
begin
  select count(*) into c from pg_policies where schemaname='public' and tablename='verification_codes';
  if c <> 0 then
    raise exception 'verification_codes must remain service-role only';
  end if;
end $$;

rollback;
