import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omelo_user_app/core/app_state.dart';
import 'package:omelo_user_app/core/theme.dart';
import 'package:omelo_user_app/data/identity_repository.dart';
import 'package:omelo_user_app/data/invitations_repository.dart';
import 'package:omelo_user_app/data/messaging.dart';
import 'package:omelo_user_app/data/representations_repository.dart';
import 'package:omelo_user_app/features/identities/identity_editor_screen.dart';
import 'package:omelo_user_app/features/representations/recruiters_screen.dart';
import 'package:omelo_user_app/features/representations/representation_detail_screen.dart';
import 'package:omelo_user_app/features/representations/representations_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _consentId = '11111111-2222-4333-8444-555555555555';
const _appId = '66666666-7777-4888-9999-000000000000';

Map<String, dynamic> repJson({
  String id = _consentId,
  String status = 'requested',
  List<String> scope = const ['identity', 'skills', 'contact'],
  String? requestExpiresAt = '2026-10-03T12:00:00Z',
  String? expiresAt,
  String? respondedAt,
  bool canRevoke = false,
  Map<String, dynamic>? submission,
  Map<String, dynamic>? placement,
  String agencyId = 'ag1',
  String agencyName = 'Acme Staffing',
  bool independent = false,
  String requestedAt = '2026-09-18T09:00:00Z',
  String position = 'Warehouse Associate',
}) => {
  'id': id,
  'terms': {
    'agency': {
      'id': agencyId,
      'name': agencyName,
      'verified': true,
      'independent': independent,
      'logo_url': null,
    },
    'recruiter': {'id': 'r1', 'name': 'Priya Nair'},
    'client': {'name': 'BlueDart Logistics', 'on_omelo': true},
    'position': position,
    'reference': 'JO-7',
    'openings': 3,
    'location': 'Bhiwandi, Thane',
    'workplace_type': 'onsite',
    'work_type': 'full_time',
    'shift_types': ['day', 'night'],
    'pay': {'min': 22000, 'max': 22000, 'period': 'month', 'currency': 'INR'},
    'start_date': '2026-10-01',
    'closing_date': '2026-09-30',
    'hard_requirements': ['Can lift 25 kg'],
    'description': 'Loading and unloading trucks.',
    'identity_label': 'Warehouse Worker',
  },
  'scope': scope,
  'message': 'Your forklift experience fits this job well.',
  'work_identity_id': 'w1',
  'identity_label': 'Warehouse Worker',
  'requested_at': requestedAt,
  'request_expires_at': requestExpiresAt,
  'responded_at': respondedAt,
  'expires_at': expiresAt,
  'valid_days': 60,
  'decline_reason': null,
  'revoke_reason': null,
  'status': status,
  'can_revoke': canRevoke,
  'submission': submission,
  'placement': placement,
};

Representation rep({
  String id = _consentId,
  String status = 'requested',
  List<String> scope = const ['identity', 'skills', 'contact'],
  String? requestExpiresAt = '2026-10-03T12:00:00Z',
  String? expiresAt,
  String? respondedAt,
  bool canRevoke = false,
  Map<String, dynamic>? submission,
  Map<String, dynamic>? placement,
  String agencyId = 'ag1',
  String agencyName = 'Acme Staffing',
  bool independent = false,
  String requestedAt = '2026-09-18T09:00:00Z',
  String position = 'Warehouse Associate',
}) => Representation.fromJson(
  repJson(
    id: id,
    status: status,
    scope: scope,
    requestExpiresAt: requestExpiresAt,
    expiresAt: expiresAt,
    respondedAt: respondedAt,
    canRevoke: canRevoke,
    submission: submission,
    placement: placement,
    agencyId: agencyId,
    agencyName: agencyName,
    independent: independent,
    requestedAt: requestedAt,
    position: position,
  ),
);

Map<String, dynamic> sub(String status, {String? applicationId = _appId}) => {
  'id': 's1',
  'status': status,
  'submitted_at': '2026-09-20T10:00:00Z',
  'application_id': applicationId,
};

class _FakeReps implements RepresentationsRepository {
  final calls = <Map<String, Object?>>[];
  final allow = <String, bool>{};
  Object? revokeError;

