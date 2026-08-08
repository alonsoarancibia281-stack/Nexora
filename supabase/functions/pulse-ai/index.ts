const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  try {
    const apiKey = Deno.env.get('GEMINI_API_KEY');
    if (!apiKey) throw new Error('GEMINI_API_KEY is not configured');
    const body = await req.json();
    const q = body.quantitative ?? {};
    const prompt = `You are a conservative second-opinion classifier for a 5-minute BTC/crypto up-or-down educational model. You MUST use only the structured numbers supplied. Do not invent news, prices, probabilities or market events. Return JSON only with direction (up|down|noTrade), confidence (50-90), explanation (max 180 chars). Prefer noTrade when evidence conflicts or is weak.\n\nDATA:\n${JSON.stringify({symbol: body.symbol,startPrice: body.startPrice,currentPrice: body.currentPrice,secondsRemaining: body.secondsRemaining,quantitative: q})}`;

    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=${apiKey}`,
      {
        method: 'POST',
        headers: {'content-type': 'application/json'},
        body: JSON.stringify({
          contents: [{parts: [{text: prompt}]}],
          generationConfig: {
            temperature: 0.1,
            responseMimeType: 'application/json',
          },
        }),
      },
    );
    if (!response.ok) throw new Error(`Gemini HTTP ${response.status}`);
    const payload = await response.json();
    const text = payload?.candidates?.[0]?.content?.parts?.[0]?.text ?? '{}';
    const parsed = JSON.parse(text);
    const direction = ['up','down','noTrade'].includes(parsed.direction) ? parsed.direction : 'noTrade';
    const confidence = Math.max(50, Math.min(90, Number(parsed.confidence) || 50));
    return new Response(JSON.stringify({
      direction,
      confidence,
      explanation: String(parsed.explanation ?? 'Sin explicación adicional.').slice(0, 220),
      provider: 'Gemini 2.5 Flash-Lite',
    }), {headers: {...corsHeaders, 'content-type': 'application/json'}});
  } catch (error) {
    return new Response(JSON.stringify({error: String(error)}), {
      status: 500,
      headers: {...corsHeaders, 'content-type': 'application/json'},
    });
  }
});
