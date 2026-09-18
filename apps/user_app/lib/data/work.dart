/// Release 5 — staffing and workforce, from the worker's side.
///
/// Work I was offered or am doing (assignments), my shifts and check-in,
/// time off, timesheets and what I earned. The server owns every rule; the
/// app only explains where things stand in plain, short words.
///
/// Two rules shape this file:
///  * Times are shown in the work site's own time zone (the `timezone` the
///    server sends), never assumed to be the phone's.
///  * Money is always shown in the record's own currency.
///
/// Everything here is pure (no Supabase, no widgets) so it can be tested.
library;

import 'package:intl/intl.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'invitations.dart' show answerByLabel, shortDate;

// ---------------------------------------------------------------------------
// Time zones
// ---------------------------------------------------------------------------

bool _zonesLoaded = false;

/// Loads the time zone database once (about 10 years of rules; small).
void ensureTimeZones() {
  if (_zonesLoaded) return;
  tzdata.initializeTimeZones();
  _zonesLoaded = true;
}

/// The IANA zone ("Asia/Kolkata", "Europe/Berlin"), or null when missing or
/// unknown.
tz.Location? zoneOf(String? name) {
  final n = name?.trim();
  if (n == null || n.isEmpty) return null;
  ensureTimeZones();
  try {
    return tz.getLocation(n);
  } catch (_) {
    return null;
  }
}

/// The instant as a wall clock at the work site shows it. With no known
/// zone, the phone's clock.
DateTime inZone(DateTime at, String? zone) {
  final loc = zoneOf(zone);
  if (loc == null) return at.toLocal();
  return tz.TZDateTime.from(at, loc);
}

/// "10:00 PM"
String clockAt(DateTime at, String? zone) =>
    DateFormat('hh:mm a').format(inZone(at, zone));

/// "10:00 PM – 06:00 AM", in the site's time zone.
String shiftTimeRange(DateTime start, DateTime end, String? zone) =>
    '${clockAt(start, zone)} – ${clockAt(end, zone)}';

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

int _dayDiff(DateTime a, DateTime b) =>
    DateTime.utc(a.year, a.month, a.day)
        .difference(DateTime.utc(b.year, b.month, b.day))
        .inDays;

/// Today's date at the work site.
DateTime siteToday(String? zone, DateTime now) => _dateOnly(inZone(now, zone));

/// The date a shift starts on, at the work site.
DateTime siteDate(DateTime at, String? zone) => _dateOnly(inZone(at, zone));

/// "Today" · "Tomorrow" · "Yesterday" · "Mon 21 Sep", at the work site.
String shiftDayLabel(DateTime start, String? zone, DateTime now) {
  final d = siteDate(start, zone);
  final diff = _dayDiff(d, siteToday(zone, now));
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return DateFormat('EEE d MMM').format(d);
}

/// Said when the site's clock is not the phone's, so "10:00 PM" is never
/// misread: "Times are local to the site (Europe/London)". Null otherwise.
String? zoneNote(DateTime at, String? zone) {
  final loc = zoneOf(zone);
  if (loc == null) return null;
  final site = tz.TZDateTime.from(at, loc).timeZoneOffset;
  if (site == at.toLocal().timeZoneOffset) return null;
  return 'Times are local to the site (${loc.name})';
}

/// "7 h 30 min" · "45 min" · "8 h"
String hoursWords(int minutes) {
  final m = minutes < 0 ? 0 : minutes;
  final h = m ~/ 60, r = m % 60;
  if (h == 0) return '$r min';
  if (r == 0) return '$h h';
  return '$h h $r min';
}

/// "2026-09-21" for the server.
String wireDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

// ---------------------------------------------------------------------------
// Money and pay
// ---------------------------------------------------------------------------

/// "₹1,20,000" · "€1,234.50" · "\$18" · "£980". Always the record's own
/// currency; decimals only when there are some. Unknown or missing
/// currency: the plain number.
String money(num amount, String? currency) {
  final cur = currency?.trim().toUpperCase() ?? '';
  final whole = amount == amount.roundToDouble();
  if (!RegExp(r'^[A-Z]{3}$').hasMatch(cur)) {
    return NumberFormat.decimalPatternDigits(
      locale: 'en',
      decimalDigits: whole ? 0 : 2,
    ).format(amount);
  }
  final f = NumberFormat.simpleCurrency(
    locale: cur == 'INR' ? 'en_IN' : 'en',
    name: cur,
    decimalDigits: whole ? 0 : null,
  );
  return f.format(amount);
}

/// "per hour" · "per day" · "per task"
String payPeriodWords(String? period) => switch (period) {
  'hour' => 'per hour',
  'day' => 'per day',
  'week' => 'per week',
  'fortnight' => 'per fortnight',
  'month' => 'per month',
  'year' => 'per year',
  'per_task' => 'per task',
  _ => '',
};

/// "Paid every week"
String payFrequencyWords(String? f) => switch (f) {
  'daily' => 'Paid every day',
  'weekly' => 'Paid every week',
  'biweekly' => 'Paid every 2 weeks',
  'semimonthly' => 'Paid twice a month',
  'monthly' => 'Paid every month',
  'per_shift' => 'Paid after each shift',
  'on_completion' => 'Paid when the work ends',
  _ => '',
};

class WorkPay {
  const WorkPay({this.rate, this.period, this.frequency, this.currency});
  final num? rate;
  final String? period;
  final String? frequency;
  final String? currency;

  factory WorkPay.fromJson(dynamic v) {
    if (v is! Map) return const WorkPay();
    return WorkPay(
      rate: _num(v['rate']),
      period: _str(v['period']),
      frequency: _str(v['frequency']),
      currency: _str(v['currency'])?.trim(),
    );
  }
}

/// "₹650 per day" · "€14.50 per hour" · "Pay not set"
String payLine(WorkPay p) {
  if (p.rate == null) return 'Pay not set';
  final per = payPeriodWords(p.period);
  final amount = money(p.rate!, p.currency);
  return per.isEmpty ? amount : '$amount $per';
}

// ---------------------------------------------------------------------------
// The agreement (what was offered)
// ---------------------------------------------------------------------------

const kDayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const kDayLong = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// 1 = Monday … 7 = Sunday, sorted, no repeats, nothing else.
List<int> cleanDays(Iterable<dynamic> days) {
  final out = <int>{};
  for (final d in days) {
    final n = d is num ? d.toInt() : int.tryParse(d.toString().trim());
    if (n != null && n >= 1 && n <= 7) out.add(n);
  }
  return out.toList()..sort();
}

/// "Every day" · "Mon–Fri" · "Sat, Sun" · "Mon–Wed, Fri"
String daysLabel(Iterable<int> days) {
  final d = cleanDays(days);
  if (d.isEmpty) return '';
  if (d.length == 7) return 'Every day';
  final parts = <String>[];
  var i = 0;
  while (i < d.length) {
    var j = i;
    while (j + 1 < d.length && d[j + 1] == d[j] + 1) {
      j++;
    }
    if (j - i >= 2) {
      parts.add('${kDayShort[d[i] - 1]}–${kDayShort[d[j] - 1]}');
    } else {
      for (var k = i; k <= j; k++) {
        parts.add(kDayShort[d[k] - 1]);
      }
    }
    i = j + 1;
  }
  return parts.join(', ');
}

/// "22:00" or "22:00:00" → (22, 0). Null when it is not a time.
(int, int)? parseHm(String? v) {
  final m = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(v?.trim() ?? '');
  if (m == null) return null;
  final h = int.parse(m.group(1)!), min = int.parse(m.group(2)!);
  if (h > 23 || min > 59) return null;
  return (h, min);
}

/// "22:00:00" → "10:00 PM"; unknown text comes back as it was.
String wallClock(String? hhmm) {
  final t = parseHm(hhmm);
  if (t == null) return hhmm ?? '';
  return DateFormat('hh:mm a').format(DateTime(2000, 1, 1, t.$1, t.$2));
}

class ShiftPattern {
  const ShiftPattern({
    this.name,
    this.days = const [],
    this.start,
    this.end,
    this.breakMinutes = 0,
  });
  final String? name;
  final List<int> days;
  final String? start;
  final String? end;
  final int breakMinutes;

  factory ShiftPattern.fromJson(Map m) => ShiftPattern(
    name: _str(m['name']),
    days: m['days'] is List ? cleanDays(m['days'] as List) : const [],
    start: _str(m['start']),
    end: _str(m['end']),
    breakMinutes: _num(m['break_minutes'])?.toInt() ?? 0,
  );
}

