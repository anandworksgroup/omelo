/**
 * Formatting shared with the Flutter app's `Fmt`.
 *
 * The rule from docs/00 PR-6: money is NEVER a bare number. Amount, currency
 * and period always travel together. If these two implementations drift, an
 * employer and a worker will read the same job differently.
 */

const PERIOD_LABEL: Record<string, string> = {
  hour: '/hour',
  day: '/day',
  week: '/week',
  fortnight: '/fortnight',
  month: '/month',
  year: '/year',
  per_task: 'per task',
};

const SYMBOL: Record<string, string> = {
  INR: '₹',
  USD: '$',
  EUR: '€',
  GBP: '£',
  AED: 'AED ',
  SGD: 'S$',
  AUD: 'A$',
  CAD: 'C$',
};

function amount(value: number, currency: string) {
  const locale = currency === 'INR' ? 'en-IN' : 'en-US';
  return new Intl.NumberFormat(locale, { maximumFractionDigits: 0 }).format(
    Math.round(value)
  );
}

export function formatPay(opts: {
  min?: number | null;
  max?: number | null;
  currency?: string | null;
  period?: string | null;
  negotiable?: boolean | null;
}): string {
  const { min, max, currency, period, negotiable } = opts;
  if (min == null && max == null) return 'Pay not shown';
  const cur = currency ?? 'INR';
  const sym = SYMBOL[cur] ?? `${cur} `;
  const suffix = period ? (PERIOD_LABEL[period] ?? '') : '';

  const body =
    min != null && max != null && max !== min
      ? `${sym}${amount(min, cur)} – ${sym}${amount(max, cur)}`
      : `${sym}${amount((min ?? max)!, cur)}`;

  const sep = suffix.startsWith('/') ? '' : ' ';
  return `${body}${sep}${suffix}${negotiable ? ' · negotiable' : ''}`;
}

/** Pay periods converted to a monthly figure, mirroring omelo_pay_monthly(). */
export function payMonthly(value: number | null, period: string | null) {
  if (value == null || !period) return null;
  switch (period) {
    case 'hour':
      return value * 8 * 26;
    case 'day':
      return value * 26;
    case 'week':
      return value * 4.333;
    case 'fortnight':
      return value * 2;
    case 'month':
      return value;
    case 'year':
      return value / 12;
    default:
      return null;
  }
}

export function timeAgo(iso: string | null): string {
  if (!iso) return '';
  const then = new Date(iso).getTime();
  const days = Math.floor((Date.now() - then) / 86_400_000);
  if (days <= 0) return 'today';
  if (days === 1) return 'yesterday';
  if (days < 7) return `${days} days ago`;
  if (days < 14) return 'last week';
  if (days < 60) return `${Math.floor(days / 7)} weeks ago`;
  return `${Math.floor(days / 30)} months ago`;
}

export const WORK_TYPE_LABEL: Record<string, string> = {
  full_time: 'Full-time',
  part_time: 'Part-time',
  contract: 'Contract',
  freelance: 'Freelance',
  temporary: 'Temporary',
  internship: 'Internship',
  apprenticeship: 'Apprenticeship',
  seasonal: 'Seasonal',
  gig: 'Gig work',
  volunteer: 'Volunteer',
  daily_wage: 'Daily wage',
};

export const WORKPLACE_LABEL: Record<string, string> = {
  onsite: 'On-site',
  hybrid: 'Hybrid',
  remote: 'Remote',
  field_based: 'Field based',
  client_site: 'Client site',
  multiple_sites: 'Multiple sites',
};

export const SHIFT_LABEL: Record<string, string> = {
  day: 'Day',
  evening: 'Evening',
  night: 'Night',
  early_morning: 'Early morning',
  rotating: 'Rotating',
  split: 'Split',
  flexible: 'Flexible',
  weekend: 'Weekend',
  on_call: 'On call',
};

export const BENEFIT_LABEL: Record<string, string> = {
  accommodation: 'Accommodation',
  transport: 'Transport',
  meals: 'Meals',
  health_insurance: 'Health insurance',
  life_insurance: 'Life insurance',
  visa_sponsorship: 'Visa sponsorship',
  flight_tickets: 'Flight tickets',
  relocation_assistance: 'Relocation help',
  bonus: 'Bonus',
  overtime_pay: 'Overtime pay',
  tips: 'Tips',
  commission: 'Commission',
  paid_leave: 'Paid leave',
  sick_leave: 'Sick leave',
  parental_leave: 'Parental leave',
  training: 'Training',
  equipment_provided: 'Equipment provided',
  uniform_provided: 'Uniform provided',
  childcare: 'Childcare',
  retirement: 'Retirement',
  stock_options: 'Stock options',
  gym: 'Gym',
};

/** Candidate-visible application states, in pipeline order. */
export const STATE_LABEL: Record<string, string> = {
  applied: 'Applied',
  viewed: 'Viewed',
  shortlisted: 'Shortlisted',
  screening: 'Screening',
  assessment: 'Assessment',
  interview: 'Interview',
  offer: 'Offer',
  hired: 'Hired',
  rejected: 'Not moving forward',
  withdrawn: 'Withdrawn',
  expired: 'Expired',
  declined_by_candidate: 'Declined by candidate',
};

export function experienceLabel(
  minMonths: number | null,
  acceptsNone: boolean
): string {
  if (acceptsNone || !minMonths) return 'No experience needed';
  if (minMonths < 12) return `${minMonths} months experience`;
  const years = Math.floor(minMonths / 12);
  return `${years}+ year${years === 1 ? '' : 's'} experience`;
}
