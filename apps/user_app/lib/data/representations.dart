/// Release 4 — recruiters and agencies, from the worker's side.
///
/// A recruiter can put a worker forward for one job only with the worker's
/// clear yes, for a set time and a set purpose. The recruiter never owns the
/// candidate: the worker sees every request, exactly what would be shared,
/// with whom, for which job and for how long, and can take the yes back
/// while the employer has not started considering them.
///
/// Everything here is pure (no Supabase, no widgets) so it can be tested.
library;

import '../core/format.dart';
import 'invitations.dart' show answerByLabel, shortDate;

// ---------------------------------------------------------------------------
// Status
// ---------------------------------------------------------------------------

/// Mirrors the `status` of `omelo_my_representations()`.
enum RepresentationStatus {
  requested,
  accepted,
  active,
  declined,
  expired,
  revoked,
  withdrawn;

  static RepresentationStatus fromWire(String? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    // Unknown future values: nothing can be done with it.
    return expired;
  }

  /// The worker said yes and it has not ended.
  bool get isRepresented => this == accepted || this == active;
}

/// Mirrors `candidate_submissions.status`.
enum SubmissionStatus {
  submitted,
  reviewing,
  shortlisted,
  interview,
  offer,
  hired,
  rejected,
  withdrawn;

  static SubmissionStatus fromWire(String? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return submitted;
  }

  bool get isClosed => this == rejected || this == withdrawn;
}

// ---------------------------------------------------------------------------
// Terms (what the agency is asking about)
// ---------------------------------------------------------------------------

class RepresentationPay {
  const RepresentationPay({this.min, this.max, this.period, this.currency});
  final num? min;
  final num? max;
  final String? period;
  final String? currency;

  bool get isShown => min != null || max != null;

  factory RepresentationPay.fromJson(dynamic v) {
    if (v is! Map) return const RepresentationPay();
    return RepresentationPay(
      min: _num(v['min']),
      max: _num(v['max']),
      period: _str(v['period']),
      currency: _str(v['currency'])?.trim(),
    );
  }
}

class RepresentationTerms {
  const RepresentationTerms({
    required this.agencyName,
    required this.position,
    required this.clientName,
    this.agencyId,
    this.agencyVerified = false,
    this.agencyIndependent = false,
    this.agencyLogo,
    this.recruiterName,
    this.clientOnOmelo = false,
    this.clientCompanyId,
    this.reference,
    this.openings,
    this.location,
    this.workplaceType,
    this.workType,
    this.shiftTypes = const [],
    this.pay = const RepresentationPay(),
    this.startDate,
    this.closingDate,
    this.hardRequirements = const [],
    this.description,
    this.identityLabel,
  });

  final String? agencyId;
  final String agencyName;
  final bool agencyVerified;

  /// A one-person agency: shown as "Independent recruiter".
  final bool agencyIndependent;
  final String? agencyLogo;
  final String? recruiterName;
  final String clientName;
  final bool clientOnOmelo;
  final String? clientCompanyId;
  final String position;
  final String? reference;
  final int? openings;
  final String? location;
  final String? workplaceType;
  final String? workType;
  final List<String> shiftTypes;
  final RepresentationPay pay;
  final DateTime? startDate;
  final DateTime? closingDate;
  final List<String> hardRequirements;
  final String? description;
  final String? identityLabel;

  factory RepresentationTerms.fromJson(dynamic v) {
    final m = v is Map ? v : const {};
    final agency = m['agency'] is Map ? m['agency'] as Map : const {};
    final recruiter = m['recruiter'] is Map ? m['recruiter'] as Map : const {};
    final client = m['client'] is Map ? m['client'] as Map : const {};
    return RepresentationTerms(
      agencyId: _str(agency['id']),
      agencyName: _str(agency['name']) ?? 'A recruitment agency',
      agencyVerified: agency['verified'] == true,
      agencyIndependent: agency['independent'] == true,
      agencyLogo: _str(agency['logo_url']),
      recruiterName: _str(recruiter['name']),
      clientName: _str(client['name']) ?? 'their client',
      clientOnOmelo: client['on_omelo'] == true,
      clientCompanyId: _str(client['company_id']),
      position: _str(m['position']) ?? 'A job',
      reference: _str(m['reference']),
      openings: _num(m['openings'])?.toInt(),
      location: _str(m['location']),
      workplaceType: _str(m['workplace_type']),
      workType: _str(m['work_type']),
      shiftTypes: _strings(m['shift_types']),
      pay: RepresentationPay.fromJson(m['pay']),
      startDate: _date(m['start_date']),
      closingDate: _date(m['closing_date']),
      hardRequirements: _strings(m['hard_requirements']),
      description: _str(m['description']),
      identityLabel: _str(m['identity_label']),
    );
  }
}