/// "Mon–Fri · 10:00 PM – 06:00 AM · 30 min break"
String shiftPatternLine(ShiftPattern s) => [
  daysLabel(s.days),
  if (s.start != null && s.end != null)
    '${wallClock(s.start)} – ${wallClock(s.end)}',
  if (s.breakMinutes > 0) '${hoursWords(s.breakMinutes)} break',
].where((x) => x.isNotEmpty).join(' · ');

class Allowance {
  const Allowance({required this.kind, required this.name, this.amount, this.basis});
  final String kind;
  final String name;
  final num? amount;
  final String? basis;

  factory Allowance.fromJson(Map m) => Allowance(
    kind: _str(m['kind']) ?? 'allowance',
    name: _str(m['name']) ?? 'Allowance',
    amount: _num(m['amount']),
    basis: _str(m['basis']),
  );
}

String _basisWords(String? b) => switch (b) {
  'per_hour' => 'per hour',
  'per_shift' => 'per shift',
  'per_day' => 'per day',
  'per_period' => 'per pay period',
  _ => '',
};

/// "Night allowance · ₹100 per shift" · "Deduction: Uniform · €20 per pay
/// period"
String allowanceLine(Allowance a, String? currency) {
  final name = a.kind == 'deduction' ? 'Deduction: ${a.name}' : a.name;
  if (a.amount == null) return name;
  final basis = _basisWords(a.basis);
  final amount = money(a.amount!, currency);
  return '$name · ${basis.isEmpty ? amount : '$amount $basis'}';
}

class OvertimeRule {
  const OvertimeRule({
    this.name,
    this.multiplier,
    this.dailyThresholdMinutes,
    this.weeklyThresholdMinutes,
  });
  final String? name;
  final num? multiplier;
  final int? dailyThresholdMinutes;
  final int? weeklyThresholdMinutes;

  static OvertimeRule? fromJson(dynamic v) {
    if (v is! Map) return null;
    return OvertimeRule(
      name: _str(v['name']),
      multiplier: _num(v['multiplier']),
      dailyThresholdMinutes: _num(v['daily_threshold_minutes'])?.toInt(),
      weeklyThresholdMinutes: _num(v['weekly_threshold_minutes'])?.toInt(),
    );
  }
}

String _plainNumber(num n) =>
    n == n.roundToDouble() ? n.round().toString() : n.toString();

/// "1.5× pay after 8 h a day or 48 h a week"
String overtimeLine(OvertimeRule o) {
  final pay = o.multiplier == null
      ? 'Extra pay'
      : '${_plainNumber(o.multiplier!)}× pay';
  final after = [
    if (o.dailyThresholdMinutes != null)
      '${hoursWords(o.dailyThresholdMinutes!)} a day',
    if (o.weeklyThresholdMinutes != null)
      '${hoursWords(o.weeklyThresholdMinutes!)} a week',
  ];
  return after.isEmpty ? pay : '$pay after ${after.join(' or ')}';
}

String employmentTypeLabel(String? t) => switch (t) {
  'permanent' => 'Permanent',
  'temporary' => 'Temporary',
  'contract' => 'Contract',
  'seasonal' => 'Seasonal',
  'project' => 'Project',
  'gig' => 'Gig',
  'freelance' => 'Freelance',
  'internship' => 'Internship',
  'apprenticeship' => 'Apprenticeship',
  'on_call' => 'On call',
  _ => t ?? '',
};

/// How the worker marks arrival for this work.
String checkInMethodTitle(String? m) => switch (m) {
  'qr' => 'Check in with a code',
  'geofence' => 'Check in at the site',
  'employer' => 'Your supervisor records your arrival',
  _ => 'Check in on the app',
};

String checkInMethodHelp(String? m) => switch (m) {
  'qr' =>
    'Your supervisor shows a 6-digit code at the site. Type it in to check '
        'in.',
  'geofence' =>
    'Check in when you reach the site. The app checks your location once, '
        'only when you tap Check in.',
  'employer' =>
    'You do not need to check in. Your supervisor records when you arrive '
        'and leave.',
  _ => 'Tap Check in when you arrive and Check out when you leave.',
};

class Agreement {
  const Agreement({
    this.employer,
    this.client,
    this.title,
    this.location,
    this.startDate,
    this.endDate,
    this.employmentType,
    this.pay = const WorkPay(),
    this.hoursPerWeek,
    this.shifts = const [],
    this.supervisor,
    this.checkIn,
    this.allowances = const [],
    this.overtime,
  });

  final String? employer;
  final String? client;
  final String? title;
  final String? location;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? employmentType;
  final WorkPay pay;
  final num? hoursPerWeek;
  final List<ShiftPattern> shifts;
  final String? supervisor;
  final String? checkIn;
  final List<Allowance> allowances;
  final OvertimeRule? overtime;

  factory Agreement.fromJson(dynamic v) {
    final m = v is Map ? v : const {};
    return Agreement(
      employer: _str(m['employer']),
      client: _str(m['client']),
      title: _str(m['title']),
      location: _str(m['location']),
      startDate: _day(m['start_date']),
      endDate: _day(m['end_date']),
      employmentType: _str(m['employment_type']),
      pay: WorkPay.fromJson(m['pay']),
      hoursPerWeek: _num(m['hours_per_week']),
      shifts: [
        if (m['shifts'] is List)
          for (final s in m['shifts'] as List)
            if (s is Map) ShiftPattern.fromJson(s),
      ],
      supervisor: _str(m['supervisor']),
      checkIn: _str(m['check_in']),
      allowances: [
        if (m['allowances'] is List)
          for (final a in m['allowances'] as List)
            if (a is Map) Allowance.fromJson(a),
      ],
      overtime: OvertimeRule.fromJson(m['overtime']),
    );
  }
}

// ---------------------------------------------------------------------------
// Assignments
// ---------------------------------------------------------------------------

/// Mirrors the `status` of `omelo_my_assignments()`.
enum AssignmentStatus {
  offered,
  accepted,
  active,
  paused,
  completed,
  declined,
  cancelled,
  terminated;

  static AssignmentStatus fromWire(String? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return cancelled;
  }

  /// Work that is on (or about to be).
  bool get isOngoing => this == accepted || this == active || this == paused;
}

class Assignment {
  const Assignment({
    required this.id,
    required this.status,
    required this.title,
    this.startDate,
    this.endDate,
    this.location,
    this.timezone,
    this.employmentType,
    this.workType,
    this.pay = const WorkPay(),
    this.agreement = const Agreement(),
    this.offerExpiresAt,
    this.endReason,
    this.employer,
    this.employerIsAgency = false,
    this.client,
    this.identityLabel,
    this.nextShift,
    this.verifiedExperience = false,
  });

  final String id;
  final AssignmentStatus status;
  final String title;
  final DateTime? startDate;
  final DateTime? endDate;
  final String? location;
  final String? timezone;
  final String? employmentType;
  final String? workType;
  final WorkPay pay;
  final Agreement agreement;
  final DateTime? offerExpiresAt;
  final String? endReason;
  final String? employer;
  final bool employerIsAgency;
  final String? client;
  final String? identityLabel;
  final DateTime? nextShift;
  final bool verifiedExperience;

  String get employerName => employer ?? agreement.employer ?? 'Your employer';

  /// Where the work happens, when an agency places the worker at a client.
  String? get clientName => client ?? agreement.client;

  /// Still waiting for an answer and not past the answer-by time.
  bool isOfferOpenAt(DateTime now) =>
      status == AssignmentStatus.offered &&
      (offerExpiresAt == null || offerExpiresAt!.isAfter(now));

  factory Assignment.fromJson(Map<String, dynamic> m) => Assignment(
    id: m['id'].toString(),
    status: AssignmentStatus.fromWire(_str(m['status'])),
    title: _str(m['title']) ?? 'Work',
    startDate: _day(m['start_date']),
    endDate: _day(m['end_date']),
    location: _str(m['location']),
    timezone: _str(m['timezone']),
    employmentType: _str(m['employment_type']),
    workType: _str(m['work_type']),
    pay: WorkPay.fromJson(m['pay']),
    agreement: Agreement.fromJson(m['agreement']),
    offerExpiresAt: _time(m['offer_expires_at']),
    endReason: _str(m['end_reason']),
    employer: _str(m['employer']),
    employerIsAgency: m['employer_is_agency'] == true,
    client: _str(m['client']),
    identityLabel: _str(m['identity_label']),
    nextShift: _time(m['next_shift']),
    verifiedExperience: m['verified_experience'] == true,
  );
}

