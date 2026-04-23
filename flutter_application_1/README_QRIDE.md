# QRide (Flutter + Supabase)

## Configure Supabase

1. Copy `lib/config/supabase_config.dart` values from Supabase (**Integrations → Data API → API URL**) and (**Settings → API Keys → anon public**).
2. In Supabase **SQL Editor**, run [`../supabase/schema.sql`](../supabase/schema.sql) (copy/paste the whole file, then Run).
3. **Deploy Edge Functions** for username login + forgot password: see [`../supabase/EDGE_FUNCTIONS.md`](../supabase/EDGE_FUNCTIONS.md).
4. **Authentication → Email templates**: for **6-digit codes**, include `{{ .Token }}` in **Confirm signup** and **Reset password** (see [`../supabase/EDGE_FUNCTIONS.md`](../supabase/EDGE_FUNCTIONS.md)). Keep **Confirm email** enabled so accounts are verified via OTP.
5. Set your user as admin (after they confirm email and appear in **Authentication → Users**):

```sql
update public.profiles set role = 'admin' where id = '<your-auth-user-uuid>';
```

## Run

```bash
flutter pub get
flutter run
```

## Auth rules (app)

- **Register**: Gmail + **username** + password → **Send 6-digit code** to Gmail, then verify. Gmail is for anti-spam / recovery only.
- **Login**: **username + password** only (no Gmail field). Edge Function `login-with-username`.
- **Forgot password**: username → **send-recovery-otp**; then enter code + new password → **reset-password-with-otp**.

## Demo flow

- **Active rental** tab → **Start demo rental** (picks an available bike, starts GPS writes).
- **Profile → Admin dashboard** → Bikes / Active / Reports.

## GPS retention

- History rows in `rental_locations` are intended to be pruned after **7 days** using `prune_rental_locations_older_than_7_days()` (schedule with pg_cron or run manually).
