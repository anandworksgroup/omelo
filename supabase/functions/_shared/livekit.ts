// LiveKit access tokens and room-service calls, with no SDK dependency.
//
// Uses only Web Crypto + fetch, so the same file runs in Supabase Edge
// Functions (Deno) and in Node 22 for tests. LiveKit is the media layer
// only: who may join, and with which rights, is decided by the Omelo
// database before any token is minted.

export type VideoGrant = {
  room?: string;
  roomJoin?: boolean;
  roomAdmin?: boolean;
  roomCreate?: boolean;
  canPublish?: boolean;
  canSubscribe?: boolean;
  canPublishData?: boolean;
  canUpdateOwnMetadata?: boolean;
  hidden?: boolean;
};

export type LiveKitConfig = { url: string; apiKey: string; apiSecret: string };

export function liveKitConfig(env: (k: string) => string | undefined): LiveKitConfig | null {
  const url = env("LIVEKIT_URL");
  const apiKey = env("LIVEKIT_API_KEY");
  const apiSecret = env("LIVEKIT_API_SECRET");
  if (!url || !apiKey || !apiSecret) return null;
  return { url, apiKey, apiSecret };
}

function base64url(input: Uint8Array | string): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : input;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

export async function signAccessToken(
  cfg: LiveKitConfig,
  opts: { identity: string; name?: string; metadata?: string; ttlSeconds: number; grant: VideoGrant },
): Promise<{ token: string; expiresAt: number }> {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + opts.ttlSeconds;
  const header = { alg: "HS256", typ: "JWT" };
  const payload: Record<string, unknown> = {
    iss: cfg.apiKey,
    sub: opts.identity,
    jti: `${opts.identity}-${now}`,
    nbf: now - 5,
    exp,
    video: opts.grant,
  };
  if (opts.name) payload.name = opts.name;
  if (opts.metadata) payload.metadata = opts.metadata;

  const signingInput = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(payload))}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(cfg.apiSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signingInput)));
  return { token: `${signingInput}.${base64url(sig)}`, expiresAt: exp };
}

function httpUrl(url: string): string {
  return url.replace(/^wss:\/\//, "https://").replace(/^ws:\/\//, "http://").replace(/\/+$/, "");
}

async function roomService(cfg: LiveKitConfig, method: string, body: unknown, grant: VideoGrant) {
  const { token } = await signAccessToken(cfg, { identity: "omelo-control-plane", ttlSeconds: 60, grant });
  const res = await fetch(`${httpUrl(cfg.url)}/twirp/livekit.RoomService/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
    body: JSON.stringify(body),
  });
  // 404 = room or participant already gone, which is the outcome we wanted.
  if (!res.ok && res.status !== 404) {
    throw new Error(`LiveKit ${method} failed: ${res.status} ${await res.text()}`);
  }
}

export function removeParticipant(cfg: LiveKitConfig, room: string, identity: string) {
  return roomService(cfg, "RemoveParticipant", { room, identity }, { roomAdmin: true, room });
}

export function deleteRoom(cfg: LiveKitConfig, room: string) {
  return roomService(cfg, "DeleteRoom", { room }, { roomCreate: true });
}
