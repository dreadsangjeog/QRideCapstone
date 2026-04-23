// Verifies recovery OTP via GoTrue, then sets password with the service role (no email on client).
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
    const body = await req.json();
    const u = String(body.username ?? "").trim().toLowerCase();
    const token = String(body.token ?? "").trim();
    const newPassword = String(body.new_password ?? "");

    if (!u || !token || newPassword.length < 6) {
      return json({ ok: false, error: "Invalid request" }, 400);
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
      return json({ ok: false, error: "Invalid or expired code" }, 401);
    }

    const { data: userWrap, error: uErr } = await admin.auth.admin.getUserById(
      profile.id,
    );
    if (uErr || !userWrap?.user?.email) {
      return json({ ok: false, error: "Invalid or expired code" }, 401);
    }

    const email = userWrap.user.email;

    const verifyRes = await fetch(`${url}/auth/v1/verify`, {
      method: "POST",
      headers: {
        apikey: anonKey,
        Authorization: `Bearer ${anonKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        type: "recovery",
        email,
        token,
      }),
    });

    if (!verifyRes.ok) {
      const t = await verifyRes.text();
      console.error("verify recovery", verifyRes.status, t);
      return json({ ok: false, error: "Invalid or expired code" }, 401);
    }

    const { error: upErr } = await admin.auth.admin.updateUserById(
      profile.id,
      { password: newPassword },
    );

    if (upErr) {
      console.error("updateUserById", upErr);
      return json({ ok: false, error: "Could not update password" }, 500);
    }

    return json({ ok: true });
  } catch (e) {
    console.error(e);
    return json({ ok: false, error: String(e) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
