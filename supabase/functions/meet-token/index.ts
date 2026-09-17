// meet-token — the only way into an Omelo Meet room.
//
// POST { room_name }  with the user's Supabase JWT.
//
// 1. Calls omelo_meet_join AS THE USER. The database decides everything:
//    who you are to this interview, whether the room is open, whether you
//    wait for the host, whether you were removed. It also writes the audit.
// 2. Only when the answer is `admitted` is a LiveKit token minted:
//    10 minutes, this room only, never stored.
//
// Responses
//   200 { state: "too_early", opens_at, interview }
//   200 { state: "waiting", interview }
//   200 { state: "admitted", url, token, expires_at, role, identity, ... }
//   503 { code: "meet_not_configured" }    media server keys not set yet
//   401/403/409/429 with the database's message

import { createClient } from "npm:@supabase/supabase-js@2";
import { corsHeaders, dbError, json } from "../_shared/http.ts";
import { liveKitConfig, signAccessToken } from "../_shared/livekit.ts";

const TOKEN_TTL_SECONDS = 600;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authorization = req.headers.get("Authorization");
  if (!authorization) return json({ error: "Sign in to join this interview", code: "unauthenticated" }, 401);

  let roomName: unknown;
  try {
    ({ room_name: roomName } = await req.json());
  } catch {
    return json({ error: "Invalid request" }, 400);
  }
  if (typeof roomName !== "string" || !/^om-[0-9a-f]{36}$/.test(roomName)) {
    return json({ error: "Interview not found", code: "not_found" }, 404);
  }

  const supabase = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });

  const { data, error } = await supabase.rpc("omelo_meet_join", { p_room_name: roomName });
  if (error) return dbError(error);

  const join = data as Record<string, unknown>;
  if (join.state !== "admitted") return json(join);

  const cfg = liveKitConfig((k) => Deno.env.get(k));
  if (!cfg) {
    return json({
      ...join,
      state: "unavailable",
      code: "meet_not_configured",
      error: "Omelo Meet video is not switched on for this environment yet.",
    }, 503);
  }

  const role = String(join.role);
  const { token, expiresAt } = await signAccessToken(cfg, {
    identity: String(join.identity),
    name: String(join.display_name ?? "Participant"),
    metadata: JSON.stringify({ role }),
    ttlSeconds: TOKEN_TTL_SECONDS,
    grant: {
      room: roomName,
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
      canUpdateOwnMetadata: false,
      // Moderation goes through meet-control so it is authorised and audited;
      // nobody gets raw media-server admin rights from a client token.
      roomAdmin: false,
    },
  });

  return json({ ...join, url: cfg.url, token, expires_at: new Date(expiresAt * 1000).toISOString() });
});
