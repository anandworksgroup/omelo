import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omelo_user_app/core/app_state.dart';
import 'package:omelo_user_app/core/router.dart' show careerRoutes;
import 'package:omelo_user_app/core/theme.dart';
import 'package:omelo_user_app/data/career_repository.dart';
import 'package:omelo_user_app/data/global_repository.dart'
    show countriesProvider, parseCountries;
import 'package:omelo_user_app/data/identity.dart' show WorkIdentity;
import 'package:omelo_user_app/data/identity_repository.dart'
    show myIdentitiesProvider;
import 'package:omelo_user_app/features/career/career_widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final fixedNow = DateTime(2026, 9, 19, 12);

Map<String, dynamic> goalJson({String status = 'active'}) => {
  'id': 'g1',
  'work_identity_id': 'wi1',
  'profession_id': 'p-ind',
  'profession': 'Industrial Electrician',
  'goal_text': null,
  'target_countries': ['de', 'XX1', 'DE'],
  'target_pay_amount': 3200,
  'target_pay_period': 'month',
  'target_currency': 'eur',
  'target_date': '2028-01-01',
  'priority': 1,
  'status': status,
  'created_at': '2026-09-19T10:00:00Z',
};

Map<String, dynamic> pathJson({int readiness = 48}) => {
  'work_identity_id': 'wi1',
  'current': {
    'profession': 'Electrician',
    'profession_id': 'p-elec',
    'experience_months': 38,
    'verified_employers': 1,
  },
  'goal': goalJson(),
  'transition': {'typical_months': 24, 'common': true, 'observed': 0},
  'readiness': readiness,
  'skills': [
    {
      'skill_id': 's-pm',
      'name': 'Preventive maintenance',
      'importance': 0.6,
      'status': 'missing',
      'proficiency': null,
      'evidence': null,
      'verified': false,
    },
    {
      'skill_id': 's-plc',
      'name': 'PLC programming',
      'slug': 'plc-programming',
      'importance': 0.9,
      'status': 'missing',
      'proficiency': null,
      'evidence': null,
      'verified': false,
    },
    {
      'skill_id': 's-mc',
      'name': 'Motor controls',
      'importance': 0.9,
      'status': 'weak',
      'proficiency': 'intermediate',
      'evidence': 'self_declared',
      'verified': false,
    },
    {
      'skill_id': 's-wire',
      'name': 'Electrical wiring',
      'importance': 1.0,
      'status': 'strong',
      'proficiency': 'advanced',
      'evidence': 'experience',
      'verified': false,
    },
  ],
  'missing': ['PLC programming', 'Preventive maintenance'],
  'weak': ['Motor controls'],
  'strong': ['Electrical wiring'],
  'recommended': [
    {
      'skill_id': 's-plc',
      'skill': 'PLC programming',
      'status': 'missing',
      'assessment': {
        'id': 'a1',
        'title': 'PLC programming basics',
        'questions': 5,
        'pass_percent': 70,
        'last': null,
      },
      'resources': [
        {
          'id': 'r0',
          'kind': 'omelo_assessment',
          'title': 'PLC programming basics — Omelo assessment',
          'cost': 'free',
          'hours': 0.5,
        },
        {
          'id': 'r1',
          'kind': 'course',
          'title': 'Vendor or ITI course in PLC programming',
          'provider': 'Training provider',
          'url': 'https://training.example.org/plc',
          'cost': 'varies',
          'hours': 40,
        },
        {
          'id': 'r2',
          'kind': 'practice',
          'title': 'Wire a starter at home',
          'url': 'http://insecure.example.org',
          'cost': 'free',
          'hours': 6,
        },
      ],
    },
    {
      'skill_id': 's-mc',
      'skill': 'Motor controls',
      'status': 'weak',
      'assessment': {
        'id': 'a2',
        'title': 'Motor control fundamentals',
        'questions': 5,
        'pass_percent': 70,
        'last': {'status': 'failed', 'score': 40, 'at': '2026-09-18T10:00:00Z'},
      },
      'resources': [],
    },
  ],
  'licences': [
    {
      'country': 'DE',
      'name': 'Elektrofachkraft qualification',
      'description': 'Recognised electrical qualification.',
      'url': 'https://www.anerkennung-in-deutschland.de',
      'source': 'Official portal',
    },
  ],
  'market': {'open_jobs': 4, 'pay_monthly': null},
  'jobs': [
    {
      'job_id': 'j1',
      'title': 'Industrial Electrician',
      'company': 'Werk GmbH',
      'country': 'DE',
      'location_text': 'Munich',
      'score': 82,
      'eligible': false,
      'eligibility': 'potentially_eligible',
      'missing_skills': ['PLC programming'],
    },
  ],
  'plan': [
    {
      'id': 'pi2',
      'goal_id': 'g1',
      'kind': 'skill',
      'skill_id': 's-mc',
      'title': 'Show evidence of Motor controls',
      'status': 'done',
      'position': 2,
    },
    {
      'id': 'pi1',
      'goal_id': 'g1',
      'kind': 'assessment',
      'skill_id': 's-plc',
      'title': 'Learn PLC programming',
      'status': 'todo',
      'position': 1,
    },
    {
      'id': 'pi3',
      'goal_id': 'g1',
      'kind': 'custom',
      'title': 'Old idea',
      'status': 'dismissed',
      'position': 3,
    },
  ],
  'note': 'Readiness weighs each skill by how much the role needs it and by the evidence behind it.',
};

