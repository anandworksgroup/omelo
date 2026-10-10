import type { Metadata } from 'next';
import { notFound } from 'next/navigation';
import DashboardNav from '../dashboard/nav';

export const metadata: Metadata = {
  title: 'Design system · Omelo for Employers',
  robots: { index: false, follow: false },
};

/**
 * The portal's design system, on one page.
 *
 * Every screen is built from these pieces (see src/app/globals.css). Having
 * them side by side is how we notice that two things that should match no
 * longer do — a button that drifted, a status colour used for two meanings.
 *
 * Development only: it ships no product data and is not part of the app.
 */
export default function DesignSystem() {
  if (process.env.NODE_ENV === 'production') notFound();

  return (
    <main className="max-w-5xl mx-auto px-5 py-10 space-y-12">
      <header>
        <p className="section-title">Omelo for employers</p>
        <h1 className="mt-1">Design system</h1>
        <p className="muted mt-2 max-w-prose">
          The pieces every screen is built from. Change them in{' '}
          <code className="pill">globals.css</code> and the whole product moves together.
        </p>
      </header>

      <Section title="Colour" note="Brand green carries actions. Status colours mean one thing each.">
        <div className="grid grid-cols-2 sm:grid-cols-5 gap-3">
          {[
            ['brand-600', 'var(--color-brand-600)', 'Actions'],
            ['verified', 'var(--color-verified)', 'Verified, approved'],
            ['accent-500', 'var(--color-accent-500)', 'Match, highlight'],
            ['warn', 'var(--color-warn)', 'Needs attention'],
            ['danger', 'var(--color-danger)', 'Destructive, failed'],
          ].map(([name, value, meaning]) => (
            <div key={name} className="card overflow-hidden">
              <div style={{ background: value, height: 56 }} />
              <div className="p-2.5">
                <p className="text-sm font-semibold">{name}</p>
                <p className="hint">{meaning}</p>
              </div>
            </div>
          ))}
        </div>
      </Section>

      <Section title="Type" note="Headings are tightened and balanced; body text stays at 0.95rem for long reading.">
        <div className="card p-5 space-y-3">
          <h1>Hire the people who are already near you</h1>
          <h2>Candidates waiting on you</h2>
          <h3>Pipeline</h3>
          <p>
            Omelo reaches workers by distance, not by keyword. Body copy sits at a comfortable
            measure so a job description or an offer letter stays readable.
          </p>
          <p className="muted text-sm">Secondary text, used for context under a heading.</p>
          <p className="hint">A hint under a field: what this does and why you would set it.</p>
        </div>
      </Section>

      <Section title="Buttons" note="One primary action per screen. Everything else is quieter than it.">
        <div className="card p-5 space-y-4">
          <div className="flex flex-wrap gap-2 items-center">
            <button className="btn btn-primary">Post a job</button>
            <button className="btn btn-ghost">Save draft</button>
            <button className="btn btn-subtle">Duplicate</button>
            <button className="btn btn-danger">Delete</button>
            <button className="btn btn-quiet">Cancel</button>
            <button className="btn btn-primary" disabled>Disabled</button>
          </div>
          <div className="flex flex-wrap gap-2 items-center">
            <button className="btn btn-sm btn-primary">Small</button>
            <button className="btn btn-primary">Default</button>
            <button className="btn btn-lg btn-primary">Large</button>
            <button className="btn btn-primary"><span className="spinner" /> Working</button>
          </div>
          <p>
            A sentence with an <a className="link" href="#">inline action link</a> inside it.
          </p>
        </div>
      </Section>

      <Section title="Fields">
        <div className="card p-5 grid sm:grid-cols-2 gap-4">
          <div>
            <label className="label" htmlFor="d1">Job title</label>
            <input className="input" id="d1" placeholder="Line cook" />
            <p className="hint">What a worker would call this job, not an internal grade.</p>
          </div>
          <div>
            <label className="label" htmlFor="d2">Workplace</label>
            <select className="input" id="d2" defaultValue="on_site">
              <option value="on_site">On site</option>
              <option value="hybrid">Hybrid</option>
              <option value="remote">Remote</option>
            </select>
          </div>
          <div>
            <label className="label" htmlFor="d3">Pay</label>
            <input className="input" id="d3" aria-invalid="true" defaultValue="-5" />
            <p className="error-text">Pay has to be above zero.</p>
          </div>
          <div>
            <label className="label" htmlFor="d4">Description</label>
            <textarea className="input" id="d4" placeholder="What the work actually involves." />
          </div>
          <label className="flex items-center gap-2 text-sm">
            <input type="checkbox" defaultChecked /> Visa sponsorship available
          </label>
        </div>
      </Section>

      <Section title="Status" note="A pill states a fact. The colour repeats the fact; it never adds a new one.">
        <div className="card p-5 flex flex-wrap gap-2">
          <span className="pill">Draft</span>
          <span className="pill pill-brand">Published</span>
          <span className="pill pill-success"><span className="dot" /> Verified</span>
          <span className="pill pill-info">In review</span>
          <span className="pill pill-warn">Needs approval</span>
          <span className="pill pill-danger">Rejected</span>
          <span className="pill pill-accent">92% match</span>
        </div>
      </Section>

      <Section title="Cards and tables">
        <div className="grid sm:grid-cols-2 gap-4">
          <a href="#" className="card card-interactive p-4 block">
            <div className="flex items-start gap-3">
              <span className="avatar">AR</span>
              <div className="flex-1">
                <p className="font-semibold">Aarti Rao</p>
                <p className="muted text-sm">Line cook · 2.4 km away</p>
                <div className="meter mt-3"><span style={{ width: '82%' }} /></div>
                <p className="hint">82% match — skills, distance and availability</p>
              </div>
            </div>
          </a>
          <div className="card p-0 overflow-hidden">
            <table className="table table-hover">
              <thead>
                <tr><th>Candidate</th><th>Stage</th><th className="table-numeric">Days</th></tr>
              </thead>
              <tbody>
                <tr><td>Aarti Rao</td><td><span className="pill pill-info">Interview</span></td><td className="table-numeric tnum">3</td></tr>
                <tr><td>Sam Oyelaran</td><td><span className="pill">Applied</span></td><td className="table-numeric tnum">11</td></tr>
                <tr><td>Wei Chen</td><td><span className="pill pill-success">Offer</span></td><td className="table-numeric tnum">1</td></tr>
              </tbody>
            </table>
          </div>
        </div>
      </Section>

      <Section
        title="Numbers and rows"
        note="A number that can be acted on is a link and wears the brand wash. A list row lights up rather than fading out."
      >
        <div className="space-y-4">
          <div className="grid grid-cols-2 sm:grid-cols-3 lg:grid-cols-6 gap-3">
            {[
              ['New', 7, true],
              ['Interviews', 2, true],
              ['Published jobs', 4, false],
              ['Applications', 38, false],
              ['Shortlisted', 6, false],
              ['Hired', 1, false],
            ].map(([label, value, lead]) => (
              <a
                key={label as string}
                href="#"
                className="card card-interactive p-4"
                style={lead ? { background: 'var(--brand-wash)', borderColor: 'transparent' } : undefined}
              >
                <div
                  className="text-2xl font-bold tnum"
                  style={lead ? { color: 'var(--brand-ink)' } : undefined}
                >
                  {value as number}
                </div>
                <div className={`text-xs mt-1 ${lead ? '' : 'muted'}`}>{label as string}</div>
              </a>
            ))}
          </div>

          <div className="card divide-y hairline overflow-hidden">
            {[
              ['Line cook', 'Live', 12, 3],
              ['Night warehouse picker', 'Draft', 0, 0],
            ].map(([title, state, apps, unseen]) => (
              <a key={title as string} href="#" className="flex items-center gap-4 p-4 row-link">
                <div className="min-w-0 flex-1">
                  <div className="font-semibold truncate">{title as string}</div>
                  <div className="text-xs muted mt-1 flex items-center gap-2 flex-wrap">
                    {state === 'Live' ? (
                      <span className="pill pill-success"><span className="dot" /> Live</span>
                    ) : (
                      <span className="pill">Draft</span>
                    )}
                    <span>
                      {state === 'Live' ? 'Published 2 days ago · 140 views' : 'Not visible to workers · 0 views'}
                    </span>
                  </div>
                </div>
                {(unseen as number) > 0 && <span className="pill pill-brand">{unseen as number} new</span>}
                <div className="text-right">
                  <div className="font-bold tnum">{apps as number}</div>
                  <div className="text-xs muted">applicants</div>
                </div>
              </a>
            ))}
          </div>
        </div>
      </Section>

      <Section title="Tabs">
        <div className="card p-5">
          <nav className="tabs">
            <span className="tab is-active">All</span>
            <span className="tab">Applied</span>
            <span className="tab">Interviewing</span>
            <span className="tab">Offered</span>
            <span className="tab">Hired</span>
          </nav>
        </div>
      </Section>

      <Section title="Nothing there yet" note="An empty screen still has to say what to do next.">
        <div className="empty">
          <p className="empty-title">No candidates yet</p>
          <p className="empty-body">
            This job went live an hour ago. Workers nearby see it in their feed as they open the
            app — most first applications arrive within a day.
          </p>
          <button className="btn btn-ghost btn-sm mt-1">Share the job</button>
        </div>
      </Section>

      <Section title="Loading" note="A skeleton of the thing that is coming, never a spinner on an empty page.">
        <div className="card p-4 space-y-3">
          <div className="flex gap-3">
            <div className="skeleton rounded-full" style={{ width: 36, height: 36 }} />
            <div className="flex-1 space-y-2">
              <div className="skeleton" style={{ height: 12, width: '40%' }} />
              <div className="skeleton" style={{ height: 12, width: '65%' }} />
            </div>
          </div>
          <div className="skeleton" style={{ height: 12, width: '90%' }} />
          <div className="skeleton" style={{ height: 12, width: '75%' }} />
        </div>
      </Section>

      <Section
        title="Navigation"
        note="Grouped by the job being done. The same list becomes a sheet on a phone."
      >
        <div className="card p-4 flex gap-6">
          {/* A well-formed id that matches nothing, so the unread count asks a
              real question and gets a real empty answer. */}
          <DashboardNav
            companyId="00000000-0000-0000-0000-000000000000"
            isAdmin
            capabilities={{ client_recruitment: true, workforce: true, rpo: true, billing: true }}
          />
          <div className="flex-1 muted text-sm">
            The real component, rendered with a preview workspace. Nothing is marked current here
            because the current page is this one.
          </div>
        </div>
      </Section>

      <Section title="Banners">
        <div className="space-y-2">
          <div className="banner banner-brand px-4 py-2.5">Fresh Foods invited you to join as a recruiter.</div>
          <div className="banner banner-warn px-4 py-2.5">Two timesheets are waiting on your approval.</div>
          <div className="banner banner-danger px-4 py-2.5">Your account will be deleted on 14 November.</div>
        </div>
      </Section>
    </main>
  );
}

function Section({
  title,
  note,
  children,
}: {
  title: string;
  note?: string;
  children: React.ReactNode;
}) {
  return (
    <section className="space-y-3">
      <div>
        <h2>{title}</h2>
        {note && <p className="muted text-sm mt-1">{note}</p>}
      </div>
      {children}
    </section>
  );
}
