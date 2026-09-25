// Stores hashed password + OTP in pending_signups and emails a 6-digit code.
// Does NOT call GoTrue signUp — no auth user until `complete-signup`.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import bcrypt from "npm:bcryptjs@2.4.3";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const OTP_TTL_MS = 15 * 60 * 1000;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }

  try {
    const body = await req.json();
    const email = String(body.email ?? "").trim().toLowerCase();
    const username = String(body.username ?? "").trim().toLowerCase();
    const password = String(body.password ?? "");
    const firstName = cleanName(body.first_name);
    const middleName = cleanName(body.middle_name);
    const lastName = cleanName(body.last_name);
    const birthdate = String(body.birthdate ?? "").trim();

    if (!email || !username || !password) {
      return json({ error: "Email, username, and password are required." }, 400);
    }
    const nameErr = validateLegalName(firstName, middleName, lastName);
    if (nameErr) return json({ error: nameErr }, 400);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(birthdate)) {
      return json({ error: "Choose your birthdate." }, 400);
    }
    if (password.length < 6) {
      return json({ error: "Password must be at least 6 characters." }, 400);
    }

    const url = Deno.env.get("SUPABASE_URL")!;
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(url, serviceKey);

    const { data: taken, error: rpcErr } = await admin.rpc(
      "signup_auth_email_taken",
      { check_email: email },
    );
    if (rpcErr) {
      console.error(rpcErr);
      return json({ error: "Could not verify email availability." }, 500);
    }
    if (taken === true) {
      return json(
        {
          error:
            "This Gmail address is already in use. Sign in with your username and password, or use a different Gmail address.",
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

    const { data: pendingOther } = await admin
      .from("pending_signups")
      .select("email")
      .eq("username", username)
      .maybeSingle();
    if (pendingOther && pendingOther.email !== email) {
      return json({ error: "Username is already taken." }, 400);
    }

    const otp = String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000)
      .padStart(6, "0");
    const otpHash = await hashOtp(otp);
    const passwordHash = bcrypt.hashSync(password, 10);
    const expiresAt = new Date(Date.now() + OTP_TTL_MS).toISOString();

    const { error: upsertErr } = await admin.from("pending_signups").upsert(
      {
        email,
        username,
        first_name: firstName,
        middle_name: middleName || null,
        last_name: lastName,
        birthdate,
        password_hash: passwordHash,
        otp_hash: otpHash,
        expires_at: expiresAt,
      },
      { onConflict: "email" },
    );
    if (upsertErr) {
      console.error(upsertErr);
      return json({ error: "Could not start signup. Try again." }, 500);
    }

    if (Deno.env.get("LOG_SIGNUP_OTP") === "1") {
      console.log(`[request-signup-otp] OTP for ${email}: ${otp}`);
    }

    try {
      await sendSignupEmail(email, otp);
    } catch (mailErr) {
      console.error(mailErr);
      await admin.from("pending_signups").delete().eq("email", email);
      return json(
        {
          error:
            "Could not send the verification email. For Edge Functions, set BREVO_API_KEY or RESEND_API_KEY and SIGNUP_FROM_EMAIL (see EDGE_FUNCTIONS.md).",
        },
        503,
      );
    }

    return json({ ok: true });
  } catch (e) {
    console.error(e);
    return json({ error: String(e) }, 500);
  }
});

function cleanName(v: unknown): string {
  return String(v ?? "").trim().replace(/\s+/g, " ");
}

