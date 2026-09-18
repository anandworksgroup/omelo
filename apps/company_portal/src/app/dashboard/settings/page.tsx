import type { Metadata } from 'next';
import { createClient } from '@/lib/supabase/server';
import { asTrustStatus, deviceLabel, relativeTime } from '@/lib/account';
import { reportError } from '@/lib/observability';
import PasswordForm from '@/components/account/password-form';
import Verification from './verification';
import Sessions, { type SessionRow } from './sessions';
import DeleteAccount from './delete-account';

export const metadata: Metadata = { title: 'Account settings · Omelo for Employers' };

function Section({
  id,
  title,
  description,
  children,
}: {
  id: string;
  title: string;
  description?: string;
  children: React.ReactNode;
}) {
  return (
    <section id={id} className="card p-5 sm:p-6 scroll-mt-6" aria-labelledby={`${id}-title`}>
      <h2 id={`${id}-title`} className="text-lg font-bold">
        {title}
      </h2>
      {description && <p className="text-sm muted mt-1">{description}</p>}
      <div className="mt-3">{children}</div>
    </section>
  );
}

export default async function SettingsPage() {
  const supabase = await createClient();
  const [trustRes, sessionsRes] = await Promise.all([
    supabase.rpc('omelo_my_trust_status'),
    supabase.rpc('omelo_my_sessions'),
  ]);
  if (trustRes.error) throw trustRes.error;
  if (sessionsRes.error) reportError(sessionsRes.error, { action: 'settings.sessions' });

  const trust = asTrustStatus(trustRes.data);
  if (!trust) throw new Error('Account status is unavailable.');

  // This device first, then most recently active.
  const sessions: SessionRow[] = [...(sessionsRes.data ?? [])]
    .sort(
      (a, b) =>
        Number(b.is_current) - Number(a.is_current) ||
        new Date(b.last_active_at).getTime() - new Date(a.last_active_at).getTime()
    )
    .map((s) => ({
      id: s.id,
      device: deviceLabel(s.user_agent),
      lastActive: relativeTime(s.last_active_at),
      ipHint: s.ip_hint || null,
      isCurrent: s.is_current,
    }));

  return (
    <div className="max-w-2xl space-y-5">
      <div>
        <h1 className="text-2xl font-bold">Account settings</h1>
        <p className="text-sm muted mt-1">Your own sign-in and account. Company details are under Company.</p>
      </div>

      <Section
        id="verification"
        title="Verification"
        description="A verified email helps workers trust the people who contact them."
      >
        <Verification trust={trust} />
      </Section>

      <Section id="password" title="Change password">
        <PasswordForm mode="settings" />
      </Section>

      <Section
        id="sessions"
        title="Where you are signed in"
        description="Sign out of any device you do not recognise."
      >
        {sessionsRes.error ? (
          <p className="text-sm muted">Your sessions could not be loaded. Reload the page to try again.</p>
        ) : (
          <Sessions sessions={sessions} />
        )}
      </Section>

      <Section id="delete" title="Delete account">
        <DeleteAccount scheduledFor={trust.deletion_scheduled_for} />
      </Section>
    </div>
  );
}
