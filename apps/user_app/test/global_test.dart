import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omelo_user_app/core/app_state.dart';
import 'package:omelo_user_app/core/router.dart' show globalRoutes;
import 'package:omelo_user_app/core/theme.dart';
import 'package:omelo_user_app/data/applications_repository.dart'
    show HiringCopy, MatchFactor, MatchResult;
import 'package:omelo_user_app/data/global_repository.dart';
import 'package:omelo_user_app/data/identity_repository.dart' show TaxonomyHit;
import 'package:omelo_user_app/features/global/authorization_editor.dart';
import 'package:omelo_user_app/features/global/country_guide_screen.dart';
import 'package:omelo_user_app/features/global/eligibility_panel.dart';
import 'package:omelo_user_app/features/global/global_jobs_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final countriesJson = [
  {
    'country_code': 'DE',
    'name': 'Germany',
    'default_currency': 'EUR',
    'default_language': 'deu',
    'default_timezone': 'Europe/Berlin',
    'calling_code': '49',
    'world_region': 'europe',
  },
  {
    'country_code': 'IN',
    'name': 'India',
    'default_currency': 'INR',
    'default_language': 'hin',
    'default_timezone': 'Asia/Kolkata',
    'calling_code': '+91',
    'world_region': 'south_asia',
  },
  {'country_code': 'IE', 'name': 'Ireland', 'default_currency': 'EUR'},
];

final testCountries = parseCountries(countriesJson);

Map<String, dynamic> normalizedEur() => {
  'amount': 3400,
  'period': 'month',
  'currency': 'EUR',
  'hourly': 16.35,
  'monthly': 3400,
  'yearly': 40800,
  'target': {
    'currency': 'INR',
    'hourly': 1500.5,
    'monthly': 312100,
    'yearly': 3745200,
    'rate': 91.7941176,
    'effective_at': '2026-09-15T00:00:00Z',
    'source': 'ECB reference rate',
  },
};

Map<String, dynamic> globalJobJson({
  String id = 'j1',
  String status = 'potentially_eligible',
}) => {
  'job_id': id,
  'title': 'Nurse (Pflegefachkraft)',
  'company_name': 'Klinikum Berlin',
  'company_verified': true,
  'country': 'DE',
  'country_name': 'Germany',
  'location_text': 'Berlin',
  'distance_km': null,
  'workplace_type': 'onsite',
  'work_type': 'full_time',
  'remote_scope': null,
  'remote_countries': null,
  'sponsorship': 'yes',
  'relocation_support': true,
  'support': {
    'immigration': true,
    'legal': false,
    'visa_fees': true,
    'travel': false,
    'accommodation': true,
  },
  'pay': {
    'min': 2800,
    'max': 3400,
    'period': 'month',
    'currency': 'EUR',
    'normalized': normalizedEur(),
  },
  'published_at': '2026-09-10T08:00:00Z',
  'eligibility': {
    'status': status,
    'summary': 'Potentially eligible',
    'missing': [
      {'kind': 'work_authorization', 'text': 'Work authorization for Germany'},
      {'kind': 'licence', 'text': 'Licence: Nursing recognition'},
    ],
    'notes': ['Employer sponsors visas'],
  },
};

Map<String, dynamic> eligibilityJson({String status = 'potentially_eligible'}) => {
  'status': status,
  'summary': status == 'eligible' ? 'Eligible' : 'Potentially eligible',
  'missing': status == 'eligible'
      ? []
      : [
          {'kind': 'work_authorization', 'text': 'Work authorization for Germany'},
        ],
  'notes': ['Authorization expires 31 Jan 2029'],
  'country': 'DE',
  'official_sources': [
    {
      'title': 'Make it in Germany: work visa',
      'url': 'https://www.make-it-in-germany.com/en/visa',
      'source': 'Federal Government',
      'topic': 'work_authorization',
      'reviewed_at': '2026-08-01',
    },
    {'title': 'Unsafe link', 'url': 'http://example.com', 'topic': 'hiring'},
  ],
  'licence_requirements': [
    {
      'name': 'Nursing recognition',
      'description': 'Foreign nursing degrees must be recognised.',
      'url': 'https://www.anerkennung-in-deutschland.de',
      'source': 'Anerkennung',
      'level': 'required',
    },
  ],
  'pay': normalizedEur(),
  'disclaimer':
      'Based on what is on the profile and the job. Not legal advice; the '
      'official sources decide.',
};

