/// Release 7 — career intelligence, from the worker's side.
///
/// Current identity → skills → experience → evidence → career goal → skill
/// gap → recommended development → assessments → better jobs.
///
/// Rules that shape this file:
///  * The server owns every score. Readiness, skill status (strong / weak /
///    missing), match scores and pay ranges are shown as sent, never
///    recomputed here.
///  * Money is always shown in its own currency, and a pay range the server
///    could not build (too few jobs) says so instead of guessing.
///  * An assessment never reveals its answers: the result says which
///    questions were right, not what the right answer was.
///  * Only secure (https) links are opened.
///
/// Everything here is pure (no Supabase, no widgets) so it can be tested.
library;

import 'package:intl/intl.dart';

import 'global.dart' show EligibilityStatus, safeLink;
import 'identity.dart' show kProficiencyLabels;
import 'work.dart' show money, payPeriodWords, wireDate;

Map<String, dynamic>? _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.map(_map).whereType<Map<String, dynamic>>().toList()
    : const [];

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

num? _num(dynamic v) =>
    v == null ? null : (v is num ? v : num.tryParse(v.toString()));

int? _int(dynamic v) => _num(v)?.round();

bool _bool(dynamic v) => v == true || v?.toString() == 'true';

List<String> _strings(dynamic v) {
  if (v is! List) return const [];
  return v.map(_str).whereType<String>().toList();
}

List<String> _codes(dynamic v) {
  if (v is! List) return const [];
  final out = <String>[];
  for (final e in v) {
    final c = e?.toString().trim().toUpperCase() ?? '';
    if (RegExp(r'^[A-Z]{2}$').hasMatch(c) && !out.contains(c)) out.add(c);
  }
  return out;
}

/// "2026-11-01" is a calendar day; timestamps are shown in the phone's time.
DateTime? _date(dynamic v) {
  final s = _str(v);
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return s.length <= 10 ? d : d.toLocal();
}

// ---------------------------------------------------------------------------
// Words
// ---------------------------------------------------------------------------

/// "About 6 months" · "About 1 year" · "About 2½ years"
String typicalTimeLabel(int? months) {
  if (months == null || months <= 0) return 'Time varies';
  if (months < 12) return 'About $months month${months == 1 ? '' : 's'}';
  final years = months / 12;
  final whole = years.floor();
  final half = (years - whole) >= 0.5;
  if (whole == 1 && !half) return 'About 1 year';
  return 'About $whole${half ? '½' : ''} years';
}

/// "3 years 2 months experience" · "8 months experience" · null for none.
String? experienceLine(int? months) {
  if (months == null || months <= 0) return null;
  final y = months ~/ 12;
  final m = months % 12;
  final parts = [
    if (y > 0) '$y year${y == 1 ? '' : 's'}',
    if (m > 0) '$m month${m == 1 ? '' : 's'}',
  ];
  return '${parts.join(' ')} experience';
}

/// "62% ready" · "Readiness not measured yet"
String readinessLabel(int? readiness) =>
    readiness == null ? 'Readiness not measured yet' : '$readiness% ready';

/// How much the target role needs a skill.
String importanceLabel(num? importance) {
  final i = importance ?? 0;
  if (i >= 0.9) return 'Essential';
  if (i >= 0.7) return 'Important';
  return 'Useful';
}

/// What backs a skill, in plain words. Null when there is no evidence.
String? careerEvidenceLabel(String? evidence, {bool verified = false}) {
  if (verified) return 'Verified';
  return switch (evidence) {
    null || '' => null,
    'employer_verified' || 'verified_employment' => 'Employer confirmed',
    'assessment' => 'Passed Omelo test',
    'license' || 'credential' => 'Licence or certificate',
    'experience' => 'From work experience',
    'reference' => 'Reference',
    'project' => 'Project',
    'self_declared' => 'Self-declared',
    _ => 'Other evidence',
  };
}

String? proficiencyWords(String? p) => p == null ? null : kProficiencyLabels[p] ?? p;

// ---------------------------------------------------------------------------
// Suggestions
// ---------------------------------------------------------------------------

class CareerSuggestion {
  const CareerSuggestion({
    required this.professionId,
    required this.name,
    this.slug,
    this.typicalMonths,
    this.readiness,
    this.missing = const [],
    this.openJobs = 0,
    this.rank,
  });

  final String professionId;
  final String name;
  final String? slug;
  final int? typicalMonths;

