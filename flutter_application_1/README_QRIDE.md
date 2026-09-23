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

Admin **website** (public URL after you host it): see [`WEB_HOSTING.md`](WEB_HOSTING.md). Local preview (loads CanvasKit from your PC, not Google CDN):

```bash
flutter run -d chrome --no-web-resources-cdn
```

Plain `flutter run -d chrome` often dies with `Failed to fetch … canvaskit.js` / Roboto from `gstatic.com` if that network is blocked.

## Notifications (inbox)

Run [`../supabase/notifications.sql`](../supabase/notifications.sql) in the SQL Editor, then enable **Realtime** on `public.notifications` (Database → Replication). Riders and admins get an in-app history (bell icon). Approve/reject still works even if the rider is not on the Active tab.

## Live map GPS

Maps use **CARTO Voyager**. Get a free key (no CARTO account) at [carto.com/basemaps/apikey](https://carto.com/basemaps/apikey/) and paste it into `lib/config/map_config.dart` as `cartoBasemapKey`. Without it, tiles show **API KEY REQUIRED**.

Run [`../supabase/location_heading.sql`](../supabase/location_heading.sql) so rider **heading** (facing direction) is stored. Enable Realtime on `rental_last_location` in Supabase **Database → Replication**.

## Auth rules (app)

- **Register**: Gmail + **username** + password → **Send 6-digit code** to Gmail, then verify. Gmail is for anti-spam / recovery only.
- **Login**: **username + password** only (no Gmail field). Edge Function `login-with-username`.
- **Forgot password**: username → **send-recovery-otp**; then enter code + new password → **reset-password-with-otp**.

## Demo flow

- **Active rental** tab → **Start demo rental** (picks an available bike, starts GPS writes).
- **Profile → Admin dashboard** → Bikes / Active / Reports.

## GPS retention

- History rows in `rental_locations` are intended to be pruned after **7 days** using `prune_rental_locations_older_than_7_days()` (schedule with pg_cron or run manually).
