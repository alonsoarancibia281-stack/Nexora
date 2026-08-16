import { createClient } from 'npm:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const OUTCOMES = ['open', 'win', 'loss', 'skipped'];

function positiveNumber(value: unknown): number {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed <= 0) {
    throw new Error('invalid number in payload');
  }
  return parsed;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const url = Deno.env.get('SUPABASE_URL');
    const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!url || !serviceKey) throw new Error('Supabase credentials are not configured');

    const body = await req.json();

    // Only the fields the public table holds. Anything else is dropped.
    const row = {
      id: String(body.id ?? '').slice(0, 120),
      symbol: String(body.symbol ?? '').slice(0, 24),
      pair: String(body.pair ?? '').slice(0, 32),
      strategy_id: String(body.strategyId ?? '').slice(0, 40),
      strategy_name: String(body.strategyName ?? '').slice(0, 60),
      entry: positiveNumber(body.entry),
      stop: positiveNumber(body.stop),
      target: positiveNumber(body.target),
      hit_rate: Math.min(Math.max(Number(body.hitRate) || 0, 0), 1),
      trades: Math.max(Math.trunc(Number(body.trades) || 0), 0),
      created_at: new Date(String(body.createdAt)).toISOString(),
      outcome: OUTCOMES.includes(body.outcome) ? body.outcome : 'open',
      closed_at: body.closedAt ? new Date(String(body.closedAt)).toISOString() : null,
      result_percent: Number.isFinite(Number(body.resultPercent))
        ? Number(body.resultPercent)
        : null,
      updated_at: new Date().toISOString(),
    };

    if (!row.id || !row.symbol) throw new Error('id and symbol are required');

    const client = createClient(url, serviceKey, {
      auth: { persistSession: false },
    });
    const { error } = await client
      .from('signal_history')
      .upsert(row, { onConflict: 'id' });
    if (error) throw new Error(error.message);

    return new Response(JSON.stringify({ ok: true, id: row.id }), {
      headers: { ...corsHeaders, 'content-type': 'application/json' },
    });
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 400,
      headers: { ...corsHeaders, 'content-type': 'application/json' },
    });
  }
});
