-- Public, read-only history of the signals Nexora published.
--
-- Anyone can read it; nobody can write to it directly. Inserts and updates go
-- through the publish-signal edge function, which uses the service role.

create table if not exists public.signal_history (
  id text primary key,
  symbol text not null,
  pair text not null,
  strategy_id text not null,
  strategy_name text not null,
  entry numeric not null check (entry > 0),
  stop numeric not null check (stop > 0),
  target numeric not null check (target > 0),
  hit_rate numeric check (hit_rate >= 0 and hit_rate <= 1),
  trades integer not null default 0 check (trades >= 0),
  created_at timestamptz not null,
  outcome text not null default 'open'
    check (outcome in ('open', 'win', 'loss', 'skipped')),
  closed_at timestamptz,
  result_percent numeric,
  published_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists signal_history_created_at_idx
  on public.signal_history (created_at desc);

create index if not exists signal_history_symbol_idx
  on public.signal_history (symbol);

alter table public.signal_history enable row level security;

-- Read: everyone, including anonymous visitors.
drop policy if exists "signal_history_public_read" on public.signal_history;
create policy "signal_history_public_read"
  on public.signal_history
  for select
  to anon, authenticated
  using (true);

-- Write: nobody. No insert, update or delete policy exists on purpose, so the
-- anon key cannot touch the table. The edge function bypasses RLS with the
-- service role after validating the payload.

revoke insert, update, delete on public.signal_history from anon, authenticated;
grant select on public.signal_history to anon, authenticated;