  /// 0–100, or null when the role has no skill list yet.
  final int? readiness;
  final List<String> missing;
  final int openJobs;
  final num? rank;

  static CareerSuggestion? fromJson(Map<String, dynamic> m) {
    final id = _str(m['profession_id']);
    if (id == null) return null;
    return CareerSuggestion(
      professionId: id,
      name: _str(m['name']) ?? 'Role',
      slug: _str(m['slug']),
      typicalMonths: _int(m['typical_months']),
      readiness: _int(m['readiness'])?.clamp(0, 100),
      missing: _strings(m['missing']),
      openJobs: _int(m['open_jobs']) ?? 0,
      rank: _num(m['rank']),
    );
  }
}

List<CareerSuggestion> parseSuggestions(dynamic v) =>
    _maps(v).map(CareerSuggestion.fromJson).whereType<CareerSuggestion>().toList();

/// "12 open jobs" · "1 open job" · "No open jobs right now"
String openJobsLabel(int n) => n <= 0
    ? 'No open jobs right now'
    : '$n open job${n == 1 ? '' : 's'}';

class CareerSuggestions {
  const CareerSuggestions({
    this.identityId,
    this.current,
    this.suggestions = const [],
  });

  final String? identityId;
  final String? current;
  final List<CareerSuggestion> suggestions;

  factory CareerSuggestions.fromJson(dynamic v) {
    final m = _map(v) ?? const <String, dynamic>{};
    return CareerSuggestions(
      identityId: _str(m['work_identity_id']),
      current: _str(m['current']),
      suggestions: parseSuggestions(m['suggestions']),
    );
  }
}

// ---------------------------------------------------------------------------
// Goals
// ---------------------------------------------------------------------------

enum GoalStatus {
  active('active', 'Active'),
  achieved('achieved', 'Achieved'),
  archived('archived', 'Archived');

  const GoalStatus(this.wire, this.label);
  final String wire;
  final String label;

  static GoalStatus fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? active;
}

/// Pay periods the server accepts for a target pay.
const kGoalPayPeriods = <String>[
  'hour',
  'day',
  'week',
  'fortnight',
  'month',
  'year',
  'per_task',
];

class CareerGoal {
  const CareerGoal({
    required this.id,
    this.workIdentityId,
    this.professionId,
    this.profession,
    this.goalText,
    this.targetCountries = const [],
    this.targetPayAmount,
    this.targetPayPeriod,
    this.targetCurrency,
    this.targetDate,
    this.priority = 1,
    this.status = GoalStatus.active,
    this.createdAt,
  });

  final String id;
  final String? workIdentityId;
  final String? professionId;
  final String? profession;
  final String? goalText;
  final List<String> targetCountries;
  final num? targetPayAmount;
  final String? targetPayPeriod;
  final String? targetCurrency;
  final DateTime? targetDate;
  final int priority;
  final GoalStatus status;
  final DateTime? createdAt;

  bool get isActive => status == GoalStatus.active;

  /// "Industrial Electrician", or the worker's own words.
  String get title => profession ?? goalText ?? 'My goal';

  static CareerGoal? fromJson(dynamic v) {
    final m = _map(v);
    final id = _str(m?['id']);
    if (m == null || id == null) return null;
    final prof = m['professions'];
    return CareerGoal(
      id: id,
      workIdentityId: _str(m['work_identity_id']),
      professionId: _str(m['profession_id']),
      profession: _str(m['profession']) ??
          (prof is Map ? _str(prof['name']) : null),
      goalText: _str(m['goal_text']),
      targetCountries: _codes(m['target_countries']),
      targetPayAmount: _num(m['target_pay_amount']),
      targetPayPeriod: _str(m['target_pay_period']),
      targetCurrency: _str(m['target_currency'])?.toUpperCase(),
      targetDate: _date(m['target_date']),
      priority: _int(m['priority']) ?? 1,
      status: GoalStatus.fromWire(_str(m['status'])),
      createdAt: _date(m['created_at']),
    );
  }

  /// "Target pay: €3,000 per month" or null.
  String? get targetPayLine {
    final a = targetPayAmount;
    if (a == null) return null;
    final per = payPeriodWords(targetPayPeriod);
    final body = money(a, targetCurrency);
    return per.isEmpty ? body : '$body $per';
  }
}

List<CareerGoal> parseGoals(dynamic v) =>
    _maps(v).map(CareerGoal.fromJson).whereType<CareerGoal>().toList();