function validateLegalName(first: string, middle: string, last: string): string | null {
  const re = /^[A-Za-z][A-Za-z .'\-]*$/;
  if (!first) return "First name is required.";
  if (!last) return "Last name is required.";
  for (const [label, value, required] of [
    ["First name", first, true],
    ["Middle name", middle, false],
    ["Last name", last, true],
  ] as const) {
    if (!value) {
      if (required) return `${label} is required.`;
      continue;
    }
    if (value.length > 40) return `${label} must be at most 40 characters.`;
    if (!re.test(value)) {
      return `${label} may only use letters, spaces, hyphens, and apostrophes.`;
    }
  }
  return null;
}

async function hashOtp(otp: string): Promise<string> {
  const pepper = Deno.env.get("SIGNUP_OTP_PEPPER") ??
    "dev-pepper-change-in-production";
  const data = new TextEncoder().encode(`${pepper}:${otp}`);
  const buf = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Safe to embed in HTML / XML. */
function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/**
 * Transactional HTML aligned with the Flutter app: primary #007AFF, wordmark + tagline.
 * Table layout + inline styles for Gmail and common clients.
 */
function buildSignupOtpEmailHtml(code: string): string {
  const c = escapeHtml(code);
  const primary = "#007AFF";
  const surface = "#FFFFFF";
  const pageBg = "#EEF1F6";
  const muted = "#6B7280";
  const border = "#E5E7EB";
  const codeBg = "#F3F4F6";

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<meta http-equiv="X-UA-Compatible" content="IE=edge">
<title>QRide — Verify your email</title>
</head>
<body style="margin:0;padding:0;background-color:${pageBg};-webkit-text-size-adjust:100%;">
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:${pageBg};">
  <tr>
    <td align="center" style="padding:32px 16px;">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="max-width:480px;background-color:${surface};border-radius:20px;border:1px solid ${border};overflow:hidden;">
        <tr>
          <td style="padding:28px 28px 8px 28px;">
            <table role="presentation" cellspacing="0" cellpadding="0" border="0">
              <tr>
                <td valign="middle" style="padding-right:14px;">
                  <table role="presentation" cellspacing="0" cellpadding="0" border="0">
                    <tr>
                      <td align="center" valign="middle" style="width:48px;height:48px;background-color:${primary};border-radius:14px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:22px;font-weight:800;color:#ffffff;line-height:48px;">Q</td>
                    </tr>
                  </table>
                </td>
                <td valign="middle">
                  <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:26px;font-weight:800;letter-spacing:-0.5px;color:${primary};line-height:1.15;">QRide</div>
                  <div style="font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:14px;color:${muted};padding-top:4px;line-height:1.3;">Scan &#8226; Ride &#8226; Return</div>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding:8px 28px 4px 28px;">
            <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:17px;font-weight:600;color:#111827;line-height:1.4;">Verify your Gmail</p>
            <p style="margin:10px 0 0 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:15px;color:${muted};line-height:1.55;">Use this code in the QRide app to finish creating your account. It expires in <strong style="color:#374151;">15 minutes</strong>.</p>
          </td>
        </tr>
        <tr>
          <td style="padding:20px 28px 28px 28px;">
            <table role="presentation" width="100%" cellspacing="0" cellpadding="0" border="0" style="background-color:${codeBg};border-radius:14px;border:1px solid ${border};">
              <tr>
                <td align="center" style="padding:22px 16px;">
                  <p style="margin:0 0 8px 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;font-weight:600;color:${muted};text-transform:uppercase;letter-spacing:0.08em;">Your code</p>
                  <p style="margin:0;font-family:'SF Mono',ui-monospace,Menlo,Monaco,'Cascadia Mono','Segoe UI Mono',Consolas,monospace;font-size:32px;font-weight:700;letter-spacing:0.35em;color:#111827;line-height:1.2;">${c}</p>
                </td>
              </tr>
            </table>
          </td>
        </tr>
        <tr>
          <td style="padding:0 28px 24px 28px;">
            <p style="margin:0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:13px;color:#9CA3AF;line-height:1.5;">If you didn&rsquo;t request this, you can ignore this email. Your account won&rsquo;t be created without the code.</p>
          </td>
        </tr>
      </table>
      <p style="margin:20px 0 0 0;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,Helvetica,Arial,sans-serif;font-size:12px;color:#9CA3AF;text-align:center;max-width:480px;">QRide &mdash; campus bike sharing</p>
    </td>
  </tr>
</table>
</body>
</html>`;
}

function buildSignupOtpEmailText(code: string): string {
  return [
    "QRide — Scan • Ride • Return",
    "",
    "Verify your Gmail",
    "",
    `Your verification code: ${code}`,
    "",
    "Enter this code in the QRide app to finish creating your account.",
    "This code expires in 15 minutes.",
    "",
    "If you didn't request this, ignore this email.",
  ].join("\n");
}

async function sendSignupEmail(to: string, code: string): Promise<void> {
  const from = Deno.env.get("SIGNUP_FROM_EMAIL");
  const fromName = Deno.env.get("SIGNUP_FROM_NAME") ?? "QRide";
  if (!from) {
    throw new Error("SIGNUP_FROM_EMAIL is not set");
  }

  const htmlContent = buildSignupOtpEmailHtml(code);
  const textContent = buildSignupOtpEmailText(code);
  const subject = "Verify your email — QRide";

  const brevo = Deno.env.get("BREVO_API_KEY");
  if (brevo) {
    const r = await fetch("https://api.brevo.com/v3/smtp/email", {
      method: "POST",
      headers: { "api-key": brevo, "Content-Type": "application/json" },
      body: JSON.stringify({
        sender: { email: from, name: fromName },
        to: [{ email: to }],
        subject,
        htmlContent,
        textContent,
      }),
    });
    if (!r.ok) throw new Error(`Brevo: ${await r.text()}`);
    return;
  }

  const resend = Deno.env.get("RESEND_API_KEY");
  if (resend) {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${resend}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        from: `${fromName} <${from}>`,
        to: [to],
        subject,
        html: htmlContent,
        text: textContent,
      }),
    });
    if (!r.ok) throw new Error(`Resend: ${await r.text()}`);
    return;
  }

  throw new Error("No BREVO_API_KEY or RESEND_API_KEY");
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
