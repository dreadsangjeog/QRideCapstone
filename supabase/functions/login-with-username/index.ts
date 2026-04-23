// Deno / Supabase Edge Function — sign in with username + password (Gmail not shown on client).
// Uses service role only to map username → auth user email, then performs password sign-in.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const { username, password } = await req.json();
    const u = String(username ?? "").trim().toLowerCase();
    const p = String(password ?? "");

    if (!u || !p) {
      return json({ error: "Invalid username or password" }, 401);
    }

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const admin = createClient(url, serviceKey);
    const anon = createClient(url, anonKey);

    const { data: profile, error: pErr } = await admin
      .from("profiles")
      .select("id")
      .eq("username", u)
      .maybeSingle();

    if (pErr || !profile?.id) {
      return json({ error: "Invalid username or password" }, 401);
    }

    const { data: userWrap, error: uErr } = await admin.auth.admin.getUserById(
      profile.id,
    );
    if (uErr || !userWrap?.user?.email) {
      return json({ error: "Invalid username or password" }, 401);
    }

    const email = userWrap.user.email;

    const { data: signIn, error: sErr } = await anon.auth.signInWithPassword({
      email,
      password: p,
    });

    if (sErr || !signIn.session) {
      return json({ error: "Invalid username or password" }, 401);
    }

    return json({
      access_token: signIn.session.access_token,
      refresh_token: signIn.session.refresh_token,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