/// What the worker filled in on the goal form.
class GoalDraft {
  const GoalDraft({
    this.id,
    this.workIdentityId,
    this.professionId,
    this.professionName,
    this.goalText,
    this.targetCountries = const [],
    this.targetPayAmount,
    this.targetPayPeriod = 'month',
    this.targetCurrency,
    this.targetDate,
    this.generatePlan = true,
  });

  final String? id;
  final String? workIdentityId;
  final String? professionId;
  final String? professionName;
  final String? goalText;
  final List<String> targetCountries;
  final num? targetPayAmount;
  final String? targetPayPeriod;
  final String? targetCurrency;
  final DateTime? targetDate;
  final bool generatePlan;

  factory GoalDraft.fromGoal(CareerGoal g) => GoalDraft(
    id: g.id,
    workIdentityId: g.workIdentityId,
    professionId: g.professionId,
    professionName: g.profession,
    goalText: g.goalText,
    targetCountries: g.targetCountries,
    targetPayAmount: g.targetPayAmount,
    targetPayPeriod: g.targetPayPeriod ?? 'month',
    targetCurrency: g.targetCurrency,
    targetDate: g.targetDate,
    generatePlan: false,
  );

  /// The body for `omelo_save_career_goal`. The identity is always sent, so
  /// an update never moves the goal to another identity.
  Map<String, Object?> toPayload() {
    final hasPay = targetPayAmount != null;
    return {
      'id': ?id,
      'work_identity_id': ?workIdentityId,
      'profession_id': professionId,
      'goal_text': goalText?.trim().isEmpty ?? true ? null : goalText!.trim(),
      'target_countries': targetCountries,
      'target_pay_amount': targetPayAmount,
      'target_pay_period': hasPay ? targetPayPeriod : null,
      'target_currency': hasPay ? targetCurrency : null,
      'target_date': targetDate == null ? null : wireDate(targetDate!),
      'generate_plan': generatePlan,
    };
  }
}

/// A plain problem with the goal form, or null when it can be saved.
String? validateGoal(GoalDraft d, {DateTime? now}) {
  if (d.professionId == null && (d.goalText?.trim().isEmpty ?? true)) {
    return 'Choose the role you are aiming for.';
  }
  if ((d.goalText?.length ?? 0) > 500) return 'Keep your note under 500 characters.';
  final pay = d.targetPayAmount;
  if (pay != null) {
    if (pay <= 0) return 'Target pay must be more than zero.';
    if (d.targetCurrency == null) return 'Choose the currency for your target pay.';
  }
  final t = d.targetDate;
  if (t != null) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    if (t.isBefore(today)) return 'Choose a target date in the future.';
  }
  return null;
}

/// A number typed by the worker ("25,000" · "18.5"), or null.
num? parseAmount(String s) {
  final t = s.trim().replaceAll(RegExp(r'[,\s]'), '');
  if (t.isEmpty) return null;
  return num.tryParse(t);
}

// ---------------------------------------------------------------------------
// The path
// ---------------------------------------------------------------------------

enum SkillStatus {
  strong('strong', 'Strong'),
  weak('weak', 'Needs evidence or practice'),
  missing('missing', 'Missing');

  const SkillStatus(this.wire, this.label);
  final String wire;
  final String label;

  static SkillStatus fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? missing;
}

class PathSkill {
  const PathSkill({
    required this.skillId,
    required this.name,
    this.slug,
    this.importance,
    this.status = SkillStatus.missing,
    this.proficiency,
    this.evidence,
    this.verified = false,
  });

  final String skillId;
  final String name;
  final String? slug;
  final num? importance;
  final SkillStatus status;
  final String? proficiency;
  final String? evidence;
  final bool verified;

  String? get evidenceLabel => careerEvidenceLabel(evidence, verified: verified);

  /// Why a skill counts as weak, in the worker's words.
  String? get weakReason {
    if (status != SkillStatus.weak) return null;
    if (proficiency == 'beginner' || proficiency == 'basic') {
      return 'Your level is ${proficiencyWords(proficiency)!.toLowerCase()}. '
          'Practise to build it up.';
    }
    return 'Backed only by ${evidenceLabel?.toLowerCase() ?? 'little evidence'}. '
        'A passed test or work experience makes it count.';
  }

