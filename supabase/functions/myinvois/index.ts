// ════════════════════════════════════════════════════════════════════════════
// Bookly MY — MyInvois proxy Edge Function (Phase 4 #28, sandbox MVP)
//
// Brokers LHDN MyInvois API calls so the taxpayer's client_id/secret never live
// on the device. The caller is authenticated by their Supabase JWT; their
// MyInvois credentials are read (RLS-protected) from `myinvois_credentials`.
//
// Actions (POST JSON body):
//   { action: "submit", document: <UBL JSON>, codeNumber: "INV-..." }
//   { action: "status", submissionUid: "..." }
//
// Deploy:  supabase functions deploy myinvois
// ════════════════════════════════════════════════════════════════════════════
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function apiBase(env: string): string {
  return env === "prod"
    ? "https://api.myinvois.hasil.gov.my"
    : "https://preprod-api.myinvois.hasil.gov.my";
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    // User-scoped client → RLS lets us read only the caller's own credentials.
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: userData } = await supabase.auth.getUser();
    const user = userData?.user;
    if (!user) return json({ error: "Not authenticated" }, 401);

    const { data: creds } = await supabase
      .from("myinvois_credentials")
      .select("client_id, client_secret, env")
      .eq("user_id", user.id)
      .maybeSingle();

    if (!creds || !creds.client_id || !creds.client_secret) {
      return json({ error: "MyInvois credentials not configured" }, 400);
    }

    const base = apiBase(creds.env ?? "sandbox");

    // ── 1. OAuth2 client-credentials token ────────────────────────────────────
    const tokenRes = await fetch(`${base}/connect/token`, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        client_id: creds.client_id,
        client_secret: creds.client_secret,
        grant_type: "client_credentials",
        scope: "InvoicingAPI",
      }),
    });
    if (!tokenRes.ok) {
      return json({ error: "Auth failed", detail: await tokenRes.text() }, 502);
    }
    const token = (await tokenRes.json()).access_token as string;

    const body = await req.json();
    const action = body.action as string;

    // ── 2a. Submit a document ──────────────────────────────────────────────────
    if (action === "submit") {
      // Prefer the exact serialized string from the device (byte-identical to
      // what was digitally signed). Fall back to stringifying the object for
      // unsigned callers.
      const docStr = typeof body.documentString === "string"
        ? body.documentString
        : JSON.stringify(body.document);
      const submitRes = await fetch(`${base}/api/v1.0/documentsubmissions/`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          documents: [
            {
              format: "JSON",
              document: btoa(unescape(encodeURIComponent(docStr))),
              documentHash: await sha256Hex(docStr),
              codeNumber: body.codeNumber,
            },
          ],
        }),
      });
      const out = await submitRes.json().catch(() => ({}));
      return json({ ok: submitRes.ok, status: submitRes.status, data: out });
    }

    // ── 2b. Poll a submission's status ─────────────────────────────────────────
    if (action === "status") {
      const sid = body.submissionUid as string;
      const stRes = await fetch(
        `${base}/api/v1.0/documentsubmissions/${sid}?pageNo=1&pageSize=100`,
        { headers: { "Authorization": `Bearer ${token}` } },
      );
      const out = await stRes.json().catch(() => ({}));
      return json({ ok: stRes.ok, status: stRes.status, data: out });
    }

    // ── 2c. Cancel a validated document (within LHDN's 72h window) ──────────────
    if (action === "cancel") {
      const uuid = body.uuid as string;
      const reason = (body.reason as string) || "Cancelled by issuer";
      const cancelRes = await fetch(
        `${base}/api/v1.0/documents/state/${uuid}/state`,
        {
          method: "PUT",
          headers: {
            "Authorization": `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({ status: "cancelled", reason }),
        },
      );
      const out = await cancelRes.json().catch(() => ({}));
      return json({ ok: cancelRes.ok, status: cancelRes.status, data: out });
    }

    return json({ error: "Unknown action" }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
