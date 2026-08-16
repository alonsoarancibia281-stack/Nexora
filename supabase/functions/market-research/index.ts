import Anthropic from 'npm:@anthropic-ai/sdk@^0.110.0';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

// The model reads numbers only. It has no news feed, so it must never claim to
// know about news, listings, partnerships or anything outside this payload.
const SYSTEM = `Eres el analista de Nexora. Lees SOLO los números que te entregan sobre un par de criptomonedas de Binance y explicas qué está pasando.

Reglas duras:
- No tienes acceso a noticias, redes, anuncios ni calendarios. NUNCA menciones noticias, listados, asociaciones, ballenas identificadas ni eventos concretos. Si no está en los números, no existe.
- No inventes cifras. Usa solo las que recibes.
- No des consejo financiero ni digas "compra" o "vende". Describes lo que muestran los datos.
- Escribe en español simple, en presente, frases cortas. Cada campo es una sola línea, sin saltos de línea.
- Si los datos son débiles o contradictorios, dilo claramente.`;

const SCHEMA = {
  type: 'object',
  properties: {
    why: {
      type: 'string',
      description: 'Por qué se mueve el precio, según la fuerza de la semana y el mes.',
    },
    money: {
      type: 'string',
      description: 'Qué hace el dinero: volumen frente a su media y profundidad del libro.',
    },
    watch: {
      type: 'string',
      description: 'Qué vigilar en los próximos días.',
    },
    risk: {
      type: 'string',
      description: 'El riesgo principal de esta idea.',
    },
    grade: {
      type: 'string',
      enum: ['fuerte', 'normal', 'flojo'],
      description: 'Qué tan sólida es la señal según los números.',
    },
  },
  required: ['why', 'money', 'watch', 'risk', 'grade'],
  additionalProperties: false,
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });

  try {
    const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
    if (!apiKey) throw new Error('ANTHROPIC_API_KEY is not configured');

    const body = await req.json();
    const symbol = String(body.symbol ?? '').slice(0, 24);
    if (!symbol) throw new Error('symbol is required');

    const client = new Anthropic({ apiKey });

    const response = await client.messages.create({
      model: Deno.env.get('ANTHROPIC_MODEL') ?? 'claude-opus-5',
      max_tokens: 8000,
      system: SYSTEM,
      output_config: {
        effort: 'low',
        format: { type: 'json_schema', schema: SCHEMA },
      },
      messages: [
        {
          role: 'user',
          content: `Analiza este par de Binance con los números de abajo.\n\n${JSON.stringify({
            symbol,
            price: body.price,
            changePercent24h: body.changePercent24h,
            weekChangePercent: body.weekChangePercent,
            monthChangePercent: body.monthChangePercent,
            quoteVolume24h: body.quoteVolume24h,
            volumeSurge: body.volumeSurge,
            distanceFromMonthHighPercent: body.distanceFromMonthHighPercent,
            upDayRatio: body.upDayRatio,
            atrPercent: body.atrPercent,
            strength: body.strength,
            strategy: body.strategy,
            hitRate: body.hitRate,
            trades: body.trades,
          })}`,
        },
      ],
    });

    // Safety classifiers can decline; the response is a 200 with no usable text.
    if (response.stop_reason === 'refusal') {
      return new Response(
        JSON.stringify({ error: 'refusal', category: response.stop_details?.category ?? null }),
        { status: 422, headers: { ...corsHeaders, 'content-type': 'application/json' } },
      );
    }

    const text = response.content.find((block) => block.type === 'text')?.text ?? '';
    if (!text) throw new Error('empty response from model');

    const parsed = JSON.parse(text);
    return new Response(
      JSON.stringify({
        why: String(parsed.why ?? '').slice(0, 280),
        money: String(parsed.money ?? '').slice(0, 280),
        watch: String(parsed.watch ?? '').slice(0, 280),
        risk: String(parsed.risk ?? '').slice(0, 280),
        grade: ['fuerte', 'normal', 'flojo'].includes(parsed.grade) ? parsed.grade : 'normal',
        provider: response.model,
        truncated: response.stop_reason === 'max_tokens',
      }),
      { headers: { ...corsHeaders, 'content-type': 'application/json' } },
    );
  } catch (error) {
    return new Response(JSON.stringify({ error: String(error) }), {
      status: 500,
      headers: { ...corsHeaders, 'content-type': 'application/json' },
    });
  }
});