// ---------------------------------------------------------------------------
// Submission and placement
// ---------------------------------------------------------------------------

class RepresentationSubmission {
  const RepresentationSubmission({
    required this.id,
    required this.status,
    this.submittedAt,
    this.applicationId,
  });

  final String id;
  final SubmissionStatus status;
  final DateTime? submittedAt;

  /// Set when the client is on Omelo: a normal application of mine.
  final String? applicationId;

  static RepresentationSubmission? fromJson(dynamic v) {
    if (v is! Map || v['id'] == null) return null;
    return RepresentationSubmission(
      id: v['id'].toString(),
      status: SubmissionStatus.fromWire(_str(v['status'])),
      submittedAt: _date(v['submitted_at']),
      applicationId: _str(v['application_id']),
    );
  }
}

class RepresentationPlacement {
  const RepresentationPlacement({
    required this.id,
    this.status,
    this.startDate,
  });

  final String id;
  final String? status;
  final DateTime? startDate;

  static RepresentationPlacement? fromJson(dynamic v) {
    if (v is! Map || v['id'] == null) return null;
    return RepresentationPlacement(
      id: v['id'].toString(),
      status: _str(v['status']),
      startDate: _date(v['start_date']),
    );
  }
}

// ---------------------------------------------------------------------------
// One representation
// ---------------------------------------------------------------------------

class Representation {
  const Representation({
    required this.id,
    required this.terms,
    required this.status,
    required this.requestedAt,
    this.scope = const ['identity'],
    this.message,
    this.workIdentityId,
    this.identityLabel,
    this.requestExpiresAt,
    this.respondedAt,
    this.expiresAt,
    this.validDays = 60,
    this.declineReason,
    this.revokeReason,
    this.canRevoke = false,
    this.submission,
    this.placement,
  });

  final String id;
  final RepresentationTerms terms;
  final List<String> scope;
  final String? message;
  final String? workIdentityId;
  final String? identityLabel;
  final DateTime requestedAt;

  /// An unanswered request ends here.
  final DateTime? requestExpiresAt;
  final DateTime? respondedAt;

  /// The yes ends here (set by the server when the worker accepts).
  final DateTime? expiresAt;
  final int validDays;
  final String? declineReason;
  final String? revokeReason;

  /// The status as sent by the server. Use [statusAt] for display.
  final RepresentationStatus status;

  /// No submission yet, or the employer has not moved it forward.
  final bool canRevoke;
  final RepresentationSubmission? submission;
  final RepresentationPlacement? placement;

  String get agencyName => terms.agencyName;
  String get position => terms.position;

  /// The status the worker should see now. The server already turns ended
  /// requests into `expired`; this does the same for a list loaded a while
  /// ago, so an old screen never offers "Accept" on a dead request.
  RepresentationStatus statusAt(DateTime now) {
    if (status == RepresentationStatus.requested &&
        requestExpiresAt != null &&
        !requestExpiresAt!.isAfter(now)) {
      return RepresentationStatus.expired;
    }
    if (status == RepresentationStatus.accepted &&
        expiresAt != null &&
        !expiresAt!.isAfter(now)) {
      return RepresentationStatus.expired;
    }
    return status;
  }

  bool isPendingAt(DateTime now) =>
      statusAt(now) == RepresentationStatus.requested;

  /// The newest thing that happened, for "last activity".
  DateTime get lastActivityAt {
    var at = requestedAt;
    for (final d in [respondedAt, submission?.submittedAt]) {
      if (d != null && d.isAfter(at)) at = d;
    }
    return at;
  }

  factory Representation.fromJson(Map<String, dynamic> m) {
    final terms = RepresentationTerms.fromJson(m['terms']);
    return Representation(
      id: m['id'].toString(),
      terms: terms,
      scope: _strings(m['scope']),
      message: _str(m['message']),
      workIdentityId: _str(m['work_identity_id']),
      identityLabel: _str(m['identity_label']) ?? terms.identityLabel,
      requestedAt: _date(m['requested_at']) ?? DateTime.now(),
      requestExpiresAt: _date(m['request_expires_at']),
      respondedAt: _date(m['responded_at']),
      expiresAt: _date(m['expires_at']),
      validDays: _num(m['valid_days'])?.toInt() ?? 60,
      declineReason: _str(m['decline_reason']),
      revokeReason: _str(m['revoke_reason']),
      status: RepresentationStatus.fromWire(_str(m['status'])),
      canRevoke: m['can_revoke'] == true,
      submission: RepresentationSubmission.fromJson(m['submission']),
      placement: RepresentationPlacement.fromJson(m['placement']),
    );
  }