  @override
  Future<void> accept(String consentId) async =>
      calls.add(acceptRepresentationPayload(consentId));

  @override
  Future<void> decline(
    String consentId,
    RepresentationDeclineReason? reason, [
    String? otherText,
  ]) async =>
      calls.add(declineRepresentationPayload(consentId, reason, otherText));

  @override
  Future<void> revoke(String consentId, [String? reason]) async {
    if (revokeError != null) throw revokeError!;
    calls.add(revokeRepresentationPayload(consentId, reason));
  }

  @override
  Future<void> setAllowRecruiterRequests(String identityId, bool allow) async =>
      this.allow[identityId] = allow;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInvites implements InvitationsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  final now = DateTime(2026, 9, 19, 12);

  // -------------------------------------------------------------------------
  group('parse', () {
    test('reads terms, scope, submission and placement', () {
      final list = parseRepresentations([
        repJson(
          status: 'active',
          submission: sub('reviewing'),
          placement: {
            'id': 'p1',
            'status': 'pending_start',
            'start_date': '2026-10-01',
          },
        ),
        {'no': 'id'},
        'junk',
      ]);
      expect(list, hasLength(1));
      final r = list.single;
      expect(r.agencyName, 'Acme Staffing');
      expect(r.terms.agencyVerified, isTrue);
      expect(r.terms.recruiterName, 'Priya Nair');
      expect(r.terms.clientName, 'BlueDart Logistics');
      expect(r.terms.clientOnOmelo, isTrue);
      expect(r.terms.shiftTypes, ['day', 'night']);
      expect(r.terms.hardRequirements, ['Can lift 25 kg']);
      expect(r.terms.openings, 3);
      expect(r.status, RepresentationStatus.active);
      expect(r.submission!.status, SubmissionStatus.reviewing);
      expect(r.submission!.applicationId, _appId);
      expect(r.placement!.status, 'pending_start');
      expect(parseRepresentations(null), isEmpty);
    });

    test('missing terms fall back to plain words', () {
      final r = Representation.fromJson({
        'id': 'x',
        'status': 'requested',
        'terms': null,
        'scope': null,
      });
      expect(r.agencyName, 'A recruitment agency');
      expect(r.position, 'A job');
      expect(r.terms.clientName, 'their client');
      expect(r.scope, isEmpty);
      expect(
        RepresentationStatus.fromWire('weird'),
        RepresentationStatus.expired,
      );
    });

    test('waiting first, then newest', () {
      final list = sortRepresentations([
        rep(id: 'old', status: 'declined', requestedAt: '2026-09-10T00:00:00Z'),
        rep(id: 'new', status: 'accepted', requestedAt: '2026-09-18T00:00:00Z'),
        rep(id: 'wait', requestedAt: '2026-09-01T00:00:00Z'),
      ], now);
      expect(list.map((r) => r.id), ['wait', 'new', 'old']);
    });
  });