  static PathSkill? fromJson(Map<String, dynamic> m) {
    final id = _str(m['skill_id']);
    if (id == null) return null;
    return PathSkill(
      skillId: id,
      name: _str(m['name']) ?? 'Skill',
      slug: _str(m['slug']),
      importance: _num(m['importance']),
      status: SkillStatus.fromWire(_str(m['status'])),
      proficiency: _str(m['proficiency']),
      evidence: _str(m['evidence']),
      verified: _bool(m['verified']),
    );
  }
}

/// Skills grouped Strong → Weak → Missing, each keeping the server's order,
/// most important first. Empty groups are left out.
List<(SkillStatus, List<PathSkill>)> groupSkills(Iterable<PathSkill> skills) {
  final out = <(SkillStatus, List<PathSkill>)>[];
  for (final s in SkillStatus.values) {
    final list = skills.where((k) => k.status == s).toList()
      ..sort((a, b) => (b.importance ?? 0).compareTo(a.importance ?? 0));
    if (list.isNotEmpty) out.add((s, list));
  }
  return out;
}

class AttemptSummary {
  const AttemptSummary({required this.status, this.score, this.at});
  final String status;
  final int? score;
  final DateTime? at;

  bool get passed => status == 'passed';
  bool get inProgress => status == 'in_progress';

  static AttemptSummary? fromJson(dynamic v) {
    final m = _map(v);
    final s = _str(m?['status']);
    if (m == null || s == null) return null;
    return AttemptSummary(status: s, score: _int(m['score']), at: _date(m['at']));
  }
}

class AssessmentInfo {
  const AssessmentInfo({
    required this.id,
    required this.title,
    this.questions,
    this.passPercent,
    this.last,
  });

  final String id;
  final String title;
  final int? questions;
  final int? passPercent;
  final AttemptSummary? last;

  static AssessmentInfo? fromJson(dynamic v) {
    final m = _map(v);
    final id = _str(m?['id']);
    if (m == null || id == null) return null;
    return AssessmentInfo(
      id: id,
      title: _str(m['title']) ?? 'Omelo assessment',
      questions: _int(m['questions']),
      passPercent: _int(m['pass_percent']),
      last: AttemptSummary.fromJson(m['last']),
    );
  }

  /// "5 questions · pass mark 70%"
  String get detailLine => [
    if (questions != null) '$questions questions',
    if (passPercent != null) 'pass mark $passPercent%',
  ].join(' · ');

  /// "Last try: 60%, not passed (19 Sep)" or null.
  String? lastLine(DateTime now) {
    final l = last;
    if (l == null) return null;
    final when = l.at == null ? '' : ' (${_shortDay(l.at!, now)})';
    return switch (l.status) {
      'passed' => 'Passed${l.score == null ? '' : ' with ${l.score}%'}$when',
      'failed' => 'Last try: ${l.score ?? 0}%, not passed$when',
      'in_progress' => 'You have a test in progress$when',
      'expired' => 'Last try ran out of time$when',
      _ => null,
    };
  }
}

String _shortDay(DateTime at, DateTime now) => at.year == now.year
    ? DateFormat('d MMM').format(at)
    : DateFormat('d MMM yyyy').format(at);

class LearningResource {
  const LearningResource({
    required this.id,
    required this.kind,
    required this.title,
    this.description,
    this.provider,
    this.url,
    this.cost,
    this.hours,
  });

  final String id;
  final String kind;
  final String title;
  final String? description;
  final String? provider;
  final String? url;
  final String? cost;
  final num? hours;

  /// Only secure links are opened.
  Uri? get link => safeLink(url);

  bool get isOmeloAssessment => kind == 'omelo_assessment';

  static LearningResource? fromJson(Map<String, dynamic> m) {
    final id = _str(m['id']);
    if (id == null) return null;
    return LearningResource(
      id: id,
      kind: _str(m['kind']) ?? 'course',
      title: _str(m['title']) ?? 'Resource',
      description: _str(m['description']),
      provider: _str(m['provider']),
      url: _str(m['url']),
      cost: _str(m['cost']),
      hours: _num(m['hours']),
    );
  }

  String get kindLabel => switch (kind) {
    'omelo_assessment' => 'Omelo test',
    'practice' => 'Practice',
    'on_the_job' => 'On the job',
    'course' => 'Course',
    'certification' => 'Certification',
    'official_guidance' => 'Official guidance',
    _ => 'Resource',
  };

  String? get costLabel => switch (cost) {
    'free' => 'Free',
    'paid' => 'Paid',
    'employer_sponsored' => 'Employer pays',
    'varies' => 'Cost varies',
    _ => null,
  };

