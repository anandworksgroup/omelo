import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omelo_user_app/core/app_state.dart';
import 'package:omelo_user_app/core/theme.dart';
import 'package:omelo_user_app/data/auth_repository.dart';
import 'package:omelo_user_app/data/identity_repository.dart';
import 'package:omelo_user_app/data/job.dart';
import 'package:omelo_user_app/features/apply/apply_screen.dart';
import 'package:omelo_user_app/features/discover/job_detail_screen.dart';
import 'package:omelo_user_app/features/identities/identities_screen.dart';
import 'package:omelo_user_app/features/identities/identity_editor_screen.dart';
import 'package:omelo_user_app/features/identities/profile_field_input.dart';

/// Signed in, without a Supabase client (the apply screen only asks this).
class _SignedInAuth implements AuthRepository {
  @override
  bool get isSignedIn => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

JobDetail cookJob() => JobDetail(
      job: Job(
        id: 'j1',
        title: 'Tandoor cook',
        companyId: 'co1',
        companyName: 'Hotel Sagar',
        companySlug: null,
        companyVerified: true,
        companyResponseHours: null,
        distanceKm: null,
        locationText: 'Pune',
        payMin: 18000,
        payMax: 24000,
        payPeriod: 'month',
        payCurrency: 'INR',
        payNegotiable: false,
        payMonthlyMin: null,
        workType: 'full_time',
        workplace: null,
        shiftTypes: const [],
        acceptsNoExperience: false,
        minExperienceMonths: null,
        isImmediateStart: false,
        quickApplyEnabled: true,
        openings: 1,
        categorySlug: 'food-restaurant',
        professionName: 'Cook',
        professionId: 'p-cook',
        benefits: const [],
        publishedAt: null,
      ),
      description: null,
      responsibilities: const [],
      requiredSkills: const [],
      preferredSkills: const [],
      questions: const [],
      stages: const [],
      hoursPerWeek: null,
      workingDays: null,
      applicationMethod: null,
      walkInDetails: null,
      contactPhone: null,
      aboutCompany: null,
      companyTotalHires: null,
      companyResponseRate: null,
      uniformRequired: null,
      ownVehicleRequired: null,
      ownToolsRequired: null,
      visaSponsorship: null,
    );

ProfileField field(String type,
        {List<String> options = const [], Object? value, bool req = false}) =>
    ProfileField(
      attributeId: 'a-$type',
      slug: 'f-$type',
      label: 'Field $type',
      dataType: type,
      options: options,
      value: value,
      isRequired: req,
    );

WorkIdentity wi(String id, String label,
        {String? prof,
        String? profName,
        bool primary = false,
        String status = 'active',
        int score = 40}) =>
    WorkIdentity(
      id: id,
      label: label,
      professionId: prof,
      professionName: profName,
      isPrimary: primary,
      status: status,
      completenessScore: score,
    );

void main() {
  group('completeness tip', () {
    test('nothing missing means no tip', () {
      expect(completenessTip(const []), isNull);
    });

    test('skills tip counts what is left', () {
      expect(completenessTip(['skills'], skillCount: 1),
          'Next: add 2 more skills');
      expect(completenessTip(['skills'], skillCount: 2),
          'Next: add 1 more skill');
      expect(completenessTip(['skills'], skillCount: 0), 'Next: add 3 skills');
      expect(completenessTip(['skills']), 'Next: add 3 skills');
    });

    test('picks the most useful step first, whatever the server order', () {
      expect(completenessTip(['about', 'location', 'profession']),
          'Next: choose your job type');
      expect(completenessTip(['headline', 'about', 'experience']),
          'Next: add your work experience');
      expect(completenessTip(['about', 'profile_questions']),
          'Next: answer the questions for your job');
      expect(completenessTip(['location', 'preferences']),
          'Next: say when and how you want to work');
      expect(completenessTip(['location']), 'Next: add where you want to work');
      expect(completenessTip(['about']), 'Next: say a little about yourself');
      expect(completenessTip(['headline']), 'Next: write a short headline');
    });

    test('an unknown key still gives a tip', () {
      expect(completenessTip(['something_new']), 'Next: finish your profile');
    });

    test('every missing key maps to an editor section', () {
      for (final k in kCompletenessPriority) {
        expect(
            ['basics', 'questions', 'skills', 'experience', 'preferences'],
            contains(sectionForMissing(k)));
      }
    });

    test('skill count includes shared skills', () {
      expect(skillCountFor('a', ['a', null, 'b', 'a']), 3);
    });

    test('parses completeness from the server', () {
      final c = Completeness.fromJson({
        'score': 130,
        'missing': ['skills', 'about']
      });
      expect(c.score, 100);
      expect(c.missing, ['skills', 'about']);
    });
  });

  group('adaptive field widget per data type', () {
    test('maps each data type', () {
      expect(inputKindFor(field('text')), FieldInputKind.text);
      expect(inputKindFor(field('location')), FieldInputKind.text);
      expect(inputKindFor(field('long_text')), FieldInputKind.longText);
      expect(inputKindFor(field('number')), FieldInputKind.number);
      expect(inputKindFor(field('years')), FieldInputKind.number);
      expect(inputKindFor(field('boolean')), FieldInputKind.toggle);
      expect(inputKindFor(field('date')), FieldInputKind.date);
      expect(inputKindFor(field('file')), FieldInputKind.unsupported);
      expect(inputKindFor(field('multi_select', options: ['A', 'B'])),
          FieldInputKind.chips);
      expect(inputKindFor(field('something_else')), FieldInputKind.text);
    });

    test('single select: few short options are segmented, else radio', () {
      expect(
          inputKindFor(field('single_select',
              options: ['Registered', 'In progress', 'No'])),
          FieldInputKind.segmented);
      expect(
          inputKindFor(field('single_select',
              options: ['Helper', 'Apprentice', 'Semi-skilled', 'Skilled'])),
          FieldInputKind.radio);
      expect(
          inputKindFor(field('single_select',
              options: ['Registration in progress', 'Registered'])),
          FieldInputKind.radio);
    });

    test('open multi-select takes typed items; single select needs options', () {
      expect(inputKindFor(field('multi_select')), FieldInputKind.tags);
      expect(inputKindFor(field('single_select')), FieldInputKind.unsupported);
    });

    test('open list values are trimmed and de-duplicated ignoring case', () {
      final open = field('multi_select');
      expect(
          encodeFieldValue(open, [' Airport road ', 'airport road', 'Ring road', ''])
              .value,
          ['Airport road', 'Ring road']);
      expect(encodeFieldValue(open, <String>['  ']).value, isNull);
    });

    test('options may arrive as objects', () {
      final f = ProfileField.fromJson({
        'attribute_id': 'x',
        'slug': 's',
        'label': 'L',
        'data_type': 'multi_select',
        'options': [
          {'value': 'a', 'label': 'Apple'},
          'Pear'
        ],
      });
      expect(f.options, ['Apple', 'Pear']);
    });
  });

  group('value serialisation', () {
    final multi =
        field('multi_select', options: ['Two-wheeler', 'Car (LMV)', 'Van']);

    test('multi_select keeps option order, drops unknowns, empty clears', () {
      expect(encodeFieldValue(multi, ['Van', 'Two-wheeler', 'Bus']).value,
          ['Two-wheeler', 'Van']);
      expect(encodeFieldValue(multi, ['Van', 'Van']).value, ['Van']);
      expect(encodeFieldValue(multi, <String>[]).value, isNull);
      expect(encodeFieldValue(multi, null).value, isNull);
      expect(decodeFieldValue('multi_select', ['Van']), ['Van']);
      expect(decodeFieldValue('multi_select', null), isEmpty);
    });

    test('years: whole numbers as integers, decimals kept, bounds checked', () {
      final y = field('years');
      expect(encodeFieldValue(y, '3').value, 3);
      expect(encodeFieldValue(y, '3').value, isA<int>());
      expect(encodeFieldValue(y, '2.5').value, 2.5);
      expect(encodeFieldValue(y, '2,5').value, 2.5);
      expect(encodeFieldValue(y, 4.0).value, 4);
      expect(encodeFieldValue(y, '').value, isNull);
      expect(encodeFieldValue(y, '').ok, isTrue);
      expect(encodeFieldValue(y, 'abc').error, 'Enter a number');
      expect(encodeFieldValue(y, '71').error, 'Enter between 0 and 70 years');
      expect(encodeFieldValue(y, '-1').error, 'Enter 0 or more');
      expect(decodeFieldValue('years', 3), 3);
      expect(decodeFieldValue('years', '2.5'), 2.5);
    });

    test('number allows larger values than years', () {
      final n = field('number');
      expect(encodeFieldValue(n, '250').value, 250);
      expect(encodeFieldValue(n, '100001').ok, isFalse);
    });

    test('date goes as YYYY-MM-DD', () {
      final d = field('date');
      expect(encodeFieldValue(d, DateTime(2024, 3, 7)).value, '2024-03-07');
      expect(encodeFieldValue(d, DateTime(2024, 12, 31, 23, 59)).value,
          '2024-12-31');
      expect(encodeFieldValue(d, '2023-01-05').value, '2023-01-05');
      expect(encodeFieldValue(d, 'soon').ok, isFalse);
      expect(encodeFieldValue(d, null).value, isNull);
      expect(decodeFieldValue('date', '2024-03-07'), DateTime(2024, 3, 7));
    });

    test('boolean, select and text', () {
      expect(encodeFieldValue(field('boolean'), false).value, false);
      expect(encodeFieldValue(field('boolean'), null).value, isNull);
      final s = field('single_select', options: ['Junior', 'Senior']);
      expect(encodeFieldValue(s, 'Senior').value, 'Senior');
      expect(encodeFieldValue(s, 'CEO').value, isNull);
      expect(encodeFieldValue(field('text'), '  hi  ').value, 'hi');
      expect(encodeFieldValue(field('text'), '   ').value, isNull);
      expect(encodeFieldValue(field('text'), 'x' * 301).ok, isFalse);
      expect(encodeFieldValue(field('long_text'), 'x' * 1500).ok, isTrue);
    });

    test('hasAnswer', () {
      expect(hasAnswer(null), isFalse);
      expect(hasAnswer(''), isFalse);
      expect(hasAnswer(<String>[]), isFalse);
      expect(hasAnswer(false), isTrue);
      expect(hasAnswer(['a']), isTrue);
    });
  });

  group('visibility levels', () {
    test('five levels in order, matching the database', () {
      expect(IdentityVisibility.values.map((v) => v.wire), [
        'private',
        'matched_only',
        'discoverable',
        'recruiters',
        'public',
      ]);
    });

    test('each level is explained in one plain sentence', () {
      for (final v in IdentityVisibility.values) {
        expect(v.title, isNotEmpty);
        expect(v.description.trim().endsWith('.'), isTrue);
        // One sentence: no full stop before the end.
        expect(
            v.description
                .substring(0, v.description.length - 1)
                .contains(RegExp(r'\.\s')),
            isFalse,
            reason: v.wire);
        expect(v.description.length, lessThan(100), reason: v.wire);
      }
      expect(IdentityVisibility.private.description, contains('when you apply'));
      expect(IdentityVisibility.matchedOnly.description,
          contains('strong match'));
      expect(IdentityVisibility.recruiters.description,
          contains('recruitment agencies'));
    });

    test('only public warns', () {
      expect(IdentityVisibility.public.warning, isNotNull);
      for (final v in IdentityVisibility.values
          .where((v) => v != IdentityVisibility.public)) {
        expect(v.warning, isNull);
      }
    });

    test('new identities default to private; unknown values are private', () {
      expect(IdentityVisibility.fallback, IdentityVisibility.private);
      expect(IdentityVisibility.fromWire(null), IdentityVisibility.private);
      expect(IdentityVisibility.fromWire('weird'), IdentityVisibility.private);
      expect(IdentityVisibility.fromWire('matched_only'),
          IdentityVisibility.matchedOnly);
    });
  });

  group('default identity when applying', () {
    final driver = wi('d', 'Delivery Driver', prof: 'p-driver', profName: 'Delivery Driver', primary: true);
    final cook = wi('c', 'Cook', prof: 'p-cook', profName: 'Cook');
    final nurse = wi('n', 'Nurse', prof: 'p-nurse', profName: 'Nurse', status: 'archived');

    test('the identity whose profession matches the job', () {
      expect(
          defaultIdentityForJob([driver, cook], jobProfessionId: 'p-cook')?.id,
          'c');
    });

    test('matches by profession name when the id is unknown', () {
      expect(
          defaultIdentityForJob([driver, cook], jobProfessionName: 'cook')?.id,
          'c');
    });

    test('else the main one', () {
      expect(
          defaultIdentityForJob([cook, driver], jobProfessionId: 'p-other')?.id,
          'd');
      expect(defaultIdentityForJob([cook, driver])?.id, 'd');
    });

    test('never an archived identity', () {
      expect(
          defaultIdentityForJob([driver, nurse], jobProfessionId: 'p-nurse')
              ?.id,
          'd');
      expect(defaultIdentityForJob([nurse]), isNull);
      expect(defaultIdentityForJob(const []), isNull);
    });

    test('several matches prefer the main one', () {
      final cook2 = wi('c2', 'Head Cook', prof: 'p-cook', primary: true);
      expect(defaultIdentityForJob([cook, cook2], jobProfessionId: 'p-cook')?.id,
          'c2');
    });

    test('preview copy names the identity', () {
      expect(applyPreviewLine(cook), 'Employers will see your Cook profile only');
      expect(nudgeTitle(cook),
          'Complete your Cook profile to get better matches');
    });
  });

  group('parsing', () {
    test('identity profile', () {
      final p = IdentityProfile.fromJson({
        'identity': {
          'id': 'i1',
          'label': 'Cook',
          'profession_id': 'p',
          'profession': 'Cook',
          'is_primary': true,
          'status': 'active',
          'discoverability': 'recruiters',
          'total_experience_months': 30,
        },
        'completeness': {
          'score': 55,
          'missing': ['skills']
        },
        'fields': [
          {
            'attribute_id': 'a',
            'slug': 'cuisines',
            'label': 'Cuisines you can cook',
            'data_type': 'multi_select',
            'options': ['North Indian', 'Chinese'],
            'is_required': false,
            'scope': 'category',
            'value': ['Chinese'],
          }
        ],
      });
      expect(p.identity.label, 'Cook');
      expect(p.identity.professionName, 'Cook');
      expect(p.identity.visibility, IdentityVisibility.recruiters);
      expect(p.identity.completenessScore, 55);
      expect(p.fields.single.scope, 'category');
      expect(decodeFieldValue('multi_select', p.fields.single.value),
          ['Chinese']);
    });

    test('evidence', () {
      final e = IdentityEvidence.fromJson({
        'skills': [
          {
            'skill_id': 's',
            'name': 'Wiring',
            'verified': true,
            'evidence': [
              {'type': 'verified_employment', 'label': 'x', 'verified': true},
              {'type': 'self_declared', 'label': 'y', 'verified': false},
            ],
          }
        ],
        'trust': {'email_verified': true},
      });
      expect(e.skills.single.evidence.map((x) => evidenceBadge(x.type)),
          ['Verified job', 'Self-declared']);
      expect(e.emailVerified, isTrue);
      expect(e.phoneVerified, isFalse);
    });

    test('months label', () {
      expect(monthsLabel(6), '6 months');
      expect(monthsLabel(12), '1 year');
      expect(monthsLabel(18), '1.5 years');
      expect(monthsLabel(null), '');
    });
  });

  group('field widgets', () {
    Future<void> pumpField(WidgetTester tester, ProfileField f, Object? value,
        ValueChanged<Object?> onChanged) async {
      await tester.pumpWidget(MaterialApp(
        theme: OmeloTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProfileFieldInput(
                field: f, value: value, onChanged: onChanged),
          ),
        ),
      ));
    }

    testWidgets('multi_select renders chips and reports a list',
        (tester) async {
      Object? got;
      await pumpField(
          tester,
          field('multi_select', options: ['Van', 'Bus'], req: true),
          <String>['Van'],
          (v) => got = v);
      expect(find.byType(FilterChip), findsNWidgets(2));
      expect(find.textContaining('Required'), findsOneWidget);
      await tester.tap(find.text('Bus'));
      expect(got, ['Van', 'Bus']);
    });

    testWidgets('each data type gets its widget', (tester) async {
      final cases = <ProfileField, Finder>{
        field('boolean'): find.byType(SwitchListTile),
        field('single_select', options: ['Yes', 'No']):
            find.byType(SegmentedButton<String>),
        field('single_select', options: ['A1', 'B2', 'C3', 'D4']):
            find.byType(RadioListTile<String>),
        field('years'): find.byType(TextField),
        field('long_text'): find.byType(TextField),
        field('date'): find.text('Choose a date'),
        field('file'): find.textContaining('document'),
      };
      for (final e in cases.entries) {
        await pumpField(tester, e.key,
            decodeFieldValue(e.key.dataType, e.key.value), (_) {});
        expect(e.value, findsWidgets, reason: e.key.dataType);
      }
    });

    testWidgets('years field shows its unit and reports text',
        (tester) async {
      Object? got;
      await pumpField(tester, field('years'), 3, (v) => got = v);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('years'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '4.5');
      expect(encodeFieldValue(field('years'), got).value, 4.5);
    });
  });

  group('screens', () {
    Future<void> pumpAt(WidgetTester tester, Size size, Widget screen,
        List<Override> overrides, String location) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isSignedInProvider.overrideWithValue(true),
          ...overrides,
        ],
        child: MaterialApp.router(
          theme: OmeloTheme.light(),
          routerConfig: GoRouter(
            initialLocation: location,
            routes: [
              GoRoute(path: location, builder: (_, __) => screen),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    IdentityCardData card(WorkIdentity i, List<String> missing, int skills) =>
        IdentityCardData(
          identity: i,
          completeness:
              Completeness(score: i.completenessScore, missing: missing),
          skillCount: skills,
        );

    for (final size in const [Size(320, 2400), Size(1400, 1800)]) {
      testWidgets('hub renders at ${size.width.toInt()}px', (tester) async {
        await pumpAt(
          tester,
          size,
          const IdentitiesScreen(),
          [
            identityHubProvider.overrideWith((_) async => [
                  card(
                      wi('d', 'Delivery Driver',
                          profName: 'Delivery Driver',
                          primary: true,
                          score: 70),
                      ['about'],
                      4),
                  card(wi('c', 'Cook', profName: 'Cook', score: 35),
                      ['skills', 'about'], 1),
                  card(
                      wi('n', 'Nurse',
                          profName: 'Nurse', status: 'archived', score: 20),
                      ['skills'],
                      0),
                ]),
          ],
          '/identities',
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Main'), findsOneWidget);
        expect(find.text('Next: add 2 more skills'), findsOneWidget);
        expect(find.text('Archived'), findsOneWidget);
        expect(find.text('Restore'), findsOneWidget);
        expect(find.text('Only me'), findsNWidgets(2));
        final add = tester.widget<ButtonStyleButton>(find.ancestor(
            of: find.text('Add an identity'),
            matching: find.bySubtype<ButtonStyleButton>()));
        expect(add.onPressed, isNotNull);
      });
    }

    testWidgets('hub disables Add at five identities', (tester) async {
      await pumpAt(
        tester,
        const Size(400, 3000),
        const IdentitiesScreen(),
        [
          identityHubProvider.overrideWith((_) async => [
                for (var n = 0; n < 5; n++)
                  card(wi('$n', 'Job $n', primary: n == 0), const [], 3),
              ]),
        ],
        '/identities',
      );
      final add = tester.widget<ButtonStyleButton>(find.ancestor(
          of: find.text('Add an identity'),
          matching: find.bySubtype<ButtonStyleButton>()));
      expect(add.onPressed, isNull);
      expect(find.textContaining('the most you can have'), findsOneWidget);
    });

    testWidgets('apply: defaults to the matching identity and can switch',
        (tester) async {
      await pumpAt(
        tester,
        const Size(360, 2400),
        const ApplyScreen(jobId: 'j1'),
        [
          authRepositoryProvider.overrideWithValue(_SignedInAuth()),
          jobDetailProvider.overrideWith((_, __) async => cookJob()),
          myIdentitiesProvider.overrideWith((_) async => [
                wi('d', 'Delivery Driver', prof: 'p-driver', primary: true),
                wi('c', 'Cook', prof: 'p-cook', profName: 'Cook'),
                wi('n', 'Nurse', prof: 'p-nurse', status: 'archived'),
              ]),
        ],
        '/apply/j1',
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Apply as'), findsOneWidget);
      expect(find.text('Nurse'), findsNothing); // archived: not offered
      expect(find.text('Employers will see your Cook profile only'),
          findsOneWidget);
      await tester.tap(find.text('Delivery Driver'));
      await tester.pump();
      expect(find.text('Employers will see your Delivery Driver profile only'),
          findsOneWidget);
    });

    testWidgets('apply: one identity shows no chooser', (tester) async {
      await pumpAt(
        tester,
        const Size(360, 2400),
        const ApplyScreen(jobId: 'j1'),
        [
          authRepositoryProvider.overrideWithValue(_SignedInAuth()),
          jobDetailProvider.overrideWith((_, __) async => cookJob()),
          myIdentitiesProvider.overrideWith(
              (_) async => [wi('d', 'Delivery Driver', primary: true)]),
        ],
        '/apply/j1',
      );
      expect(find.text('Apply as'), findsNothing);
      expect(find.text('Employers will see your Delivery Driver profile only'),
          findsOneWidget);
    });

    for (final size in const [Size(320, 6000), Size(1400, 6000)]) {
      testWidgets('editor renders every section at ${size.width.toInt()}px',
          (tester) async {
        final profile = IdentityProfile.fromJson({
          'identity': {
            'id': 'c',
            'label': 'Cook',
            'profession_id': 'p',
            'profession': 'Cook',
            'is_primary': true,
            'status': 'active',
            'discoverability': 'private',
          },
          'completeness': {
            'score': 45,
            'missing': ['skills', 'profile_questions']
          },
          'fields': [
            {
              'attribute_id': '1',
              'slug': 'cuisines',
              'label': 'Cuisines you can cook',
              'data_type': 'multi_select',
              'options': ['North Indian', 'South Indian', 'Chinese'],
              'is_required': true,
              'scope': 'category',
              'value': null,
            },
            {
              'attribute_id': '2',
              'slug': 'food-safety-cert',
              'label': 'Food safety certification',
              'data_type': 'boolean',
              'scope': 'category',
              'value': true,
            },
            {
              'attribute_id': '3',
              'slug': 'can-travel-daily-km',
              'label': 'How far can you travel to work each day?',
              'data_type': 'number',
              'unit': 'km',
              'scope': 'universal',
              'value': 12,
            },
          ],
        });
        await pumpAt(
          tester,
          size,
          const IdentityEditorScreen(identityId: 'c'),
          [
            identityProfileProvider.overrideWith((_, __) async => profile),
            identitySkillsProvider.overrideWith((_, __) async => const [
                  PersonSkill(
                      id: 'r1',
                      skillId: 's1',
                      name: 'Tandoor',
                      workIdentityId: 'c',
                      proficiency: 'advanced',
                      monthsUsed: 24),
                ]),
            identityExperiencesProvider.overrideWith((_, __) async => [
                  Experience(
                      id: 'e1',
                      employerName: 'Hotel Sagar',
                      title: 'Line cook',
                      workIdentityId: 'c',
                      startedOn: DateTime(2021, 1),
                      isCurrent: true,
                      isVerified: true),
                ]),
            identityPreferencesProvider
                .overrideWith((_, __) async => const WorkPreferences()),
            identityPlacesProvider.overrideWith((_, __) async => const [
                  LocationPreference(id: 'l1', name: 'Pune', radiusKm: 10),
                ]),
            identityEvidenceProvider.overrideWith((_, __) async =>
                IdentityEvidence.fromJson({
                  'skills': [
                    {
                      'skill_id': 's1',
                      'name': 'Tandoor',
                      'evidence': [
                        {
                          'type': 'experience',
                          'label': '2 years using it',
                        },
                        {'type': 'self_declared', 'label': 'Added'},
                      ],
                    }
                  ],
                })),
          ],
          '/identities/c',
        );
        final err = tester.takeException();
        expect(err, isNull, reason: '$err');
        expect(find.text('Next: add 2 more skills'), findsOneWidget);
        expect(find.textContaining('Cuisines you can cook'), findsOneWidget);
        expect(find.byType(FilterChip), findsWidgets);
        // Work preferences, and (Release 4) recruiter requests.
        expect(find.byType(SwitchListTile), findsNWidgets(2));
        expect(
            find.widgetWithText(SwitchListTile,
                'Let recruiters and agencies ask to represent me'),
            findsOneWidget);
        expect(find.text('km'), findsOneWidget);
        expect(find.text('Verified by Omelo'), findsOneWidget);
        for (final v in IdentityVisibility.values) {
          expect(find.text(v.description), findsOneWidget);
        }
        expect(find.text('Experience'), findsWidgets);
        expect(find.text('Self-declared'), findsOneWidget);
        expect(find.text('Pune'), findsOneWidget);
      });
    }
  });
}
