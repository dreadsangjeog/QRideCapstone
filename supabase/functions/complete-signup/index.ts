// Creates the auth user (confirmed) after OTP + password match pending_signups row.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import bcrypt from "npm:bcryptjs@2.4.3";

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
    const email = String(body.email ?? "").trim().toLowerCase();
    const username = String(body.username ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const otp = String(body.otp ?? "").trim();
    const firstName = String(body.first_name ?? "").trim().replace(/\s+/g, " ");
    const middleName = String(body.middle_name ?? "").trim().replace(/\s+/g, " ");
    const lastName = String(body.last_name ?? "").trim().replace(/\s+/g, " ");
    const birthdate = String(body.birthdate ?? "").trim();

    if (!email || !username || !password || !otp) {
      return json({ error: "Email, username, password, and code are required." }, 400);
    }
    if (!/^\d{6}$/.test(otp)) {
      return json({ error: "Enter the 6-digit code from your Gmail." }, 400);
    }

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, serviceKey);

    const { data: row, error: selErr } = await admin
      .from("pending_signups")
      .select(
        "username,password_hash,otp_hash,expires_at,first_name,middle_name,last_name,birthdate",
      )
      .eq("email", email)
      .maybeSingle();

    if (selErr) {
      console.error(selErr);
      return json({ error: "Could not load signup. Request a new code." }, 500);
    }
    if (!row) {
      return json(
        { error: "No pending signup for this email. Tap Get code first." },
        400,
      );
    }

    const expires = new Date(String(row.expires_at)).getTime();
    if (Date.now() > expires) {
      await admin.from("pending_signups").delete().eq("email", email);
      return json(
        { error: "That code has expired. Tap Resend for a new code." },
        400,
      );
    }

    if (String(row.username) !== username) {
      return json({ error: "Username does not match this signup." }, 400);
    }
    if (
      String(row.first_name ?? "") !== firstName ||
      String(row.middle_name ?? "") !== middleName ||
      String(row.last_name ?? "") !== lastName ||
      String(row.birthdate ?? "").slice(0, 10) !== birthdate
    ) {
      return json({ error: "Name does not match this signup. Request a new code." }, 400);
    }

    if (!bcrypt.compareSync(password, String(row.password_hash))) {
      return json({ error: "Password does not match what you used for Get code." }, 400);
    }

    const expectedHash = String(row.otp_hash);
    const actualHash = await hashOtp(otp);
    if (!timingSafeEqualHex(expectedHash, actualHash)) {
      return json({ error: "Invalid verification code." }, 400);
    }

    const { data: taken } = await admin.rpc("signup_auth_email_taken", {
      check_email: email,
    });
    if (taken === true) {
      await admin.from("pending_signups").delete().eq("email", email);
      return json(
        {
          error:
            "This Gmail address is already registered. Sign in instead.",
        },
        400,
      );
    }

    const { data: prof } = await admin
      .from("profiles")
      .select("id")
      .eq("username", username)
      .maybeSingle();
    if (prof?.id) {
      return json({ error: "Username is already taken." }, 400);
    }

    const { data: created, error: createErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        username,
        first_name: firstName,
        middle_name: middleName,
        last_name: lastName,
        birthdate,
      },
    });

    if (createErr || !created?.user) {
      console.error(createErr);
      const msg = createErr?.message ?? "Could not create account.";
      if (/already|exists|registered/i.test(msg)) {
        await admin.from("pending_signups").delete().eq("email", email);
        return json(
          {
            error:
              "This Gmail address is already registered. Sign in instead.",
          },
          400,
        );
      }
      return json({ error: msg }, 400);
    }

    await admin.from("pending_signups").delete().eq("email", email);

    return json({ ok: true });
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});

async function hashOtp(otp: string): Promise<string> {
  const pepper = Deno.env.get("SIGNUP_OTP_PEPPER") ??
    "dev-pepper-change-in-production";
  const data = new TextEncoder().encode(`${pepper}:${otp}`);
  const buf = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function timingSafeEqualHex(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let x = 0;
  for (let i = 0; i < a.length; i++) {
    x |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return x === 0;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
