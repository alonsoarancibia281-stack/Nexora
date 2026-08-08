# Nexora Markets AI

Flutter application for educational and probabilistic cryptocurrency market analysis. Nexora does not custody funds, execute trades, or guarantee financial results.

## Phase 1

Implemented foundation: Flutter/Riverpod/GoRouter, Supabase authentication, registration validation, six-digit server OTP, consent-ready schema, roles, subscription plans, RLS, owner authorization, dark UI foundation, and tests scaffold.

## Setup

1. Install Flutter stable and Supabase CLI.
2. Copy `.env.example` to `.env` and set the project URL and public anon key.
3. Create a Supabase project and run migrations in `supabase/migrations` in timestamp order.
4. Configure Edge Function secrets: `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, `OWNER_EMAIL`, `OTP_PEPPER`, `RESEND_API_KEY`, `EMAIL_FROM`.
5. Set `OWNER_EMAIL` to the intended owner account only in Supabase server secrets. Never add it as a Flutter authorization condition.
6. Deploy `request-verification-code` and `verify-email-code` Edge Functions.
7. Configure Resend (or replace the transport while preserving server-side OTP logic) and verify the sender domain.
8. Run `flutter pub get`, then `flutter run`.

## Security notes

OTP codes are generated server-side with Web Crypto, stored only as a SHA-256 hash salted with a server-only pepper, expire after 10 minutes, are single-use, have a five-attempt lock, and old codes are invalidated on resend. Verification endpoints intentionally avoid exposing whether an email exists where practical. RLS is enabled and verification rows have no client policy.

The owner role is assigned only by trusted server logic after comparing a normalized address with `OWNER_EMAIL`. `assign_owner` is revoked from client roles. Administrative role changes should always be audited.

## Next configuration

Production deployments should add CAPTCHA/bot protection, gateway-level IP/device rate limits, Apple/Google sign-in configuration, transactional email legal/support URLs, device attestation where appropriate, and billing receipt verification before enabling paid access.
