// Drains queued SMS from app.notifications (via The SMS Works) and queued web-push alerts from app.push_outbox.
// Secrets (Supabase > Edge Functions > Secrets): SMSWORKS_JWT, SMS_SENDER, VAPID_PRIVATE_KEY.
// (The VAPID public key and subject are not secret and are set below.)
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are injected by Supabase.
// Safe to call at any time: it ignores the request body and only processes already-queued rows.
import { createClient } from "jsr:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const VAPID_PUBLIC_KEY = "BBOV4d9tJmk-RNq3XEHlGd-4m70cNYHJawCWqyoYiN_ZPREFW8Ja0Wb-s1cs-2gruld1fIoyp-4rJxak1v-A1Yw";
const VAPID_SUBJECT = "https://www.shahinaahmed.co.uk";

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

type PushItem = { id: number; title: string; body: string; url: string; tag: string | null; subs: { id: number; endpoint: string; p256dh: string; auth: string }[] };

// Web push to the Studio phones. Never throws: a push problem must not stop the SMS part.
// deno-lint-ignore no-explicit-any
async function drainPush(db: { rpc: (fn: string, args?: Record<string, unknown>) => Promise<{ data: any; error: { message: string } | null }> }) {
  const priv = Deno.env.get("VAPID_PRIVATE_KEY");
  if (!priv) return { configured: false };
  try {
    webpush.setVapidDetails(VAPID_SUBJECT, VAPID_PUBLIC_KEY, priv);
    const { data, error } = await db.rpc("push_claim", { p_limit: 10 });
    if (error) return { configured: true, error: "claim_failed", detail: error.message };
    let sent = 0, failed = 0;
    for (const it of (data ?? []) as PushItem[]) {
      const payload = JSON.stringify({ title: it.title, body: it.body, url: it.url, tag: it.tag });
      const results = await Promise.all(it.subs.map(async (sub) => {
        try {
          const r = await webpush.sendNotification(
            { endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } },
            payload, { TTL: 6 * 3600, urgency: "high", timeout: 10000 });
          return { sub_id: sub.id, status: r.statusCode };
        } catch (e) {
          const err = e as { statusCode?: number; body?: string; message?: string };
          return { sub_id: sub.id, status: err.statusCode ?? null, error: String(err.body || err.message || "error").slice(0, 200) };
        }
      }));
      if (results.some((r) => r.status !== null && r.status >= 200 && r.status < 300)) sent++; else failed++;
      const { error: e2 } = await db.rpc("push_complete", { p_id: it.id, p_results: results });
      if (e2) console.error("push_complete_failed", it.id, e2.message);
    }
    return { configured: true, claimed: (data ?? []).length, sent, failed };
  } catch (e) {
    console.error("push_failed", (e as Error).message);
    return { configured: true, error: "push_exception", detail: (e as Error).message.slice(0, 200) };
  }
}

Deno.serve(async () => {
  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });
  const push = await drainPush(db);

  const jwt = Deno.env.get("SMSWORKS_JWT");
  const sender = Deno.env.get("SMS_SENDER");
  if (!jwt || !sender) return Response.json({ ok: false, error: "missing_secrets", push }, { status: 500 });

  const { data, error } = await db.rpc("sms_claim", { p_limit: 10 });
  if (error) return Response.json({ ok: false, error: "claim_failed", detail: error.message, push }, { status: 500 });

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

  return Response.json({ ok: true, claimed: (data ?? []).length, ...counts, push });
});
