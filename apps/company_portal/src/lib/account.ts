/**
 * Account, trust and session helpers shared by the settings page, the
 * dashboard layout (deletion banner) and the admin area.
 */

export type TrustStatus = {
  email: string | null;
  email_verified: boolean;
  phone: string | null;
  phone_verified: boolean;
  identity_verified: boolean;
  verified_employments: number;
  phone_otp_available: boolean;
  email_required_to_accept_offer: boolean;
  deletion_scheduled_for: string | null;
};

export function asTrustStatus(raw: unknown): TrustStatus | null {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const r = raw as Record<string, unknown>;
  return {
    email: typeof r.email === 'string' ? r.email : null,
    email_verified: r.email_verified === true,
    phone: typeof r.phone === 'string' ? r.phone : null,
    phone_verified: r.phone_verified === true,
    identity_verified: r.identity_verified === true,
    verified_employments: Number(r.verified_employments ?? 0) || 0,
    phone_otp_available: r.phone_otp_available === true,
    email_required_to_accept_offer: r.email_required_to_accept_offer === true,
    deletion_scheduled_for: typeof r.deletion_scheduled_for === 'string' ? r.deletion_scheduled_for : null,
  };
}

/**
 * "Chrome on Windows", "Safari on iPhone", "Omelo app on Android".
 * Deliberately coarse: enough to recognise a device, no version noise.
 */
export function deviceLabel(ua: string | null | undefined): string {
  if (!ua) return 'Unknown device';
  const s = ua;

  let os = '';
  if (/iPhone/i.test(s)) os = 'iPhone';
  else if (/iPad/i.test(s)) os = 'iPad';
  else if (/Android/i.test(s)) os = 'Android';
  else if (/Windows/i.test(s)) os = 'Windows';
  else if (/CrOS/i.test(s)) os = 'ChromeOS';
  else if (/Mac OS X|Macintosh/i.test(s)) os = 'macOS';
  else if (/Linux/i.test(s)) os = 'Linux';

  let app = '';
  if (/^Dart\/|dart:io|Flutter/i.test(s)) app = 'Omelo app';
  else if (/Edg(e|A|iOS)?\//i.test(s)) app = 'Edge';
  else if (/OPR\/|Opera/i.test(s)) app = 'Opera';
  else if (/SamsungBrowser/i.test(s)) app = 'Samsung Internet';
  else if (/Firefox\/|FxiOS/i.test(s)) app = 'Firefox';
  else if (/Chrome\/|CriOS/i.test(s)) app = 'Chrome';
  else if (/Safari\//i.test(s)) app = 'Safari';
  else if (/^node|undici|supabase-js|postman|curl/i.test(s)) app = 'API client';

  if (app && os) return `${app} on ${os}`;
  if (app) return app;
  if (os) return `Browser on ${os}`;
  return 'Unknown device';
}

/** Fine-grained relative time for "last active" (minutes, hours, days). */
export function relativeTime(iso: string | null): string {
  if (!iso) return '—';
  const diff = Date.now() - new Date(iso).getTime();
  const min = Math.round(diff / 60_000);
  if (min < 2) return 'Active now';
  if (min < 60) return `${min} minutes ago`;
  const h = Math.round(min / 60);
  if (h < 24) return h === 1 ? '1 hour ago' : `${h} hours ago`;
  const d = Math.round(h / 24);
  if (d < 30) return d === 1 ? 'Yesterday' : `${d} days ago`;
  const m = Math.round(d / 30);
  return m === 1 ? '1 month ago' : `${m} months ago`;
}

/** Whole days from now until an instant (at least 0). */
export function daysUntil(iso: string): number {
  return Math.max(0, Math.ceil((new Date(iso).getTime() - Date.now()) / 86_400_000));
}