List<Assignment> parseAssignments(dynamic v) =>
    _parseList(v, Assignment.fromJson);

/// Open offers first, then work that is on, then the rest (newest start
/// first).
List<Assignment> sortAssignments(Iterable<Assignment> list, DateTime now) {
  int rank(Assignment a) {
    if (a.isOfferOpenAt(now)) return 0;
    if (a.status.isOngoing) return 1;
    return 2;
  }

  final out = list.toList();
  out.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final sa = a.startDate, sb = b.startDate;
    if (sa == null || sb == null) return 0;
    return sb.compareTo(sa);
  });
  return out;
}

String assignmentStatusLabel(Assignment a, DateTime now) {
  if (a.status == AssignmentStatus.offered && !a.isOfferOpenAt(now)) {
    return 'Offer ended';
  }
  return switch (a.status) {
    AssignmentStatus.offered => 'New offer',
    AssignmentStatus.accepted => 'Starting soon',
    AssignmentStatus.active => 'Working',
    AssignmentStatus.paused => 'On pause',
    AssignmentStatus.completed => 'Finished',
    AssignmentStatus.declined => 'You said no',
    AssignmentStatus.cancelled => 'Cancelled',
    AssignmentStatus.terminated => 'Ended early',
  };
}

/// "Acme Staffing · at BlueDart Warehouse" or just the employer.
String employerLine(Assignment a) {
  final client = a.clientName;
  if (client == null || client == a.employerName) return a.employerName;
  return '${a.employerName} · at $client';
}

/// "From 1 Oct" · "1 Oct – 31 Dec"
String? datesLine(DateTime? start, DateTime? end, DateTime now) {
  if (start == null && end == null) return null;
  if (end == null) return 'From ${shortDate(start!, now)}';
  if (start == null) return 'Until ${shortDate(end, now)}';
  return '${shortDate(start, now)} – ${shortDate(end, now)}';
}

class AssignmentActions {
  const AssignmentActions({
    this.canAccept = false,
    this.canDecline = false,
    this.canRequestLeave = false,
    this.canTimesheet = false,
    this.verified = false,
    required this.note,
  });

  final bool canAccept;
  final bool canDecline;
  final bool canRequestLeave;
  final bool canTimesheet;

  /// Finished work that is now verified work history ("Verified by Omelo").
  final bool verified;

  /// One plain sentence about where things stand.
  final String note;
}

AssignmentActions assignmentActions(Assignment a, DateTime now) {
  switch (a.status) {
    case AssignmentStatus.offered:
      if (!a.isOfferOpenAt(now)) {
        return const AssignmentActions(
          note: 'This offer ended before you answered.',
        );
      }
      final by = a.offerExpiresAt == null
          ? ''
          : ' ${answerByLabel(a.offerExpiresAt!, now)}.';
      return AssignmentActions(
        canAccept: true,
        canDecline: true,
        note: 'Read the details, then say yes or no.$by',
      );
    case AssignmentStatus.accepted:
      return AssignmentActions(
        canRequestLeave: true,
        canTimesheet: true,
        note: a.startDate == null
            ? 'You said yes. Your employer will share your shifts.'
            : 'You said yes. You start on ${shortDate(a.startDate!, now)}.',
      );
    case AssignmentStatus.active:
      return const AssignmentActions(
        canRequestLeave: true,
        canTimesheet: true,
        note: 'You work here now.',
      );
    case AssignmentStatus.paused:
      return const AssignmentActions(
        canRequestLeave: true,
        canTimesheet: true,
        note: 'Your employer paused this work for now.',
      );
    case AssignmentStatus.completed:
      return AssignmentActions(
        canTimesheet: true,
        verified: a.verifiedExperience,
        note: a.endDate == null
            ? 'This work is finished.'
            : 'This work finished on ${shortDate(a.endDate!, now)}.',
      );
    case AssignmentStatus.declined:
      return const AssignmentActions(note: 'You said no to this offer.');
    case AssignmentStatus.cancelled:
      return AssignmentActions(
        note: a.endReason == 'Offer expired'
            ? 'This offer ended before you answered.'
            : 'This work was cancelled.${_reason(a.endReason)}',
      );
    case AssignmentStatus.terminated:
      return AssignmentActions(
        canTimesheet: true,
        note: 'This work ended early.${_reason(a.endReason)}',
      );
  }
}

String _reason(String? r) => r == null ? '' : ' Reason: $r';

/// "No thanks" reasons for an offer, in the words workers use.
enum AssignmentDeclineReason {
  payTooLow('Pay too low'),
  tooFar('Too far'),
  hours('Hours do not suit me'),
  otherWork('Found other work'),
  other('Other');

  const AssignmentDeclineReason(this.label);
  final String label;
}

const kWorkReasonMax = 300;

String? _clip(String? text, int max) {
  final t = text?.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (t == null || t.isEmpty) return null;
  return t.length > max ? t.substring(0, max) : t;
}

/// The reason sent with a no: a chip sends its label, "Other" what the
/// worker typed (or "Other").
String? assignmentDeclineText(AssignmentDeclineReason? r, [String? other]) {
  if (r == null) return null;
  if (r == AssignmentDeclineReason.other) {
    return _clip(other, kWorkReasonMax) ?? r.label;
  }
  return r.label;
}

Map<String, Object?> respondToAssignmentPayload(
  String assignmentId, {
  required bool accept,
  AssignmentDeclineReason? reason,
  String? otherText,
}) => {
  'p_assignment': assignmentId,
  'p_accept': accept,
  if (!accept) 'p_reason': assignmentDeclineText(reason, otherText),
};

/// What the server said after a yes.
String acceptedMessage(String result, Assignment a, DateTime now) =>
    result == 'active'
    ? 'You said yes. You work here from today.'
    : a.startDate == null
    ? 'You said yes.'
    : 'You said yes. You start on ${shortDate(a.startDate!, now)}.';

// ---------------------------------------------------------------------------
// Shifts and attendance
// ---------------------------------------------------------------------------

/// Mirrors `shift_workers.status` for my own shifts.
enum ShiftWorkerStatus {
  offered,
  assigned,
  completed,
  absent,
  onLeave,
  cancelled;

  static ShiftWorkerStatus fromWire(String? v) => switch (v) {
    'offered' => offered,
    'assigned' => assigned,
    'completed' => completed,
    'absent' => absent,
    'on_leave' => onLeave,
    _ => cancelled,
  };
}

class Attendance {
  const Attendance({
    required this.id,
    this.checkInAt,
    this.checkOutAt,
    this.status,
    this.reviewStatus = 'none',
    this.workedMinutes,
  });

  final String id;
  final DateTime? checkInAt;
  final DateTime? checkOutAt;

  /// checked_in | present | late | absent | partial | early_departure |
  /// approved_leave | unapproved_absence
  final String? status;

  /// none | pending | approved | adjusted | rejected
  final String reviewStatus;
  final int? workedMinutes;

  bool get needsReview => reviewStatus == 'pending';

  static Attendance? fromJson(dynamic v) {
    if (v is! Map || v['id'] == null) return null;
    return Attendance(
      id: v['id'].toString(),
      checkInAt: _time(v['check_in_at']),
      checkOutAt: _time(v['check_out_at']),
      status: _str(v['status']),
      reviewStatus: _str(v['review_status']) ?? 'none',
      workedMinutes: _num(v['worked_minutes'])?.toInt(),
    );
  }
}

class Supervisor {
  const Supervisor({this.name, this.phone});
  final String? name;
  final String? phone;

  static Supervisor? fromJson(dynamic v) {
    if (v is! Map) return null;
    final s = Supervisor(name: _str(v['name']), phone: _str(v['phone']));
    return s.name == null && s.phone == null ? null : s;
  }
}

/// One of my shifts, from `omelo_my_work()`.
class WorkShift {
  const WorkShift({
    required this.shiftWorkerId,
    required this.shiftId,
    required this.assignmentId,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.title,
    this.shiftStatus,
    this.timezone,
    this.breakMinutes = 0,
    this.kind,
    this.shiftType,
    this.location,
    this.employer,
    this.client,
    this.supervisor,
    this.instructions,
    this.pay = const WorkPay(),
    this.checkInMethod = 'app',
    this.attendance,
  });

