import 'package:intl/intl.dart';

import 'job.dart';

/// Hiring loop models and the plain-words copy that explains them.
///
/// Everything in this file is pure Dart (no Flutter, no Supabase) so the
/// "what happens next" logic can be unit tested. The worker should never
/// wonder what happened to an application — every state maps to a sentence.

// ---------------------------------------------------------------------------
// Parse helpers — tolerant of missing or oddly typed fields.
// ---------------------------------------------------------------------------

Map<String, dynamic>? _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

/// PostgREST returns a to-one embed as a map, but some relationship shapes
/// come back as a single-element list. Accept both.
Map<String, dynamic>? _embed(dynamic v) {
  if (v is List) return v.isEmpty ? null : _map(v.first);
  return _map(v);
}

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

num? _num(dynamic v) =>
    v == null ? null : (v is num ? v : num.tryParse(v.toString()));

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

bool _bool(dynamic v) => v == true || v?.toString() == 'true';

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.map(_map).whereType<Map<String, dynamic>>().toList()
    : const [];

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

const kOpenApplicationStates = {
  'applied',
  'viewed',
  'shortlisted',
  'screening',
  'assessment',
  'interview',
  'offer',
};

const kOpenInterviewStatuses = {'scheduled', 'rescheduled'};
const kOpenOfferStatuses = {'sent', 'viewed', 'negotiating'};

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class Interview {
  Interview({
    required this.id,
    required this.applicationId,
    required this.type,
    required this.status,
    this.round,
    this.scheduledAt,
    this.durationMinutes,
    this.timezone,
    this.meetingUrl,
    this.locationText,
    this.instructions,
    this.candidateConfirmedAt,
    this.cancelReason,
  });

  final String id;
  final String applicationId;
  final String type;
  final String status;
  final int? round;
  final DateTime? scheduledAt;
  final int? durationMinutes;
  final String? timezone;
  final String? meetingUrl;
  final String? locationText;
  final String? instructions;
  final DateTime? candidateConfirmedAt;
  final String? cancelReason;

  bool get isOpen => kOpenInterviewStatuses.contains(status);
  bool get isConfirmed => candidateConfirmedAt != null;

  /// Still worth acting on: open, and not more than a few hours in the past.
  bool isUpcoming(DateTime now) =>
      isOpen &&
      (scheduledAt == null ||
          scheduledAt!
              .add(Duration(minutes: durationMinutes ?? 60))
              .isAfter(now));

  factory Interview.fromRow(Map<String, dynamic> m) => Interview(
        id: m['id'].toString(),
        applicationId: (m['application_id'] ?? '').toString(),
        type: _str(m['type']) ?? 'in_person',
        status: _str(m['status']) ?? 'scheduled',
        round: _num(m['round'])?.toInt(),
        scheduledAt: _date(m['scheduled_at']),
        durationMinutes: _num(m['duration_minutes'])?.toInt(),
        timezone: _str(m['timezone']),
        meetingUrl: _str(m['meeting_url']),
        locationText: _str(m['location_text']),
        instructions: _str(m['instructions']),
        candidateConfirmedAt: _date(m['candidate_confirmed_at']),
        cancelReason: _str(m['cancel_reason']),
      );
}

class Offer {
  Offer({
    required this.id,
    required this.applicationId,
    required this.status,
    this.title,
    this.payAmount,
    this.payPeriod,
    this.payCurrency,
    this.startDate,
    this.expiresAt,
    this.conditions,
    this.benefits = const [],
    this.sentAt,
    this.respondedAt,
  });

  final String id;
  final String applicationId;
  final String status;
  final String? title;
  final num? payAmount;
  final String? payPeriod;
  final String? payCurrency;
  final DateTime? startDate;
  final DateTime? expiresAt;
  final String? conditions;
  final List<String> benefits;
  final DateTime? sentAt;
  final DateTime? respondedAt;

  bool isExpired(DateTime now) =>
      status == 'expired' || (expiresAt != null && expiresAt!.isBefore(now));

  /// An offer the worker can still accept or decline.
  bool isOpen(DateTime now) =>
      kOpenOfferStatuses.contains(status) && !isExpired(now);

