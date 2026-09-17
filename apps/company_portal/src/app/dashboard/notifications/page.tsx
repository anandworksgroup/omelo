import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import { getUser } from '@/lib/supabase/server';
import NotificationList from '@/components/notifications/notification-list';

export const metadata: Metadata = { title: 'Notifications · Omelo for Employers' };

export default async function NotificationsPage() {
  const user = await getUser();
  if (!user) notFound();

  return (
    <div className="max-w-3xl space-y-4">
      <div>
        <h1 className="text-xl sm:text-2xl font-bold">Notifications</h1>
        <p className="text-sm muted mt-1">Candidate replies, interview updates and offer responses.</p>
      </div>
      <NotificationList personId={user.id} />
    </div>
  );
}