  final String shiftWorkerId;
  final String shiftId;
  final String assignmentId;
  final ShiftWorkerStatus status;
  final String? shiftStatus;
  final DateTime startsAt;
  final DateTime endsAt;
  final String? timezone;
  final int breakMinutes;
  final String? kind;
  final String? shiftType;
  final String title;
  final String? location;
  final String? employer;
  final String? client;
  final Supervisor? supervisor;
  final String? instructions;
  final WorkPay pay;
  final String checkInMethod;
  final Attendance? attendance;

  bool get isCancelled =>
      status == ShiftWorkerStatus.cancelled || shiftStatus == 'cancelled';

  bool get isCheckedIn =>
      attendance?.checkInAt != null && attendance?.checkOutAt == null;

  factory WorkShift.fromJson(Map<String, dynamic> m) {
    final start = _time(m['starts_at']);
    final end = _time(m['ends_at']);
    if (start == null || end == null) {
      throw const FormatException('shift without times');
    }
    return WorkShift(
      shiftWorkerId: m['shift_worker_id'].toString(),
      shiftId: (m['shift_id'] ?? '').toString(),
      assignmentId: (m['assignment_id'] ?? '').toString(),
      status: ShiftWorkerStatus.fromWire(_str(m['status'])),
      shiftStatus: _str(m['shift_status']),
      startsAt: start,
      endsAt: end,
      timezone: _str(m['timezone']),
      breakMinutes: _num(m['break_minutes'])?.toInt() ?? 0,
      kind: _str(m['kind']),
      shiftType: _str(m['shift_type']),
      title: _str(m['title']) ?? 'Shift',
      location: _str(m['location']),
      employer: _str(m['employer']),
      client: _str(m['client']),
      supervisor: Supervisor.fromJson(m['supervisor']),
      instructions: _str(m['instructions']),
      pay: WorkPay.fromJson(m['pay']),
      checkInMethod: _str(m['check_in_method']) ?? 'app',
      attendance: Attendance.fromJson(m['attendance']),
    );
  }
}

List<WorkShift> parseWork(dynamic v) {
  final out = _parseList(v, WorkShift.fromJson, key: 'shift_worker_id');
  out.sort((a, b) => a.startsAt.compareTo(b.startsAt));
  return out;
}

/// "Acme Staffing · at BlueDart Warehouse"
String shiftEmployerLine(WorkShift s) {
  final e = s.employer ?? 'Your employer';
  if (s.client == null || s.client == s.employer) return e;
  return '$e · at ${s.client}';
}

/// "Night shift · Extra shift" — the shift's name and kind, when known.
String shiftNameLine(WorkShift s) => [
  if (s.shiftType != null) _shiftTypeLabel(s.shiftType!),
  switch (s.kind) {
    'overtime' => 'Extra shift',
    'emergency' => 'Urgent shift',
    'split' => 'Split shift',
    'on_call' => 'On call',
    _ => '',
  },
].where((x) => x.isNotEmpty).join(' · ');

String _shiftTypeLabel(String s) => switch (s) {
  'day' => 'Day shift',
  'evening' => 'Evening shift',
  'night' => 'Night shift',
  'early_morning' => 'Early morning',
  'rotating' => 'Rotating shift',
  'split' => 'Split shift',
  'flexible' => 'Flexible hours',
  'weekend' => 'Weekend shift',
  'on_call' => 'On call',
  _ => s,
};

/// How early check-in opens before the start (server rule).
const kCheckInOpensBefore = Duration(minutes: 60);

/// How long after the end check-out stays open (server rule).
const kCheckOutClosesAfter = Duration(hours: 6);

enum CheckInPhase {
  /// An extra shift offered to me — accept it first.
  offered,
  cancelled,
  onLeave,
  absent,

  /// The supervisor records arrival; nothing for the worker to press.
  supervisor,

  /// Too early: opens 60 minutes before the start.
  notOpenYet,

  /// "Check in" can be pressed now.
  open,

  /// Checked in, not out: "Check out" can be pressed.
  checkedIn,

  /// Checked in but too late to check out on the app.
  checkOutClosed,

  /// Checked in and out (or recorded by the supervisor).
  done,

  /// The shift ended without a check-in.
  missed,
}

class CheckInState {
  const CheckInState(
    this.phase, {
    this.opensAt,
    this.checkedInAt,
    this.workedMinutes,
    this.needsReview = false,
  });

  final CheckInPhase phase;
  final DateTime? opensAt;
  final DateTime? checkedInAt;
  final int? workedMinutes;
  final bool needsReview;

  bool get canCheckIn => phase == CheckInPhase.open;
  bool get canCheckOut => phase == CheckInPhase.checkedIn;

  @override
  String toString() => 'CheckInState(${phase.name})';
}

/// Where check-in stands for this shift right now.
CheckInState checkInState(WorkShift s, DateTime now) {
  if (s.isCancelled) return const CheckInState(CheckInPhase.cancelled);
  if (s.status == ShiftWorkerStatus.offered) {
    return const CheckInState(CheckInPhase.offered);
  }
  if (s.status == ShiftWorkerStatus.onLeave) {
    return const CheckInState(CheckInPhase.onLeave);
  }
  final a = s.attendance;
  if (a != null && a.checkInAt != null && a.checkOutAt != null) {
    return CheckInState(
      CheckInPhase.done,
      checkedInAt: a.checkInAt,
      workedMinutes:
          a.workedMinutes ?? a.checkOutAt!.difference(a.checkInAt!).inMinutes,
      needsReview: a.needsReview,
    );
  }
  if (a != null && a.checkInAt != null) {
    final closed = now.isAfter(s.endsAt.add(kCheckOutClosesAfter));
    return CheckInState(
      closed ? CheckInPhase.checkOutClosed : CheckInPhase.checkedIn,
      checkedInAt: a.checkInAt,
      needsReview: a.needsReview,
    );
  }
  if (s.status == ShiftWorkerStatus.absent ||
      a?.status == 'absent' ||
      a?.status == 'unapproved_absence') {
    return const CheckInState(CheckInPhase.absent);
  }
  if (a?.status == 'approved_leave') {
    return const CheckInState(CheckInPhase.onLeave);
  }
  if (s.status == ShiftWorkerStatus.completed) {
    return CheckInState(
      CheckInPhase.done,
      workedMinutes: a?.workedMinutes,
      needsReview: a?.needsReview ?? false,
    );
  }
  if (s.checkInMethod == 'employer') {
    return const CheckInState(CheckInPhase.supervisor);
  }
  final opens = s.startsAt.subtract(kCheckInOpensBefore);
  if (now.isBefore(opens)) {
    return CheckInState(CheckInPhase.notOpenYet, opensAt: opens);
  }
  if (!now.isAfter(s.endsAt)) return const CheckInState(CheckInPhase.open);
  return const CheckInState(CheckInPhase.missed);
}

/// The big button's words (and whether it is a button at all).
class CheckInButton {
  const CheckInButton(this.label, {this.detail, this.action});
  final String label;
  final String? detail;

  /// 'check_in' | 'check_out' | null (not pressable).
  final String? action;
}

CheckInButton checkInButton(CheckInState st, WorkShift s, DateTime now) {
  final zone = s.timezone;
  String? reviewDetail() => st.needsReview ? 'Needs review' : null;
  switch (st.phase) {
    case CheckInPhase.offered:
      return const CheckInButton('Accept the shift first');
    case CheckInPhase.cancelled:
      return const CheckInButton('Shift cancelled');
    case CheckInPhase.onLeave:
      return const CheckInButton('You are on leave');
    case CheckInPhase.absent:
      return const CheckInButton('Marked absent');
    case CheckInPhase.supervisor:
      return const CheckInButton('Your supervisor records your arrival');
    case CheckInPhase.notOpenYet:
      final d = shiftDayLabel(st.opensAt!, zone, now);
      final at = clockAt(st.opensAt!, zone);
      return CheckInButton(
        d == 'Today' ? 'Check-in opens at $at' : 'Check-in opens $d, $at',
      );
    case CheckInPhase.open:
      return const CheckInButton('Check in', action: 'check_in');
    case CheckInPhase.checkedIn:
      return CheckInButton(
        'Check out',
        detail: [
          'Checked in at ${clockAt(st.checkedInAt!, zone)}',
          ?reviewDetail(),
        ].join(' · '),
        action: 'check_out',
      );
    case CheckInPhase.checkOutClosed:
      return CheckInButton(
        'Check-out closed',
        detail:
            'Checked in at ${clockAt(st.checkedInAt!, zone)}. Ask your '
            'supervisor to record when you left.',
      );
    case CheckInPhase.done:
      return CheckInButton(
        st.workedMinutes == null
            ? 'Done'
            : 'Done · ${hoursWords(st.workedMinutes!)}',
        detail: reviewDetail(),
      );
    case CheckInPhase.missed:
      return const CheckInButton(
        'Check-in closed',
        detail: 'Ask your supervisor to record your time.',
      );
  }
}