  /// A local answer shown before the list reloads.
  Representation copyWith({
    RepresentationStatus? status,
    bool? canRevoke,
    DateTime? respondedAt,
    DateTime? expiresAt,
  }) => Representation(
    id: id,
    terms: terms,
    scope: scope,
    message: message,
    workIdentityId: workIdentityId,
    identityLabel: identityLabel,
    requestedAt: requestedAt,
    requestExpiresAt: requestExpiresAt,
    respondedAt: respondedAt ?? this.respondedAt,
    expiresAt: expiresAt ?? this.expiresAt,
    validDays: validDays,
    declineReason: declineReason,
    revokeReason: revokeReason,
    status: status ?? this.status,
    canRevoke: canRevoke ?? this.canRevoke,
    submission: submission,
    placement: placement,
  );
}

/// `omelo_my_representations()` → list. Bad rows are skipped, not fatal.
List<Representation> parseRepresentations(dynamic v) {
  if (v is! List) return const [];
  final out = <Representation>[];
  for (final e in v) {
    if (e is! Map || e['id'] == null) continue;
    try {
      out.add(Representation.fromJson(Map<String, dynamic>.from(e)));
    } catch (_) {}
  }
  return out;
}

/// Waiting ones first, then newest. (The server sends this order; the app
/// keeps it after a local change.)
List<Representation> sortRepresentations(
  Iterable<Representation> list,
  DateTime now,
) {
  final out = list.toList();
  out.sort((a, b) {
    final pa = a.isPendingAt(now), pb = b.isPendingAt(now);
    if (pa != pb) return pa ? -1 : 1;
    return b.requestedAt.compareTo(a.requestedAt);
  });
  return out;
}

List<Representation> pendingRepresentations(
  Iterable<Representation> list,
  DateTime now,
) => list.where((r) => r.isPendingAt(now)).toList();

// ---------------------------------------------------------------------------
// Words
// ---------------------------------------------------------------------------

/// Short chip text for each status.
String representationStatusLabel(RepresentationStatus s) => switch (s) {
  RepresentationStatus.requested => 'Waiting for you',
  RepresentationStatus.accepted => 'You said yes',
  RepresentationStatus.active => 'Put forward',
  RepresentationStatus.declined => 'You said no',
  RepresentationStatus.expired => 'Ended',
  RepresentationStatus.revoked => 'You took it back',
  RepresentationStatus.withdrawn => 'Cancelled by agency',
};

String submissionStatusLabel(SubmissionStatus s) => switch (s) {
  SubmissionStatus.submitted => 'Submitted',
  SubmissionStatus.reviewing => 'Reviewing',
  SubmissionStatus.shortlisted => 'Shortlisted',
  SubmissionStatus.interview => 'Interview',
  SubmissionStatus.offer => 'Offer',
  SubmissionStatus.hired => 'Hired',
  SubmissionStatus.rejected => 'Not selected',
  SubmissionStatus.withdrawn => 'Withdrawn',
};

/// "Acme Staffing wants to represent you"
String wantsToRepresentTitle(Representation r) =>
    '${r.agencyName} wants to represent you';

/// Home card title. One request names the agency and the job; several are
/// counted.
String representHomeTitle(List<Representation> pending) {
  if (pending.length == 1) {
    final r = pending.single;
    return '${r.agencyName} wants to represent you for ${r.position}';
  }
  return '${pending.length} agencies want to represent you';
}

/// "₹22,000 / month" · "₹700 – ₹900 / day" · null when pay is not given.
String? representationPayLabel(RepresentationPay p) {
  if (!p.isShown) return null;
  final body = Fmt.pay(min: p.min, max: p.max, currency: p.currency).trim();
  final period = switch (p.period) {
    'hour' => 'hour',
    'day' => 'day',
    'week' => 'week',
    'fortnight' => 'fortnight',
    'month' => 'month',
    'year' => 'year',
    'per_task' => 'task',
    _ => null,
  };
  return period == null ? body : '$body / $period';
}

