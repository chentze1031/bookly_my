# MyInvois e-Invoice — Setup & Test (Phase 4 #28)

Submits invoices to LHDN MyInvois via a Supabase Edge Function proxy, **digitally
signs them on-device** (production-grade UBL v1.1), polls status, embeds the
validation QR on the PDF, and supports 72-hour cancellation.

> **Security model.** Two secrets, two places — neither lives in app code:
> - **API client_id / client_secret** → `myinvois_credentials` table (RLS; only
>   you can read your row). The `myinvois` Edge Function reads them with your JWT
>   and calls LHDN server-side. The device never holds the secret.
> - **Signing private key** → on this **device only**, in Android Keystore-backed
>   encrypted storage. Never uploaded, never logged. Only the *public* X.509
>   certificate is embedded in the signed document. This satisfies LHDN's
>   non-repudiation requirement (key under the taxpayer's sole control).

## 1. Database migrations

In **Supabase Dashboard → SQL Editor** (project `dgquwkdzmufnrnwquvci`), run both
(idempotent — safe to re-run):

- `supabase_multicompany_migration.sql` — adds `company_id` to synced tables.
- `supabase_myinvois_migration.sql` — creates `myinvois_credentials` (+RLS) and
  adds `customers.tin / city / postcode / state`.

## 2. Deploy the Edge Function

```bash
supabase login
supabase link --project-ref dgquwkdzmufnrnwquvci
supabase functions deploy myinvois
```

Uses the built-in `SUPABASE_URL` / `SUPABASE_ANON_KEY` env vars — no extra secrets.

## 3. Get API credentials

1. Log in to the **MyInvois portal** (preprod for sandbox, production for live).
2. **View → Register ERP / API client** → copy **Client ID** + **Client Secret**
   (sandbox and production are separate pairs).
3. Note your **MSIC code** (5-digit industry code) + business activity.

## 4. Get a digital certificate (production only — sandbox can skip)

Production requires every e-Invoice to be digitally signed.

1. Buy an **organisation** e-Invoice digital certificate from a Malaysian CA on
   the MCMC list (e.g. Pos Digicert, MSC Trustgate). One cert per company; valid
   3 years; cannot be shared.
2. You'll receive a `.p12` / `.pfx` (password-protected) — **import it directly**
   in the app. If import fails (some CAs use AES-encrypted .p12 that pure-Dart
   can't open), export it to PEM once and import that:
   ```bash
   # one PEM file containing BOTH the key and the certificate
   openssl pkcs12 -in cert.p12 -nodes -out bookly_cert.pem
   ```

## 5. Configure in the app

Settings → **🧾 MyInvois e-Invoice** (Pro; must be signed in):
- Environment: **Sandbox** (test) or **Production**
- Client ID / Client Secret
- MSIC code + business activity + **default classification code** (e.g. `022`)
- **Digital certificate** → Import (`.p12`/`.pfx` + password, or `.pem`). Card
  shows subject + expiry; warns ≤30 days / expired.

Also fill, for correct UBL:
- **Company Info**: TIN, address, **city / postcode / state**.
- **Each B2B customer**: TIN, city / postcode / state. Buyers without a TIN fall
  back to the general-public TIN `EI00000000010`.

## 6. End-to-end test

1. Create + save an invoice.
2. Invoice History → invoice detail → **MyInvois** tile → **Submit to MyInvois**.
   - With a certificate imported → signed **v1.1**. Without → unsigned **v1.0**
     (sandbox only).
3. Status → `In progress`; **Refresh status** until `Validated` (or `Invalid`).
4. `Validated` → **Export PDF** carries the MyInvois QR + UUID.
5. To void: **Cancel e-Invoice** (≤72h after validation) with a reason.

### If `Invalid` / signature rejected

The error names the offending area — share it and we adjust precisely:
- **Schema / field error** → a UBL field in `lib/services/myinvois_ubl.dart`
  (state code, classification, tax scheme, TIN format).
- **Signature invalid** (structure accepted but signature fails) → almost always
  **numeric canonicalisation**: emit amounts/percentages as strings in the UBL
  builder so LHDN's re-minify round-trip is byte-stable. The signing math in
  `lib/services/myinvois_signer.dart` is verified correct (RSA-SHA256 round-trip)
  and does not change.

## Production go-live checklist

- [ ] Both SQL migrations run on production project.
- [ ] Edge Function deployed.
- [ ] Production Client ID/Secret saved; environment = **Production**.
- [ ] Organisation digital certificate imported; not expired.
- [ ] One real invoice submitted → `Validated` in the production portal.
- [ ] App release build has `_debugProMode = false`.

## Also available

- **Consolidated e-Invoice (B2C)** and **Self-billed e-Invoice** — both launched
  from the MyInvois settings card.

## Notes

- Certificate is stored per active company — switching companies needs each
  company's own certificate imported.