/// What happened to my time, in words that never threaten. Null when there
/// is nothing to say.
String? attendanceReviewLine(Attendance? a) {
  if (a == null) return null;
  switch (a.reviewStatus) {
    case 'pending':
      return switch (a.status) {
        'early_departure' || 'partial' =>
          'Early finish recorded — your supervisor will review it',
        'late' || 'checked_in' =>
          'Late arrival recorded — your supervisor will review it',
        _ => 'Your supervisor will review this shift',
      };
    case 'approved':
      return 'Your supervisor approved this time';
    case 'adjusted':
      return 'Your supervisor corrected this time';
    case 'rejected':
      return 'Your supervisor did not accept this time. Ask them about it.';
  }
  return null;
}

/// One recorded exception on my attendance (late, early finish …).
class AttendanceNote {
  const AttendanceNote({
    required this.kind,
    this.minutes,
    this.status = 'pending',
    this.resolutionNote,
  });
  final String kind;
  final int? minutes;
  final String status;
  final String? resolutionNote;

  factory AttendanceNote.fromJson(Map<String, dynamic> m) => AttendanceNote(
    kind: _str(m['kind']) ?? 'manual_correction',
    minutes: _num(m['minutes'])?.toInt(),
    status: _str(m['status']) ?? 'pending',
    resolutionNote: _str(m['resolution_note']),
  );
}

/// "Late arrival (12 min) — your supervisor will review it"
String attendanceNoteLine(AttendanceNote n) {
  final what = switch (n.kind) {
    'late' => 'Late arrival',
    'early_departure' => 'Early finish',
    'absent' => 'Absence',
    'missing_check_out' => 'No check-out',
    'location_mismatch' => 'Checked in away from the site',
    _ => 'Time corrected',
  };
  final mins = n.minutes == null || n.minutes! <= 0
      ? ''
      : ' (${hoursWords(n.minutes!)})';
  final state = switch (n.status) {
    'approved' => 'approved by your supervisor',
    'adjusted' => 'corrected by your supervisor',
    'rejected' => 'not accepted by your supervisor',
    _ => 'your supervisor will review it',
  };
  return '$what$mins — $state';
}

bool isValidShiftCode(String code) => RegExp(r'^\d{6}$').hasMatch(code.trim());

Map<String, Object?> checkInPayload(
  String shiftWorkerId, {
  required String method,
  double? lat,
  double? lng,
  String? code,
}) => {
  'p_shift_worker': shiftWorkerId,
  'p_method': method == 'qr' || method == 'geofence' ? method : 'app',
  if (lat != null && lng != null) ...{'p_lat': lat, 'p_lng': lng},
  if (method == 'qr' && code != null) 'p_code': code.trim(),
};

class CheckOutResult {
  const CheckOutResult({
    this.workedMinutes,
    this.status,
    this.needsReview = false,
  });
  final int? workedMinutes;
  final String? status;
  final bool needsReview;

  factory CheckOutResult.fromJson(dynamic v) {
    if (v is! Map) return const CheckOutResult();
    return CheckOutResult(
      workedMinutes: _num(v['worked_minutes'])?.toInt(),
      status: _str(v['status']),
      needsReview: v['needs_review'] == true,
    );
  }
}

String checkOutMessage(CheckOutResult r) {
  final worked = r.workedMinutes == null
      ? 'Checked out.'
      : 'Checked out · ${hoursWords(r.workedMinutes!)} worked.';
  return r.needsReview
      ? '$worked Your supervisor will review this shift.'
      : worked;
}

/// My Work, sorted into what matters today, what is coming and extra shifts
/// offered to me.
class WorkOverview {
  const WorkOverview({
    this.today = const [],
    this.upcoming = const [],
    this.offers = const [],
  });
  final List<WorkShift> today;
  final List<WorkShift> upcoming;
  final List<WorkShift> offers;

  bool get isEmpty => today.isEmpty && upcoming.isEmpty && offers.isEmpty;
}

WorkOverview workOverview(Iterable<WorkShift> shifts, DateTime now) {
  final today = <WorkShift>[], upcoming = <WorkShift>[], offers = <WorkShift>[];
  for (final s in shifts) {
    if (s.status == ShiftWorkerStatus.offered && !s.isCancelled) {
      if (s.endsAt.isAfter(now)) offers.add(s);
      continue;
    }
    final isToday =
        s.isCheckedIn && !now.isAfter(s.endsAt.add(kCheckOutClosesAfter)) ||
        _dayDiff(siteDate(s.startsAt, s.timezone), siteToday(s.timezone, now)) ==
            0 ||
        (!s.startsAt.isAfter(now) && !s.endsAt.isBefore(now));
    if (isToday) {
      today.add(s);
    } else if (s.startsAt.isAfter(now) &&
        (s.status == ShiftWorkerStatus.assigned || s.isCancelled)) {
      upcoming.add(s);
    }
  }
  int byStart(WorkShift a, WorkShift b) => a.startsAt.compareTo(b.startsAt);
  return WorkOverview(
    today: today..sort(byStart),
    upcoming: upcoming..sort(byStart),
    offers: offers..sort(byStart),
  );
}

Map<String, Object?> respondToShiftPayload(String shiftWorkerId, bool accept) =>
    {'p_shift_worker': shiftWorkerId, 'p_accept': accept};

// ---------------------------------------------------------------------------
// Leave
// ---------------------------------------------------------------------------

enum LeaveType {
  paid('Paid leave'),
  unpaid('Unpaid leave'),
  sick('Sick'),
  personal('Personal'),
  other('Other');

  const LeaveType(this.label);
  final String label;

  static LeaveType fromWire(String? v) {
    for (final t in values) {
      if (t.name == v) return t;
    }
    return other;
  }
}

enum LeaveStatus {
  requested,
  approved,
  rejected,
  cancelled;

  static LeaveStatus fromWire(String? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return cancelled;
  }
}

String leaveStatusLabel(LeaveStatus s) => switch (s) {
  LeaveStatus.requested => 'Waiting',
  LeaveStatus.approved => 'Approved',
  LeaveStatus.rejected => 'Not approved',
  LeaveStatus.cancelled => 'Cancelled',
};

class LeaveRequest {
  const LeaveRequest({
    required this.id,
    required this.assignmentId,
    required this.type,
    required this.startDate,
    required this.endDate,
    required this.status,
    this.label,
    this.reason,
    this.reviewNote,
    this.createdAt,
  });

  final String id;
  final String assignmentId;
  final LeaveType type;

  /// The worker's own (local) name for it, e.g. "Casual leave".
  final String? label;
  final DateTime startDate;
  final DateTime endDate;
  final String? reason;
  final LeaveStatus status;
  final String? reviewNote;
  final DateTime? createdAt;

  bool get canCancel => status == LeaveStatus.requested;

  /// "Casual leave" when named, else the type ("Sick").
  String get title => label ?? type.label;

  factory LeaveRequest.fromJson(Map<String, dynamic> m) {
    final start = _day(m['start_date']);
    final end = _day(m['end_date']) ?? start;
    if (start == null) throw const FormatException('leave without dates');
    return LeaveRequest(
      id: m['id'].toString(),
      assignmentId: (m['assignment_id'] ?? '').toString(),
      type: LeaveType.fromWire(_str(m['leave_type'])),
      label: _str(m['label']),
      startDate: start,
      endDate: end!,
      reason: _str(m['reason']),
      status: LeaveStatus.fromWire(_str(m['status'])),
      reviewNote: _str(m['review_note']),
      createdAt: _time(m['created_at']),
    );
  }
}

