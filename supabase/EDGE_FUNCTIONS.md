# Username login + password reset (Edge Functions)

Supabase’s Flutter client can only sign in with **email + password**. To support **username + password** (while keeping Gmail only for verification / reset), this project uses Edge Functions:

- `login-with-username` — maps `username` → user’s Gmail (server-side), then signs in.
- `send-recovery-otp` — maps `username` → Gmail, then calls GoTrue `**/auth/v1/recover`** so Supabase emails a recovery message. Use `**{{ .Token }}**` in the **Reset password** email template so users receive a **6-digit code** (otherwise a magic link is sent).
- `reset-password-with-otp` — verifies the recovery code with `**/auth/v1/verify`** (`type: recovery`), then sets the new password with the **service role** (so the Flutter app never needs the account email on the client).
- `request-signup-otp` — stores a pending signup (`pending_signups` table: hashed password + OTP) and sends a **6-digit code** via **Brevo** or **Resend**. Does **not** call `auth.signUp`, so no row appears in **Authentication → Users** until `complete-signup` runs.
- `complete-signup` — verifies the code and password against `pending_signups`, then `**auth.admin.createUser`** with `email_confirm: true`. This is what runs when the user taps **Create account** in the app.

## 1) Apply SQL (if you haven’t already)

Run in Supabase **SQL Editor** (or use the CLI):

1. Prefer full `[schema.sql](./schema.sql)` (tables, RLS, triggers, signup helpers).
2. Or apply migrations in order, including at least `**023_pending_signups.sql`** and `**024_signup_auth_email_taken.sql**` for deferred registration.

## 2) Signup OTP email (Brevo or Resend)

Deferred signup does **not** use the Supabase “Confirm signup” template. Configure **one** of:


| Secret              | Purpose                                                           |
| ------------------- | ----------------------------------------------------------------- |
| `BREVO_API_KEY`     | [Brevo](https://developers.brevo.com/) transactional API          |
| `RESEND_API_KEY`    | [Resend](https://resend.com/docs) API                             |
| `SIGNUP_FROM_EMAIL` | Verified sender address (required)                                |
| `SIGNUP_FROM_NAME`  | Optional display name (default `QRide`)                           |
| `SIGNUP_OTP_PEPPER` | Optional extra secret for OTP hashing (recommended in production) |
| `LOG_SIGNUP_OTP`    | Set to `1` only in dev to print OTP in function logs              |


In the Supabase dashboard: **Project Settings → Edge Functions → Secrets**, add the keys above.

## 3) Email templates (6-digit OTP) — password reset only

In the Supabase dashboard: **Authentication → Email templates**.

**Reset password**: Supabase only emails a **6-digit code** if the template body **includes** `{{ .Token }}` ([docs](https://supabase.com/docs/guides/auth/auth-email-templates)). If the body only has `{{ .ConfirmationURL }}`, users get a **link**, and the QRide forgot-password screen will not match.

Paste-style example (replace the whole **Body** if you want code-only mail):

**Reset password** body:

```html
<h2>Reset your QRide password</h2>
<p>Your password reset code is:</p>
<p style="font-size:24px;font-weight:bold;letter-spacing:4px;">{{ .Token }}</p>
<p>If you did not request a reset, ignore this email.</p>
```

Optional: **Authentication → Providers → Email** — adjust **OTP expiration** if offered; the code is still **6 digits** by default on hosted Supabase.

## 4) SQL: `pending_signups` + `signup_auth_email_taken`

Run new migrations from `[migrations/](./migrations/)` (at least `**023_pending_signups.sql`** and `**024_signup_auth_email_taken.sql**`) or apply the matching sections in `[schema.sql](./schema.sql)`.

## 5) Install Supabase CLI and link the project

From the repo root (`QRideCapstone/`). Do **not** use `npm i -g supabase` (unsupported). Use `npx`:

```bash
npx supabase login
npx supabase link --project-ref YOUR_PROJECT_REF
```

(`YOUR_PROJECT_REF` is the subdomain in `https://YOUR_PROJECT_REF.supabase.co`.)

## 5) Deploy the functions

```bash
# On Windows, if Docker is not installed/running, add --use-api so the CLI
# bundles the function in the cloud instead of locally.
npx supabase functions deploy login-with-username --use-api
npx supabase functions deploy send-recovery-otp --use-api
npx supabase functions deploy reset-password-with-otp --use-api
npx supabase functions deploy request-signup-otp --use-api
npx supabase functions deploy complete-signup --use-api
```

`supabase/config.toml` sets `verify_jwt = false` so the app can call these **before** the user is signed in.

## 6) Flutter app

No secrets in the app beyond the normal **anon** key. The Edge runtime uses the **service role** automatically (never put the service role key in Flutter).