/// "Full-time · On-site"
String representationTypeLine(RepresentationTerms t) => [
  if (t.workType != null) Fmt.workType(t.workType),
  if (t.workplaceType != null) Fmt.workplace(t.workplaceType),
].where((s) => s.isNotEmpty).join(' · ');

/// "Day shift, Night shift"
String representationShiftLine(RepresentationTerms t) =>
    t.shiftTypes.map(Fmt.shift).join(', ');

/// "Starts 1 Oct"
String? representationStartLine(RepresentationTerms t, DateTime now) =>
    t.startDate == null ? null : 'Starts ${shortDate(t.startDate!, now)}';

/// "3 openings"
String? openingsLine(RepresentationTerms t) {
  final n = t.openings;
  if (n == null || n <= 0) return null;
  return n == 1 ? '1 opening' : '$n openings';
}

/// "Valid for 60 days after you accept"
String durationLine(Representation r) =>
    'Valid for ${r.validDays} day${r.validDays == 1 ? '' : 's'} after you '
    'accept';

/// "You're represented for this job until 17 Nov". Before the server has
/// sent the end date: "... for 60 days".
String representedUntilLine(Representation r, DateTime now) {
  final until = r.expiresAt;
  if (until == null) {
    return "You're represented for this job for ${r.validDays} days";
  }
  return "You're represented for this job until ${shortDate(until, now)}";
}

/// "Answer by 3 Oct" while waiting; null otherwise.
String? representationAnswerBy(Representation r, DateTime now) {
  final at = r.requestExpiresAt;
  if (at == null || !r.isPendingAt(now)) return null;
  return answerByLabel(at, now);
}

/// "Starts 1 Oct" and a plain placement status, or null without one.
String? placementLine(RepresentationPlacement? p, DateTime now) {
  if (p == null) return null;
  final status = switch (p.status) {
    'pending_start' => 'You got the job',
    'active' => 'Working',
    'completed' => 'Finished',
    'fell_through' => 'Did not go ahead',
    _ => 'You got the job',
  };
  if (p.startDate == null) return status;
  return '$status · starts ${shortDate(p.startDate!, now)}';
}

// ---------------------------------------------------------------------------
// What will be shared
// ---------------------------------------------------------------------------

/// Everything an agency could ever ask to share, in reading order.
const kRepresentationScopes = [
  'identity',
  'skills',
  'experience',
  'evidence',
  'answers',
  'contact',
];

class ScopeItem {
  const ScopeItem(this.key, this.label, {required this.shared});
  final String key;
  final String label;
  final bool shared;

  @override
  String toString() => '${shared ? '✓' : '–'} $label';
}

/// The "What will be shared" checklist: every possible item, ticked when
/// the agency asked for it and greyed ("Not shared") when it did not. The
/// profile itself is always shared.
List<ScopeItem> scopeChecklist(
  Iterable<String> scope, {
  String? identityLabel,
}) {
  final asked = scope.toSet()..add('identity');
  final label = identityLabel?.trim();
  final profile = label == null || label.isEmpty
      ? 'Your work profile (name, headline, experience summary)'
      : 'Your $label profile (name, headline, experience summary)';
  return [
    for (final key in kRepresentationScopes)
      ScopeItem(key, switch (key) {
        'identity' => profile,
        'skills' => 'Skills',
        'experience' => 'Work history',
        'evidence' => 'Verified evidence (verified jobs, licences)',
        'answers' => 'Profile answers',
        'contact' =>
          asked.contains('contact')
              ? 'Your phone and email — only after you accept'
              : 'Your phone and email',
        _ => key,
      }, shared: asked.contains(key)),
  ];
}

// ---------------------------------------------------------------------------
// Submission timeline
// ---------------------------------------------------------------------------

enum SubmissionStepState { done, current, upcoming, stopped }

class SubmissionStep {
  const SubmissionStep(this.label, this.state);
  final String label;
  final SubmissionStepState state;

  @override
  String toString() => '$label:${state.name}';
}

const _pipeline = [
  SubmissionStatus.submitted,
  SubmissionStatus.reviewing,
  SubmissionStatus.shortlisted,
  SubmissionStatus.interview,
  SubmissionStatus.offer,
  SubmissionStatus.hired,
];