List<LeaveRequest> parseLeave(dynamic v) {
  final out = _parseList(v, LeaveRequest.fromJson);
  out.sort((a, b) {
    if (a.canCancel != b.canCancel) return a.canCancel ? -1 : 1;
    return b.startDate.compareTo(a.startDate);
  });
  return out;
}

int inclusiveDays(DateTime start, DateTime end) => _dayDiff(end, start) + 1;

/// "21 Oct" · "21 Oct – 23 Oct · 3 days"
String leaveDaysLine(DateTime start, DateTime end, DateTime now) {
  final n = inclusiveDays(start, end);
  if (n <= 1) return '${shortDate(start, now)} · 1 day';
  return '${shortDate(start, now)} – ${shortDate(end, now)} · $n days';
}

/// A problem with the chosen dates, or null.
String? validateLeaveDates(DateTime? start, DateTime? end) {
  if (start == null) return 'Pick the first day.';
  if (end == null) return 'Pick the last day.';
  if (end.isBefore(start)) return 'The last day is before the first day.';
  if (inclusiveDays(start, end) > 366) return 'Leave can be at most a year.';
  return null;
}

const kLeaveLabelMax = 80;
const kLeaveReasonMax = 500;

Map<String, Object?> requestLeavePayload({
  required String assignmentId,
  required LeaveType type,
  required DateTime start,
  required DateTime end,
  String? reason,
  String? label,
}) => {
  'p_assignment': assignmentId,
  'p_type': type.name,
  'p_start': wireDate(start),
  'p_end': wireDate(end),
  'p_reason': _clip(reason, kLeaveReasonMax),
  'p_label': _clip(label, kLeaveLabelMax),
};

// ---------------------------------------------------------------------------
// Timesheets
// ---------------------------------------------------------------------------

enum TimesheetStatus {
  draft,
  submitted,
  underReview,
  approved,
  rejected,
  locked;

  static TimesheetStatus fromWire(String? v) => switch (v) {
    'draft' => draft,
    'submitted' => submitted,
    'under_review' => underReview,
    'approved' => approved,
    'rejected' => rejected,
    _ => locked,
  };
}

String timesheetStatusLabel(TimesheetStatus s) => switch (s) {
  TimesheetStatus.draft => 'Not sent yet',
  TimesheetStatus.submitted => 'Sent',
  TimesheetStatus.underReview => 'Being checked',
  TimesheetStatus.approved => 'Approved',
  TimesheetStatus.rejected => 'Sent back',
  TimesheetStatus.locked => 'Closed',
};

class Timesheet {
  const Timesheet({
    required this.id,
    required this.assignmentId,
    required this.periodStart,
    required this.periodEnd,
    required this.status,
    this.totalMinutes = 0,
    this.regularMinutes = 0,
    this.overtimeMinutes = 0,
    this.daysWorked = 0,
    this.shiftsWorked = 0,
    this.rejectReason,
    this.submittedAt,
  });

  final String id;
  final String assignmentId;
  final DateTime periodStart;
  final DateTime periodEnd;
  final TimesheetStatus status;
  final int totalMinutes;
  final int regularMinutes;
  final int overtimeMinutes;
  final int daysWorked;
  final int shiftsWorked;
  final String? rejectReason;
  final DateTime? submittedAt;

  factory Timesheet.fromJson(Map<String, dynamic> m) {
    final start = _day(m['period_start']);
    final end = _day(m['period_end']);
    if (start == null || end == null) {
      throw const FormatException('timesheet without a period');
    }
    return Timesheet(
      id: m['id'].toString(),
      assignmentId: (m['assignment_id'] ?? '').toString(),
      periodStart: start,
      periodEnd: end,
      status: TimesheetStatus.fromWire(_str(m['status'])),
      totalMinutes: _num(m['total_minutes'])?.toInt() ?? 0,
      regularMinutes: _num(m['regular_minutes'])?.toInt() ?? 0,
      overtimeMinutes: _num(m['overtime_minutes'])?.toInt() ?? 0,
      daysWorked: _num(m['days_worked'])?.toInt() ?? 0,
      shiftsWorked: _num(m['shifts_worked'])?.toInt() ?? 0,
      rejectReason: _str(m['reject_reason']),
      submittedAt: _time(m['submitted_at']),
    );
  }
}

List<Timesheet> parseTimesheets(dynamic v) {
  final out = _parseList(v, Timesheet.fromJson);
  out.sort((a, b) => b.periodStart.compareTo(a.periodStart));
  return out;
}

class TimesheetEntry {
  const TimesheetEntry({
    required this.id,
    required this.workDate,
    required this.minutes,
    required this.kind,
    this.note,
  });

  final String id;
  final DateTime workDate;
  final int minutes;

  /// regular | manual | leave
  final String kind;
  final String? note;

  /// Only time I added myself can be removed.
  bool get isMine => kind == 'manual';

  factory TimesheetEntry.fromJson(Map<String, dynamic> m) {
    final d = _day(m['work_date']);
    if (d == null) throw const FormatException('entry without a day');
    return TimesheetEntry(
      id: m['id'].toString(),
      workDate: d,
      minutes: _num(m['minutes'])?.toInt() ?? 0,
      kind: _str(m['kind']) ?? 'regular',
      note: _str(m['note']),
    );
  }
}

List<TimesheetEntry> parseTimesheetEntries(dynamic v) =>
    _parseList(v, TimesheetEntry.fromJson);

String entryKindLabel(String kind) => switch (kind) {
  'manual' => 'Extra time',
  'leave' => 'Leave',
  _ => 'Shift',
};

class TimesheetDay {
  const TimesheetDay(this.day, this.entries);
  final DateTime day;
  final List<TimesheetEntry> entries;
  int get minutes => entries.fold(0, (s, e) => s + e.minutes);
}

/// Entries grouped by day, in date order.
List<TimesheetDay> entriesByDay(Iterable<TimesheetEntry> entries) {
  final by = <DateTime, List<TimesheetEntry>>{};
  for (final e in entries) {
    (by[_dateOnly(e.workDate)] ??= []).add(e);
  }
  final days = by.keys.toList()..sort();
  return [for (final d in days) TimesheetDay(d, by[d]!)];
}

/// "15 Sep – 21 Sep"
String periodLine(DateTime start, DateTime end, DateTime now) =>
    '${shortDate(start, now)} – ${shortDate(end, now)}';

class TimesheetActions {
  const TimesheetActions({
    this.canAddTime = false,
    this.canSubmit = false,
    this.canRefresh = false,
    this.canReopen = false,
    required this.note,
  });

  final bool canAddTime;
  final bool canSubmit;

  /// Pull in newly finished shifts (draft only).
  final bool canRefresh;

  /// Sent back: rebuild as a draft, fix it and send again.
  final bool canReopen;
  final String note;

  bool get isReadOnly => !canAddTime && !canSubmit && !canReopen;
}

TimesheetActions timesheetActions(Timesheet t) => switch (t.status) {
  TimesheetStatus.draft => const TimesheetActions(
    canAddTime: true,
    canSubmit: true,
    canRefresh: true,
    note:
        'Check your hours, add any extra time, then send it for approval.',
  ),
  TimesheetStatus.submitted => const TimesheetActions(
    note: 'Sent. Your supervisor will check it.',
  ),
  TimesheetStatus.underReview => const TimesheetActions(
    note: 'Your supervisor is checking it.',
  ),
  TimesheetStatus.approved => const TimesheetActions(
    note: 'Approved. Your pay for these days is being worked out.',
  ),
  TimesheetStatus.rejected => TimesheetActions(
    canReopen: true,
    note: t.rejectReason == null
        ? 'Sent back. Fix it and send it again.'
        : 'Sent back: ${t.rejectReason}. Fix it and send it again.',
  ),
  TimesheetStatus.locked => const TimesheetActions(
    note: 'Closed. This timesheet has been paid and cannot change.',
  ),
};

enum TimesheetPeriod {
  thisWeek('This week'),
  lastWeek('Last week'),
  thisMonth('This month'),
  lastMonth('Last month');

  const TimesheetPeriod(this.label);
  final String label;
}