Map<String, dynamic> noGoalJson() => {
  'work_identity_id': 'wi1',
  'current': {'profession': 'Electrician', 'experience_months': 38},
  'goal': null,
  'suggestions': [
    {
      'profession_id': 'p-ind',
      'name': 'Industrial Electrician',
      'slug': 'industrial-electrician',
      'typical_months': 24,
      'readiness': 48,
      'missing': ['PLC programming', 'Preventive maintenance'],
      'open_jobs': 4,
      'rank': 0.67,
    },
    {
      'profession_id': 'p-mt',
      'name': 'Maintenance Technician',
      'typical_months': 18,
      'readiness': null,
      'missing': [],
      'open_jobs': 0,
      'rank': 0.36,
    },
  ],
  'message': 'Choose a career goal to see your path',
};

Map<String, dynamic> sessionJson() => {
  'attempt_id': 'att1',
  'title': 'PLC programming basics',
  'expires_at': fixedNow.add(const Duration(minutes: 20)).toUtc().toIso8601String(),
  'pass_percent': 70,
  'questions': [
    {
      'id': 'q1',
      'prompt': 'What does a normally open contact do when its bit is ON?',
      'options': ['Blocks power', 'Passes power', 'Resets output'],
    },
    {
      'id': 'q2',
      'prompt': 'What is the order of a PLC scan cycle?',
      'options': ['Execute, read, write', 'Read, execute, write'],
    },
    {
      'id': 'q3',
      'prompt': 'Why are stop buttons wired normally closed?',
      'options': ['Cheaper', 'Fail-safe', 'Fewer inputs'],
    },
  ],
};

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeCareer implements CareerRepository {
  Map<String, dynamic> pathData = pathJson();
  final calls = <String, Object?>{};
  final pathCalls = <CareerKey>[];
  Object? startError;
  Map<String, dynamic> result = {
    'status': 'passed',
    'score_percent': 67,
    'pass_percent': 60,
    'correct': 2,
    'total': 3,
    'review': [
      {'question_id': 'q1', 'correct': true},
      {'question_id': 'q2', 'correct': false},
      {'question_id': 'q3', 'correct': true},
    ],
    'retry_after': null,
  };
  List<CareerGoal> goals = [];

  @override
  Future<CareerPath> path({String? goalId, String? identityId}) async {
    pathCalls.add((goal: goalId, identity: identityId));
    return CareerPath.fromJson(pathData);
  }

  @override
  Future<CareerSuggestions> suggestions({String? identityId}) async =>
      CareerSuggestions.fromJson(noGoalJson());

  @override
  Future<List<CareerGoal>> myGoals() async => goals;

  @override
  Future<CareerGoal?> saveGoal(GoalDraft d) async {
    calls['save'] = d.toPayload();
    pathData = pathJson();
    return CareerGoal.fromJson(goalJson());
  }

  @override
  Future<void> setGoalStatus(CareerGoal g, GoalStatus s) async =>
      calls['status'] = s.wire;

  @override
  Future<void> addPlanItem({
    required String goalId,
    required PlanKind kind,
    required String title,
    required int position,
    String? skillId,
    String? resourceId,
    String? jobId,
  }) async =>
      calls['add'] = {
        'goal': goalId,
        'kind': kind.wire,
        'title': title,
        'position': position,
        'resource': resourceId,
        'job': jobId,
      };

  @override
  Future<void> setPlanStatus(String itemId, PlanStatus s) async =>
      calls['plan'] = '$itemId:${s.wire}';

  @override
  Future<AssessmentSession?> startAssessment(String skillId, {String? identityId}) async {
    calls['start'] = skillId;
    if (startError != null) throw startError!;
    return AssessmentSession.fromJson(sessionJson());
  }

  @override
  Future<AssessmentResult> submitAssessment(String attemptId, List<int> answers) async {
    calls['submit'] = {'attempt': attemptId, 'answers': answers};
    return AssessmentResult.fromJson(result);
  }

  @override
  Future<MarketInsights> marketInsights(
    String professionId, {
    String? country,
    String? currency,
  }) async {
    calls['market'] = '$professionId/$country';
    return MarketInsights.fromJson({
      'profession': 'Electrician',
      'country': country,
      'open_jobs': 12,
      'openings': 20,
      'remote_jobs': 0,
      'sponsored_jobs': 2,
      'pay_monthly': {'currency': 'INR', 'p25': 18000, 'median': 22000, 'p75': 28000, 'jobs': 9},
      'skills_in_demand': [
        {'name': 'Electrical wiring', 'jobs': 10},
      ],
      'workers': 40,
      'note': null,
    });
  }
}

