/// Release 3 — invitations to apply, and "who viewed me".
///
/// A verified employer who found one of my visible work identities can invite
/// me to apply to a job. Applying is the answer "yes" (the database marks the
/// invitation applied by itself); "Not interested" is the answer "no".
///
/// Everything here is pure (no Supabase, no widgets) so it can be tested.
library;

import 'package:intl/intl.dart';

// ---------------------------------------------------------------------------
// Invitations
// ---------------------------------------------------------------------------

/// Mirrors the `status` of `omelo_my_invitations()`.
enum InvitationStatus {
  pending,
  applied,
  declined,
  withdrawn,
  expired,
  closed;

  static InvitationStatus fromWire(String? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    // Unknown future values: nothing can be done with it.
    return closed;
  }
}

class JobInvitation {
  const JobInvitation({
    required this.id,
    required this.jobId,
    required this.jobTitle,
    required this.companyName,
    required this.status,
    required this.sentAt,
    this.jobStatus,
    this.companyVerified = false,
    this.companyLogo,
    this.locationText,
    this.workType,
    this.workplaceType,
    this.payMin,
    this.payMax,
    this.payPeriod,
    this.payCurrency,
    this.message,
    this.expiresAt,
    this.viewedAt,
    this.workIdentityId,
    this.identityLabel,
    this.applicationId,
  });

  final String id;
  final String jobId;
  final String jobTitle;
  final String? jobStatus;
  final String companyName;
  final bool companyVerified;
  final String? companyLogo;
  final String? locationText;
  final String? workType;
  final String? workplaceType;
  final num? payMin;
  final num? payMax;
  final String? payPeriod;
  final String? payCurrency;

  /// The employer's own note, if they wrote one.
  final String? message;
  final DateTime sentAt;
  final DateTime? expiresAt;
  final DateTime? viewedAt;

  /// The identity the employer found and invited.
  final String? workIdentityId;
  final String? identityLabel;
  final String? applicationId;
  final InvitationStatus status;

  bool get isPending => status == InvitationStatus.pending;
  bool get isNew => isPending && viewedAt == null;

  factory JobInvitation.fromJson(Map<String, dynamic> m) => JobInvitation(
        id: m['id'].toString(),
        jobId: (m['job_id'] ?? '').toString(),
        jobTitle: _str(m['job_title']) ?? 'A job',
        jobStatus: _str(m['job_status']),
        companyName: _str(m['company_name']) ?? 'An employer',
        companyVerified: m['company_verified'] == true,
        companyLogo: _str(m['company_logo']),
        locationText: _str(m['location_text']),
        workType: _str(m['work_type']),
        workplaceType: _str(m['workplace_type']),
        payMin: _num(m['pay_min']),
        payMax: _num(m['pay_max']),
        payPeriod: _str(m['pay_period']),
        payCurrency: _str(m['pay_currency'])?.trim(),
        message: _str(m['message']),
        sentAt: _date(m['sent_at']) ?? DateTime.now(),
        expiresAt: _date(m['expires_at']),
        viewedAt: _date(m['viewed_at']),
        workIdentityId: _str(m['work_identity_id']),
        identityLabel: _str(m['identity_label']),
        applicationId: _str(m['application_id']),
        status: InvitationStatus.fromWire(_str(m['status'])),
      );

  JobInvitation copyWith({DateTime? viewedAt, InvitationStatus? status}) =>
      JobInvitation(
        id: id,
        jobId: jobId,
        jobTitle: jobTitle,
        jobStatus: jobStatus,
        companyName: companyName,
        companyVerified: companyVerified,
        companyLogo: companyLogo,
        locationText: locationText,
        workType: workType,
        workplaceType: workplaceType,
        payMin: payMin,
        payMax: payMax,
        payPeriod: payPeriod,
        payCurrency: payCurrency,
        message: message,
        sentAt: sentAt,
        expiresAt: expiresAt,
        viewedAt: viewedAt ?? this.viewedAt,
        workIdentityId: workIdentityId,
        identityLabel: identityLabel,
        applicationId: applicationId,
        status: status ?? this.status,
      );
}

/// `omelo_my_invitations()` → list. Bad rows are skipped, not fatal.
List<JobInvitation> parseInvitations(dynamic v) {
  if (v is! List) return const [];
  final out = <JobInvitation>[];
  for (final e in v) {
    if (e is! Map || e['id'] == null) continue;
    try {
      out.add(JobInvitation.fromJson(Map<String, dynamic>.from(e)));
    } catch (_) {}
  }
  return out;
}

