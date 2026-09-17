// comms-dispatch — sends due messages from the outbound_messages outbox.
//
// Invoked every minute by pg_cron (migration 30) and safe to invoke at any
// time: it takes no input, only sends messages that are already due, claims
// them with FOR UPDATE SKIP LOCKED, and is idempotent. That is why it does
// not require a JWT.
//
// Provider: Resend (RESEND_API_KEY, EMAIL_FROM). Without a key it reports
// how many emails are waiting and leaves them queued.

import { createClient } from "npm:@supabase/supabase-js@2";
import { json } from "../_shared/http.ts";
import { renderEmail } from "../_shared/email-templates.ts";

Deno.serve(async () => {
  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  const resendKey = Deno.env.get("RESEND_API_KEY");
  if (!resendKey) {
    const { count } = await supabase
      .from("outbound_messages")
      .select("id", { count: "exact", head: true })
      .eq("status", "queued")
      .lte("send_after", new Date().toISOString());
    return json({ configured: false, due: count ?? 0 });
  }

  const from = Deno.env.get("EMAIL_FROM") ?? "Omelo <onboarding@resend.dev>";
  const links = { workerAppUrl: (Deno.env.get("WORKER_APP_URL") ?? "http://localhost:5173/#").replace(/\/+$/, "") };

  const { data: batch, error } = await supabase.rpc("omelo_comms_claim", { p_limit: 25 });
  if (error) return json({ error: error.message }, 500);

  let sent = 0;
  let failed = 0;
  for (const m of (batch ?? []) as Array<Record<string, unknown>>) {
    const rendered = renderEmail(String(m.template), (m.payload ?? {}) as Record<string, unknown>, links);
    if (!rendered || !m.to_address) {
      await supabase.rpc("omelo_comms_mark", { p_id: m.id, p_ok: false, p_error: `no template or address for ${m.template}` });
      failed++;
      continue;
    }
    try {
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${resendKey}`,
          "Content-Type": "application/json",
          "Idempotency-Key": String(m.id),
        },
        body: JSON.stringify({
          from,
          to: [m.to_address],
          subject: m.subject ?? rendered.subject,
          html: rendered.html,
          text: rendered.text,
        }),
      });
      const body = await res.json().catch(() => ({}));
      if (res.ok) {
        await supabase.rpc("omelo_comms_mark", { p_id: m.id, p_ok: true, p_provider_id: body.id ?? null });
        sent++;
      } else {
        await supabase.rpc("omelo_comms_mark", { p_id: m.id, p_ok: false, p_error: `${res.status} ${JSON.stringify(body)}` });
        failed++;
      }
    } catch (e) {
      await supabase.rpc("omelo_comms_mark", { p_id: m.id, p_ok: false, p_error: (e as Error).message });
      failed++;
    }
  }
  return json({ configured: true, claimed: batch?.length ?? 0, sent, failed });
});