  factory Offer.fromRow(Map<String, dynamic> m) => Offer(
        id: m['id'].toString(),
        applicationId: (m['application_id'] ?? '').toString(),
        status: _str(m['status']) ?? 'sent',
        title: _str(m['title']),
        payAmount: _num(m['pay_amount']),
        payPeriod: _str(m['pay_period']),
        payCurrency: _str(m['pay_currency']),
        // A date column: parse without shifting it across a timezone.
        startDate: m['start_date'] == null
            ? null
            : DateTime.tryParse(m['start_date'].toString()),
        expiresAt: _date(m['expires_at']),
        conditions: _str(m['conditions']),
        benefits: Job.parseStrList(m['benefits']),
        sentAt: _date(m['sent_at']),
        respondedAt: _date(m['responded_at']),
      );
}

class ApplicationEvent {
  ApplicationEvent({
    required this.eventType,
    required this.actorType,
    this.fromState,
    this.toState,
    this.reason,
    this.metadata = const {},
    this.occurredAt,
  });

  final String eventType;
  final String actorType;
  final String? fromState;
  final String? toState;
  final String? reason;
  final Map<String, dynamic> metadata;
  final DateTime? occurredAt;

  factory ApplicationEvent.fromRow(Map<String, dynamic> m) => ApplicationEvent(
        eventType: _str(m['event_type']) ?? '',
        actorType: _str(m['actor_type']) ?? 'system',
        fromState: _str(m['from_state']),
        toState: _str(m['to_state']),
        reason: _str(m['reason']),
        metadata: _map(m['metadata']) ?? const {},
        occurredAt: _date(m['occurred_at']),
      );
}

class ApplicationSummary {
  ApplicationSummary({
    required this.id,
    required this.jobId,
    required this.jobTitle,
    required this.companyName,
    required this.state,
    required this.appliedAt,
    this.lastActivityAt,
    this.companyId,
    this.companySlug,
    this.companyLogoUrl,
    this.matchScore,
    this.firstViewedAt,
    this.closedAt,
    this.rejectionReason,
    this.withdrawalReason,
    this.medianResponseHours,
    this.payMin,
    this.payMax,
    this.payPeriod,
    this.payCurrency,
    this.locationText,
    this.interviews = const [],
    this.offers = const [],
  });

  final String id;
  final String jobId;
  final String jobTitle;
  final String companyName;
  final String state;
  final DateTime appliedAt;
  final DateTime? lastActivityAt;
  final String? companyId;
  final String? companySlug;
  final String? companyLogoUrl;
  final int? matchScore;
  final DateTime? firstViewedAt;
  final DateTime? closedAt;
  final String? rejectionReason;
  final String? withdrawalReason;
  final int? medianResponseHours;
  final num? payMin;
  final num? payMax;
  final String? payPeriod;
  final String? payCurrency;
  final String? locationText;
  final List<Interview> interviews;
  final List<Offer> offers;

  bool get isOpen => kOpenApplicationStates.contains(state);
  bool get isHired => state == 'hired';

  /// Closed for good — rejected, withdrawn, expired or declined.
  bool get isTerminal => !isOpen && !isHired;

  int daysSinceActivity(DateTime now) =>
      now.difference(lastActivityAt ?? appliedAt).inDays;

  /// PR-4: silence is a displayed state, not an absence of one.
  bool isSilent(DateTime now) =>
      isOpen && state != 'offer' && daysSinceActivity(now) >= 5;

  /// The next interview still to happen, soonest first.
  Interview? nextInterview(DateTime now) {
    final open = interviews.where((i) => i.isUpcoming(now)).toList()
      ..sort((a, b) => (a.scheduledAt ?? DateTime(9999))
          .compareTo(b.scheduledAt ?? DateTime(9999)));
    return open.isEmpty ? null : open.first;
  }

  Offer? openOffer(DateTime now) {
    for (final o in _offersNewestFirst) {
      if (o.isOpen(now)) return o;
    }
    return null;
  }

  Offer? get acceptedOffer {
    for (final o in _offersNewestFirst) {
      if (o.status == 'accepted') return o;
    }
    return null;
  }

  /// The most relevant offer to show: open, else accepted, else newest.
  Offer? latestOffer(DateTime now) =>
      openOffer(now) ??
      acceptedOffer ??
      (offers.isEmpty ? null : _offersNewestFirst.first);

  List<Offer> get _offersNewestFirst => [...offers]..sort((a, b) =>
      (b.sentAt ?? DateTime(0)).compareTo(a.sentAt ?? DateTime(0)));