  // -------------------------------------------------------------------------
  group('status and actions', () {
    test('labels', () {
      expect(
        RepresentationStatus.values.map(representationStatusLabel).toList(),
        [
          'Waiting for you',
          'You said yes',
          'Put forward',
          'You said no',
          'Ended',
          'You took it back',
          'Cancelled by agency',
        ],
      );
      expect(SubmissionStatus.values.map(submissionStatusLabel).toList(), [
        'Submitted',
        'Reviewing',
        'Shortlisted',
        'Interview',
        'Offer',
        'Hired',
        'Not selected',
        'Withdrawn',
      ]);
    });

    test('a waiting request can be accepted or declined', () {
      final a = representationActions(rep(), now);
      expect(a.canAccept, isTrue);
      expect(a.canDecline, isTrue);
      expect(a.canRevoke, isFalse);
      expect(a.isAnswerable, isTrue);
      expect(representationAnswerBy(rep(), now), 'Answer by 3 Oct');
    });

    test('an unanswered request past its date is expired (computed)', () {
      final r = rep(requestExpiresAt: '2026-09-18T08:00:00Z');
      expect(r.status, RepresentationStatus.requested);
      expect(r.statusAt(now), RepresentationStatus.expired);
      expect(r.isPendingAt(now), isFalse);
      final a = representationActions(r, now);
      expect(a.isAnswerable, isFalse);
      expect(a.note, contains('ended before you answered'));
      expect(representationAnswerBy(r, now), isNull);
      expect(pendingRepresentations([r], now), isEmpty);
    });

    test('an accepted yes past its end date is expired (computed)', () {
      final r = rep(
        status: 'accepted',
        canRevoke: true,
        respondedAt: '2026-07-01T00:00:00Z',
        expiresAt: '2026-08-30T00:00:00Z',
      );
      expect(r.statusAt(now), RepresentationStatus.expired);
      final a = representationActions(r, now);
      expect(a.canRevoke, isFalse);
      expect(a.note, contains('Your yes for this job has ended'));
    });

    test('accepted: represented until, can revoke, nothing submitted', () {
      final r = rep(
        status: 'accepted',
        canRevoke: true,
        respondedAt: '2026-09-18T10:00:00Z',
        expiresAt: '2026-11-17T10:00:00Z',
      );
      final a = representationActions(r, now);
      expect(a.headline, "You're represented for this job until 17 Nov");
      expect(a.canRevoke, isTrue);
      expect(a.canViewApplication, isFalse);
      expect(a.note, contains('can now put you forward to BlueDart Logistics'));
    });

    test('can_revoke comes from the server; blocked explains why', () {
      final open = rep(
        status: 'active',
        canRevoke: true,
        expiresAt: '2026-11-17T10:00:00Z',
        submission: sub('submitted'),
      );
      expect(representationActions(open, now).canRevoke, isTrue);
      expect(representationActions(open, now).canViewApplication, isTrue);

      final blocked = rep(
        status: 'active',
        canRevoke: false,
        expiresAt: '2026-11-17T10:00:00Z',
        submission: sub('interview'),
      );
      final a = representationActions(blocked, now);
      expect(a.canRevoke, isFalse);
      expect(a.note, kRevokeBlockedMessage);
      expect(a.canViewApplication, isTrue);

      final rejected = rep(
        status: 'active',
        canRevoke: true,
        expiresAt: '2026-11-17T10:00:00Z',
        submission: sub('rejected'),
      );
      expect(
        representationActions(rejected, now).note,
        contains('not a verdict'),
      );
    });

    test('ended states have no actions', () {
      for (final s in ['declined', 'revoked', 'withdrawn']) {
        final a = representationActions(rep(status: s), now);
        expect(a.isAnswerable, isFalse, reason: s);
        expect(a.canRevoke, isFalse, reason: s);
        expect(a.note, isNotNull, reason: s);
      }
      expect(
        representationActions(rep(status: 'declined'), now).note,
        contains('You said no'),
      );
      expect(
        representationActions(rep(status: 'withdrawn'), now).note,
        contains('agency cancelled'),
      );
    });

    test('revoke blocked error is recognised', () {
      expect(
        isRevokeBlockedError(
          const PostgrestException(message: kRevokeBlockedMessage),
        ),
        isTrue,
      );
      expect(isRevokeBlockedError(Exception('offline')), isFalse);
      expect(kRevokeEffect, contains('can no longer submit you'));
    });
  });

