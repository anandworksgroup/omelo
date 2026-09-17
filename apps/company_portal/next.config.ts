import type { NextConfig } from "next";

/*
 * Security headers for every response.
 *
 * No Content-Security-Policy yet: the portal talks to Supabase (https + wss
 * Realtime) and LiveKit Cloud (https + wss, URL issued at join time), and a
 * CSP must be verified end-to-end against both before it ships. When added it
 * needs at least: connect-src 'self' https://*.supabase.co wss://*.supabase.co
 * https://*.livekit.cloud wss://*.livekit.cloud.
 *
 * camera/microphone/display-capture are allowed for this origin only, for
 * Omelo Meet interviews.
 */
const securityHeaders = [
  { key: "X-Content-Type-Options", value: "nosniff" },
  { key: "Referrer-Policy", value: "strict-origin-when-cross-origin" },
  { key: "X-Frame-Options", value: "DENY" },
  {
    key: "Permissions-Policy",
    value: "camera=(self), microphone=(self), display-capture=(self), geolocation=()",
  },
  {
    key: "Strict-Transport-Security",
    value: "max-age=63072000; includeSubDomains; preload",
  },
];

const nextConfig: NextConfig = {
  poweredByHeader: false,
  async headers() {
    return [{ source: "/:path*", headers: securityHeaders }];
  },
};

export default nextConfig;
