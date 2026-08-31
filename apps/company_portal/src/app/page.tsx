import Link from 'next/link';
import { redirect } from 'next/navigation';
import { getUser } from '@/lib/supabase/server';

export default async function Home() {
  const user = await getUser();
  if (user) redirect('/dashboard');

  return (
    <main className="min-h-screen">
      <header className="max-w-5xl mx-auto px-5 sm:px-6 py-5 sm:py-6 flex items-center justify-between gap-3 flex-wrap">
        <div>
          <span className="text-xl font-black tracking-tight text-brand-600">
            Omelo
          </span>
          <span className="text-sm muted ml-2">for employers</span>
        </div>
        <nav className="flex gap-2 sm:gap-3">
          <Link href="/sign-in" className="btn btn-ghost">
            Sign in
          </Link>
          <Link href="/sign-up" className="btn btn-primary">
            Post a job
          </Link>
        </nav>
      </header>

      <section className="max-w-5xl mx-auto px-5 sm:px-6 pt-10 sm:pt-16 pb-16 sm:pb-20">
        <h1 className="text-3xl sm:text-5xl font-black tracking-tight leading-[1.08] sm:leading-[1.05] max-w-2xl">
          Hire the people who are already near you.
        </h1>
        <p className="mt-4 sm:mt-5 text-base sm:text-lg muted max-w-xl leading-relaxed">
          Omelo reaches workers by distance, not by keyword. Post a job in
          minutes — no HR department, no resume screening, no per-applicant
          fees.
        </p>
        <div className="mt-8 flex flex-col sm:flex-row gap-3">
          <Link href="/sign-up" className="btn btn-primary">
            Post a job free
          </Link>
          <Link href="/sign-in" className="btn btn-ghost">
            I already have an account
          </Link>
        </div>

        <div className="mt-14 sm:mt-20 grid gap-5 sm:gap-6 sm:grid-cols-3">
          {[
            {
              t: 'Reach people who can actually get there',
              d: 'Jobs are ranked by real distance from each worker. A cook two kilometres away sees you before one across the city.',
            },
            {
              t: 'Most workers have no resume',
              d: 'Quick apply sends a structured profile instead. You get consistent, comparable information on every candidate.',
            },
            {
              t: 'Candidates see honest progress',
              d: 'Name your pipeline stages however you like. Workers always see the true state — which is why they keep replying.',
            },
          ].map((f) => (
            <div key={f.t} className="card p-5">
              <h3 className="font-bold mb-2 leading-snug">{f.t}</h3>
              <p className="text-sm muted leading-relaxed">{f.d}</p>
            </div>
          ))}
        </div>
      </section>

      <footer className="max-w-5xl mx-auto px-5 sm:px-6 py-10 border-t hairline text-sm muted">
        Omelo — a universal employment platform.
      </footer>
    </main>
  );
}