/// The first and last day of a quick period (weeks run Monday to Sunday).
(DateTime, DateTime) timesheetPeriod(TimesheetPeriod p, DateTime today) {
  final d = _dateOnly(today);
  final monday = DateTime(d.year, d.month, d.day - (d.weekday - 1));
  return switch (p) {
    TimesheetPeriod.thisWeek => (
      monday,
      DateTime(monday.year, monday.month, monday.day + 6),
    ),
    TimesheetPeriod.lastWeek => (
      DateTime(monday.year, monday.month, monday.day - 7),
      DateTime(monday.year, monday.month, monday.day - 1),
    ),
    TimesheetPeriod.thisMonth => (
      DateTime(d.year, d.month, 1),
      DateTime(d.year, d.month + 1, 0),
    ),
    TimesheetPeriod.lastMonth => (
      DateTime(d.year, d.month - 1, 1),
      DateTime(d.year, d.month, 0),
    ),
  };
}

const kTimesheetMaxDays = 31;

/// A problem with the chosen period, or null.
String? validateTimesheetPeriod(DateTime? start, DateTime? end) {
  if (start == null || end == null) return 'Pick the first and last day.';
  if (end.isBefore(start)) return 'The last day is before the first day.';
  if (inclusiveDays(start, end) > kTimesheetMaxDays) {
    return 'A timesheet can cover up to $kTimesheetMaxDays days.';
  }
  return null;
}

Map<String, Object?> buildTimesheetPayload(
  String assignmentId,
  DateTime start,
  DateTime end,
) => {
  'p_assignment': assignmentId,
  'p_period_start': wireDate(start),
  'p_period_end': wireDate(end),
};

const kEntryNoteMax = 300;

/// A problem with extra time, or null. The note says what it was for.
String? validateExtraTime(int? minutes, String? note) {
  if (minutes == null || minutes <= 0) return 'Enter how long you worked.';
  if (minutes > 1440) return 'One day has at most 24 hours.';
  final n = note?.trim() ?? '';
  if (n.length < 3) return 'Say what the extra time was for.';
  return null;
}

/// "1:30", "1.5", "90m", "2h" … → minutes. Plain numbers are hours.
int? parseDurationInput(String? text) {
  final t = text?.trim().toLowerCase().replaceAll(' ', '') ?? '';
  if (t.isEmpty) return null;
  final hm = RegExp(r'^(\d{1,2}):(\d{1,2})$').firstMatch(t);
  if (hm != null) {
    return int.parse(hm.group(1)!) * 60 + int.parse(hm.group(2)!);
  }
  final m = RegExp(r'^(\d{1,4})(m|min|mins)$').firstMatch(t);
  if (m != null) return int.parse(m.group(1)!);
  final h = RegExp(r'^(\d{1,2}(?:[.,]\d{1,2})?)(h|hr|hrs)?$').firstMatch(t);
  if (h != null) {
    final v = double.tryParse(h.group(1)!.replaceAll(',', '.'));
    return v == null ? null : (v * 60).round();
  }
  return null;
}

Map<String, Object?> addEntryPayload(
  String timesheetId,
  DateTime day,
  int minutes,
  String note,
) => {
  'p_timesheet': timesheetId,
  'p_work_date': wireDate(day),
  'p_minutes': minutes,
  'p_note': _clip(note, kEntryNoteMax),
};

// ---------------------------------------------------------------------------
// Earnings
// ---------------------------------------------------------------------------

enum EarningStatus {
  calculated,
  approved,
  scheduled,
  processing,
  paid,
  failed;

  static EarningStatus fromWire(String? v) {
    for (final s in values) {
      if (s.name == v) return s;
    }
    return calculated;
  }
}

String earningStatusLabel(EarningStatus s) => switch (s) {
  EarningStatus.calculated => 'Being checked',
  EarningStatus.approved => 'Approved',
  EarningStatus.scheduled => 'Scheduled',
  EarningStatus.processing => 'On its way',
  EarningStatus.paid => 'Paid',
  EarningStatus.failed => 'Payment failed',
};

class EarningLine {
  const EarningLine({
    required this.kind,
    required this.description,
    required this.amount,
    this.quantity,
    this.unit,
    this.rate,
    this.reason,
  });
  final String kind;
  final String description;
  final num amount;
  final num? quantity;
  final String? unit;
  final num? rate;
  final String? reason;

  factory EarningLine.fromJson(Map m) => EarningLine(
    kind: _str(m['kind']) ?? 'adjustment',
    description: _str(m['description']) ?? '',
    amount: _num(m['amount']) ?? 0,
    quantity: _num(m['quantity']),
    unit: _str(m['unit']),
    rate: _num(m['rate']),
    reason: _str(m['reason']),
  );
}

/// "8 hours × ₹90" — how a line was worked out, when known.
String? earningLineMath(EarningLine l, String? currency) {
  if (l.quantity == null || l.rate == null) return null;
  final q = _plainNumber(l.quantity!);
  final unit = switch (l.unit) {
    'hour' => l.quantity == 1 ? 'hour' : 'hours',
    'day' => l.quantity == 1 ? 'day' : 'days',
    'shift' => l.quantity == 1 ? 'shift' : 'shifts',
    'week' => l.quantity == 1 ? 'week' : 'weeks',
    'month' => l.quantity == 1 ? 'month' : 'months',
    _ => '',
  };
  final what = unit.isEmpty ? q : '$q $unit';
  return '$what × ${money(l.rate!, currency)}';
}

class EarningPayment {
  const EarningPayment({
    required this.amount,
    required this.status,
    this.paidAt,
    this.scheduledFor,
    this.reference,
  });
  final num amount;
  final String status;
  final DateTime? paidAt;
  final DateTime? scheduledFor;
  final String? reference;

  factory EarningPayment.fromJson(Map m) => EarningPayment(
    amount: _num(m['amount']) ?? 0,
    status: _str(m['status']) ?? 'scheduled',
    paidAt: _time(m['paid_at']),
    scheduledFor: _day(m['scheduled_for']),
    reference: _str(m['reference']),
  );
}

class Earning {
  const Earning({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    required this.currency,
    required this.status,
    this.base = 0,
    this.overtime = 0,
    this.allowances = 0,
    this.bonus = 0,
    this.deductions = 0,
    this.adjustments = 0,
    this.gross = 0,
    this.title,
    this.employer,
    this.lines = const [],
    this.payments = const [],
  });

  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final String currency;
  final EarningStatus status;
  final num base;
  final num overtime;
  final num allowances;
  final num bonus;
  final num deductions;
  final num adjustments;
  final num gross;
  final String? title;
  final String? employer;
  final List<EarningLine> lines;
  final List<EarningPayment> payments;

  factory Earning.fromJson(Map<String, dynamic> m) {
    final start = _day(m['period_start']);
    final end = _day(m['period_end']);
    if (start == null || end == null) {
      throw const FormatException('earning without a period');
    }
    return Earning(
      id: m['id'].toString(),
      periodStart: start,
      periodEnd: end,
      currency: (_str(m['currency']) ?? '').trim(),
      status: EarningStatus.fromWire(_str(m['status'])),
      base: _num(m['base']) ?? 0,
      overtime: _num(m['overtime']) ?? 0,
      allowances: _num(m['allowances']) ?? 0,
      bonus: _num(m['bonus']) ?? 0,
      deductions: _num(m['deductions']) ?? 0,
      adjustments: _num(m['adjustments']) ?? 0,
      gross: _num(m['gross']) ?? 0,
      title: _str(m['title']),
      employer: _str(m['employer']),
      lines: [
        if (m['lines'] is List)
          for (final l in m['lines'] as List)
            if (l is Map) EarningLine.fromJson(l),
      ],
      payments: [
        if (m['payments'] is List)
          for (final p in m['payments'] as List)
            if (p is Map) EarningPayment.fromJson(p),
      ],
    );
  }
}

List<Earning> parseEarnings(dynamic v) {
  final out = _parseList(v, Earning.fromJson);
  out.sort((a, b) => b.periodStart.compareTo(a.periodStart));
  return out;
}

/// "Pending" · "Scheduled for 21 Oct" · "Paid 21 Oct · UTR123" — the
/// newest payment, in words.
String paymentLine(Earning e, DateTime now) {
  if (e.payments.isEmpty) {
    return e.status == EarningStatus.failed ? 'Payment failed' : 'Pending';
  }
  final p = e.payments.last;
  switch (p.status) {
    case 'paid':
      return [
        p.paidAt == null ? 'Paid' : 'Paid ${shortDate(p.paidAt!, now)}',
        ?p.reference,
      ].join(' · ');
    case 'scheduled':
      return p.scheduledFor == null
          ? 'Scheduled'
          : 'Scheduled for ${shortDate(p.scheduledFor!, now)}';
    case 'processing':
      return 'On its way';
    case 'failed':
      return 'Payment failed — your employer will fix it';
    case 'reversed':
      return 'Payment reversed';
  }
  return 'Pending';
}