  String get companyOrEmployer =>
      companyName.trim().isEmpty ? 'the employer' : companyName.trim();

  ApplicationSummary copyWith({
    List<Interview>? interviews,
    List<Offer>? offers,
  }) =>
      ApplicationSummary(
        id: id,
        jobId: jobId,
        jobTitle: jobTitle,
        companyName: companyName,
        state: state,
        appliedAt: appliedAt,
        lastActivityAt: lastActivityAt,
        companyId: companyId,
        companySlug: companySlug,
        companyLogoUrl: companyLogoUrl,
        matchScore: matchScore,
        firstViewedAt: firstViewedAt,
        closedAt: closedAt,
        rejectionReason: rejectionReason,
        withdrawalReason: withdrawalReason,
        medianResponseHours: medianResponseHours,
        payMin: payMin,
        payMax: payMax,
        payPeriod: payPeriod,
        payCurrency: payCurrency,
        locationText: locationText,
        interviews: interviews ?? this.interviews,
        offers: offers ?? this.offers,
      );

  factory ApplicationSummary.fromRow(Map<String, dynamic> m) {
    final job = _embed(m['jobs']);
    final co = _embed(m['companies']);
    return ApplicationSummary(
      id: m['id'].toString(),
      jobId: (m['job_id'] ?? '').toString(),
      companyId: _str(m['company_id']),
      jobTitle: _str(job?['title']) ?? 'Job',
      companyName: _str(co?['display_name']) ?? '',
      companySlug: _str(co?['slug']),
      companyLogoUrl: _str(co?['logo_url']),
      medianResponseHours: _num(co?['median_response_hours'])?.toInt(),
      state: _str(m['state']) ?? 'applied',
      matchScore: _num(m['match_score'])?.toInt(),
      appliedAt: _date(m['applied_at']) ?? DateTime.now(),
      lastActivityAt: _date(m['last_activity_at']),
      firstViewedAt: _date(m['first_viewed_at']),
      closedAt: _date(m['closed_at']),
      rejectionReason: _str(m['rejection_reason']),
      withdrawalReason: _str(m['withdrawal_reason']),
      payMin: _num(job?['pay_min']),
      payMax: _num(job?['pay_max']),
      payPeriod: _str(job?['pay_period']),
      payCurrency: _str(job?['pay_currency']),
      locationText: _str(job?['location_text']),
    );
  }
}

class ApplicationDetail {
  ApplicationDetail({required this.application, required this.events});
  final ApplicationSummary application;

  /// Oldest first.
  final List<ApplicationEvent> events;
}

class OfferResponse {
  const OfferResponse({required this.status, this.employmentId, this.experienceId});
  final String status;
  final String? employmentId;
  final String? experienceId;

  factory OfferResponse.fromJson(dynamic v) {
    final m = _map(v) ?? const {};
    return OfferResponse(
      status: _str(m['status']) ?? '',
      employmentId: _str(m['employment_id']),
      experienceId: _str(m['experience_id']),
    );
  }
}

class MatchFactor {
  const MatchFactor({required this.factor, required this.weight, required this.text});
  final String factor;
  final double weight;
  final String text;

  static List<MatchFactor> listFrom(dynamic v) => _maps(v)
      .map((m) => MatchFactor(
            factor: _str(m['factor']) ?? '',
            weight: _num(m['weight'])?.toDouble() ?? 0,
            text: _str(m['text']) ?? '',
          ))
      .where((f) => f.text.isNotEmpty || f.factor.isNotEmpty)
      .toList()
    ..sort((a, b) => b.weight.compareTo(a.weight));
}

class MatchResult {
  MatchResult({
    required this.score,
    required this.eligible,
    this.gateFailures = const [],
    this.strengths = const [],
    this.gaps = const [],
    this.unknowns = const [],
    this.missingSkills = const [],
  });

  final int score;
  final bool eligible;
  final List<String> gateFailures;
  final List<MatchFactor> strengths;
  final List<MatchFactor> gaps;
  final List<MatchFactor> unknowns;
  final List<String> missingSkills;