Map<String, dynamic> guideJson() => {
  'country': 'DE',
  'name': 'Germany',
  'currency': 'EUR',
  'currency_name': 'Euro',
  'language': 'deu',
  'timezone': 'Europe/Berlin',
  'calling_code': '49',
  'region': 'europe',
  'information': [
    {
      'topic': 'work_authorization',
      'title': 'Work visas',
      'summary': 'Most non-EU workers need a residence permit for work.',
      'url': 'https://www.make-it-in-germany.com/en/visa',
      'source': 'Federal Government',
      'reviewed_at': '2026-08-01',
    },
    {
      'topic': 'worker_rights',
      'title': 'Minimum wage',
      'summary': 'A national minimum wage applies.',
      'url': 'https://www.bmas.de',
      'source': 'BMAS',
    },
  ],
  'licence_requirements': [],
  'disclaimer':
      'Information only, from the official sources linked. Not legal or '
      'immigration advice.',
};

// ---------------------------------------------------------------------------
// Fake repository
// ---------------------------------------------------------------------------

class _FakeGlobal implements GlobalRepository {
  final calls = <String, Object?>{};
  MyMobility mobility = MyMobility.fromJson({
    'mobility': null,
    'defaults': {'authorization_visibility': 'eligibility_only'},
    'authorizations': [
      {
        'id': 'a1',
        'country': 'DE',
        'country_name': 'Germany',
        'status': 'work_permit',
        'valid_from': '2025-01-01',
        'expires_on': '2029-01-31',
        'restrictions': 'Healthcare only',
        'requires_sponsorship': false,
        'is_verified': true,
        'has_document': false,
      },
    ],
  });
  Object? addError;
  final pages = <GlobalTab, GlobalJobsPage>{};

  @override
  Future<List<Country>> countries() async => testCountries;

  @override
  Future<MyMobility> myMobility() async => mobility;

  @override
  Future<MobilityProfile> saveMobility(MobilityProfile p) async {
    calls['save'] = p.toPayload();
    return p;
  }

  @override
  Future<void> addAuthorization({
    required String country,
    required WorkAuthStatus status,
    DateTime? validFrom,
    DateTime? expiresOn,
    String? restrictions,
  }) async {
    if (addError != null) throw addError!;
    calls['add'] = authorizationRow(
      country: country,
      status: status,
      validFrom: validFrom,
      expiresOn: expiresOn,
      restrictions: restrictions,
    );
  }

  @override
  Future<void> updateAuthorization(
    String id, {
    required String country,
    required WorkAuthStatus status,
    DateTime? validFrom,
    DateTime? expiresOn,
    String? restrictions,
  }) async => calls['update'] = id;

  @override
  Future<void> deleteAuthorization(String id) async => calls['delete'] = id;

  @override
  Future<List<TaxonomyHit>> citiesByIds(List<String> ids) async => const [];

  @override
  Future<List<TaxonomyHit>> searchCities(String q,
          {List<String> countries = const []}) async =>
      const [];

  @override
  Future<GlobalJobsPage> globalJobs(
    GlobalTab tab, {
    GlobalJobFilters filters = const GlobalJobFilters(),
    int limit = 20,
    int offset = 0,
  }) async {
    calls['jobs'] = {'tab': tab.wire, 'filters': filters.toJson(tab)};
    return pages[tab] ?? GlobalJobsPage(tab: tab);
  }

  @override
  Future<JobEligibility?> jobEligibility(String jobId,
          {String? identityId}) async =>
      JobEligibility.fromJson(eligibilityJson());