// ---------------------------------------------------------------------------

void main() {
  group('parsing', () {
    test('full path', () {
      final p = CareerPath.fromJson(pathJson());
      expect(p.hasPath, isTrue);
      expect(p.identityId, 'wi1');
      expect(p.currentProfession, 'Electrician');
      expect(p.currentProfessionId, 'p-elec');
      expect(p.experienceMonths, 38);
      expect(p.goal!.title, 'Industrial Electrician');
      expect(p.goal!.targetCountries, ['DE']); // cleaned, unique
      expect(p.goal!.targetCurrency, 'EUR');
      expect(p.goal!.targetPayLine, '€3,200 per month');
      expect(p.goal!.targetDate, DateTime(2028, 1, 1));
      expect(p.transition!.line,
          'People usually make this move in about 2 years. A common next step.');
      expect(p.readiness, 48);
      expect(p.skills, hasLength(4));
      expect(p.recommended, hasLength(2));
      expect(p.licences.single.link!.host, 'www.anerkennung-in-deutschland.de');
      expect(p.openJobs, 4);
      expect(p.marketPay, isNull);
      expect(p.jobs.single.scoreLabel, '82% match');
      expect(p.jobs.single.eligibility!.label, 'Potentially eligible');
      expect(p.jobs.single.missingSkills, ['PLC programming']);
      // Plan sorted by position.
      expect(p.plan.map((i) => i.id), ['pi1', 'pi2', 'pi3']);
      expect(p.plan.first.kind, PlanKind.assessment);
    });

    test('no goal: suggestions and message', () {
      final p = CareerPath.fromJson(noGoalJson());
      expect(p.hasPath, isFalse);
      expect(p.goal, isNull);
      expect(p.currentProfession, 'Electrician');
      expect(p.message, 'Choose a career goal to see your path');
      expect(p.suggestions.map((s) => s.name),
          ['Industrial Electrician', 'Maintenance Technician']);
      expect(p.suggestions.first.readiness, 48);
      expect(p.suggestions.first.missing, hasLength(2));
      expect(p.suggestions.last.readiness, isNull);
      expect(p.suggestions.last.openJobs, 0);
    });

    test('suggest_career_goals has current as a plain name', () {
      final s = CareerSuggestions.fromJson(noGoalJson()..['current'] = 'Electrician');
      expect(s.current, 'Electrician');
      expect(s.suggestions, hasLength(2));
    });

    test('a goal without a target role does not count as a path', () {
      final p = CareerPath.fromJson({
        'work_identity_id': 'wi1',
        'current': {'profession': 'Electrician'},
        'goal': {'id': 'g9', 'goal_text': 'Work in a factory', 'status': 'active'},
        'suggestions': [],
        'message': 'Choose a target role for this goal',
      });
      expect(p.hasPath, isFalse);
      expect(p.goal!.title, 'Work in a factory');
    });

    test('garbage is tolerated', () {
      final p = CareerPath.fromJson('nope');
      expect(p.hasPath, isFalse);
      expect(p.skills, isEmpty);
      expect(CareerGoal.fromJson(null), isNull);
      expect(parseSuggestions([{'name': 'no id'}]), isEmpty);
    });

    test('resources: https only, test resource folded into the test button', () {
      final r = CareerPath.fromJson(pathJson()).recommended.first;
      expect(r.assessment!.detailLine, '5 questions · pass mark 70%');
      expect(r.otherResources.map((x) => x.id), ['r1', 'r2']);
      expect(r.otherResources[0].link!.host, 'training.example.org');
      expect(r.otherResources[1].link, isNull); // http is never opened
      expect(r.otherResources[0].costLabel, 'Cost varies');
      expect(r.otherResources[0].hoursLabel, 'About 40 hours');
      expect(r.resources[0].hoursLabel, 'About 30 minutes');
    });

    test('last attempt line', () {
      final a = CareerPath.fromJson(pathJson()).recommended.last.assessment!;
      expect(a.lastLine(fixedNow), 'Last try: 40%, not passed (18 Sep)');
    });

    test('assessment session and result', () {
      final s = AssessmentSession.fromJson(sessionJson())!;
      expect(s.attemptId, 'att1');
      expect(s.questions, hasLength(3));
      expect(s.remaining(fixedNow), const Duration(minutes: 20));
      expect(s.remaining(fixedNow.add(const Duration(hours: 1))), Duration.zero);

      final r = AssessmentResult.fromJson({
        'status': 'failed',
        'score_percent': 40,
        'pass_percent': 70,
        'correct': 2,
        'total': 5,
        'review': [
          {'question_id': 'q1', 'correct': true},
          {'question_id': 'q2', 'correct': false},
        ],
        'retry_after': DateTime(2026, 9, 20, 14, 30).toUtc().toIso8601String(),
      });
      expect(r.passed, isFalse);
      expect(r.review.map((x) => x.correct), [true, false]);
      expect(r.retryLine(fixedNow), 'You can try again after 20 Sep, 14:30.');
    });

    test('market insights', () {
      final m = MarketInsights.fromJson({
        'profession': 'Electrician',
        'open_jobs': 3,
        'pay_monthly': null,
        'skills_in_demand': [
          {'name': 'Wiring', 'jobs': 3},
          {'jobs': 1},
        ],
        'note': 'Too few jobs with pay to show a reliable range.',
      });
      expect(m.pay, isNull);
      expect(m.skillsInDemand.single.name, 'Wiring');
      expect(m.note, startsWith('Too few'));
    });
  });

  group('readiness and skills', () {
    test('grouped Strong, Weak, Missing, most important first', () {
      final groups = groupSkills(CareerPath.fromJson(pathJson()).skills);
      expect(groups.map((g) => g.$1),
          [SkillStatus.strong, SkillStatus.weak, SkillStatus.missing]);
      expect(groups.last.$2.map((s) => s.name),
          ['PLC programming', 'Preventive maintenance']);
    });

    test('empty groups are left out', () {
      final groups = groupSkills(const [
        PathSkill(skillId: 'a', name: 'A', status: SkillStatus.missing),
      ]);
      expect(groups.single.$1, SkillStatus.missing);
    });

    test('evidence labels and why a skill is weak', () {
      final skills = CareerPath.fromJson(pathJson()).skills;
      final weak = skills.firstWhere((s) => s.status == SkillStatus.weak);
      expect(weak.evidenceLabel, 'Self-declared');
      expect(weak.weakReason, contains('self-declared'));
      expect(careerEvidenceLabel('assessment'), 'Passed Omelo test');
      expect(careerEvidenceLabel('self_declared', verified: true), 'Verified');
      expect(careerEvidenceLabel(null), isNull);
      const basic = PathSkill(
        skillId: 'x',
        name: 'X',
        status: SkillStatus.weak,
        proficiency: 'basic',
        evidence: 'experience',
      );
      expect(basic.weakReason, contains('basic'));
    });

    test('words', () {
      expect(readinessLabel(62), '62% ready');
      expect(readinessLabel(null), 'Readiness not measured yet');
      expect(typicalTimeLabel(6), 'About 6 months');
      expect(typicalTimeLabel(12), 'About 1 year');
      expect(typicalTimeLabel(18), 'About 1½ years');
      expect(typicalTimeLabel(24), 'About 2 years');
      expect(typicalTimeLabel(null), 'Time varies');
      expect(experienceLine(38), '3 years 2 months experience');
      expect(experienceLine(0), isNull);
      expect(importanceLabel(1.0), 'Essential');
      expect(importanceLabel(0.7), 'Important');
      expect(importanceLabel(0.3), 'Useful');
      expect(openJobsLabel(1), '1 open job');
      expect(openJobsLabel(0), 'No open jobs right now');
    });
  });

  group('money', () {
    test('pay range in its own currency', () {
      expect(marketPayRange(null), 'Not enough data');
      expect(
        marketPayRange(const MarketPay(currency: 'EUR', p25: 2800, median: 3100, p75: 3400, jobs: 5)),
        '€2,800 – €3,400 a month',
      );
      expect(
        marketPayRange(const MarketPay(currency: 'INR', p25: 118000, median: 150000, p75: 180000)),
        '₹1,18,000 – ₹1,80,000 a month',
      );
      expect(marketPayRange(const MarketPay(currency: 'USD', median: 4000)), '\$4,000 a month');
      expect(
        marketPayDetail(const MarketPay(currency: 'GBP', median: 2500, jobs: 1)),
        'Typical £2,500 · from 1 job with pay',
      );
      // No numbers at all is the same as no data.
      expect(MarketPay.fromJson({'currency': 'EUR', 'jobs': 2}), isNull);
    });
  });

  group('goals', () {
    test('payload keeps the identity and sends ISO dates', () {
      final d = GoalDraft.fromGoal(CareerGoal.fromJson(goalJson())!);
      final p = d.toPayload();
      expect(p['id'], 'g1');
      expect(p['work_identity_id'], 'wi1');
      expect(p['profession_id'], 'p-ind');
      expect(p['target_countries'], ['DE']);
      expect(p['target_pay_amount'], 3200);
      expect(p['target_pay_period'], 'month');
      expect(p['target_currency'], 'EUR');
      expect(p['target_date'], '2028-01-01');
      expect(p['generate_plan'], isFalse);
    });

    test('no pay: no period or currency', () {
      final p = const GoalDraft(professionId: 'p', targetCurrency: 'EUR').toPayload();
      expect(p.containsKey('id'), isFalse);
      expect(p['target_pay_period'], isNull);
      expect(p['target_currency'], isNull);
      expect(p['generate_plan'], isTrue);
    });

    test('validation', () {
      expect(validateGoal(const GoalDraft()), 'Choose the role you are aiming for.');
      expect(validateGoal(const GoalDraft(goalText: 'Factory work')), isNull);
      expect(validateGoal(const GoalDraft(professionId: 'p', targetPayAmount: 0)),
          'Target pay must be more than zero.');
      expect(validateGoal(const GoalDraft(professionId: 'p', targetPayAmount: 10)),
          'Choose the currency for your target pay.');
      expect(
        validateGoal(GoalDraft(professionId: 'p', targetDate: DateTime(2026, 9, 18)),
            now: fixedNow),
        'Choose a target date in the future.',
      );
      expect(parseAmount('25,000'), 25000);
      expect(parseAmount('abc'), isNull);
    });
  });

  group('plan', () {
    test('progress, toggling, positions, titles', () {
      final plan = CareerPath.fromJson(pathJson()).plan;
      expect(planProgress(plan), (done: 1, total: 2)); // dismissed not counted
      expect(nextPlanPosition(plan), 4);
      expect(nextPlanPosition(const []), 1);
      expect(toggledStatus(PlanStatus.todo), PlanStatus.done);
      expect(toggledStatus(PlanStatus.inProgress), PlanStatus.done);
      expect(toggledStatus(PlanStatus.done), PlanStatus.todo);
      expect(validateStepTitle(' a '), isNotNull);
      expect(validateStepTitle('Ask about training'), isNull);
      expect(validateStepTitle('x' * 201), isNotNull);
    });

    test('assessment helpers', () {
      final s = AssessmentSession.fromJson(sessionJson())!;
      expect(answersInOrder(s.questions, {'q1': 1, 'q2': 0}), isNull);
      expect(answersInOrder(s.questions, {'q3': 1, 'q1': 1, 'q2': 0}), [1, 0, 1]);
      expect(countdownLabel(const Duration(minutes: 12, seconds: 4)), '12:04');
      expect(countdownLabel(const Duration(hours: 1, minutes: 2, seconds: 9)), '1:02:09');
      expect(countdownLabel(const Duration(seconds: -5)), '0:00');
    });
  });

  group('errors', () {
    test('server words are kept', () {
      const e = PostgrestException(
        message: 'You can take this assessment again after 20 Sep 14:00 UTC',
        code: '22023',
      );
      expect(careerError(e), 'You can take this assessment again after 20 Sep 14:00 UTC');
      expect(needsIdentity(const PostgrestException(
          message: 'Create a work identity first', code: '22023')), isTrue);
      expect(careerError(Exception('x')), startsWith('Could not reach Omelo'));
    });
  });

  // -------------------------------------------------------------------------
  group('screens', () {
    late _FakeCareer repo;
    setUp(() => repo = _FakeCareer());

    List<Override> overrides() => [
      isSignedInProvider.overrideWithValue(true),
      currentUserProvider.overrideWithValue(null),
      careerRepositoryProvider.overrideWithValue(repo),
      careerClockProvider.overrideWithValue(() => fixedNow),
      homeCountryProvider.overrideWith((_) => 'IN'),
      myGoalsProvider.overrideWith((_) async => repo.goals),
      countriesProvider.overrideWith((_) async => parseCountries([
            {'country_code': 'DE', 'name': 'Germany', 'default_currency': 'EUR'},
            {'country_code': 'IN', 'name': 'India', 'default_currency': 'INR'},
          ])),
      myIdentitiesProvider.overrideWith((_) async => [
            WorkIdentity.fromRow({
              'id': 'wi1',
              'label': 'Electrician',
              'profession_id': 'p-elec',
              'is_primary': true,
              'status': 'active',
            }),
          ]),
    ];

    Future<void> pumpAt(WidgetTester tester, Size size, String location) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: overrides(),
        child: MaterialApp.router(
          theme: OmeloTheme.light(),
          routerConfig: GoRouter(
            initialLocation: location,
            routes: [
              ...careerRoutes(),
              GoRoute(path: '/profile', builder: (_, __) => const Text('profile')),
              GoRoute(
                path: '/job/:id',
                builder: (_, s) => Scaffold(body: Text('job ${s.pathParameters['id']}')),
              ),
              GoRoute(
                path: '/identities/:id',
                builder: (_, s) => const Text('identity'),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    for (final size in const [Size(360, 5200), Size(1400, 3000)]) {
      testWidgets('career path at ${size.width.toInt()}px', (tester) async {
        await pumpAt(tester, size, '/career');
        expect(tester.takeException(), isNull);
        expect(find.text('My career'), findsOneWidget);
        expect(find.text('48%'), findsOneWidget);
        expect(find.text('Industrial Electrician'), findsWidgets);
        expect(find.textContaining('about 2 years'), findsOneWidget);
        expect(find.text('Strong (1)'), findsOneWidget);
        expect(find.text('Needs evidence or practice (1)'), findsOneWidget);
        expect(find.text('Missing (2)'), findsOneWidget);
        expect(find.text('Self-declared'), findsOneWidget);
        expect(find.text('Take the test'), findsOneWidget);
        expect(find.text('Try the test again'), findsOneWidget);
        expect(find.text('Open training.example.org'), findsOneWidget);
        expect(find.textContaining('insecure.example.org'), findsNothing);
        expect(find.text('Elektrofachkraft qualification'), findsOneWidget);
        // Target-role pay is too thin; the current-role market is in INR.
        expect(find.text('Not enough data'), findsOneWidget);
        expect(find.text('₹18,000 – ₹28,000 a month'), findsOneWidget);
        expect(repo.calls['market'], 'p-elec/IN');
        expect(find.text('82% match'), findsOneWidget);
        expect(find.text('Potentially eligible'), findsOneWidget);
        expect(find.text('1 of 2 done'), findsOneWidget);
        expect(find.text('Target €3,200 per month'), findsOneWidget);
      });
    }

    testWidgets('plan: tick a step, add a resource, open a job', (tester) async {
      await pumpAt(tester, const Size(1400, 3000), '/career');
      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(repo.calls['plan'], 'pi1:done');
      expect(find.text('2 of 2 done'), findsOneWidget);

      await tester.tap(find.byTooltip('Add to my plan').first);
      await tester.pumpAndSettle();
      final add = repo.calls['add'] as Map;
      expect(add['kind'], 'resource');
      expect(add['resource'], 'r1');
      expect(add['position'], 4);

      await tester.tap(find.text('Werk GmbH · Munich, Germany'));
      await tester.pumpAndSettle();
      expect(find.text('job j1'), findsOneWidget);
    });

    testWidgets('plan: add a custom step', (tester) async {
      await pumpAt(tester, const Size(1400, 3000), '/career');
      await tester.tap(find.text('Add a step'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add'));
      await tester.pump();
      expect(find.text('Write a few words for this step.'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Ask about PLC training');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      final add = repo.calls['add'] as Map;
      expect(add['kind'], 'custom');
      expect(add['title'], 'Ask about PLC training');
    });

    testWidgets('mark achieved asks first, then saves', (tester) async {
      await pumpAt(tester, const Size(1400, 3000), '/career');
      await tester.tap(find.byTooltip('Goal options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark achieved'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Well done'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Mark achieved'));
      await tester.pumpAndSettle();
      expect(repo.calls['status'], 'achieved');
    });

    for (final size in const [Size(360, 3000), Size(1400, 2400)]) {
      testWidgets('no goal: suggestions at ${size.width.toInt()}px', (tester) async {
        repo.pathData = noGoalJson();
        await pumpAt(tester, size, '/career');
        expect(tester.takeException(), isNull);
        expect(find.text('Roles you could grow into'), findsOneWidget);
        expect(find.text('Industrial Electrician'), findsOneWidget);
        expect(find.text('48% ready'), findsOneWidget);
        expect(find.text('About 2 years'), findsOneWidget);
        expect(find.text('4 open jobs'), findsOneWidget);
        expect(find.textContaining('PLC programming, Preventive maintenance'), findsOneWidget);
        expect(find.text('Choose any role'), findsOneWidget);
        expect(find.textContaining('Market for Electrician in India'), findsOneWidget);
      });
    }

    testWidgets('no goal: set a suggestion as my goal', (tester) async {
      repo.pathData = noGoalJson();
      await pumpAt(tester, const Size(1400, 2400), '/career');
      await tester.tap(find.text('Set as my goal').first);
      await tester.pumpAndSettle();
      final saved = repo.calls['save'] as Map;
      expect(saved['profession_id'], 'p-ind');
      expect(saved['work_identity_id'], 'wi1');
      expect(saved['generate_plan'], isTrue);
      // Path reloads for the new goal.
      expect(repo.pathCalls.last.goal, 'g1');
      expect(find.text('Missing (2)'), findsOneWidget);
    });

    testWidgets('no identity: points to work identities', (tester) async {
      final failing = _FailingCareer();
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...overrides(),
          careerRepositoryProvider.overrideWithValue(failing),
        ],
        child: MaterialApp.router(
          theme: OmeloTheme.light(),
          routerConfig: GoRouter(initialLocation: '/career', routes: careerRoutes()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Start with your work identity'), findsOneWidget);
    });

    // -- Assessment flow -----------------------------------------------------

    testWidgets('assessment: answer, submit, result, back to a reloaded path',
        (tester) async {
      await pumpAt(tester, const Size(420, 1600), '/career');
      final before = repo.pathCalls.length;

      await tester.tap(find.text('Take the test'));
      await tester.pumpAndSettle();
      expect(repo.calls['start'], 's-plc');
      expect(find.text('Question 1 of 3'), findsOneWidget);
      expect(find.text('20:00'), findsOneWidget); // countdown

      // Submit only once every question is answered.
      await tester.tap(find.text('Passes power'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read, execute, write'));
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Question 3 of 3'), findsOneWidget);
      final submit = find.widgetWithText(FilledButton, 'Submit answers');
      expect(tester.widget<FilledButton>(submit).onPressed, isNull);
      expect(find.textContaining('2 of 3 answered'), findsOneWidget);

      await tester.tap(find.text('Fail-safe'));
      await tester.pump();
      expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
      await tester.tap(submit);
      await tester.pumpAndSettle();

      final sent = repo.calls['submit'] as Map;
      expect(sent['attempt'], 'att1');
      expect(sent['answers'], [1, 1, 1]);

      expect(find.text('You passed'), findsOneWidget);
      expect(find.textContaining('You scored 67% (2 of 3 correct)'), findsOneWidget);
      expect(find.text('Correct'), findsNWidgets(2));
      expect(find.text('Not correct'), findsOneWidget);
      // The right answer is never shown.
      expect(find.text('Passes power'), findsNothing);
      expect(find.text('Execute, read, write'), findsNothing);

      repo.pathData = pathJson(readiness: 63);
      await tester.tap(find.text('Back to my career path'));
      await tester.pumpAndSettle();
      expect(repo.pathCalls.length, greaterThan(before));
      expect(find.text('63%'), findsOneWidget);
    });

    testWidgets('assessment: failed shows when to retry', (tester) async {
      repo.result = {
        'status': 'failed',
        'score_percent': 33,
        'pass_percent': 70,
        'correct': 1,
        'total': 3,
        'review': [
          {'question_id': 'q1', 'correct': true},
          {'question_id': 'q2', 'correct': false},
          {'question_id': 'q3', 'correct': false},
        ],
        'retry_after': DateTime(2026, 9, 20, 12).toUtc().toIso8601String(),
      };
      await pumpAt(tester, const Size(420, 1600), '/career/assessment/s-plc?name=PLC');
      for (final a in ['Blocks power', 'Execute, read, write', 'Cheaper']) {
        await tester.tap(find.text(a));
        await tester.pump();
        if (find.text('Next').evaluate().isNotEmpty) {
          await tester.tap(find.text('Next'));
          await tester.pumpAndSettle();
        }
      }
      await tester.tap(find.text('Submit answers'));
      await tester.pumpAndSettle();
      expect(find.text('Not passed this time'), findsOneWidget);
      expect(find.textContaining('You can try again after 20 Sep, 12:00.'), findsOneWidget);
    });

    testWidgets('assessment: cooldown message from the server', (tester) async {
      repo.startError = const PostgrestException(
        message: 'You can take this assessment again after 20 Sep 14:00 UTC',
        code: '22023',
      );
      await pumpAt(tester, const Size(420, 1200), '/career/assessment/s-plc');
      expect(find.text('You cannot take this test right now'), findsOneWidget);
      expect(find.text('You can take this assessment again after 20 Sep 14:00 UTC'),
          findsOneWidget);
    });

    testWidgets('assessment: time up disables answers and offers a restart',
        (tester) async {
      var now = fixedNow;
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ...overrides(),
          careerClockProvider.overrideWithValue(() => now),
        ],
        child: MaterialApp.router(
          theme: OmeloTheme.light(),
          routerConfig: GoRouter(
            initialLocation: '/career/assessment/s-plc',
            routes: careerRoutes(),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('20:00'), findsOneWidget);
      now = fixedNow.add(const Duration(minutes: 19, seconds: 30));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('0:30'), findsOneWidget);
      now = fixedNow.add(const Duration(minutes: 21));
      await tester.pump(const Duration(seconds: 1));
      expect(find.textContaining('Time is up'), findsOneWidget);
      expect(find.text('Start again'), findsOneWidget);
    });
  });
}

class _FailingCareer extends _FakeCareer {
  @override
  Future<CareerPath> path({String? goalId, String? identityId}) async =>
      throw const PostgrestException(message: 'Create a work identity first', code: '22023');
}