  factory MatchResult.fromJson(dynamic v) {
    final m = _map(v) ?? const {};
    return MatchResult(
      score: (_num(m['score']) ?? 0).round().clamp(0, 100),
      eligible: m['eligible'] == null ? true : _bool(m['eligible']),
      gateFailures: Job.parseStrList(m['gate_failures']),
      strengths: MatchFactor.listFrom(m['strengths']),
      gaps: MatchFactor.listFrom(m['gaps']),
      unknowns: MatchFactor.listFrom(m['unknowns']),
      missingSkills: Job.parseStrList(m['missing_skills']),
    );
  }
}

class RecommendedJob {
  RecommendedJob({
    required this.jobId,
    required this.score,
    required this.eligible,
    this.distanceKm,
    this.strengths = const [],
    this.gaps = const [],
  });

  final String jobId;
  final int score;
  final bool eligible;
  final double? distanceKm;
  final List<MatchFactor> strengths;
  final List<MatchFactor> gaps;

  factory RecommendedJob.fromRow(Map<String, dynamic> m) => RecommendedJob(
        jobId: m['job_id'].toString(),
        score: (_num(m['score']) ?? 0).round(),
        eligible: m['eligible'] == null ? true : _bool(m['eligible']),
        distanceKm: _num(m['distance_km'])?.toDouble(),
        strengths: MatchFactor.listFrom(m['strengths']),
        gaps: MatchFactor.listFrom(m['gaps']),
      );
}

// ---------------------------------------------------------------------------
// Plain-words copy
// ---------------------------------------------------------------------------

enum StepTone { action, waiting, good, closed }

class NextStep {
  const NextStep(this.text, this.tone);
  final String text;
  final StepTone tone;

  bool get needsAction => tone == StepTone.action;

  @override
  String toString() => 'NextStep($tone, $text)';
}

class TimelineEntry {
  const TimelineEntry(this.title, {this.detail, this.tone = StepTone.waiting, this.at});
  final String title;
  final String? detail;
  final StepTone tone;
  final DateTime? at;
}

/// Summary-bar filters on the Application Center.
enum ApplicationFilter { active, interviews, offers, hired }

class HiringCopy {
  static String day(DateTime d) => DateFormat('EEE d MMM').format(d);
  static String dayTime(DateTime d) => DateFormat('EEE d MMM, h:mm a').format(d);
  static String date(DateTime d) => DateFormat('d MMM yyyy').format(d);

  /// Short chip label for a state, in plain words.
  static String statusLabel(String state) => switch (state) {
        'applied' => 'Applied',
        'viewed' => 'Seen',
        'shortlisted' => 'Shortlisted',
        'screening' => 'Screening',
        'assessment' => 'Test stage',
        'interview' => 'Interview',
        'offer' => 'Offer',
        'hired' => 'Hired',
        'rejected' => 'Not selected',
        'withdrawn' => 'Withdrawn',
        'expired' => 'Closed',
        'declined_by_candidate' => 'You declined',
        _ => state.replaceAll('_', ' '),
      };

  static String interviewType(String type) => switch (type) {
        'phone' => 'Phone call',
        'video' => 'Video call',
        'in_person' => 'In person',
        'group' => 'Group interview',
        'walk_in' => 'Walk-in',
        'trial_shift' => 'Trial shift',
        'practical_test' => 'Practical test',
        'assessment_centre' => 'Assessment day',
        'panel' => 'Panel interview',
        _ => type.replaceAll('_', ' '),
      };

