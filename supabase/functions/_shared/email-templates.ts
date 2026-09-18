// Omelo transactional email templates.
//
// Every value from the payload is HTML-escaped. Buttons deep-link into
// Omelo (worker app for candidates), never to a third-party meeting tool.

type Payload = Record<string, unknown>;
export type Rendered = { subject: string; html: string; text: string };
export type Links = { workerAppUrl: string };

const esc = (v: unknown) =>
  String(v ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

function when(p: Payload, key = "scheduled_at"): { date: string; time: string } {
  const raw = p[key];
  if (!raw) return { date: "", time: "" };
  const d = new Date(String(raw));
  const timeZone = typeof p.timezone === "string" && p.timezone ? p.timezone : "Asia/Kolkata";
  try {
    return {
      date: d.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric", timeZone }),
      time: d.toLocaleTimeString("en-GB", { hour: "numeric", minute: "2-digit", hour12: true, timeZone, timeZoneName: "short" }),
    };
  } catch {
    return { date: d.toUTCString(), time: "" };
  }
}

function modeLine(p: Payload): string {
  switch (p.meeting_mode) {
    case "omelo_meet": return "Omelo Meet (video, in your browser or the Omelo app — nothing to install)";
    case "phone": return "Phone call";
    default: return `In person${p.location_text ? ` — ${p.location_text}` : ""}`;
  }
}

function layout(title: string, bodyHtml: string, button?: { label: string; href: string }): string {
  const btn = button
    ? `<p style="margin:28px 0"><a href="${esc(button.href)}" style="background:#0f766e;color:#ffffff;text-decoration:none;padding:12px 22px;border-radius:8px;font-weight:600;display:inline-block">${esc(button.label)}</a></p>`
    : "";
  return `<!doctype html><html><body style="margin:0;background:#f4f5f7;font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#111827">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0"><tr><td align="center" style="padding:24px 12px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:560px;background:#ffffff;border-radius:12px;padding:28px">
<tr><td>
<div style="font-weight:700;font-size:18px;color:#0f766e;margin-bottom:18px">Omelo</div>
<h1 style="font-size:20px;line-height:1.35;margin:0 0 14px">${esc(title)}</h1>
${bodyHtml}
${btn}
<p style="font-size:12px;color:#6b7280;margin-top:28px">You are receiving this because you applied for a job on Omelo. Omelo will never ask you to pay a fee for an interview or a job.</p>
</td></tr></table></td></tr></table></body></html>`;
}

function details(rows: [string, string][]): { html: string; text: string } {
  const filtered = rows.filter(([, v]) => v);
  return {
    html: `<table role="presentation" cellpadding="0" cellspacing="0" style="font-size:15px;line-height:1.6;margin:8px 0">${filtered
      .map(([k, v]) => `<tr><td style="color:#6b7280;padding-right:14px;vertical-align:top">${esc(k)}</td><td>${esc(v)}</td></tr>`)
      .join("")}</table>`,
    text: filtered.map(([k, v]) => `${k}: ${v}`).join("\n"),
  };
}

export function renderEmail(template: string, p: Payload, links: Links): Rendered | null {
  const job = String(p.job_title ?? "the role");
  const company = String(p.company_name ?? "the employer");
  const round = String(p.round_name ?? "Interview");
  const joinUrl = p.room_name ? `${links.workerAppUrl}/meet/${p.room_name}` : null;
  const appUrl = p.application_id ? `${links.workerAppUrl}/applications/${p.application_id}` : links.workerAppUrl;
  const { date, time } = when(p);

  const interviewRows = (): [string, string][] => [
    ["Interview", round],
    ["Date", date],
    ["Time", time],
    ["Duration", p.duration_minutes ? `${p.duration_minutes} minutes` : ""],
    ["Where", modeLine(p)],
    ["Instructions", String(p.instructions ?? "")],
  ];

  switch (template) {
    case "interview_invitation":
    case "next_round_invitation": {
      const next = template === "next_round_invitation";
      const title = next
        ? `You're invited to the next round for ${job} at ${company}`
        : `You have been invited to an interview for ${job} at ${company}`;
      const d = details(interviewRows());
      const button = p.meeting_mode === "omelo_meet" && joinUrl
        ? { label: "Join Interview", href: joinUrl }
        : { label: "View interview details", href: appUrl };
      return {
        subject: next ? `Next round: ${round} — ${job} at ${company}` : `Interview invitation: ${job} at ${company}`,
        html: layout(title, `${d.html}<p style="font-size:15px">Please open Omelo to confirm you can attend.</p>`, button),
        text: `${title}\n\n${d.text}\n\n${button.label}: ${button.href}`,
      };
    }
    case "interview_rescheduled": {
      const prev = when(p, "previous_scheduled_at");
      const title = `Your interview for ${job} at ${company} has a new time`;
      const d = details([...interviewRows(), ["Was", [prev.date, prev.time].filter(Boolean).join(", ")], ["Reason", String(p.reason ?? "")]]);
      const button = { label: "Confirm the new time", href: appUrl };
      return {
        subject: `New time: ${round} — ${job} at ${company}`,
        html: layout(title, d.html, button),
        text: `${title}\n\n${d.text}\n\n${button.label}: ${button.href}`,
      };
    }
    case "interview_cancelled": {
      const title = `Your interview for ${job} at ${company} was cancelled`;
      const d = details([["Interview", round], ["Was", [date, time].filter(Boolean).join(", ")], ["Reason", String(p.cancel_reason ?? "")]]);
      const button = { label: "View your application", href: appUrl };
      return {
        subject: `Interview cancelled: ${job} at ${company}`,
        html: layout(title, d.html, button),
        text: `${title}\n\n${d.text}\n\n${button.label}: ${button.href}`,
      };
    }
    case "interview_reminder": {
      const soon = p.lead === "1h" ? "in 1 hour" : "tomorrow";
      const title = `Reminder: your ${round} with ${company} is ${soon}`;
      const d = details(interviewRows());
      const button = p.meeting_mode === "omelo_meet" && joinUrl
        ? { label: "Join Interview", href: joinUrl }
        : { label: "View interview details", href: appUrl };
      return {
        subject: `Reminder: ${round} with ${company} ${soon}`,
        html: layout(title, `${d.html}<p style="font-size:15px">You can join up to 15 minutes early.</p>`, button),
        text: `${title}\n\n${d.text}\n\n${button.label}: ${button.href}`,
      };
    }
    case "interview_completed": {
      const title = "Interview completed ✓";
      const body = `<p style="font-size:15px;line-height:1.6">Your ${esc(round)} for <b>${esc(job)}</b> at ${esc(company)} has been submitted to the employer.</p>
<p style="font-size:15px;line-height:1.6">Current status: <b>Final review</b>. You will be notified when the employer updates your application.</p>`;
      const button = { label: "View your application", href: appUrl };
      return {
        subject: `Interview completed: ${job} at ${company}`,
        html: layout(title, body, button),
        text: `${title}\n\nYour ${round} for ${job} at ${company} has been submitted to the employer.\nCurrent status: Final review.\n\n${button.href}`,
      };
    }
    case "offer_received": {
      const title = `You received a job offer from ${company}`;
      const start = p.start_date ? new Date(String(p.start_date)).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" }) : "";
      const expires = when(p, "expires_at");
      const pay = p.pay_amount ? `${p.pay_currency ?? ""} ${Number(p.pay_amount).toLocaleString("en-IN")} per ${p.pay_period ?? "month"}`.trim() : "";
      const d = details([["Role", String(p.title ?? job)], ["Pay", pay], ["Start date", start], ["Respond by", expires.date]]);
      const button = { label: "View your offer", href: appUrl };
      return {
        subject: `Job offer: ${p.title ?? job} at ${company}`,
        html: layout(title, d.html, button),
        text: `${title}\n\n${d.text}\n\n${button.label}: ${button.href}`,
      };
    }
    case "new_message": {
      const title = `New message from ${company}`;
      const body = `<p style="font-size:15px;line-height:1.6">About your application for <b>${esc(job)}</b>:</p>
<blockquote style="margin:12px 0;padding:10px 14px;border-left:3px solid #0f766e;background:#f4f5f7;font-size:15px;line-height:1.6">${esc(p.preview)}</blockquote>`;
      const href = p.conversation_id ? `${links.workerAppUrl}/messages/${p.conversation_id}` : appUrl;
      const button = { label: "Reply in Omelo", href };
      return {
        subject: `New message from ${company} about ${job}`,
        html: layout(title, body, button),
        text: `${title}\n\nAbout your application for ${job}:\n"${p.preview ?? ""}"\n\n${button.label}: ${button.href}`,
      };
    }
    case "verify_email": {
      const code = String(p.code ?? "");
      const title = "Your Omelo verification code";
      const body = `<p style="font-size:15px;line-height:1.6">Enter this code in Omelo to verify your email address:</p>
<p style="font-size:32px;font-weight:700;letter-spacing:8px;margin:18px 0">${esc(code)}</p>
<p style="font-size:14px;color:#6b7280">It expires in ${esc(p.expires_minutes ?? 15)} minutes. If you did not ask for this, you can ignore this email.</p>`;
      return {
        subject: title,
        html: layout(title, body),
        text: `${title}: ${code}\n\nIt expires in ${p.expires_minutes ?? 15} minutes. If you did not ask for this, ignore this email.`,
      };
    }
    case "account_deletion_scheduled": {
      const on = p.scheduled_for
        ? new Date(String(p.scheduled_for)).toLocaleDateString("en-GB", { day: "numeric", month: "long", year: "numeric" })
        : "in 14 days";
      const title = "Your Omelo account will be deleted";
      const body = `<p style="font-size:15px;line-height:1.6">You asked us to delete your Omelo account. Your profile, applications and messages will be permanently deleted on <b>${esc(on)}</b>.</p>
<p style="font-size:15px;line-height:1.6">Changed your mind? Open Omelo and cancel the deletion in Settings before then.</p>`;
      return {
        subject: title,
        html: layout(title, body, { label: "Open Settings", href: `${links.workerAppUrl}/settings` }),
        text: `${title}\n\nYour account will be permanently deleted on ${on}. To keep it, cancel in Settings before then: ${links.workerAppUrl}/settings`,
      };
    }
    default:
      return null;
  }
}