  /// "About 16 hours" · "About 30 minutes"
  String? get hoursLabel {
    final h = hours;
    if (h == null || h <= 0) return null;
    if (h < 1) return 'About ${(h * 60).round()} minutes';
    final whole = h == h.roundToDouble();
    final n = whole ? h.round().toString() : h.toStringAsFixed(1);
    return 'About $n hour${n == '1' ? '' : 's'}';
  }
}

class Recommendation {
  const Recommendation({
    required this.skillId,
    required this.skill,
    required this.status,
    this.assessment,
    this.resources = const [],
  });

  final String skillId;
  final String skill;
  final SkillStatus status;
  final AssessmentInfo? assessment;
  final List<LearningResource> resources;

  /// Resources to list separately: the Omelo test has its own button.
  List<LearningResource> get otherResources => assessment == null
      ? resources
      : resources.where((r) => !r.isOmeloAssessment).toList();

  static Recommendation? fromJson(Map<String, dynamic> m) {
    final id = _str(m['skill_id']);
    if (id == null) return null;
    return Recommendation(
      skillId: id,
      skill: _str(m['skill']) ?? 'Skill',
      status: SkillStatus.fromWire(_str(m['status'])),
      assessment: AssessmentInfo.fromJson(m['assessment']),
      resources: _maps(m['resources'])
          .map(LearningResource.fromJson)
          .whereType<LearningResource>()
          .toList(),
    );
  }
}

class CareerLicence {
  const CareerLicence({
    required this.name,
    this.country,
    this.description,
    this.url,
    this.source,
  });

  final String name;
  final String? country;
  final String? description;
  final String? url;
  final String? source;

  Uri? get link => safeLink(url);

  factory CareerLicence.fromJson(Map<String, dynamic> m) => CareerLicence(
    name: _str(m['name']) ?? 'Licence',
    country: _str(m['country'])?.toUpperCase(),
    description: _str(m['description']),
    url: _str(m['url']),
    source: _str(m['source']),
  );
}

/// Monthly pay across open jobs, in one currency.
class MarketPay {
  const MarketPay({
    required this.currency,
    this.p25,
    this.median,
    this.p75,
    this.jobs = 0,
  });

  final String currency;
  final num? p25;
  final num? median;
  final num? p75;
  final int jobs;

  static MarketPay? fromJson(dynamic v) {
    final m = _map(v);
    final cur = _str(m?['currency'])?.toUpperCase();
    if (m == null || cur == null) return null;
    final p = MarketPay(
      currency: cur,
      p25: _num(m['p25']),
      median: _num(m['median']),
      p75: _num(m['p75']),
      jobs: _int(m['jobs']) ?? 0,
    );
    return p.median == null && p.p25 == null && p.p75 == null ? null : p;
  }
}

const notEnoughPayData = 'Not enough data';

/// "₹25,000 – ₹40,000 a month" · "Not enough data"
String marketPayRange(MarketPay? p) {
  if (p == null) return notEnoughPayData;
  final lo = p.p25, hi = p.p75;
  if (lo != null && hi != null && lo != hi) {
    return '${money(lo, p.currency)} – ${money(hi, p.currency)} a month';
  }
  final one = p.median ?? lo ?? hi;
  return '${money(one!, p.currency)} a month';
}

/// "Typical ₹32,000 · from 9 jobs with pay" or null.
String? marketPayDetail(MarketPay? p) {
  if (p == null) return null;
  return [
    if (p.median != null) 'Typical ${money(p.median!, p.currency)}',
    if (p.jobs > 0) 'from ${p.jobs} job${p.jobs == 1 ? '' : 's'} with pay',
  ].join(' · ');
}

class PathJob {
  const PathJob({
    required this.jobId,
    required this.title,
    this.company,
    this.country,
    this.locationText,
    this.score,
    this.eligible,
    this.eligibility,
    this.missingSkills = const [],
  });

  final String jobId;
  final String title;
  final String? company;
  final String? country;
  final String? locationText;
  final int? score;
  final bool? eligible;
  final EligibilityStatus? eligibility;
  final List<String> missingSkills;