  /// The single most important line on an application card.
  static NextStep nextStep(ApplicationSummary a, DateTime now) {
    final co = a.companyOrEmployer;

    switch (a.state) {
      case 'hired':
        final start = a.acceptedOffer?.startDate;
        return NextStep(
          start == null
              ? 'Hired. Added to your verified work history.'
              : 'Hired — starts ${day(start)}. Added to your verified work history.',
          StepTone.good,
        );
      case 'rejected':
        return NextStep(
          a.rejectionReason == null
              ? 'Not moving forward. $co did not give a reason.'
              : 'Not moving forward: ${a.rejectionReason}',
          StepTone.closed,
        );
      case 'withdrawn':
        return const NextStep('You withdrew this application.', StepTone.closed);
      case 'declined_by_candidate':
        return const NextStep('You turned down this offer.', StepTone.closed);
      case 'expired':
        return NextStep(
            'Closed. $co did not reply in time.', StepTone.closed);
    }

    if (a.state == 'offer') {
      final offer = a.openOffer(now);
      if (offer != null) {
        return NextStep(
          offer.expiresAt == null
              ? 'Next: respond to your offer'
              : 'Next: respond to your offer by ${day(offer.expiresAt!)}',
          StepTone.action,
        );
      }
      final latest = a.latestOffer(now);
      if (latest != null && latest.isExpired(now)) {
        return const NextStep('Your offer has expired.', StepTone.closed);
      }
      return NextStep('Next: $co is preparing your offer', StepTone.waiting);
    }

    // An interview can be booked at any open stage.
    final interview = a.nextInterview(now);
    if (interview != null) {
      final when = interview.scheduledAt;
      if (!interview.isConfirmed) {
        return NextStep(
          when == null
              ? 'Next: confirm your interview'
              : 'Next: confirm your interview on ${day(when)}',
          StepTone.action,
        );
      }
      return NextStep(
        when == null
            ? 'Next: attend your interview'
            : 'Next: attend interview ${dayTime(when)}',
        StepTone.waiting,
      );
    }

    return switch (a.state) {
      'applied' => NextStep('Next: waiting for $co to view', StepTone.waiting),
      'viewed' => NextStep('Next: $co is reviewing', StepTone.waiting),
      'interview' => NextStep(
          'Next: $co will tell you what happens after the interview',
          StepTone.waiting),
      _ => NextStep('Next: $co may contact you', StepTone.waiting),
    };
  }

  /// Applications needing the worker, then the rest of the open ones, then
  /// hires, then closed. Each list keeps the input order.
  static ({
    List<ApplicationSummary> needsAction,
    List<ApplicationSummary> active,
    List<ApplicationSummary> hired,
    List<ApplicationSummary> closed,
  }) sections(List<ApplicationSummary> apps, DateTime now) {
    final needs = <ApplicationSummary>[];
    final active = <ApplicationSummary>[];
    final hired = <ApplicationSummary>[];
    final closed = <ApplicationSummary>[];
    for (final a in apps) {
      if (a.isHired) {
        hired.add(a);
      } else if (a.isTerminal) {
        closed.add(a);
      } else if (nextStep(a, now).needsAction) {
        needs.add(a);
      } else {
        active.add(a);
      }
    }
    return (needsAction: needs, active: active, hired: hired, closed: closed);
  }

  static bool matchesFilter(
      ApplicationSummary a, ApplicationFilter f, DateTime now) {
    return switch (f) {
      ApplicationFilter.active => a.isOpen,
      ApplicationFilter.interviews => a.isOpen &&
          (a.state == 'interview' || a.nextInterview(now) != null),
      ApplicationFilter.offers => a.state == 'offer',
      ApplicationFilter.hired => a.isHired,
    };
  }

