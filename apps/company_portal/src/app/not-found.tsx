import type { Metadata } from 'next';
import Link from 'next/link';

export const metadata: Metadata = {
  title: 'Page not found · Omelo for Employers',
  robots: { index: false, follow: false },
};

export default function NotFound() {
  return (
    <main className="min-h-[70vh] flex items-center justify-center px-5 py-16">
      <div className="max-w-md text-center">
        <Link href="/" className="text-xl font-black tracking-tight text-brand-600">
          Omelo
        </Link>
        <p className="text-5xl font-black mt-8" style={{ color: 'var(--color-brand-600)' }}>
          404
        </p>
        <h1 className="text-xl font-bold mt-3">We could not find that page</h1>
        <p className="muted mt-2 text-sm leading-relaxed">
          The link may be old, or the item may have been removed or belong to another company.
        </p>
        <div className="mt-6 flex gap-3 justify-center flex-wrap">
          <Link href="/dashboard" className="btn btn-primary">
            Go to dashboard
          </Link>
          <Link href="/" className="btn btn-ghost">
            Home
          </Link>
        </div>
      </div>
    </main>
  );
}
