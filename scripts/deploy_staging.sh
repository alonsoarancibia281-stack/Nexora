#!/usr/bin/env bash
set -euo pipefail

if ! command -v npx >/dev/null 2>&1; then
  echo "Node.js/npm is required." >&2
  exit 1
fi

: "${SUPABASE_PROJECT_REF:?Set SUPABASE_PROJECT_REF}"
: "${SUPABASE_DB_PASSWORD:?Set SUPABASE_DB_PASSWORD}"

SECRETS_FILE="${SECRETS_FILE:-supabase/.env.staging}"
if [[ ! -f "$SECRETS_FILE" ]]; then
  echo "Missing $SECRETS_FILE. Copy supabase/.env.staging.example and fill real values locally." >&2
  exit 1
fi

echo "Linking staging project..."
npx supabase link --project-ref "$SUPABASE_PROJECT_REF" --password "$SUPABASE_DB_PASSWORD"

echo "Checking pending migrations..."
npx supabase db push --dry-run

echo "Applying migrations..."
npx supabase db push

echo "Uploading Edge Function secrets..."
npx supabase secrets set --env-file "$SECRETS_FILE" --project-ref "$SUPABASE_PROJECT_REF"

echo "Deploying Edge Functions..."
npx supabase functions deploy register-consent --project-ref "$SUPABASE_PROJECT_REF"
npx supabase functions deploy request-verification-code --no-verify-jwt --project-ref "$SUPABASE_PROJECT_REF"
npx supabase functions deploy verify-email-code --no-verify-jwt --project-ref "$SUPABASE_PROJECT_REF"

echo "Staging deployment complete."