  static PathJob? fromJson(Map<String, dynamic> m) {
    final id = _str(m['job_id']);
    if (id == null) return null;
    final missing = m['missing_skills'];
    return PathJob(
      jobId: id,
      title: _str(m['title']) ?? 'Job',
      company: _str(m['company']),
      country: _str(m['country'])?.toUpperCase(),
      locationText: _str(m['location_text']),
      score: _int(m['score'])?.clamp(0, 100),
      eligible: m['eligible'] == null ? null : _bool(m['eligible']),
      eligibility: EligibilityStatus.fromWire(_str(m['eligibility'])),
      // Names, or objects with a name.
      missingSkills: missing is List
          ? missing
                .map((e) => e is Map ? _str(e['name']) : _str(e))
                .whereType<String>()
                .toList()
          : const [],
    );
  }

  String? get scoreLabel => score == null ? null : '$score% match';
}

// ---------------------------------------------------------------------------
// Plan
// ---------------------------------------------------------------------------

enum PlanKind {
  skill('skill'),
  assessment('assessment'),
  resource('resource'),
  project('project'),
  job('job'),
  licence('licence'),
  custom('custom');

  const PlanKind(this.wire);
  final String wire;

  static PlanKind fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? custom;
}

enum PlanStatus {
  todo('todo', 'To do'),
  inProgress('in_progress', 'In progress'),
  done('done', 'Done'),
  dismissed('dismissed', 'Dismissed');

  const PlanStatus(this.wire, this.label);
  final String wire;
  final String label;

  static PlanStatus fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? todo;
}

class PlanItem {
  const PlanItem({
    required this.id,
    required this.goalId,
    required this.kind,
    required this.title,
    this.skillId,
    this.resourceId,
    this.jobId,
    this.status = PlanStatus.todo,
    this.dueOn,
    this.position = 0,
  });

  final String id;
  final String goalId;
  final PlanKind kind;
  final String title;
  final String? skillId;
  final String? resourceId;
  final String? jobId;
  final PlanStatus status;
  final DateTime? dueOn;
  final int position;

  bool get isDone => status == PlanStatus.done;
  bool get isDismissed => status == PlanStatus.dismissed;

  PlanItem withStatus(PlanStatus s) => PlanItem(
    id: id,
    goalId: goalId,
    kind: kind,
    title: title,
    skillId: skillId,
    resourceId: resourceId,
    jobId: jobId,
    status: s,
    dueOn: dueOn,
    position: position,
  );

  static PlanItem? fromJson(Map<String, dynamic> m) {
    final id = _str(m['id']);
    final goal = _str(m['goal_id']);
    if (id == null || goal == null) return null;
    return PlanItem(
      id: id,
      goalId: goal,
      kind: PlanKind.fromWire(_str(m['kind'])),
      title: _str(m['title']) ?? 'Step',
      skillId: _str(m['skill_id']),
      resourceId: _str(m['resource_id']),
      jobId: _str(m['job_id']),
      status: PlanStatus.fromWire(_str(m['status'])),
      dueOn: _date(m['due_on']),
      position: _int(m['position']) ?? 0,
    );
  }
}

List<PlanItem> parsePlan(dynamic v) {
  final list = _maps(v).map(PlanItem.fromJson).whereType<PlanItem>().toList();
  // Stable sort keeps the server's created order within a position.
  final indexed = list.asMap().entries.toList()
    ..sort((a, b) {
      final c = a.value.position.compareTo(b.value.position);
      return c != 0 ? c : a.key.compareTo(b.key);
    });
  return indexed.map((e) => e.value).toList();
}

/// "3 of 7 done" (dismissed steps do not count).
({int done, int total}) planProgress(Iterable<PlanItem> items) {
  final live = items.where((i) => !i.isDismissed);
  return (done: live.where((i) => i.isDone).length, total: live.length);
}

/// Next position for a new step.
int nextPlanPosition(Iterable<PlanItem> items) =>
    items.fold<int>(0, (m, i) => i.position > m ? i.position : m) + 1;

/// Tapping the checkbox: done ↔ to do (in progress becomes done).
PlanStatus toggledStatus(PlanStatus s) =>
    s == PlanStatus.done ? PlanStatus.todo : PlanStatus.done;

/// A plain problem with a custom step title, or null.
String? validateStepTitle(String s) {
  final t = s.trim();
  if (t.length < 2) return 'Write a few words for this step.';
  if (t.length > 200) return 'Keep the step under 200 characters.';
  return null;
}

// ---------------------------------------------------------------------------
// The whole path
// ---------------------------------------------------------------------------

class CareerTransition {
  const CareerTransition({this.typicalMonths, this.common = false, this.observed});
  final int? typicalMonths;
  final bool common;
  final int? observed;

