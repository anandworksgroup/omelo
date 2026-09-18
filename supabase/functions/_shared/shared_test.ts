// Unit tests for the shared Edge Function modules.
//   deno test supabase/functions/_shared/shared_test.ts
import { assert, assertEquals } from "jsr:@std/assert@1";
import { liveKitConfig, signAccessToken } from "./livekit.ts";
import { renderEmail } from "./email-templates.ts";

const cfg = { url: "wss://example.livekit.cloud", apiKey: "APIkey123", apiSecret: "s3cr3t-very-long-secret-value-for-test" };

function b64urlDecode(s: string): Uint8Array {
  const b64 = s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4);
  return Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
}

Deno.test("liveKitConfig is null until all three secrets exist", () => {
  assertEquals(liveKitConfig(() => undefined), null);
  assertEquals(liveKitConfig((k) => (k === "LIVEKIT_URL" ? "wss://x" : undefined)), null);
});

Deno.test("access token is a valid HS256 JWT scoped to one room", async () => {
  const { token, expiresAt } = await signAccessToken(cfg, {
    identity: "user-1", name: "Ravi", ttlSeconds: 600,
    grant: { room: "om-abc", roomJoin: true, canPublish: true, canSubscribe: true },
  });
  const [h, p, s] = token.split(".");
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(cfg.apiSecret),
    { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  assert(await crypto.subtle.verify("HMAC", key, b64urlDecode(s), new TextEncoder().encode(`${h}.${p}`)));
  const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(p)));
  assertEquals(claims.iss, "APIkey123");
  assertEquals(claims.sub, "user-1");
  assertEquals(claims.video.room, "om-abc");
  assert(!claims.video.roomAdmin);
  assertEquals(claims.exp, expiresAt);
  assert(claims.exp - Math.floor(Date.now() / 1000) <= 600);
});

const links = { workerAppUrl: "https://app.omelo.com/#" };
const payload = {
  job_title: "Cook", company_name: "Spice <script>x</script> Route", round_name: "Technical Interview",
  meeting_mode: "omelo_meet", scheduled_at: "2026-09-25T05:30:00Z", duration_minutes: 60, timezone: "Asia/Kolkata",
  room_name: "om-" + "a".repeat(36), application_id: "app-1", instructions: "Bring ID", lead: "1h",
  previous_scheduled_at: "2026-09-24T05:30:00Z", cancel_reason: "Role filled", title: "Cook",
  pay_amount: 22000, pay_currency: "INR", pay_period: "month", start_date: "2026-10-01",
  expires_at: "2026-09-30T00:00:00Z", preview: "Can you <b>come</b> Friday?", conversation_id: "c-1",
  code: "<i>123456</i>", scheduled_for: "2026-10-02T00:00:00Z",
};

for (const t of ["verify_email", "account_deletion_scheduled", "interview_invitation", "next_round_invitation", "interview_rescheduled", "interview_cancelled",
                 "interview_reminder", "interview_completed", "offer_received", "new_message"]) {
  Deno.test(`email ${t} renders and escapes HTML`, () => {
    const r = renderEmail(t, payload, links);
    assert(r && r.html.length > 200 && r.text.length > 20);
    assert(!r.html.includes("<script>") && !r.html.includes("<b>come") && !r.html.includes("<i>123456"));
  });
}

Deno.test("invitation deep-links into Omelo Meet, never a third-party tool", () => {
  const r = renderEmail("interview_invitation", payload, links)!;
  assert(r.html.includes(`https://app.omelo.com/#/meet/om-${"a".repeat(36)}`));
  assert(!/zoom\.us|meet\.google|teams\.microsoft/.test(r.html));
  assert(r.text.includes("11:00"));
});

Deno.test("unknown template renders nothing", () => {
  assertEquals(renderEmail("nope", payload, links), null);
});
