# MyInvois e-Invoice — Setup & Test (Phase 4 #28, Sandbox MVP)

This is the **sandbox MVP** (no digital signature yet). It submits invoices to the
LHDN MyInvois **preprod** environment via a Supabase Edge Function proxy, polls
the status, and embeds the validation QR on the invoice PDF.

> Architecture: the app never holds your MyInvois secret. Credentials are stored
> in the `myinvois_credentials` table (RLS — only you can read your row); the
> `myinvois` Edge Function reads them with your JWT and calls LHDN server-side.

## 1. Database migration

In **Supabase Dashboard → SQL Editor** (project `dgquwkdzmufnrnwquvci`), run:

- `supabase_myinvois_migration.sql`

It creates `myinvois_credentials` (+ RLS) and adds `customers.tin`. Idempotent.

## 2. Deploy the Edge Function

```bash
# one-time
supabase login
supabase link --project-ref dgquwkdzmufnrnwquvci

# deploy
supabase functions deploy myinvois
```

The function uses the built-in `SUPABASE_URL` / `SUPABASE_ANON_KEY` env vars
(provided automatically) — no extra secrets to set for the sandbox MVP.

## 3. Get sandbox API credentials

1. Register / log in at the **MyInvois preprod portal**.
2. Create an **ERP / API client** → copy the **Client ID** and **Client Secret**
   (sandbox set — production uses a different pair).
3. Note your **MSIC code** (5-digit industry code) and business activity.

## 4. Configure in the app

Settings → **🧾 MyInvois e-Invoice**:
- Environment: **Sandbox**
- Client ID / Client Secret
- MSIC code + business activity
- Save (Pro feature; must be signed in)

Also fill your supplier **TIN** (Company Info) and each B2B customer's **TIN**
(customer form). Buyers without a TIN fall back to the general-public TIN
`EI00000000010`.

## 5. End-to-end test

1. Create + save an invoice.
2. Open it in **发票记录 / Invoice History** → invoice detail.
3. In the **MyInvois** tile → **Submit to MyInvois**.
4. Status → `In progress`; tap **Refresh status** until `Validated` (or `Invalid`).
5. If `Invalid`, the error names the offending UBL field — tell me and I'll
   adjust `lib/services/myinvois_ubl.dart` (codes/fields marked `TODO`).
6. When `Validated`, **Export PDF** → the invoice carries the MyInvois QR + UUID.

## Known limits (this MVP)

- **No digital signature** — document version 1.0. LHDN may require signed (1.1)
  documents for production; that's Phase 2 (needs a digital certificate).
- **Production endpoint** wired but untested; use Sandbox first.
- UBL field set is best-effort and validated against the sandbox — address state
  code, item classification code, and tax scheme codes are defaults (`TODO`).
- Cancellation / consolidated e-invoices not included yet.
