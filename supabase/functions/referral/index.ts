// ════════════════════════════════════════════════════════════════════════════
// Bookly MY — Referral Edge Function
//
// Each user has an invite code. A referee links to a referrer; once the referee
// becomes ACTIVE (≥3 transactions), the referrer's reward tier is re-evaluated.
// Reward = HIGHEST tier reached (not additive), granted as a RevenueCat
// promotional entitlement on "pro":
//   1 active referral  → 7 days  (weekly)
//   5  → 2 months (two_month)   10 → 6 months (six_month)   20 → 1 year (yearly)
//
// Setup:
//   1) Run supabase/referral_setup.sql
//   2) supabase functions deploy referral
//   3) Set secret: REVENUECAT_SECRET_KEY = <RevenueCat SECRET API key>
//      (SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY are auto-provided)
// ════════════════════════════════════════════════════════════════════════════
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (d: unknown, s = 200) =>
  new Response(JSON.stringify(d), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const ANON_KEY     = Deno.env.get("SUPABASE_ANON_KEY")!;
const RC_KEY       = Deno.env.get("REVENUECAT_SECRET_KEY") ?? "";
const RC_ENTITLEMENT = "pro";
const ACTIVE_MIN_TX = 3;

const TIER_DURATION: Record<number, string> = { 1: "weekly", 5: "two_month", 10: "six_month", 20: "yearly" };
const highestTier = (n: number) => (n >= 20 ? 20 : n >= 10 ? 10 : n >= 5 ? 5 : n >= 1 ? 1 : 0);

function genCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"; // no ambiguous 0/O/1/I
  let s = ""; for (let i = 0; i < 6; i++) s += chars[Math.floor(Math.random() * chars.length)];
  return s;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const userClient = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } } });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "unauthorized" }, 401);
    const uid = user.id;
    const svc = createClient(SUPABASE_URL, SERVICE_KEY);
    const body = await req.json().catch(() => ({}));

    async function ensureProfile(id: string) {
      const { data } = await svc.from("referral_profiles").select("*").eq("user_id", id).maybeSingle();
      if (data) return data;
      let code = genCode();
      for (let i = 0; i < 6; i++) {
        const { data: ex } = await svc.from("referral_profiles").select("user_id").eq("code", code).maybeSingle();
        if (!ex) break;
        code = genCode();
      }
      const { data: created } = await svc.from("referral_profiles")
        .insert({ user_id: id, code }).select().single();
      return created;
    }

    async function countActive(refId: string): Promise<number> {
      const { count } = await svc.from("referral_profiles")
        .select("user_id", { count: "exact", head: true })
        .eq("referred_by", refId).eq("active", true);
      return count ?? 0;
    }

    // Grant a RevenueCat promotional `pro` entitlement. Returns true ONLY when
    // RevenueCat confirms the grant — so the caller never records a reward the
    // user didn't actually receive. A missing key or any error → false.
    async function grantPromo(appUserId: string, duration: string): Promise<boolean> {
      if (!RC_KEY) {
        console.error("grantPromo: REVENUECAT_SECRET_KEY not set");
        return false;
      }
      try {
        const res = await fetch(
          `https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(appUserId)}/entitlements/${RC_ENTITLEMENT}/promotional`,
          {
            method: "POST",
            headers: { "Authorization": `Bearer ${RC_KEY}`, "Content-Type": "application/json" },
            body: JSON.stringify({ duration }),
          },
        );
        if (!res.ok) {
          console.error(`grantPromo failed (${res.status}) for ${appUserId}: ${await res.text()}`);
          return false;
        }
        return true;
      } catch (e) {
        console.error(`grantPromo threw for ${appUserId}:`, e);
        return false;
      }
    }

    async function evaluate(refId: string | null) {
      if (!refId) return;
      const prof = await ensureProfile(refId);
      const tier = highestTier(await countActive(refId));
      if (tier > (prof.granted_tier ?? 0)) {
        // Only record the new tier when the promo was actually granted, so the
        // DB/UI can never claim a reward RevenueCat never issued. On failure we
        // leave granted_tier untouched — the next sync retries.
        const granted = await grantPromo(refId, TIER_DURATION[tier]);
        if (granted) {
          await svc.from("referral_profiles").update({ granted_tier: tier }).eq("user_id", refId);
        }
      }
    }

    switch (body.action) {
      case "me": {
        const p = await ensureProfile(uid);
        return json({ code: p.code, referredBy: p.referred_by, grantedTier: p.granted_tier, validReferrals: await countActive(uid) });
      }
      case "link": {
        const myProfile = await ensureProfile(uid);
        const code = String(body.code ?? "").trim().toUpperCase();
        if (!code) return json({ error: "no_code" }, 400);
        const { data: ref } = await svc.from("referral_profiles").select("user_id").eq("code", code).maybeSingle();
        if (!ref) return json({ error: "invalid_code" }, 404);
        if (ref.user_id === uid) return json({ error: "self_referral" }, 400);
        if (myProfile.referred_by) return json({ error: "already_linked" }, 409);
        await svc.from("referral_profiles").update({ referred_by: ref.user_id }).eq("user_id", uid);
        // 兜底：若被邀请人此刻已是活跃用户（先记满 3 笔才填码），其「活跃翻转」
        // 时机已过，sync 不会再触发 evaluate。这里立即评估一次邀请人奖励，避免漏发。
        if (myProfile.active) await evaluate(ref.user_id);
        return json({ ok: true });
      }
      case "sync": {
        const p = await ensureProfile(uid);
        if (!p.active) {
          const { count } = await svc.from("transactions").select("id", { count: "exact", head: true }).eq("user_id", uid);
          if ((count ?? 0) >= ACTIVE_MIN_TX) {
            await svc.from("referral_profiles").update({ active: true }).eq("user_id", uid);
            await evaluate(p.referred_by);
          }
        }
        return json({ ok: true, validReferrals: await countActive(uid) });
      }
      default:
        return json({ error: "unknown_action" }, 400);
    }
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
