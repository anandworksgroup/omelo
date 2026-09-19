import { redirect } from 'next/navigation';

/** "Global" in the menu opens the country guides. */
export default function GlobalPage() {
  redirect('/dashboard/global/countries');
}