  @override
  Future<CountryGuide?> countryGuide(String code, {String? professionId}) async =>
      CountryGuide.fromJson(guideJson());
}

void main() {
  // -------------------------------------------------------------------------
  group('parsing', () {
    test('countries sort by name and look up names', () {
      expect(testCountries.map((c) => c.code), ['DE', 'IN', 'IE']);
      expect(countryName('IE', testCountries), 'Ireland');
      expect(countryName('ZZ', testCountries), 'ZZ');
      expect(searchCountries(testCountries, 'ger').single.code, 'DE');
      expect(searchCountries(testCountries, 'in').map((c) => c.code), ['IN']);
      expect(languageName('deu'), 'German');
    });

    test('mobility defaults to "eligibility only" and round-trips', () {
      final empty = MyMobility.fromJson({
        'mobility': null,
        'defaults': {'authorization_visibility': 'eligibility_only'},
        'authorizations': [],
      });
      expect(empty.saved, isFalse);
      expect(empty.profile.visibility, AuthorizationVisibility.eligibilityOnly);
      expect(AuthorizationVisibility.standard.title,
          'Employers see only whether I\'m eligible');

      final p = MobilityProfile.fromJson({
        'current_country': 'in',
        'citizenships': ['IN', 'in', 'bad'],
        'timezone': 'Asia/Kolkata',
        'open_to_relocation': true,
        'preferred_countries': ['DE', 'IE'],
        'preferred_city_ids': ['c1'],
        'countries_willing_to_work': [],
        'relocation_assistance_required': true,
        'earliest_relocation_date': '2026-11-01',
        'remote_preference': 'hybrid',
        'requires_sponsorship': null,
        'authorization_visibility': 'details_with_applications',
      });
      expect(p.currentCountry, 'IN');
      expect(p.citizenships, ['IN']);
      expect(p.remotePreference, RemotePreference.hybrid);
      expect(p.requiresSponsorship, isNull);
      expect(p.toPayload(), {
        'current_country': 'IN',
        'citizenships': ['IN'],
        'timezone': 'Asia/Kolkata',
        'open_to_relocation': true,
        'preferred_countries': ['DE', 'IE'],
        'preferred_city_ids': ['c1'],
        'countries_willing_to_work': [],
        'relocation_assistance_required': true,
        'earliest_relocation_date': '2026-11-01',
        'remote_preference': 'hybrid',
        'requires_sponsorship': null,
        'authorization_visibility': 'details_with_applications',
      });
      expect(p == MobilityProfile.fromJson(p.toPayload()), isTrue);
      expect(p.copyWith(requiresSponsorship: () => true) == p, isFalse);
      expect(
        validateMobility(p.copyWith(
            citizenships: ['IN', 'DE', 'IE', 'FR', 'IT', 'ES'])),
        'Add up to 5 citizenships.',
      );
    });

    test('work authorizations: plain labels, dates, row, validation', () {
      final a = parseAuthorizations([
        {
          'id': 'a1',
          'country': 'DE',
          'country_name': 'Germany',
          'status': 'student_visa_limited',
          'valid_from': '2025-01-01',
          'expires_on': '2026-01-31',
          'restrictions': '20 hours a week',
          'requires_sponsorship': true,
          'is_verified': false,
          'has_document': true,
        },
        {'id': '', 'country': 'IN', 'status': 'citizen'},
      ]);
      expect(a, hasLength(1));
      expect(a.single.status.label, 'Student visa (limited hours)');
      expect(a.single.hasDocument, isTrue);
      final now = DateTime(2026, 9, 19);
      expect(authorizationDatesLine(a.single, now), 'Expired 31 Jan');
      expect(
        authorizationDatesLine(
            WorkAuthorization(
                id: 'x',
                country: 'DE',
                status: WorkAuthStatus.workPermit,
                validFrom: DateTime(2025, 1, 1),
                expiresOn: DateTime(2029, 1, 31)),
            now),
        'Valid 1 Jan 2025 – 31 Jan 2029',
      );
      expect(WorkAuthStatus.fromWire('employer_sponsored').label,
          'Visa tied to one employer');
      expect(WorkAuthStatus.fromWire('nonsense'), WorkAuthStatus.unknown);
      expect(WorkAuthStatus.citizen.hasDates, isFalse);

      // requires_sponsorship is computed by the database; is_verified is
      // Omelo's. Neither is ever written.
      final row = authorizationRow(
        personId: 'p1',
        country: 'de',
        status: WorkAuthStatus.workPermit,
        validFrom: DateTime(2025, 1, 1),
        expiresOn: DateTime(2029, 1, 31),
        restrictions: '  Healthcare only ',
      );
      expect(row, {
        'person_id': 'p1',
        'country_code': 'DE',
        'status': 'work_permit',
        'valid_from': '2025-01-01',
        'expires_on': '2029-01-31',
        'work_restrictions': 'Healthcare only',
      });
      expect(
          authorizationRow(country: 'DE', status: WorkAuthStatus.citizen,
              restrictions: ' '),
          isNot(contains('person_id')));

      expect(
        validateAuthorization(
            country: 'DE',
            status: WorkAuthStatus.workPermit,
            validFrom: DateTime(2027, 1, 1),
            expiresOn: DateTime(2026, 1, 1)),
        'The end date is before the start date.',
      );
      expect(validateAuthorization(country: null, status: null),
          'Choose the country.');
      expect(
          validateAuthorization(
              country: 'DE',
              status: WorkAuthStatus.citizen,
              restrictions: 'x' * 501),
          isNotNull);
    });

    test('global jobs: pay in the job currency, ≈ in mine with the source', () {
      final page = GlobalJobsPage.fromJson({
        'tab': 'work_abroad',
        'total': 1,
        'results': [globalJobJson(), {'title': 'no id'}],
        'viewer_currency': 'INR',
        'home_country': 'IN',
      });
      expect(page.tab, GlobalTab.workAbroad);
      expect(page.results, hasLength(1));
      final j = page.results.single;
      expect(j.placeLine, 'Germany · Berlin');
      expect(payLineOf(j.pay!), '€2,800 – €3,400 per month');
      expect(approxPayLineOf(j.pay!), '≈ up to ₹3,12,100 a month in INR');
      final src = conversionSource(j.pay!.normalized,
          now: DateTime(2026, 9, 19))!;
      expect(src, contains('Rate: 1 EUR = 91.7941 INR'));
      expect(src, contains('Source: ECB reference rate'));
      expect(src, contains('The job pays in EUR.'));
      expect(sponsorshipLabel(j.sponsorship), 'Visa sponsorship');
      expect(sponsorshipLabel('no'), isNull);
      expect(supportLabels(j),
          ['Relocation help', 'Immigration help', 'Visa fees paid', 'Housing help']);
      expect(j.eligibility!.headline,
          'Potentially eligible — Missing: Work authorization for Germany; '
          'Licence: Nursing recognition');

      // Same currency: nothing to convert.
      final same = JobPay.fromJson({
        'min': 20000,
        'max': null,
        'period': 'month',
        'currency': 'INR',
        'normalized': {'amount': 20000, 'period': 'month', 'currency': 'INR',
          'monthly': 20000, 'target': null},
      })!;
      expect(payLineOf(same), '₹20,000 per month');
      expect(approxPayLineOf(same), isNull);
      expect(JobPay.fromJson(null), isNull);
    });

    test('tab filters: location only for Near me', () {
      const f = GlobalJobFilters(country: 'DE', query: ' nurse ', lat: 1, lng: 2);
      expect(f.toJson(GlobalTab.remote), {'country': 'DE', 'query': 'nurse'});
      expect(f.toJson(GlobalTab.nearMe),
          {'country': 'DE', 'query': 'nurse', 'lat': 1.0, 'lng': 2.0});
      expect(GlobalTab.values.map((t) => t.wire), [
        'near_me', 'remote', 'relocation', 'visa_sponsorship',
        'international', 'work_abroad',
      ]);
    });

    test('eligibility wording', () {
      final e = JobEligibility.fromJson(eligibilityJson())!;
      expect(e.headline,
          'Potentially eligible — Missing: Work authorization for Germany');
      expect(e.officialSources.first.link, isNotNull);
      expect(e.officialSources.last.link, isNull); // http is never opened
      expect(e.licences.single.isRequired, isTrue);
      final no = JobEligibility.fromJson(
          {...eligibilityJson(), 'status': 'not_eligible'})!;
      expect(no.headline,
          'Not currently eligible — Missing: Work authorization for Germany');
      expect(JobEligibility.fromJson(eligibilityJson(status: 'eligible'))!.headline,
          'Eligible');
    });

    test('country guide', () {
      final g = CountryGuide.fromJson(guideJson())!;
      expect(g.dialCode, '+49');
      expect(g.byTopic.keys, ['Permission to work', 'Your rights at work']);
      expect(CountryGuide.fromJson(null), isNull);
    });

    test('match v1.2: eligibility and labelled mobility factors', () {
      final m = MatchResult.fromJson({
        'score': 71,
        'eligible': true,
        'strengths': [
          {'factor': 'mobility_fit', 'weight': 0.06,
            'text': 'Open to relocating to Germany'},
        ],
        'gaps': [
          {'factor': 'eligibility_fit', 'weight': 0.08,
            'text': 'Potentially eligible — missing: Work authorization for Germany'},
        ],
        'unknowns': [
          {'factor': 'mobility_fit', 'weight': 0.06, 'text': 'Time zone not set'},
        ],
        'eligibility': {'status': 'potentially_eligible', 'missing': []},
      });
      expect(m.eligibility!.status, EligibilityStatus.potentiallyEligible);
      expect(HiringCopy.factorLine(m.strengths.single),
          'Moving and time zones: Open to relocating to Germany');
      expect(HiringCopy.factorLine(m.gaps.single),
          startsWith('Right to work: Potentially eligible'));
      expect(HiringCopy.tips(m), ['Add your time zone in Global mobility']);
      expect(HiringCopy.factorLabel('eligibility_fit'), 'Right to work');
      expect(
          HiringCopy.factorLine(const MatchFactor(
              factor: 'distance_fit', weight: 0.1, text: '3 km away')),
          '3 km away');
    });

    test('server errors in plain words', () {
      expect(globalError(const PostgrestException(message: 'dup', code: '23505')),
          'You already added this country. Edit that one instead.');
      expect(
          globalError(const PostgrestException(
              message: 'Unknown time zone Mars/Olympus', code: '22023')),
          'Unknown time zone Mars/Olympus');
      expect(globalError(Exception('x')), startsWith('Could not reach Omelo'));
    });
  });

  // -------------------------------------------------------------------------
  group('screens', () {
    late _FakeGlobal repo;
    setUp(() => repo = _FakeGlobal());

    List<Override> base({bool signedIn = true}) => [
      isSignedInProvider.overrideWithValue(signedIn),
      currentUserProvider.overrideWithValue(null),
      globalRepositoryProvider.overrideWithValue(repo),
    ];

    Future<void> pumpAt(WidgetTester tester, Size size, String location,
        {bool signedIn = true}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: base(signedIn: signedIn),
        child: MaterialApp.router(
          theme: OmeloTheme.light(),
          routerConfig: GoRouter(
            initialLocation: location,
            routes: [
              ...globalRoutes(),
              GoRoute(path: '/profile', builder: (_, __) => const Text('profile')),
              GoRoute(path: '/discover', builder: (_, __) => const Text('discover')),
              GoRoute(
                  path: '/job/:id',
                  builder: (_, s) => Scaffold(
                        body: ListView(children: [
                          EligibilityPanel(jobId: s.pathParameters['id']!),
                        ]),
                      )),
              GoRoute(path: '/sign-in', builder: (_, __) => const Text('sign in')),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    for (final size in const [Size(320, 3200), Size(1400, 2400)]) {
      testWidgets('mobility screen at ${size.width.toInt()}px', (tester) async {
        await pumpAt(tester, size, '/mobility');
        expect(tester.takeException(), isNull);
        expect(find.text('Global mobility'), findsOneWidget);
        expect(find.text('Employers see only whether I\'m eligible (recommended)'),
            findsOneWidget);
        expect(find.text('Only me'), findsOneWidget);
        expect(find.text('Show details to employers I apply to'), findsOneWidget);
        expect(find.text('Germany'), findsOneWidget);
        expect(find.text('Work permit or work visa'), findsOneWidget);
        expect(find.text('Verified by Omelo'), findsOneWidget);
        expect(find.text('Limits: Healthcare only'), findsOneWidget);
      });
    }

    testWidgets('mobility: choose sharing and sponsorship, then save',
        (tester) async {
      await pumpAt(tester, const Size(420, 4000), '/mobility');
      expect(find.text('Saved'), findsOneWidget); // nothing changed yet
      await tester.tap(find.text('Show details to employers I apply to'));
      await tester.tap(find.text('Yes, I need sponsorship'));
      await tester.tap(find.text('I\'m open to moving to another country or city'));
      await tester.pumpAndSettle();
      expect(find.text('I need help to move'), findsOneWidget);
      await tester.tap(find.text('Save changes'));
      await tester.pumpAndSettle();
      final saved = repo.calls['save'] as Map<String, Object?>;
      expect(saved['authorization_visibility'], 'details_with_applications');
      expect(saved['requires_sponsorship'], true);
      expect(saved['open_to_relocation'], true);
      expect(saved['remote_preference'], 'any');
    });

    testWidgets('mobility: remove an authorization after confirming',
        (tester) async {
      await pumpAt(tester, const Size(420, 4000), '/mobility');
      await tester.tap(find.byTooltip('Remove Germany'));
      await tester.pumpAndSettle();
      expect(find.text('Remove Germany?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();
      expect(repo.calls['delete'], 'a1');
    });

    testWidgets('authorization editor validates, then saves', (tester) async {
      tester.view.physicalSize = const Size(420, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: base(),
        child: MaterialApp(
          theme: OmeloTheme.light(),
          home: Scaffold(body: AuthorizationEditor(countries: testCountries)),
        ),
      ));
      await tester.tap(find.text('Save'));
      await tester.pump();
      expect(find.text('Choose the country.'), findsOneWidget);

      await tester.tap(find.text('Choose a country'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ireland'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('What lets you work there?'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Citizen').last);
      await tester.pumpAndSettle();
      expect(find.text('Valid from'), findsNothing); // citizens have no dates
      await tester.enterText(find.byType(TextField).last, ' None ');

      repo.addError = const PostgrestException(message: 'dup', code: '23505');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.text('You already added this country. Edit that one instead.'),
          findsOneWidget);

      repo.addError = null;
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(repo.calls['add'], {
        'country_code': 'IE',
        'status': 'citizen',
        'valid_from': null,
        'expires_on': null,
        'work_restrictions': 'None',
      });
    });

    for (final size in const [Size(320, 2400), Size(1400, 1600)]) {
      testWidgets('jobs worldwide at ${size.width.toInt()}px', (tester) async {
        repo.pages[GlobalTab.workAbroad] = GlobalJobsPage.fromJson({
          'tab': 'work_abroad',
          'total': 1,
          'results': [globalJobJson()],
          'viewer_currency': 'INR',
        });
        await pumpAt(tester, size, '/jobs/global?tab=work_abroad&country=de');
        expect(tester.takeException(), isNull);
        expect(repo.calls['jobs'],
            {'tab': 'work_abroad', 'filters': {'country': 'DE'}});
        for (final t in GlobalTab.values) {
          expect(find.text(t.label), findsWidgets);
        }
        expect(find.text('Nurse (Pflegefachkraft)'), findsOneWidget);
        expect(find.text('€2,800 – €3,400 per month'), findsOneWidget);
        expect(find.text('≈ up to ₹3,12,100 a month in INR'), findsOneWidget);
        expect(find.text('Potentially eligible'), findsOneWidget);
        expect(find.text('Visa sponsorship'), findsWidgets);
        expect(find.text('Housing help'), findsOneWidget);
        expect(find.text('Country guide'), findsOneWidget);
      });
    }

    testWidgets('jobs worldwide: switching tab reloads; empty says why',
        (tester) async {
      await pumpAt(tester, const Size(420, 1600), '/jobs/global?tab=near_me');
      expect(find.text(GlobalTab.nearMe.emptyText), findsOneWidget);
      await tester.tap(find.text('Remote'));
      await tester.pumpAndSettle();
      expect((repo.calls['jobs'] as Map)['tab'], 'remote');
      expect(find.text(GlobalTab.remote.emptyText), findsOneWidget);
    });

    testWidgets('job card: tapping the ≈ line explains the conversion',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: OmeloTheme.light(),
        home: Scaffold(
          body: GlobalJobCard(
              job: GlobalJob.fromJson(globalJobJson()), onTap: () {}),
        ),
      ));
      await tester.tap(find.text('≈ up to ₹3,12,100 a month in INR'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Source: ECB reference rate'), findsOneWidget);
    });

    testWidgets('Can I apply? panel', (tester) async {
      await pumpAt(tester, const Size(420, 3000), '/job/j1');
      expect(find.text('Can I apply?'), findsOneWidget);
      expect(find.text('Potentially eligible — Missing: Work authorization for Germany'),
          findsOneWidget);
      expect(find.textContaining('You can still apply'), findsOneWidget);
      expect(find.text('Authorization expires 31 Jan 2029'), findsOneWidget);
      expect(find.text('Nursing recognition'), findsOneWidget);
      expect(find.text('Make it in Germany: work visa'), findsOneWidget);
      expect(find.text('≈ ₹3,12,100 a month in INR'), findsOneWidget);
      expect(find.textContaining('Rate: 1 EUR = 91.7941 INR'), findsOneWidget);
      expect(find.text(notLegalAdvice), findsOneWidget);
      expect(find.text('Read the country guide'), findsOneWidget);
    });

    testWidgets('Can I apply? asks a signed-out visitor to sign in',
        (tester) async {
      await pumpAt(tester, const Size(420, 1200), '/job/j1', signedIn: false);
      expect(find.textContaining('Sign in to check'), findsOneWidget);
    });

    testWidgets('eligible and not eligible wording', (tester) async {
      Future<void> show(Map<String, dynamic> json) => tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: EligibilityDetails(
                      eligibility: JobEligibility.fromJson(json)!),
                ),
              ),
            ),
          );
      await show(eligibilityJson(status: 'eligible'));
      expect(find.text('Eligible'), findsOneWidget);
      expect(find.text(notLegalAdvice), findsOneWidget);
      await show({...eligibilityJson(), 'status': 'not_eligible'});
      expect(find.text('Not currently eligible — Missing: Work authorization for Germany'),
          findsOneWidget);
      expect(find.text(notLegalAdvice), findsOneWidget);
    });

    for (final size in const [Size(320, 2400), Size(1400, 1600)]) {
      testWidgets('country guide at ${size.width.toInt()}px', (tester) async {
        await pumpAt(tester, size, '/countries/de', signedIn: false);
        expect(tester.takeException(), isNull);
        expect(find.text(informationOnlyBanner), findsOneWidget);
        expect(find.text('Euro (EUR)'), findsOneWidget);
        expect(find.text('German'), findsOneWidget);
        expect(find.text('+49'), findsOneWidget);
        expect(find.text('Permission to work'), findsOneWidget);
        expect(find.text('Work visas'), findsOneWidget);
        expect(find.text('Jobs in Germany'), findsOneWidget);
      });
    }

    testWidgets('country guide view without a router', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: CountryGuideView(guide: CountryGuide.fromJson(guideJson())!)),
      ));
      expect(find.text(informationOnlyBanner), findsOneWidget);
    });
  });
}