/// Pending first, then newest. (The server already sends this order; the
/// app keeps it after a local change.)
List<JobInvitation> sortInvitations(Iterable<JobInvitation> list) {
  final out = list.toList();
  out.sort((a, b) {
    if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
    return b.sentAt.compareTo(a.sentAt);
  });
  return out;
}

int pendingInvitationCount(Iterable<JobInvitation> list) =>
    list.where((i) => i.isPending).length;

/// Home card: "2 employers invited you to apply".
String invitedYouTitle(int pending) => pending == 1
    ? '1 employer invited you to apply'
    : '$pending employers invited you to apply';

/// Short chip text for each status.
String invitationStatusLabel(InvitationStatus s) => switch (s) {
      InvitationStatus.pending => 'Waiting for you',
      InvitationStatus.applied => 'You applied',
      InvitationStatus.declined => 'Not interested',
      InvitationStatus.withdrawn => 'Withdrawn',
      InvitationStatus.expired => 'Expired',
      InvitationStatus.closed => 'Job closed',
    };

/// What the worker can do with one invitation, and what to tell them.
class InvitationActions {
  const InvitationActions({
    this.canApply = false,
    this.canDecline = false,
    this.canViewApplication = false,
    this.note,
  });

  final bool canApply;
  final bool canDecline;
  final bool canViewApplication;

  /// One plain sentence when there is nothing (more) to do.
  final String? note;

  bool get hasAnyAction => canApply || canDecline || canViewApplication;
}

InvitationActions invitationActions(JobInvitation i) {
  switch (i.status) {
    case InvitationStatus.pending:
      // Applied some other way before the server caught up: show that.
      if (i.applicationId != null) {
        return const InvitationActions(
            canViewApplication: true,
            note: 'You have applied to this job.');
      }
      return const InvitationActions(canApply: true, canDecline: true);
    case InvitationStatus.applied:
      return InvitationActions(
        canViewApplication: i.applicationId != null,
        note: 'You applied. The employer can see your application.',
      );
    case InvitationStatus.declined:
      return const InvitationActions(
          note: 'You said you are not interested. The employer has been told.');
    case InvitationStatus.withdrawn:
      return const InvitationActions(
          note: 'The employer took this invitation back. You do not need to '
              'do anything.');
    case InvitationStatus.expired:
      return const InvitationActions(
          note: 'This invitation ended before you answered. You can still '
              'look for similar jobs.');
    case InvitationStatus.closed:
      return const InvitationActions(
          note: 'This job is no longer taking applications.');
  }
}

/// "Answer by 3 Oct" · "Answer by today" · "Answer by tomorrow" ·
/// "Ended on 3 Oct". Null when there is no expiry or it does not apply.
String? expiryLabel(JobInvitation i, DateTime now) {
  final at = i.expiresAt?.toLocal();
  if (at == null) return null;
  switch (i.status) {
    case InvitationStatus.pending:
      return answerByLabel(at, now);
    case InvitationStatus.expired:
      return 'Ended on ${shortDate(at, now)}';
    default:
      return null;
  }
}

