# QRide Supabase setup

## 1) Create a project

Create a project at [supabase.com](https://supabase.com) and wait until it is ready.

## 2) Run the database schema (this creates tables + RLS + functions)

1. In the Supabase dashboard, open **SQL** → **New query**.
2. On your computer, open the file [`schema.sql`](./schema.sql) in this repo.
3. **Copy the entire file** into the Supabase SQL editor.
4. Click **Run** (or **Ctrl+Enter**).

If you already ran an older version and see errors like “already exists”, stop and paste the error here so we can apply only the missing parts.

## 2b) Username login (Edge Functions)

After the database exists, deploy Edge Functions so the app can **sign in with username + password**:

See **[EDGE_FUNCTIONS.md](./EDGE_FUNCTIONS.md)**.

## 3) Email / Gmail sign-up (required verification)

1. Go to **Authentication** → **Providers** → **Email**.
2. Turn **Confirm email** **ON** (so users must verify before they get a session).
3. Under **Authentication** → **URL configuration**, set **Site URL** to something valid for development (for Flutter mobile, Supabase still needs a site URL for email links; you can use `http://localhost` for local testing or your deployed web URL later).

**Note:** Supabase sends the confirmation email using Supabase’s mail system (or your custom SMTP if you configure it). You do **not** need a separate “Gmail API” for OTP.

The Flutter app only allows **@gmail.com** / **@googlemail.com** addresses at registration and login.

## 4) First admin user

After a user exists in **Authentication → Users**, copy their UUID and run:

```sql
update public.profiles
set role = 'admin'
where id = 'YOUR_USER_UUID_HERE';
```

## 5) Flutter app credentials

Set `flutter_application_1/lib/config/supabase_config.dart` with your **Project URL** (Data API → API URL) and **anon public** key.

## 6) GPS history (7 days)

Run occasionally or schedule:

```sql
select public.prune_rental_locations_older_than_7_days();
```