  static CareerTransition? fromJson(dynamic v) {
    final m = _map(v);
    if (m == null) return null;
    return CareerTransition(
      typicalMonths: _int(m['typical_months']),
      common: _bool(m['common']),
      observed: _int(m['observed']),
    );
  }

  /// "People usually make this move in about 2 years."
  String get line {
    final t = typicalMonths == null
        ? 'The time this move takes varies.'
        : 'People usually make this move in '
              '${typicalTimeLabel(typicalMonths).toLowerCase()}.';
    return common ? '$t A common next step.' : t;
  }
}

class CareerPath {
  const CareerPath({
    this.identityId,
    this.currentProfession,
    this.currentProfessionId,
    this.experienceMonths,
    this.verifiedEmployers,
    this.goal,
    this.transition,
    this.readiness,
    this.skills = const [],
    this.recommended = const [],
    this.licences = const [],
    this.openJobs,
    this.marketPay,
    this.jobs = const [],
    this.plan = const [],
    this.note,
    this.suggestions = const [],
    this.message,
    this.hasPath = false,
  });

  final String? identityId;
  final String? currentProfession;
  final String? currentProfessionId;
  final int? experienceMonths;
  final int? verifiedEmployers;
  final CareerGoal? goal;
  final CareerTransition? transition;
  final int? readiness;
  final List<PathSkill> skills;
  final List<Recommendation> recommended;
  final List<CareerLicence> licences;
  final int? openJobs;
  final MarketPay? marketPay;
  final List<PathJob> jobs;
  final List<PlanItem> plan;
  final String? note;

  /// When there is no goal (or it has no target role yet).
  final List<CareerSuggestion> suggestions;
  final String? message;

  /// True when the server sent the full picture for a goal.
  final bool hasPath;

  factory CareerPath.fromJson(dynamic v) {
    final m = _map(v) ?? const <String, dynamic>{};
    final cur = _map(m['current']);
    final market = _map(m['market']);
    final goal = CareerGoal.fromJson(m['goal']);
    final hasPath = goal?.professionId != null && m.containsKey('skills');
    return CareerPath(
      identityId: _str(m['work_identity_id']),
      currentProfession: cur == null ? _str(m['current']) : _str(cur['profession']),
      currentProfessionId: _str(cur?['profession_id']),
      experienceMonths: _int(cur?['experience_months']),
      verifiedEmployers: _int(cur?['verified_employers']),
      goal: goal,
      transition: CareerTransition.fromJson(m['transition']),
      readiness: _int(m['readiness'])?.clamp(0, 100),
      skills: _maps(m['skills']).map(PathSkill.fromJson).whereType<PathSkill>().toList(),
      recommended: _maps(m['recommended'])
          .map(Recommendation.fromJson)
          .whereType<Recommendation>()
          .toList(),
      licences: _maps(m['licences']).map(CareerLicence.fromJson).toList(),
      openJobs: _int(market?['open_jobs']),
      marketPay: MarketPay.fromJson(market?['pay_monthly']),
      jobs: _maps(m['jobs']).map(PathJob.fromJson).whereType<PathJob>().toList(),
      plan: parsePlan(m['plan']),
      note: _str(m['note']),
      suggestions: parseSuggestions(m['suggestions']),
      message: _str(m['message']),
      hasPath: hasPath,
    );
  }
}

// ---------------------------------------------------------------------------
// Assessments
// ---------------------------------------------------------------------------

class AssessmentQuestion {
  const AssessmentQuestion({
    required this.id,
    required this.prompt,
    required this.options,
  });

  final String id;
  final String prompt;
  final List<String> options;

  static AssessmentQuestion? fromJson(Map<String, dynamic> m) {
    final id = _str(m['id']);
    final options = (m['options'] as List? ?? const [])
        .map((o) => o?.toString() ?? '')
        .toList();
    if (id == null || options.length < 2) return null;
    return AssessmentQuestion(
      id: id,
      prompt: _str(m['prompt']) ?? '',
      options: options,
    );
  }
}

class AssessmentSession {
  const AssessmentSession({
    required this.attemptId,
    required this.title,
    required this.questions,
    this.expiresAt,
    this.passPercent,
  });

  final String attemptId;
  final String title;
  final DateTime? expiresAt;
  final int? passPercent;
  final List<AssessmentQuestion> questions;