class BreakdownRow {
  const BreakdownRow(this.label, this.amount, {this.reasons = const []});
  final String label;

  /// Signed: deductions are negative.
  final num amount;
  final List<String> reasons;

  @override
  String toString() => '$label $amount';
}

/// Base pay always; the rest only when not zero. Adjustments carry the
/// reasons the employer gave.
List<BreakdownRow> earningBreakdown(Earning e) => [
  BreakdownRow('Base pay', e.base),
  if (e.overtime != 0) BreakdownRow('Overtime', e.overtime),
  if (e.allowances != 0) BreakdownRow('Allowances', e.allowances),
  if (e.bonus != 0) BreakdownRow('Bonus', e.bonus),
  if (e.deductions != 0)
    BreakdownRow(
      'Deductions',
      -e.deductions.abs(),
      reasons: [
        for (final l in e.lines)
          if (l.kind == 'deduction') l.reason ?? l.description,
      ].where((x) => x.isNotEmpty).toList(),
    ),
  if (e.adjustments != 0)
    BreakdownRow(
      'Adjustments',
      e.adjustments,
      reasons: [
        for (final l in e.lines)
          if (l.kind == 'adjustment') l.reason ?? l.description,
      ].where((x) => x.isNotEmpty).toList(),
    ),
];

/// "+₹500" / "−₹200" for signed rows.
String signedMoney(num amount, String? currency) =>
    amount < 0 ? '−${money(-amount, currency)}' : money(amount, currency);

class MonthTotal {
  const MonthTotal(this.month, this.currency, this.gross, this.count);
  final DateTime month;
  final String currency;
  final num gross;
  final int count;

  @override
  String toString() => '${DateFormat('MMM yyyy').format(month)} $currency $gross';
}

/// Totals by month (of the period end) and currency, newest month first.
/// Different currencies are never added together.
List<MonthTotal> monthlyTotals(Iterable<Earning> list) {
  final by = <(DateTime, String), (num, int)>{};
  for (final e in list) {
    final key = (DateTime(e.periodEnd.year, e.periodEnd.month), e.currency);
    final cur = by[key] ?? (0, 0);
    by[key] = (cur.$1 + e.gross, cur.$2 + 1);
  }
  final out = [
    for (final e in by.entries) MonthTotal(e.key.$1, e.key.$2, e.value.$1, e.value.$2),
  ];
  out.sort((a, b) {
    final m = b.month.compareTo(a.month);
    return m != 0 ? m : a.currency.compareTo(b.currency);
  });
  return out;
}

String monthLabel(DateTime m) => DateFormat('MMMM yyyy').format(m);

// ---------------------------------------------------------------------------
// Availability (extends the identity's work preferences)
// ---------------------------------------------------------------------------

class WorkAvailability {
  const WorkAvailability({
    this.availableFrom,
    this.availableUntil,
    this.preferredDays = const [],
    this.preferredStart,
    this.preferredEnd,
    this.maxWeeklyHours,
    this.maxTravelKm,
  });

  final DateTime? availableFrom;
  final DateTime? availableUntil;

  /// 1 = Monday … 7 = Sunday.
  final List<int> preferredDays;

  /// "HH:MM"
  final String? preferredStart;
  final String? preferredEnd;
  final int? maxWeeklyHours;
  final int? maxTravelKm;

  factory WorkAvailability.fromRow(Map<String, dynamic>? m) {
    if (m == null) return const WorkAvailability();
    return WorkAvailability(
      availableFrom: _day(m['available_from']),
      availableUntil: _day(m['available_until']),
      preferredDays: parseDays(m['preferred_days']),
      preferredStart: hhmm(_str(m['preferred_start_time'])),
      preferredEnd: hhmm(_str(m['preferred_end_time'])),
      maxWeeklyHours: _num(m['max_weekly_hours'])?.toInt(),
      maxTravelKm: _num(m['max_travel_km'])?.toInt(),
    );
  }

  /// The columns written back to `person_work_preferences`.
  Map<String, Object?> toRow() => {
    'available_from': availableFrom == null ? null : wireDate(availableFrom!),
    'available_until': availableUntil == null
        ? null
        : wireDate(availableUntil!),
    'preferred_days': cleanDays(preferredDays),
    'preferred_start_time': hhmm(preferredStart),
    'preferred_end_time': hhmm(preferredEnd),
    'max_weekly_hours': maxWeeklyHours,
    'max_travel_km': maxTravelKm,
  };

  WorkAvailability copyWith({
    DateTime? Function()? availableFrom,
    DateTime? Function()? availableUntil,
    List<int>? preferredDays,
    String? Function()? preferredStart,
    String? Function()? preferredEnd,
    int? Function()? maxWeeklyHours,
    int? Function()? maxTravelKm,
  }) => WorkAvailability(
    availableFrom: availableFrom == null ? this.availableFrom : availableFrom(),
    availableUntil: availableUntil == null
        ? this.availableUntil
        : availableUntil(),
    preferredDays: preferredDays ?? this.preferredDays,
    preferredStart: preferredStart == null
        ? this.preferredStart
        : preferredStart(),
    preferredEnd: preferredEnd == null ? this.preferredEnd : preferredEnd(),
    maxWeeklyHours: maxWeeklyHours == null
        ? this.maxWeeklyHours
        : maxWeeklyHours(),
    maxTravelKm: maxTravelKm == null ? this.maxTravelKm : maxTravelKm(),
  );
}

/// `smallint[]` as JSON (`[1,2]`) or Postgres text (`{1,2}`) → days.
List<int> parseDays(dynamic v) {
  if (v is List) return cleanDays(v);
  if (v is String) {
    return cleanDays(
      v.replaceAll(RegExp(r'[{}\[\]\s]'), '').split(',').where((s) => s.isNotEmpty),
    );
  }
  return const [];
}

/// "08:00:00" → "08:00"; null or not a time → null.
String? hhmm(String? v) {
  final t = parseHm(v);
  if (t == null) return null;
  return '${t.$1.toString().padLeft(2, '0')}:${t.$2.toString().padLeft(2, '0')}';
}

/// A problem with the availability, or null.
String? validateAvailability(WorkAvailability a) {
  final from = a.availableFrom, until = a.availableUntil;
  if (from != null && until != null && until.isBefore(from)) {
    return '"Available until" is before "Available from".';
  }
  final h = a.maxWeeklyHours;
  if (h != null && (h < 1 || h > 168)) {
    return 'Hours a week must be between 1 and 168.';
  }
  final km = a.maxTravelKm;
  if (km != null && (km < 0 || km > 1000)) {
    return 'Travel distance must be between 0 and 1000 km.';
  }
  if ((a.preferredStart == null) != (a.preferredEnd == null)) {
    return 'Pick both a start and an end time, or neither.';
  }
  return null;
}

// ---------------------------------------------------------------------------
// Routes
// ---------------------------------------------------------------------------

String shiftRoute(String shiftId) => '/work/shifts/$shiftId';
String assignmentRoute(String id) => '/work/assignments/$id';
String timesheetRoute(String id) => '/work/timesheets/$id';

/// `/work/leave` or `/work/timesheets` for one assignment.
String workListRoute(String path, {String? assignment}) => assignment == null
    ? path
    : Uri(path: path, queryParameters: {'assignment': assignment}).toString();

// ---------------------------------------------------------------------------

List<T> _parseList<T>(
  dynamic v,
  T Function(Map<String, dynamic>) parse, {
  String key = 'id',
}) {
  if (v is! List) return <T>[];
  final out = <T>[];
  for (final e in v) {
    if (e is! Map || e[key] == null) continue;
    try {
      out.add(parse(Map<String, dynamic>.from(e)));
    } catch (_) {}
  }
  return out;
}

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  return s.trim().isEmpty ? null : s;
}

num? _num(dynamic v) =>
    v == null ? null : (v is num ? v : num.tryParse(v.toString()));

/// An instant (timestamptz). Kept as sent (UTC); display converts it.
DateTime? _time(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());

/// A calendar date with no time zone ("2026-10-01").
DateTime? _day(dynamic v) {
  if (v == null) return null;
  final s = v.toString();
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
  if (m == null) return null;
  return DateTime(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
  );
}
