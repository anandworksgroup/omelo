// meet-control — host actions that must reach the media server.
//
// POST { interview_id, action: "remove", person_id, reason? }
// POST { interview_id, action: "end" }
//
// The database call runs AS THE USER and does the authorisation, state
// change and audit. Only then is LiveKit told to eject the participant or
// close the room. If the media server is not configured the database change
// still stands (removed people cannot get a new token anyway).
//
// Admit / deny / leave do not need the media server; apps call those RPCs
// directly.

import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, dbError, json } from "../_shared/http.ts";
import { deleteRoom, liveKitConfig, removeParticipant } from "../_shared/livekit.ts";

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "Sign in required", code: "unauthenticated" }, 401);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid request" }, 400);
  }
  const interviewId = String(body.interview_id ?? "");
  const action = body.action;
  if (!UUID.test(interviewId) || (action !== "remove" && action !== "end")) {
    return json({ error: "Invalid request" }, 400);
  }

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const cfg = liveKitConfig((k) => Deno.env.get(k));

  if (action === "remove") {
    const personId = String(body.person_id ?? "");
    if (!UUID.test(personId)) return json({ error: "Invalid request" }, 400);
    const { data: room, error } = await supabase.rpc("omelo_meet_remove", {
      p_interview_id: interviewId,
      p_person_id: personId,
      p_reason: typeof body.reason === "string" ? body.reason.slice(0, 500) : null,
    });
    if (error) return dbError(error);
    let media = "skipped";
    if (cfg && room) {
      try {
        await removeParticipant(cfg, String(room), personId);
        media = "removed";
      } catch (e) {
        media = `error: ${(e as Error).message}`;
      }
    }
    return json({ ok: true, media });
  }

  const { data: room, error } = await supabase.rpc("omelo_meet_end", { p_interview_id: interviewId });
  if (error) return dbError(error);
  let media = "skipped";
  if (cfg && room) {
    try {
      await deleteRoom(cfg, String(room));
      media = "closed";
    } catch (e) {
      media = `error: ${(e as Error).message}`;
    }
  }
  return json({ ok: true, media });
});