  // -------------------------------------------------------------------------
  group('what will be shared', () {
    test('ticked items and not-shared items, in order', () {
      final items = scopeChecklist([
        'skills',
        'contact',
      ], identityLabel: 'Warehouse Worker');
      expect(items.map((i) => i.toString()).toList(), [
        '✓ Your Warehouse Worker profile (name, headline, experience summary)',
        '✓ Skills',
        '– Work history',
        '– Verified evidence (verified jobs, licences)',
        '– Profile answers',
        '✓ Your phone and email — only after you accept',
      ]);
    });

    test('the profile is always shared; contact wording when not shared', () {
      final items = scopeChecklist(const []);
      expect(items.first.shared, isTrue);
      expect(items.first.label, startsWith('Your work profile'));
      expect(items.where((i) => i.shared), hasLength(1));
      expect(items.last.label, 'Your phone and email');
      expect(items.last.shared, isFalse);
      final all = scopeChecklist(kRepresentationScopes);
      expect(all.every((i) => i.shared), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('terms formatting', () {
    test('pay', () {
      expect(representationPayLabel(rep().terms.pay), '₹22,000 / month');
      expect(
        representationPayLabel(
          const RepresentationPay(
            min: 18000,
            max: 120000,
            period: 'month',
            currency: 'INR',
          ),
        ),
        '₹18,000 – ₹1,20,000 / month',
      );
      expect(
        representationPayLabel(
          const RepresentationPay(min: 700, period: 'day', currency: 'INR'),
        ),
        '₹700 / day',
      );
      expect(
        representationPayLabel(
          const RepresentationPay(max: 15, period: 'hour', currency: 'USD'),
        ),
        '\$15 / hour',
      );
      expect(
        representationPayLabel(
          const RepresentationPay(min: 50, period: 'per_task', currency: 'INR'),
        ),
        '₹50 / task',
      );
      expect(
        representationPayLabel(
          const RepresentationPay(min: 50, currency: 'INR'),
        ),
        '₹50',
      );
      expect(representationPayLabel(const RepresentationPay()), isNull);
    });

    test('type, shifts, start, openings, duration', () {
      final t = rep().terms;
      expect(representationTypeLine(t), 'Full-time · On-site');
      expect(representationShiftLine(t), 'Day shift, Night shift');
      expect(representationStartLine(t, now), 'Starts 1 Oct');
      expect(openingsLine(t), '3 openings');
      expect(durationLine(rep()), 'Valid for 60 days after you accept');
      expect(
        representedUntilLine(rep(status: 'accepted'), now),
        "You're represented for this job for 60 days",
      );
      expect(
        wantsToRepresentTitle(rep()),
        'Acme Staffing wants to represent you',
      );
      expect(placementLine(null, now), isNull);
      expect(
        placementLine(
          RepresentationPlacement(
            id: 'p',
            status: 'pending_start',
            startDate: DateTime(2026, 10, 1),
          ),
          now,
        ),
        'You got the job · starts 1 Oct',
      );
    });

    test('submission timeline', () {
      expect(
        submissionTimeline(SubmissionStatus.shortlisted).join(' '),
        'Submitted:done Reviewing:done Shortlisted:current '
        'Interview:upcoming Offer:upcoming Hired:upcoming',
      );
      expect(
        submissionTimeline(SubmissionStatus.hired).last.state,
        SubmissionStepState.done,
      );
      expect(
        submissionTimeline(SubmissionStatus.rejected).join(' '),
        'Submitted:done Not selected:stopped',
      );
      expect(
        submissionTimeline(SubmissionStatus.withdrawn).join(' '),
        'Submitted:done Withdrawn:stopped',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('payloads', () {
    test('decline reason chips and other text', () {
      expect(
        declineRepresentationPayload(
          'c1',
          RepresentationDeclineReason.payTooLow,
        ),
        {'p_consent': 'c1', 'p_accept': false, 'p_reason': 'Pay too low'},
      );
      expect(declineRepresentationPayload('c1', null), {
        'p_consent': 'c1',
        'p_accept': false,
        'p_reason': null,
      });
      expect(
        representationDeclineText(RepresentationDeclineReason.noAgency),
        "Don't want an agency",
      );
      expect(
        representationDeclineText(
          RepresentationDeclineReason.other,
          '  Found   a job  ',
        ),
        'Found a job',
      );
      expect(
        representationDeclineText(RepresentationDeclineReason.other, '  '),
        'Other',
      );
      expect(
        representationDeclineText(
          RepresentationDeclineReason.other,
          'x' * 400,
        )!.length,
        kRepresentationReasonMax,
      );
      expect(RepresentationDeclineReason.values.map((r) => r.label), [
        'Not interested in this job',
        'Pay too low',
        'Too far',
        "Don't want an agency",
        'Other',
      ]);
    });

    test('accept and revoke', () {
      expect(acceptRepresentationPayload('c1'), {
        'p_consent': 'c1',
        'p_accept': true,
      });
      expect(revokeRepresentationPayload('c1'), {
        'p_consent': 'c1',
        'p_reason': null,
      });
      expect(revokeRepresentationPayload('c1', '  moved  city '), {
        'p_consent': 'c1',
        'p_reason': 'moved city',
      });
    });
  });

  // -------------------------------------------------------------------------
  group('agencies', () {
    test('grouped, counted, newest activity first', () {
      final list = [
        rep(id: 'a', requestedAt: '2026-09-10T00:00:00Z'),
        rep(
          id: 'b',
          status: 'active',
          canRevoke: true,
          expiresAt: '2026-11-01T00:00:00Z',
          requestedAt: '2026-09-01T00:00:00Z',
          submission: sub('submitted'),
        ),
        rep(
          id: 'c',
          agencyId: 'ag2',
          agencyName: 'Ravi Kumar',
          independent: true,
          status: 'declined',
          requestedAt: '2026-09-15T00:00:00Z',
        ),
      ];
      final groups = groupByAgency(list, now);
      expect(groups.map((g) => g.name), ['Acme Staffing', 'Ravi Kumar']);
      expect(groups.first.opportunities, 2);
      expect(groups.first.activeCount, 1);
      expect(groups.first.pendingCount, 1);
      expect(agencyCountsLine(groups.first), '2 jobs · 1 waiting · 1 active');
      expect(agencyCountsLine(groups.last), '1 job');
      expect(groups.last.independent, isTrue);
      expect(agencyByApplication(list), {_appId: 'Acme Staffing'});
      expect(
        representationsRoute(agency: 'ag1'),
        '/representations?agency=ag1',
      );
    });

    test('home card title', () {
      expect(
        representHomeTitle([rep()]),
        'Acme Staffing wants to represent you for Warehouse Associate',
      );
      expect(
        representHomeTitle([rep(), rep(id: 'x')]),
        '2 agencies want to represent you',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('deeplinks', () {
    AppNotification n(String type, {String? link, String? entity}) =>
        AppNotification(
          id: 'n',
          type: type,
          title: 'Acme Staffing wants to represent you',
          createdAt: DateTime(2026, 9, 18),
          deeplink: link,
          entityType: entity,
          entityId: _consentId,
        );

    test('both notification types open the request', () {
      for (final type in ['representation_request', 'representation_update']) {
        expect(
          n(
            type,
            link: '/representations/$_consentId',
            entity: 'candidate_consent',
          ).target,
          '/representations/$_consentId',
          reason: type,
        );
        expect(notificationKind(type), NotificationKind.representation);
      }
      expect(
        workerDeeplink('https://omelo.app/representations/$_consentId'),
        '/representations/$_consentId',
      );
      expect(workerDeeplink('/representations'), '/representations');
      expect(workerDeeplink('/recruiters'), '/recruiters');
      expect(workerDeeplink('/representations/nope'), isNull);
    });

    test('entity fallback only without a link of its own', () {
      expect(
        n('representation_update', entity: 'candidate_consent').target,
        '/representations/$_consentId',
      );
      // A recruiter's notice points at their dashboard: not a worker screen.
      expect(
        n(
          'representation_update',
          link: '/dashboard/agency/candidates',
          entity: 'candidate_consent',
        ).target,
        isNull,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('screens', () {
    late _FakeReps reps;
    setUp(() => reps = _FakeReps());

    Future<void> pumpAt(
      WidgetTester tester,
      Size size,
      Widget screen,
      List<Override> overrides,
      String location,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isSignedInProvider.overrideWithValue(true),
            representationsRepositoryProvider.overrideWithValue(reps),
            invitationsRepositoryProvider.overrideWithValue(_FakeInvites()),
            ...overrides,
          ],
          child: MaterialApp.router(
            theme: OmeloTheme.light(),
            routerConfig: GoRouter(
              initialLocation: location,
              routes: [
                GoRoute(path: location, builder: (_, __) => screen),
                GoRoute(
                  path: '/applications/:id',
                  builder: (_, s) =>
                      Text('application ${s.pathParameters['id']}'),
                ),
                GoRoute(
                  path: '/representations/:id',
                  builder: (_, s) => Text('request ${s.pathParameters['id']}'),
                ),
                GoRoute(
                  path: '/identities',
                  builder: (_, __) => const Text('identities hub'),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Override listOf(List<Representation> list) =>
        myRepresentationsProvider.overrideWith((_) async => list);

    for (final size in const [Size(320, 2600), Size(1400, 1600)]) {
      testWidgets('pending detail at ${size.width.toInt()}px', (tester) async {
        await pumpAt(
          tester,
          size,
          const RepresentationDetailScreen(consentId: _consentId),
          [
            listOf([
              rep(
                requestExpiresAt: DateTime.now()
                    .add(const Duration(days: 5))
                    .toIso8601String(),
              ),
            ]),
          ],
          '/representations/$_consentId',
        );
        expect(tester.takeException(), isNull);
        expect(
          find.text('Acme Staffing wants to represent you'),
          findsOneWidget,
        );
        expect(find.text('Verified'), findsOneWidget);
        expect(find.text('Recruiter: Priya Nair'), findsOneWidget);
        expect(find.text('Warehouse Associate'), findsOneWidget);
        expect(find.text('at BlueDart Logistics'), findsOneWidget);
        expect(find.text('₹22,000 / month'), findsOneWidget);
        expect(find.text('Day shift, Night shift'), findsOneWidget);
        expect(find.text('Can lift 25 kg'), findsOneWidget);
        expect(find.textContaining('forklift'), findsOneWidget);
        expect(find.text('What will be shared'), findsOneWidget);
        expect(find.text('Skills'), findsOneWidget);
        expect(find.text('Not shared'), findsNWidgets(3));
        expect(find.text('Valid for 60 days after you accept'), findsOneWidget);
        expect(find.textContaining('Answer by'), findsOneWidget);
        expect(find.text('Accept'), findsOneWidget);
        expect(find.text('Decline'), findsOneWidget);
      });
    }

    testWidgets('accept: confirm restates the terms, then represented', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const Size(400, 2600),
        const RepresentationDetailScreen(consentId: _consentId),
        [
          listOf([rep(requestExpiresAt: '2099-01-01T00:00:00Z')]),
        ],
        '/representations/$_consentId',
      );
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(find.text('Say yes to Acme Staffing?'), findsOneWidget);
      expect(
        find.textContaining('to BlueDart Logistics for Warehouse Associate'),
        findsOneWidget,
      );
      expect(find.textContaining('For 60 days'), findsOneWidget);
      await tester.tap(find.text('Yes, represent me'));
      await tester.pumpAndSettle();
      expect(reps.calls, [
        {'p_consent': _consentId, 'p_accept': true},
      ]);
      expect(find.text('Accept'), findsNothing);
      expect(
        find.textContaining("You're represented for this job until"),
        findsOneWidget,
      );
      expect(find.text('Take back my yes'), findsOneWidget);
    });

    testWidgets('decline: reason chips and other text', (tester) async {
      await pumpAt(
        tester,
        const Size(400, 2600),
        const RepresentationDetailScreen(consentId: _consentId),
        [
          listOf([rep(requestExpiresAt: '2099-01-01T00:00:00Z')]),
        ],
        '/representations/$_consentId',
      );
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      for (final r in RepresentationDeclineReason.values) {
        expect(find.text(r.label), findsOneWidget);
      }
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' Already working ');
      await tester.tap(find.text('Send: no thanks'));
      await tester.pumpAndSettle();
      expect(reps.calls, [
        {
          'p_consent': _consentId,
          'p_accept': false,
          'p_reason': 'Already working',
        },
      ]);
      expect(find.text('Accept'), findsNothing);
      expect(find.textContaining('You said no.'), findsOneWidget);
    });

    testWidgets('submitted: timeline, application link, revoke', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const Size(400, 3200),
        const RepresentationDetailScreen(consentId: _consentId),
        [
          listOf([
            rep(
              status: 'active',
              canRevoke: true,
              respondedAt: '2026-09-18T10:00:00Z',
              expiresAt: '2099-11-17T10:00:00Z',
              submission: sub('reviewing'),
            ),
          ]),
        ],
        '/representations/$_consentId',
      );
      expect(find.text('Where you were put forward'), findsOneWidget);
      expect(find.text('Reviewing'), findsOneWidget);
      expect(find.text('Hired'), findsOneWidget);
      expect(find.text('Open my application'), findsOneWidget);
      await tester.ensureVisible(find.text('Take back my yes'));
      await tester.tap(find.text('Take back my yes'));
      await tester.pumpAndSettle();
      expect(find.text(kRevokeEffect), findsWidgets);
      await tester.tap(find.text('Yes, take it back'));
      await tester.pumpAndSettle();
      expect(reps.calls, [
        {'p_consent': _consentId, 'p_reason': null},
      ]);
      expect(find.text('You took it back'), findsOneWidget);
      expect(find.text('Take back my yes'), findsNothing);
    });

    testWidgets('revoke refused by the server: offer the application', (
      tester,
    ) async {
      reps.revokeError = const PostgrestException(
        message: kRevokeBlockedMessage,
      );
      await pumpAt(
        tester,
        const Size(400, 3200),
        const RepresentationDetailScreen(consentId: _consentId),
        [
          listOf([
            rep(
              status: 'active',
              canRevoke: true,
              expiresAt: '2099-11-17T10:00:00Z',
              submission: sub('submitted'),
            ),
          ]),
        ],
        '/representations/$_consentId',
      );
      await tester.ensureVisible(find.text('Take back my yes'));
      await tester.tap(find.text('Take back my yes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes, take it back'));
      await tester.pumpAndSettle();
      expect(find.text('You cannot take it back here'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(FilledButton, 'Open my application'),
      );
      await tester.pumpAndSettle();
      expect(find.text('application $_appId'), findsOneWidget);
    });

    testWidgets('not revocable: no revoke button, blocked note', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const Size(400, 3200),
        const RepresentationDetailScreen(consentId: _consentId),
        [
          listOf([
            rep(
              status: 'active',
              canRevoke: false,
              expiresAt: '2099-11-17T10:00:00Z',
              submission: sub('interview'),
            ),
          ]),
        ],
        '/representations/$_consentId',
      );
      expect(find.text('Take back my yes'), findsNothing);
      expect(find.text(kRevokeBlockedMessage), findsOneWidget);
      expect(find.text('Open my application'), findsOneWidget);
    });

    testWidgets('unknown request says so', (tester) async {
      await pumpAt(
        tester,
        const Size(360, 1600),
        const RepresentationDetailScreen(consentId: 'other'),
        [
          listOf([rep()]),
        ],
        '/representations/other',
      );
      expect(find.text('Request not found'), findsOneWidget);
    });

    for (final size in const [Size(320, 1600), Size(1400, 1200)]) {
      testWidgets('list at ${size.width.toInt()}px', (tester) async {
        await pumpAt(tester, size, const RepresentationsScreen(), [
          listOf([
            rep(requestExpiresAt: '2099-01-01T00:00:00Z'),
            rep(id: 'b', status: 'declined'),
          ]),
        ], '/representations');
        expect(tester.takeException(), isNull);
        expect(
          find.text('1 request is waiting for your answer.'),
          findsOneWidget,
        );
        expect(find.text('Waiting for you'), findsOneWidget);
        expect(find.text('You said no'), findsOneWidget);
        await tester.tap(find.text('Waiting for you'));
        await tester.pumpAndSettle();
        expect(find.text('request $_consentId'), findsOneWidget);
      });
    }

    testWidgets('empty list explains visibility', (tester) async {
      await pumpAt(
        tester,
        const Size(360, 1600),
        const RepresentationsScreen(),
        [listOf(const [])],
        '/representations',
      );
      expect(find.text('No requests from recruiters yet'), findsOneWidget);
      expect(find.textContaining('Employers and agencies'), findsOneWidget);
    });

    testWidgets('agency filter shows that agency only', (tester) async {
      await pumpAt(
        tester,
        const Size(400, 1600),
        const RepresentationsScreen(agency: 'ag2'),
        [
          listOf([
            rep(),
            rep(
              id: 'c',
              agencyId: 'ag2',
              agencyName: 'Ravi Kumar',
              position: 'Forklift Driver',
            ),
          ]),
        ],
        '/representations',
      );
      expect(find.text('Forklift Driver'), findsOneWidget);
      expect(find.text('Warehouse Associate'), findsNothing);
    });

    for (final size in const [Size(320, 1600), Size(1400, 1200)]) {
      testWidgets('recruiters screen at ${size.width.toInt()}px', (
        tester,
      ) async {
        await pumpAt(tester, size, const RecruitersScreen(), [
          listOf([
            rep(requestExpiresAt: '2099-01-01T00:00:00Z'),
            rep(
              id: 'c',
              agencyId: 'ag2',
              agencyName: 'Ravi Kumar',
              independent: true,
              status: 'declined',
            ),
          ]),
        ], '/recruiters');
        expect(tester.takeException(), isNull);
        expect(
          find.textContaining('only put you forward with your yes'),
          findsOneWidget,
        );
        expect(find.text('Acme Staffing'), findsOneWidget);
        expect(find.text('Ravi Kumar'), findsOneWidget);
        expect(find.text('Independent recruiter'), findsOneWidget);
        expect(find.text('1 waiting for your answer'), findsOneWidget);
      });
    }

    // -- Identity editor --------------------------------------------------
    IdentityProfile profileWith(IdentityVisibility v) =>
        IdentityProfile.fromJson({
          'identity': {
            'id': 'c',
            'label': 'Warehouse Worker',
            'is_primary': true,
            'status': 'active',
            'discoverability': v.wire,
          },
          'completeness': {'score': 80, 'missing': []},
          'fields': [],
        });

    List<Override> editor(IdentityVisibility v, {bool allow = true}) => [
      identityProfileProvider.overrideWith((_, __) async => profileWith(v)),
      identitySkillsProvider.overrideWith((_, __) async => const []),
      identityExperiencesProvider.overrideWith((_, __) async => const []),
      identityPreferencesProvider.overrideWith(
        (_, __) async => const WorkPreferences(),
      ),
      identityPlacesProvider.overrideWith((_, __) async => const []),
      identityEvidenceProvider.overrideWith(
        (_, __) async => const IdentityEvidence(),
      ),
      allowInvitationsProvider.overrideWith((_, __) async => true),
      allowRecruiterRequestsProvider.overrideWith((_, __) async => allow),
    ];

    const switchTitle = 'Let recruiters and agencies ask to represent me';

    testWidgets('editor: recruiter switch saves; agencies can find it', (
      tester,
    ) async {
      await pumpAt(
        tester,
        const Size(400, 5000),
        const IdentityEditorScreen(identityId: 'c'),
        editor(IdentityVisibility.recruiters, allow: false),
        '/identities/c',
      );
      expect(tester.takeException(), isNull);
      final tile = find.widgetWithText(SwitchListTile, switchTitle);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      expect(
        find.textContaining('Agencies can find this profile'),
        findsOneWidget,
      );
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(reps.allow, {'c': true});
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    });

    for (final v in const [
      IdentityVisibility.private,
      IdentityVisibility.matchedOnly,
      IdentityVisibility.discoverable,
    ]) {
      testWidgets('editor: ${v.wire} says agencies cannot find it', (
        tester,
      ) async {
        await pumpAt(
          tester,
          const Size(400, 5000),
          const IdentityEditorScreen(identityId: 'c'),
          editor(v),
          '/identities/c',
        );
        expect(find.text(switchTitle), findsOneWidget);
        expect(
          find.textContaining('Agencies cannot find this profile'),
          findsOneWidget,
        );
        expect(find.text('Change to "Employers and agencies"'), findsOneWidget);
      });
    }

    test('findability follows visibility', () {
      expect(agenciesCanFind(IdentityVisibility.recruiters), isTrue);
      expect(agenciesCanFind(IdentityVisibility.public), isTrue);
      expect(agenciesCanFind(IdentityVisibility.discoverable), isFalse);
      expect(IdentityVisibility.recruiters.title, 'Employers and agencies');
    });
  });
}
