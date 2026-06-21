// ════════════════════════════════════════════════════════════════════════════
// Bookly MY — Gemini proxy Edge Function
//
// Keeps the Gemini API key server-side so it is never compiled into the app
// (can't be extracted from the APK). The caller is authenticated by their
// Supabase JWT (functions.invoke sends it automatically), so only signed-in
// users can use the proxy.
//
// Body (POST JSON) = a Gemini generateContent request:
//   { model?: "gemini-2.5-flash", contents: [...], generationConfig?: {...} }
//
// Setup:
//   supabase functions deploy gemini
//   supabase secrets set GEMINI_KEY=AIza...      (or set it in the dashboard)
// ════════════════════════════════════════════════════════════════════════════

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const key = Deno.env.get("GEMINI_KEY");
    if (!key) return json({ error: "GEMINI_KEY not configured on server" }, 500);

    const body = await req.json();
    const model = typeof body.model === "string" ? body.model : "gemini-2.5-flash";
    const payload = {
      contents: body.contents,
      generationConfig: body.generationConfig,
    };

    const r = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${key}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      },
    );
    const data = await r.json();
    // Forward Gemini's response verbatim (status 200; client checks candidates).
    return json(data, 200);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
