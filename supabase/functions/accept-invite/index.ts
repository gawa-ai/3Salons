// accept-invite — turns a one-time invitation code into a staff/owner login.
//
// Why an Edge Function: creating a confirmed auth user needs the service-role key,
// which must never reach the browser. The invitation code (shown once to the owner,
// stored only as a hash) is the proof of authorisation.
//
// Flow: validate input -> check code+email (DB) -> create confirmed user -> attach
// membership (DB, atomic, single-use). If attaching fails, the new user is removed.
import { createClient } from "jsr:@supabase/supabase-js@2";

const DEFAULT_ORIGINS = [
  "https://shahina-ahmed-salon.netlify.app",
  "http://localhost:5173",
  "http://localhost:4173",
];
const allowed = new Set(
  [...DEFAULT_ORIGINS, ...(Deno.env.get("ALLOWED_ORIGINS") ?? "").split(",")]
    .map((s) => s.trim())
    .filter(Boolean),
);

function cors(origin: string | null): Record<string, string> {
  const ok = origin && (allowed.has(origin) || /^https:\/\/[a-z0-9-]+--shahina-ahmed-salon\.netlify\.app$/.test(origin));
  return {
    "Access-Control-Allow-Origin": ok ? origin! : DEFAULT_ORIGINS[0],
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "authorization, apikey, content-type, x-client-info",
    "Access-Control-Max-Age": "600",
    "Vary": "Origin",
  };
}

function reply(origin: string | null, status: number, body: unknown) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors(origin), "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

const EMAIL_RE = /^[^@\s<>]+@[^@\s<>]+\.[a-z]{2,}$/i;

Deno.serve(async (req) => {
  const origin = req.headers.get("origin");
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: cors(origin) });
  if (req.method !== "POST") return reply(origin, 405, { ok: false, error: "method_not_allowed" });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return reply(origin, 400, { ok: false, error: "invalid_request", message: "Invalid request." });
  }
  const code = String(body.code ?? "").trim();
  const email = String(body.email ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  const name = String(body.name ?? "").trim().slice(0, 80);

  if (!EMAIL_RE.test(email) || email.length > 254) {
    return reply(origin, 400, { ok: false, error: "email_invalid", message: "Enter a valid email address." });
  }
  if (password.length < 10 || password.length > 128) {
    return reply(origin, 400, { ok: false, error: "weak_password", message: "Use a password of at least 10 characters." });
  }
  if (code.replace(/[^A-Za-z0-9]/g, "").length !== 16) {
    return reply(origin, 400, { ok: false, error: "invite_invalid", message: "This invitation code is not valid." });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) return reply(origin, 500, { ok: false, error: "not_configured", message: "Server not configured." });
  const admin = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

  const check = await admin.rpc("salon_internal_invite_check", { p_code: code, p_email: email });
  if (check.error) return reply(origin, 500, { ok: false, error: "internal_error", message: "Please try again." });
  if (!check.data?.ok) return reply(origin, 400, check.data);

  const created = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { name },
  });
  if (created.error || !created.data.user) {
    const msg = (created.error?.message ?? "").toLowerCase();
    if (msg.includes("already") || msg.includes("registered") || msg.includes("exists")) {
      return reply(origin, 409, {
        ok: false,
        error: "account_exists",
        message: "An account with this email already exists. Sign in, then enter your invitation code.",
      });
    }
    if (msg.includes("password")) {
      return reply(origin, 400, { ok: false, error: "weak_password", message: created.error?.message });
    }
    return reply(origin, 500, { ok: false, error: "internal_error", message: "Could not create the account. Please try again." });
  }

  const userId = created.data.user.id;
  const accepted = await admin.rpc("salon_internal_invite_accept", {
    p_code: code,
    p_user: userId,
    p_email: email,
    p_name: name,
  });
  if (accepted.error || !accepted.data?.ok) {
    await admin.auth.admin.deleteUser(userId); // never leave an orphan login without access
    if (accepted.error) return reply(origin, 500, { ok: false, error: "internal_error", message: "Please try again." });
    return reply(origin, 400, accepted.data);
  }
  return reply(origin, 200, { ok: true, role: accepted.data.role });
});