  /// One timeline line per event, from the worker's side. Returns null for
  /// events that would only repeat another line.
  static TimelineEntry? event(ApplicationEvent e, String companyName) {
    final co = companyName.trim().isEmpty ? 'The employer' : companyName.trim();
    final at = e.occurredAt;
    final byMe = e.actorType == 'candidate';

    switch (e.eventType) {
      case 'created':
        return TimelineEntry('You applied', at: at);
      case 'viewed':
        return TimelineEntry('$co viewed your application', at: at);
      case 'shortlisted':
        return TimelineEntry('You were shortlisted', tone: StepTone.good, at: at);
      case 'stage_changed':
        return switch (e.toState) {
          'viewed' => TimelineEntry('$co viewed your application', at: at),
          'shortlisted' =>
            TimelineEntry('You were shortlisted', tone: StepTone.good, at: at),
          'screening' => TimelineEntry('$co is screening your application', at: at),
          'assessment' => TimelineEntry('You moved to the test stage', at: at),
          'interview' => TimelineEntry('You moved to the interview stage',
              tone: StepTone.good, at: at),
          _ => TimelineEntry('Your application moved forward', at: at),
        };
      case 'interview_scheduled':
        if (_bool(e.metadata['confirmed'])) {
          return TimelineEntry('You confirmed the interview',
              tone: StepTone.good, at: at);
        }
        if (e.metadata['rescheduled_from'] != null) {
          final to = _date(e.metadata['scheduled_at']);
          return TimelineEntry('Interview moved to a new time',
              detail: to == null ? null : 'New time: ${dayTime(to)}', at: at);
        }
        final when = _date(e.metadata['scheduled_at']);
        return TimelineEntry('Interview scheduled',
            detail: when == null ? null : dayTime(when),
            tone: StepTone.good,
            at: at);
      case 'interview_completed':
        return switch (_str(e.metadata['outcome'])) {
          'cancelled' => byMe
              ? TimelineEntry("You said you can't attend the interview",
                  detail: e.reason, tone: StepTone.closed, at: at)
              : TimelineEntry('$co cancelled the interview',
                  detail: e.reason, tone: StepTone.closed, at: at),
          'no_show_candidate' => TimelineEntry('Interview marked as missed',
              tone: StepTone.closed, at: at),
          'no_show_employer' => TimelineEntry(
              "$co didn't come to the interview",
              tone: StepTone.closed,
              at: at),
          _ => TimelineEntry('Interview done', at: at),
        };
      case 'offer_extended':
        return TimelineEntry('Offer received', tone: StepTone.good, at: at);
      case 'offer_responded':
        return switch (_str(e.metadata['status'])) {
          'accepted' =>
            TimelineEntry('You accepted the offer', tone: StepTone.good, at: at),
          'declined' => TimelineEntry('You declined the offer',
              detail: e.reason, tone: StepTone.closed, at: at),
          'withdrawn' => TimelineEntry('$co withdrew the offer',
              detail: e.reason, tone: StepTone.closed, at: at),
          _ => TimelineEntry('Offer updated', at: at),
        };
      case 'decision_made':
        return switch (e.toState) {
          'hired' => TimelineEntry('Hired',
              detail: 'Added to your verified work history.',
              tone: StepTone.good,
              at: at),
          'rejected' => TimelineEntry(
              e.reason == null
                  ? 'Not moving forward'
                  : 'Not moving forward — ${e.reason}',
              tone: StepTone.closed,
              at: at),
          // "You declined the offer" already says this.
          'declined_by_candidate' => null,
          _ => null,
        };
      case 'withdrawn':
        return TimelineEntry('You withdrew your application',
            detail: e.reason, tone: StepTone.closed, at: at);
      case 'expired':
        return TimelineEntry('Closed with no reply',
            tone: StepTone.closed, at: at);
    }
    return null;
  }

  // -- Match explanations ---------------------------------------------------

  /// Strengths worth showing: skip ones that are only true because the job
  /// asks for nothing ("No licence required").
  static List<MatchFactor> topStrengths(MatchResult m, {int count = 3}) {
    final real = m.strengths.where((s) => !s.text.startsWith('No ')).toList();
    return real.take(count).toList();
  }

  static List<MatchFactor> topGaps(MatchResult m, {int count = 3}) =>
      m.gaps.where((g) => g.text.isNotEmpty).take(count).toList();

  /// Unknowns rephrased as something the worker can do. Unknowns they cannot
  /// fix (the job hides its pay) are dropped.
  static List<String> tips(MatchResult m, {int count = 3}) {
    final out = <String>[];
    for (final u in m.unknowns) {
      final t = tipFor(u);
      if (t != null && !out.contains(t)) out.add(t);
      if (out.length == count) break;
    }
    return out;
  }

  static String? tipFor(MatchFactor f) => switch (f.factor) {
        'profession_fit' => 'Add the kind of work you do to improve matches',
        'skill_coverage_required' ||
        'skill_coverage_preferred' =>
          'Add your skills to improve matches',
        'skill_depth' => 'Say how good you are at each skill',
        'experience_fit' => 'Add your work experience to improve matches',
        'distance_fit' => 'Set your location to see how far jobs are',
        'pay_fit' => f.text.toLowerCase().contains('expectation')
            ? 'Add the pay you expect to improve matches'
            : null,
        'shift_fit' => 'Add your shift preference to improve matches',
        'availability_fit' => 'Say when you can start work',
        'work_type_fit' => 'Add the type of work you want',
        'language_fit' => 'Add the languages you speak',
        'attribute_fit' => 'Fill in your profile details',
        'trajectory_fit' || 'company_preference' => null,
        _ => f.text.isEmpty ? null : f.text,
      };

  static String gateFailure(String code) => switch (code) {
        'job_open' => 'This job is no longer taking applications',
        'work_authorization' => 'You may need permission to work in this country',
        'required_licence' => 'This job needs a licence that is not on your profile',
        _ => code.replaceAll('_', ' '),
      };
}
