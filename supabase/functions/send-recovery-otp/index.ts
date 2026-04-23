// Sends Supabase password recovery email (OTP if the Reset password template uses {{ .Token }}).
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
    const { username } = await req.json();
    const u = String(username ?? "").trim().toLowerCase();

    if (!u) {
      return json({ ok: true });
    }

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;

    const admin = createClient(url, serviceKey);

    const { data: profile, error: pErr } = await admin
      .from("profiles")
      .select("id")
      .eq("username", u)
      .maybeSingle();

    if (pErr || !profile?.id) {
      return json({ ok: true });
    }

    const { data: userWrap, error: uErr } = await admin.auth.admin.getUserById(
      profile.id,
    );
    if (uErr || !userWrap?.user?.email) {
      return json({ ok: true });
    }

    const email = userWrap.user.email;

    const recoverRes = await fetch(`${url}/auth/v1/recover`, {
      method: "POST",
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${anonKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email }),
    });

    if (!recoverRes.ok) {
      const t = await recoverRes.text();
      console.error("recover", recoverRes.status, t);
    }

    return json({ ok: true });
  } catch (e) {
    console.error(e);
    return json({ ok: true });
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