  static AssessmentSession? fromJson(dynamic v) {
    final m = _map(v);
    final id = _str(m?['attempt_id']);
    if (m == null || id == null) return null;
    return AssessmentSession(
      attemptId: id,
      title: _str(m['title']) ?? 'Omelo assessment',
      expiresAt: _date(m['expires_at']),
      passPercent: _int(m['pass_percent']),
      questions: _maps(m['questions'])
          .map(AssessmentQuestion.fromJson)
          .whereType<AssessmentQuestion>()
          .toList(),
    );
  }

  Duration? remaining(DateTime now) {
    final e = expiresAt;
    if (e == null) return null;
    final d = e.difference(now);
    return d.isNegative ? Duration.zero : d;
  }
}

/// "12:04" · "1:02:09"
String countdownLabel(Duration d) {
  final s = d.inSeconds < 0 ? 0 : d.inSeconds;
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '$m:${two(sec)}';
}

/// Option indexes in question order, or null while any is unanswered.
List<int>? answersInOrder(
  List<AssessmentQuestion> questions,
  Map<String, int> chosen,
) {
  final out = <int>[];
  for (final q in questions) {
    final a = chosen[q.id];
    if (a == null) return null;
    out.add(a);
  }
  return out;
}

class QuestionReview {
  const QuestionReview({required this.questionId, required this.correct});
  final String questionId;
  final bool correct;
}

class AssessmentResult {
  const AssessmentResult({
    required this.passed,
    required this.scorePercent,
    this.passPercent,
    this.correct = 0,
    this.total = 0,
    this.review = const [],
    this.retryAfter,
  });

  final bool passed;
  final int scorePercent;
  final int? passPercent;
  final int correct;
  final int total;
  final List<QuestionReview> review;
  final DateTime? retryAfter;

  factory AssessmentResult.fromJson(dynamic v) {
    final m = _map(v) ?? const <String, dynamic>{};
    return AssessmentResult(
      passed: _str(m['status']) == 'passed',
      scorePercent: (_int(m['score_percent']) ?? 0).clamp(0, 100),
      passPercent: _int(m['pass_percent']),
      correct: _int(m['correct']) ?? 0,
      total: _int(m['total']) ?? 0,
      review: _maps(m['review'])
          .where((r) => _str(r['question_id']) != null)
          .map((r) => QuestionReview(
                questionId: _str(r['question_id'])!,
                correct: _bool(r['correct']),
              ))
          .toList(),
      retryAfter: _date(m['retry_after']),
    );
  }

  /// "You can try again after 20 Sep, 14:30."
  String? retryLine(DateTime now) {
    final r = retryAfter;
    if (passed || r == null) return null;
    final day = r.year == now.year && r.month == now.month && r.day == now.day
        ? 'today'
        : _shortDay(r, now);
    return 'You can try again after $day, ${DateFormat('HH:mm').format(r)}.';
  }
}

// ---------------------------------------------------------------------------
// Market insights
// ---------------------------------------------------------------------------

class SkillDemand {
  const SkillDemand({required this.name, this.jobs = 0});
  final String name;
  final int jobs;
}

class MarketInsights {
  const MarketInsights({
    this.profession,
    this.country,
    this.openJobs = 0,
    this.openings = 0,
    this.remoteJobs = 0,
    this.sponsoredJobs = 0,
    this.pay,
    this.skillsInDemand = const [],
    this.workers,
    this.note,
  });

  final String? profession;
  final String? country;
  final int openJobs;
  final int openings;
  final int remoteJobs;
  final int sponsoredJobs;
  final MarketPay? pay;
  final List<SkillDemand> skillsInDemand;
  final int? workers;
  final String? note;

  factory MarketInsights.fromJson(dynamic v) {
    final m = _map(v) ?? const <String, dynamic>{};
    return MarketInsights(
      profession: _str(m['profession']),
      country: _str(m['country'])?.toUpperCase(),
      openJobs: _int(m['open_jobs']) ?? 0,
      openings: _int(m['openings']) ?? 0,
      remoteJobs: _int(m['remote_jobs']) ?? 0,
      sponsoredJobs: _int(m['sponsored_jobs']) ?? 0,
      pay: MarketPay.fromJson(m['pay_monthly']),
      skillsInDemand: _maps(m['skills_in_demand'])
          .where((s) => _str(s['name']) != null)
          .map((s) => SkillDemand(name: _str(s['name'])!, jobs: _int(s['jobs']) ?? 0))
          .toList(),
      workers: _int(m['workers']),
      note: _str(m['note']),
    );
  }
}
