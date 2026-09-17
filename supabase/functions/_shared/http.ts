// Shared HTTP helpers for Omelo Edge Functions.

export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// PostgREST errors carry the database's own message and SQLSTATE; map the
// ones the hiring functions raise to HTTP statuses the apps can act on.
export function dbError(err: { message?: string; code?: string } | null): Response {
  const code = err?.code ?? "";
  const status = code === "42501" ? 403 : code === "54000" ? 429 : code === "22023" ? 409 : 400;
  return json({ error: err?.message ?? "Request failed", code: code || "db_error" }, status);
}
