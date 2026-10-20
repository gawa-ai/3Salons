// Drains queued SMS from app.notifications and sends via The SMS Works.
// Secrets (Supabase > Edge Functions > Secrets): SMSWORKS_JWT, SMS_SENDER.
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by Supabase.
// Safe to call at any time: it ignores the request body and only processes already-queued rows.
import { createClient } from "jsr:@supabase/supabase-js@2";

const SEND_URL = "https://api.thesmsworks.co.uk/v1/message/send";

type Row = { nid: number; dest: string | null; msg: string; purp: string; tries: number; purposes: Record<string, boolean> | null };

function ukMobile(raw: string | null): string | null {
  if (!raw) return null;
  let d = raw.replace(/[^\d+]/g, "");
  if (d.startsWith("+")) d = d.slice(1);
  if (d.startsWith("0044")) d = d.slice(2);
  if (d.startsWith("07")) d = "44" + d.slice(1);
  return /^447\d{9}$/.test(d) ? d : null;
}

// Non-GSM characters make a text 70 chars/segment instead of 160, so swap the common ones.
function gsmSafe(s: string): string {
  return s
    .replace(/[\u2018\u2019\u201B]/g, "'")
    .replace(/[\u201C\u201D]/g, '"')
    .replace(/[\u2013\u2014]/g, "-")
    .replace(/\u2026/g, "...")
    .replace(/\u00A0/g, " ")
    .trim()
    .slice(0, 1280);
}

// Non-secret shape of the token, only used to explain a 401 (never logs the token itself).
function shape(j: string): string {
  const p = j.split(".");
  let iat = "?";
  try { iat = String(JSON.parse(atob(p[1].replace(/-/g, "+").replace(/_/g, "/"))).iat); } catch { /* ignore */ }
  return `len=${j.length} dots=${p.length - 1} ws=${/\s/.test(j)} quote=${/["']/.test(j)} iat=${iat}`;
}

Deno.serve(async () => {
  const jwt = Deno.env.get("SMSWORKS_JWT");
  const sender = Deno.env.get("SMS_SENDER");
  if (!jwt || !sender) return Response.json({ ok: false, error: "missing_secrets" }, { status: 500 });

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  const { data, error } = await db.rpc("sms_claim", { p_limit: 10 });
  if (error) return Response.json({ ok: false, error: "claim_failed", detail: error.message }, { status: 500 });

  const counts = { sent: 0, failed: 0, retry: 0, skipped: 0 };
  const done = async (id: number, outcome: keyof typeof counts, providerId?: string, err?: string) => {
    counts[outcome]++;
    const { error: e } = await db.rpc("sms_complete", {
      p_id: id, p_outcome: outcome, p_provider_id: providerId ?? null, p_error: err ?? null,
    });
    if (e) console.error("complete_failed", id, e.message);
  };

  for (const r of (data ?? []) as Row[]) {
    if (r.purp !== "sms_test" && !(r.purposes && r.purposes[r.purp] === true)) {
      await done(r.nid, "skipped", undefined, "purpose_disabled");
      continue;
    }
    const dest = ukMobile(r.dest);
    if (!dest) { await done(r.nid, "failed", undefined, "invalid_uk_mobile"); continue; }
    const content = gsmSafe(r.msg);
    if (!content) { await done(r.nid, "failed", undefined, "empty_body"); continue; }

    const payload = JSON.stringify({
      sender, destination: dest, content,
      tag: `n${r.nid}`,
      metadata: [{ key: "notification_id", value: String(r.nid) }],
    });
    // The SMS Works requires the "JWT " scheme (verified live). One attempt only: never auto-resend.
    let res: Response;
    try {
      res = await fetch(SEND_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `JWT ${jwt}` },
        body: payload,
        signal: AbortSignal.timeout(15000),
      });
    } catch (e) {
      // Timeout/network: the provider may or may not have sent it. Never auto-resend.
      await done(r.nid, "failed", undefined, `unknown_send_state: ${(e as Error).name}`);
      continue;
    }

    const text = await res.text();
    if (res.status === 201 || res.status === 200) {
      let id: string | undefined;
      try { const j = JSON.parse(text); id = String(j.messageid ?? j.messageId ?? ""); } catch { /* keep undefined */ }
      await done(r.nid, "sent", id || undefined);
    } else if ([401, 402, 403, 429].includes(res.status) || res.status >= 500) {
      await done(r.nid, "retry", undefined, `http_${res.status}: ${text.slice(0, 120)}${res.status === 401 ? " | " + shape(jwt) : ""}`);
    } else {
      await done(r.nid, "failed", undefined, `http_${res.status}: ${text.slice(0, 200)}`);
    }
  }

  return Response.json({ ok: true, claimed: (data ?? []).length, ...counts });
});
