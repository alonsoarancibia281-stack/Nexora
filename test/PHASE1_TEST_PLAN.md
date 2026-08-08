# Phase 1 test plan

Automated unit coverage starts with registration validators. Integration tests require a dedicated Supabase test project and must cover:

- registration remains pending until OTP verification;
- OTP expires after ten minutes and cannot be reused;
- five invalid attempts trigger temporary blocking;
- resend is throttled and invalidates the previous code;
- unverified login is rejected;
- ordinary users cannot read another profile, verification code, role, subscription or audit log;
- clients cannot call `assign_owner`;
- configured OWNER_EMAIL receives server-side owner role and owner plan;
- non-owner admins cannot mutate or remove the owner (add this invariant before admin UI ships);
- consent versions and timestamps are persisted before production onboarding is enabled.

Do not run destructive integration tests against production.