String answerByLabel(DateTime expiresAt, DateTime now) {
  final day = DateTime(expiresAt.year, expiresAt.month, expiresAt.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = day.difference(today).inDays;
  if (days <= 0) return 'Answer by today';
  if (days == 1) return 'Answer by tomorrow';
  return 'Answer by ${shortDate(expiresAt, now)}';
}

/// "3 Oct", or "3 Oct 2027" when it is not this year.
String shortDate(DateTime at, DateTime now) => at.year == now.year
    ? DateFormat('d MMM').format(at)
    : DateFormat('d MMM yyyy').format(at);

/// "Invited as your Cook profile".
String invitedAsLine(JobInvitation i) {
  final label = i.identityLabel?.trim();
  if (label == null || label.isEmpty) return 'Invited to apply';
  return 'Invited as your $label profile';
}

/// "Not interested" reasons, in the words workers use.
enum DeclineReason {
  tooFar('Too far'),
  payTooLow('Pay too low'),
  notLooking('Not looking now'),
  other('Other');

  const DeclineReason(this.label);
  final String label;
}

const kDeclineReasonMax = 300;

/// The reason text sent with a decline, or null for none.
///
/// A chip sends its label. "Other" sends what the worker typed (or just
/// "Other" if they typed nothing). Always trimmed and at most 300 characters.
String? declineReasonText(DeclineReason? reason, [String? otherText]) {
  if (reason == null) return null;
  String text;
  if (reason == DeclineReason.other) {
    final typed = (otherText ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    text = typed.isEmpty ? reason.label : typed;
  } else {
    text = reason.label;
  }
  return text.length > kDeclineReasonMax
      ? text.substring(0, kDeclineReasonMax)
      : text;
}

/// Parameters for `omelo_respond_to_invitation`.
Map<String, Object?> declinePayload(String invitationId, DeclineReason? reason,
        [String? otherText]) =>
    {
      'p_invitation': invitationId,
      'p_reason': declineReasonText(reason, otherText),
    };

/// Where "Apply now" goes: the apply flow for the job, with the invited
/// identity chosen.
String invitationApplyRoute(JobInvitation i) => Uri(
      path: '/apply/${i.jobId}',
      queryParameters: {
        if (i.workIdentityId != null) 'identity': i.workIdentityId!,
        'from': 'invitation',
      },
    ).toString();

// ---------------------------------------------------------------------------
// Who viewed me
// ---------------------------------------------------------------------------

/// One row of `omelo_my_profile_views()`: one company, one identity.
class ProfileView {
  const ProfileView({
    required this.companyName,
    required this.views,
    required this.lastViewedAt,
    this.companyVerified = false,
    this.companyLogo,
    this.identityLabel,
  });

  final String companyName;
  final bool companyVerified;
  final String? companyLogo;
  final String? identityLabel;
  final int views;
  final DateTime lastViewedAt;

  factory ProfileView.fromJson(Map<String, dynamic> m) => ProfileView(
        companyName: _str(m['company_name']) ?? 'An employer',
        companyVerified: m['company_verified'] == true,
        companyLogo: _str(m['company_logo']),
        identityLabel: _str(m['identity_label']),
        views: _num(m['views'])?.toInt() ?? 1,
        lastViewedAt: _date(m['last_viewed_at']) ?? DateTime.now(),
      );
}

List<ProfileView> parseProfileViews(dynamic v) {
  if (v is! List) return const [];
  return [
    for (final e in v)
      if (e is Map) ProfileView.fromJson(Map<String, dynamic>.from(e)),
  ];
}

/// One company and every identity of mine it opened.
class CompanyViews {
  const CompanyViews({
    required this.companyName,
    required this.companyVerified,
    required this.companyLogo,
    required this.entries,
  });

  final String companyName;
  final bool companyVerified;
  final String? companyLogo;

  /// Newest first.
  final List<ProfileView> entries;

  DateTime get lastViewedAt => entries.first.lastViewedAt;
  int get totalViews => entries.fold(0, (n, e) => n + e.views);
}

/// Groups rows by company, newest company first.
List<CompanyViews> groupProfileViews(Iterable<ProfileView> rows) {
  final byCompany = <String, List<ProfileView>>{};
  for (final r in rows) {
    final key = '${r.companyName}|${r.companyVerified}|${r.companyLogo}';
    (byCompany[key] ??= []).add(r);
  }
  final out = [
    for (final list in byCompany.values)
      CompanyViews(
        companyName: list.first.companyName,
        companyVerified: list.first.companyVerified,
        companyLogo: list.first.companyLogo,
        entries: list..sort((a, b) => b.lastViewedAt.compareTo(a.lastViewedAt)),
      ),
  ];
  out.sort((a, b) => b.lastViewedAt.compareTo(a.lastViewedAt));
  return out;
}

/// "Your Cook profile · 2 times". Without a label (identity deleted):
/// "Your profile".
String viewedLine(ProfileView v) {
  final label = v.identityLabel?.trim();
  final what = label == null || label.isEmpty
      ? 'Your profile'
      : 'Your $label profile';
  return v.views > 1 ? '$what · ${v.views} times' : what;
}

/// "Today" · "Yesterday" · "3 days ago" · "12 Sep".
String viewedWhen(DateTime at, DateTime now) {
  final day = DateTime(at.year, at.month, at.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(day).inDays;
  if (days <= 0) return 'Today';
  if (days == 1) return 'Yesterday';
  if (days < 7) return '$days days ago';
  return shortDate(at, now);
}

// ---------------------------------------------------------------------------

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.trim().isEmpty ? null : s;
}

num? _num(dynamic v) =>
    v == null ? null : (v is num ? v : num.tryParse(v.toString()));

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();