/// Submitted → Reviewing → Shortlisted → Interview → Offer → Hired. A closed
/// submission shows Submitted, then how it ended ("Not selected" or
/// "Withdrawn"), because the steps in between are not known.
List<SubmissionStep> submissionTimeline(SubmissionStatus s) {
  if (s.isClosed) {
    return [
      const SubmissionStep('Submitted', SubmissionStepState.done),
      SubmissionStep(submissionStatusLabel(s), SubmissionStepState.stopped),
    ];
  }
  final at = _pipeline.indexOf(s);
  return [
    for (var i = 0; i < _pipeline.length; i++)
      SubmissionStep(
        submissionStatusLabel(_pipeline[i]),
        i < at
            ? SubmissionStepState.done
            : i == at
            ? (s == SubmissionStatus.hired
                  ? SubmissionStepState.done
                  : SubmissionStepState.current)
            : SubmissionStepState.upcoming,
      ),
  ];
}

// ---------------------------------------------------------------------------
// What the worker can do
// ---------------------------------------------------------------------------

class RepresentationActions {
  const RepresentationActions({
    this.canAccept = false,
    this.canDecline = false,
    this.canRevoke = false,
    this.canViewApplication = false,
    this.headline,
    this.note,
  });

  final bool canAccept;
  final bool canDecline;
  final bool canRevoke;
  final bool canViewApplication;

  /// The one line that says where things stand, when represented.
  final String? headline;

  /// One plain sentence about what happens now.
  final String? note;

  bool get isAnswerable => canAccept || canDecline;
}

/// The server says revoking is no longer possible (the employer has moved
/// the application on). Shown with a way to the application instead.
const kRevokeBlockedMessage =
    'The employer is already considering you through this agency. To stop, '
    'withdraw your application.';

RepresentationActions representationActions(Representation r, DateTime now) {
  final app = r.submission?.applicationId;
  final hasApp = app != null;
  switch (r.statusAt(now)) {
    case RepresentationStatus.requested:
      return const RepresentationActions(canAccept: true, canDecline: true);
    case RepresentationStatus.accepted:
    case RepresentationStatus.active:
      final sub = r.submission;
      final String note;
      if (sub == null) {
        note =
            '${r.agencyName} can now put you forward to '
            '${r.terms.clientName}. You will see it here when they do.';
      } else if (!r.canRevoke && !sub.status.isClosed) {
        note = kRevokeBlockedMessage;
      } else if (sub.status.isClosed) {
        note = sub.status == SubmissionStatus.rejected
            ? '${r.terms.clientName} did not choose you this time. This is '
                  'one job, not a verdict.'
            : 'This submission was withdrawn.';
      } else {
        note = '${r.agencyName} put you forward to ${r.terms.clientName}.';
      }
      return RepresentationActions(
        canRevoke: r.canRevoke,
        canViewApplication: hasApp,
        headline: representedUntilLine(r, now),
        note: note,
      );
    case RepresentationStatus.declined:
      return RepresentationActions(
        note:
            'You said no. ${r.agencyName} has been told and cannot put '
            'you forward for this job.',
      );
    case RepresentationStatus.expired:
      return RepresentationActions(
        canViewApplication: hasApp,
        note: r.respondedAt == null
            ? 'This request ended before you answered. The agency cannot '
                  'put you forward.'
            : 'Your yes for this job has ended. The agency can no longer '
                  'put you forward.',
      );
    case RepresentationStatus.revoked:
      return RepresentationActions(
        canViewApplication: hasApp,
        note:
            'You took back your yes. ${r.agencyName} can no longer put you '
            'forward for this job.',
      );
    case RepresentationStatus.withdrawn:
      return const RepresentationActions(
        note:
            'The agency cancelled this request. You do not need to do '
            'anything.',
      );
  }
}

/// What revoking does, said before the worker confirms.
const kRevokeEffect =
    'The agency can no longer submit you. If you were already submitted and '
    'the employer has not reviewed it yet, your application is withdrawn.';

/// True when a revoke failed because the employer is already considering
/// the worker (the application must be withdrawn instead).
bool isRevokeBlockedError(Object e) {
  final text = _errorText(e).toLowerCase();
  return text.contains('already considering you') ||
      text.contains('withdraw your application');
}

String _errorText(Object e) {
  try {
    // PostgrestException and friends carry `message`.
    final m = (e as dynamic).message;
    if (m is String) return m;
  } catch (_) {}
  return e.toString();
}

// ---------------------------------------------------------------------------
// Decline
// ---------------------------------------------------------------------------

/// "No thanks" reasons, in the words workers use.
enum RepresentationDeclineReason {
  notInterested('Not interested in this job'),
  payTooLow('Pay too low'),
  tooFar('Too far'),
  noAgency("Don't want an agency"),
  other('Other');

  const RepresentationDeclineReason(this.label);
  final String label;
}

const kRepresentationReasonMax = 300;

/// The reason text sent with a decline, or null for none. A chip sends its
/// label; "Other" sends what the worker typed (or "Other"). Trimmed, at
/// most 300 characters.
String? representationDeclineText(
  RepresentationDeclineReason? reason, [
  String? otherText,
]) {
  if (reason == null) return null;
  String text;
  if (reason == RepresentationDeclineReason.other) {
    final typed = (otherText ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
    text = typed.isEmpty ? reason.label : typed;
  } else {
    text = reason.label;
  }
  return text.length > kRepresentationReasonMax
      ? text.substring(0, kRepresentationReasonMax)
      : text;
}

/// Parameters for `omelo_respond_to_representation` (yes).
Map<String, Object?> acceptRepresentationPayload(String consentId) => {
  'p_consent': consentId,
  'p_accept': true,
};

/// Parameters for `omelo_respond_to_representation` (no).
Map<String, Object?> declineRepresentationPayload(
  String consentId,
  RepresentationDeclineReason? reason, [
  String? otherText,
]) => {
  'p_consent': consentId,
  'p_accept': false,
  'p_reason': representationDeclineText(reason, otherText),
};

/// Parameters for `omelo_revoke_representation`.
Map<String, Object?> revokeRepresentationPayload(
  String consentId, [
  String? reason,
]) {
  final text = reason?.replaceAll(RegExp(r'\s+'), ' ').trim();
  return {
    'p_consent': consentId,
    'p_reason': text == null || text.isEmpty
        ? null
        : (text.length > kRepresentationReasonMax
              ? text.substring(0, kRepresentationReasonMax)
              : text),
  };
}

// ---------------------------------------------------------------------------
// Agencies I know
// ---------------------------------------------------------------------------

class AgencySummary {
  const AgencySummary({
    required this.key,
    required this.name,
    required this.verified,
    required this.independent,
    required this.logoUrl,
    required this.representations,
    required this.now,
  });

  /// Agency id, or its name when the id is missing.
  final String key;
  final String name;
  final bool verified;
  final bool independent;
  final String? logoUrl;

  /// Newest first.
  final List<Representation> representations;
  final DateTime now;

  int get opportunities => representations.length;
  int get activeCount =>
      representations.where((r) => r.statusAt(now).isRepresented).length;
  int get pendingCount =>
      representations.where((r) => r.isPendingAt(now)).length;
  DateTime get lastActivityAt => representations
      .map((r) => r.lastActivityAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
}

/// Groups representations by agency, most recent activity first.
List<AgencySummary> groupByAgency(Iterable<Representation> list, DateTime now) {
  final by = <String, List<Representation>>{};
  for (final r in list) {
    (by[agencyKey(r)] ??= []).add(r);
  }
  final out = [
    for (final e in by.entries)
      AgencySummary(
        key: e.key,
        name: e.value.first.terms.agencyName,
        verified: e.value.any((r) => r.terms.agencyVerified),
        independent: e.value.first.terms.agencyIndependent,
        logoUrl: e.value.first.terms.agencyLogo,
        representations: e.value
          ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt)),
        now: now,
      ),
  ];
  out.sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
  return out;
}

String agencyKey(Representation r) => r.terms.agencyId ?? r.terms.agencyName;

/// "2 jobs · 1 active"
String agencyCountsLine(AgencySummary a) {
  final parts = [
    a.opportunities == 1 ? '1 job' : '${a.opportunities} jobs',
    if (a.pendingCount > 0) '${a.pendingCount} waiting',
    if (a.activeCount > 0) '${a.activeCount} active',
  ];
  return parts.join(' · ');
}

/// application id → agency name, for "Submitted by Acme Staffing".
Map<String, String> agencyByApplication(Iterable<Representation> list) => {
  for (final r in list)
    if (r.submission?.applicationId != null)
      r.submission!.applicationId!: r.agencyName,
};

/// Route for the list, optionally one agency only.
String representationsRoute({String? agency}) => agency == null
    ? '/representations'
    : Uri(
        path: '/representations',
        queryParameters: {'agency': agency},
      ).toString();

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

List<String> _strings(dynamic v) => v is List
    ? [
        for (final e in v)
          if (e != null && e.toString().trim().isNotEmpty) e.toString().trim(),
      ]
    : const [];
