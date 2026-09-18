import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omelo_user_app/core/app_state.dart';
import 'package:omelo_user_app/core/theme.dart';
import 'package:omelo_user_app/data/auth_repository.dart';
import 'package:omelo_user_app/data/identity_repository.dart';
import 'package:omelo_user_app/data/invitations_repository.dart';
import 'package:omelo_user_app/data/job.dart';
import 'package:omelo_user_app/data/job_events.dart';
import 'package:omelo_user_app/data/messaging.dart';
import 'package:omelo_user_app/data/saved_jobs_repository.dart';
import 'package:omelo_user_app/features/apply/apply_screen.dart';
import 'package:omelo_user_app/features/discover/job_detail_screen.dart';
import 'package:omelo_user_app/features/discover/tracked_job_card.dart';
import 'package:omelo_user_app/features/identities/identity_editor_screen.dart';
import 'package:omelo_user_app/features/invitations/invitation_detail_screen.dart';
import 'package:omelo_user_app/features/invitations/invitations_screen.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeTimer implements Timer {
  _FakeTimer(this.after, this.run);
  final Duration after;
  final void Function() run;
  bool active = true;

  @override
  void cancel() => active = false;
  @override
  bool get isActive => active;
  @override
  int get tick => 0;
}

/// A tracker with a recording sender, a settable clock and manual timers.
class _Rig {
  _Rig({this.signedIn = true, int batchSize = 20}) {
    events = JobEvents(
      send: (batch) async {
        if (failNext > 0) {
          failNext--;
          throw Exception('offline');
        }
        sent.add(batch);
      },
      isSignedIn: () => signedIn,
      now: () => now,
      startTimer: (after, run) {
        final t = _FakeTimer(after, run);
        timers.add(t);
        return t;
      },
      batchSize: batchSize,
    );
  }

  late final JobEvents events;
  final sent = <List<Map<String, Object?>>>[];
  final timers = <_FakeTimer>[];
  bool signedIn;
  int failNext = 0;
  DateTime now = DateTime(2026, 9, 18, 10);

  List<_FakeTimer> get activeTimers =>
      timers.where((t) => t.active).toList();

  /// Fires the pending flush timer, as if 5 seconds passed.
  Future<void> tick() async {
    for (final t in activeTimers) {
      t.active = false;
      t.run();
    }
    await pumpEventQueue();
  }

  int get sentCount => sent.fold(0, (n, b) => n + b.length);
}

class _SignedInAuth implements AuthRepository {
  @override
  bool get isSignedIn => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeInvites implements InvitationsRepository {
  final viewed = <String>[];
  final declined = <Map<String, Object?>>[];
  final allow = <String, bool>{};

  @override
  Future<void> markViewed(String invitationId) async => viewed.add(invitationId);

  @override
  Future<void> decline(String invitationId, DeclineReason? reason,
          [String? otherText]) async =>
      declined.add(declinePayload(invitationId, reason, otherText));

  @override
  Future<void> setAllowInvitations(String identityId, bool allow) async =>
      this.allow[identityId] = allow;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoSavedJobs extends SavedJobIdsController {
  @override
  Future<Set<String>> build() async => {};
}

const _inviteId = '11111111-2222-4333-8444-555555555555';
const _jobId = '66666666-7777-4888-9999-000000000000';

Map<String, dynamic> inviteJson({
  String status = 'pending',
  String? applicationId,
  String? expiresAt = '2026-10-03T12:00:00Z',
  String? viewedAt,
  String? message = 'We liked your tandoor skills. Come and talk to us.',
  String? identityId = 'c',
  String? identityLabel = 'Cook',
}) =>
    {
      'id': _inviteId,
      'job_id': _jobId,
      'job_title': 'Tandoor cook',
      'job_status': 'published',
      'company_name': 'Hotel Sagar',
      'company_verified': true,
      'company_logo': null,
      'location_text': 'Pune',
      'work_type': 'full_time',
      'workplace_type': 'onsite',
      'pay_min': 18000,
      'pay_max': 24000,
      'pay_period': 'month',
      'pay_currency': 'INR',
      'message': message,
      'sent_at': '2026-09-17T09:00:00Z',
      'expires_at': expiresAt,
      'viewed_at': viewedAt,
      'work_identity_id': identityId,
      'identity_label': identityLabel,
      'application_id': applicationId,
      'status': status,
    };

JobInvitation invite({
  String status = 'pending',
  String? applicationId,
  String? expiresAt = '2026-10-03T12:00:00Z',
  String? viewedAt,
}) =>
    JobInvitation.fromJson(inviteJson(
        status: status,
        applicationId: applicationId,
        expiresAt: expiresAt,
        viewedAt: viewedAt));

WorkIdentity wi(String id, String label,
        {String? prof,
        bool primary = false,
        String status = 'active',
        IdentityVisibility visibility = IdentityVisibility.private}) =>
    WorkIdentity(
      id: id,
      label: label,
      professionId: prof,
      isPrimary: primary,
      status: status,
      visibility: visibility,
    );

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
        categorySlug: null,
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

void main() {
  // -------------------------------------------------------------------------
  group('job events: batching', () {
    test('queues, then sends after the flush timer (about 5 s)', () async {
      final r = _Rig();
      r.events.view('j1', JobSurface.recommended, rank: 2);
      r.events.click('j2', JobSurface.search);
      expect(r.sent, isEmpty);
      expect(r.activeTimers, hasLength(1),
          reason: 'one timer for the whole batch');
      expect(r.activeTimers.single.after, const Duration(seconds: 5));
      await r.tick();
      expect(r.sent, hasLength(1));
      expect(r.sent.single, [
        {'job_id': 'j1', 'event': 'view', 'surface': 'recommended', 'rank': 2},
        {'job_id': 'j2', 'event': 'click', 'surface': 'search'},
      ]);
      expect(r.events.pending, isEmpty);
    });

    test('sends at once when 20 events are waiting', () async {
      final r = _Rig();
      for (var i = 0; i < 19; i++) {
        r.events.impression('j$i', JobSurface.nearby, rank: i + 1);
      }
      await pumpEventQueue();
      expect(r.sent, isEmpty);
      r.events.impression('j19', JobSurface.nearby, rank: 20);
      await pumpEventQueue();
      expect(r.sent, hasLength(1));
      expect(r.sent.single, hasLength(20));
      expect(r.activeTimers, isEmpty, reason: 'the timer was cancelled');
    });

    test('a manual flush (pause / sign-out) sends everything, in calls of '
        'at most 100', () async {
      final r = _Rig(batchSize: 1000);
      for (var i = 0; i < 230; i++) {
        r.events.impression('j$i', JobSurface.nearby);
      }
      await r.events.flush();
      expect(r.sent.map((b) => b.length), [100, 100, 30]);
      expect(r.events.pending, isEmpty);
    });

    test('flushing with nothing waiting sends nothing', () async {
      final r = _Rig();
      await r.events.flush();
      expect(r.sent, isEmpty);
    });

    test('surfaces use the server names', () async {
      final r = _Rig();
      r.events.save('j1', JobSurface.jobPage);
      r.events.view('j2', JobSurface.fromWire('invitation'));
      r.events.view('j3', JobSurface.fromWire('nonsense'));
      await r.events.flush();
      expect(r.sent.single.map((e) => e['surface']),
          ['job_page', 'invitation', 'other']);
      expect(r.sent.single.first['event'], 'save');
      expect(r.sent.single.first.containsKey('rank'), isFalse);
    });

    test('jobRoute carries the surface and rank', () {
      expect(jobRoute('j1', JobSurface.recommended, rank: 3),
          '/job/j1?from=recommended&rank=3');
      expect(jobRoute('j1', JobSurface.jobPage), '/job/j1?from=job_page');
    });
  });

  group('job events: dedupe', () {
    test('an impression counts once per session per job and surface',
        () async {
      final r = _Rig();
      r.events.impression('j1', JobSurface.nearby, rank: 1);
      r.events.impression('j1', JobSurface.nearby, rank: 1);
      r.events.impression('j1', JobSurface.nearby, rank: 4);
      r.events.impression('j1', JobSurface.search, rank: 1); // other surface
      r.events.impression('j2', JobSurface.nearby, rank: 2);
      await r.events.flush();
      // Still once, even after the first one was sent.
      r.now = r.now.add(const Duration(hours: 3));
      r.events.impression('j1', JobSurface.nearby, rank: 1);
      await r.events.flush();
      expect(r.sentCount, 3);
    });

    test('a repeat view / click / save within 2 s is a double tap; later '
        'is kept (the server decides)', () async {
      final r = _Rig();
      expect(r.events.track(const JobEvent(
          jobId: 'j1', type: JobEventType.click, surface: JobSurface.nearby)),
          isTrue);
      r.now = r.now.add(const Duration(milliseconds: 800));
      expect(r.events.track(const JobEvent(
          jobId: 'j1', type: JobEventType.click, surface: JobSurface.nearby)),
          isFalse);
      // A different event or surface is not a repeat.
      expect(r.events.track(const JobEvent(
          jobId: 'j1', type: JobEventType.view, surface: JobSurface.nearby)),
          isTrue);
      r.now = r.now.add(const Duration(seconds: 3));
      expect(r.events.track(const JobEvent(
          jobId: 'j1', type: JobEventType.click, surface: JobSurface.nearby)),
          isTrue);
      await r.events.flush();
      expect(r.sentCount, 3);
    });

    test('reset (a different person signed in) forgets the session', () async {
      final r = _Rig();
      r.events.impression('j1', JobSurface.nearby);
      r.events.reset();
      expect(r.events.pending, isEmpty);
      expect(r.activeTimers, isEmpty);
      r.events.impression('j1', JobSurface.nearby);
      await r.events.flush();
      expect(r.sentCount, 1);
    });
  });

  group('job events: signed out and failures', () {
    test('nothing is queued while signed out', () async {
      final r = _Rig(signedIn: false);
      expect(r.events.track(const JobEvent(
          jobId: 'j1', type: JobEventType.view, surface: JobSurface.nearby)),
          isFalse);
      await r.events.flush();
      expect(r.sent, isEmpty);
      expect(r.timers, isEmpty);
    });

    test('events waiting at sign-out are dropped, never sent later', () async {
      final r = _Rig();
      r.events.view('j1', JobSurface.nearby);
      r.signedIn = false;
      await r.tick();
      expect(r.sent, isEmpty);
      expect(r.events.pending, isEmpty);
    });

    test('a failed send is retried once, then dropped; it never throws',
        () async {
      final r = _Rig();
      r.events.view('j1', JobSurface.nearby);
      r.failNext = 1;
      await r.events.flush(); // fails, re-queued
      expect(r.events.pending, hasLength(1));
      expect(r.activeTimers, hasLength(1), reason: 'retry is scheduled');
      await r.tick(); // succeeds
      expect(r.sentCount, 1);

      r.events.view('j2', JobSurface.search);
      r.failNext = 2;
      await r.events.flush(); // fails
      await r.events.flush(); // fails again: dropped
      expect(r.events.pending, isEmpty);
      expect(r.sentCount, 1);
    });

    test('a sender that throws synchronously cannot break the caller',
        () async {
      final events = JobEvents(
        send: (_) => throw StateError('no client'),
        isSignedIn: () => true,
        startTimer: (d, run) => _FakeTimer(d, run),
      );
      events.view('j1', JobSurface.nearby);
      await events.flush();
      await events.flush();
      expect(events.pending, isEmpty);
    });

    test('a tracker whose sign-in check throws accepts nothing', () {
      final events = JobEvents(
        send: (_) async {},
        isSignedIn: () => throw StateError('Supabase not ready'),
      );
      expect(events.track(const JobEvent(
          jobId: 'j1', type: JobEventType.view, surface: JobSurface.nearby)),
          isFalse);
    });
  });

  // -------------------------------------------------------------------------
  group('invitations: status → label and actions', () {
    test('every status has a plain label', () {
      expect(invitationStatusLabel(InvitationStatus.pending), 'Waiting for you');
      expect(invitationStatusLabel(InvitationStatus.applied), 'You applied');
      expect(invitationStatusLabel(InvitationStatus.declined), 'Not interested');
      expect(invitationStatusLabel(InvitationStatus.withdrawn), 'Withdrawn');
      expect(invitationStatusLabel(InvitationStatus.expired), 'Expired');
      expect(invitationStatusLabel(InvitationStatus.closed), 'Job closed');
      expect(InvitationStatus.fromWire('something_new'),
          InvitationStatus.closed);
    });

    test('pending: apply or not interested', () {
      final a = invitationActions(invite());
      expect(a.canApply, isTrue);
      expect(a.canDecline, isTrue);
      expect(a.canViewApplication, isFalse);
      expect(a.note, isNull);
    });

    test('applied: view the application', () {
      final a = invitationActions(invite(status: 'applied', applicationId: 'a1'));
      expect(a.canApply, isFalse);
      expect(a.canDecline, isFalse);
      expect(a.canViewApplication, isTrue);
      // Applied but the application is gone: nothing to open.
      expect(invitationActions(invite(status: 'applied')).hasAnyAction, isFalse);
    });

    test('pending with an application already: view it', () {
      final a = invitationActions(invite(applicationId: 'a1'));
      expect(a.canApply, isFalse);
      expect(a.canViewApplication, isTrue);
    });

    for (final s in ['declined', 'withdrawn', 'expired', 'closed']) {
      test('$s: explained, no actions', () {
        final a = invitationActions(invite(status: s));
        expect(a.hasAnyAction, isFalse);
        expect(a.note, isNotEmpty);
      });
    }

    test('parse, sort pending first, count, home title', () {
      final list = parseInvitations([
        inviteJson(status: 'declined')..['id'] = 'a'..['sent_at'] =
            '2026-09-18T09:00:00Z',
        inviteJson()..['id'] = 'b',
        {'no': 'id'},
        'junk',
      ]);
      expect(list.map((i) => i.id), ['a', 'b']);
      expect(sortInvitations(list).map((i) => i.id), ['b', 'a']);
      expect(pendingInvitationCount(list), 1);
      expect(invitedYouTitle(1), '1 employer invited you to apply');
      expect(invitedYouTitle(2), '2 employers invited you to apply');
      final b = list[1];
      expect(b.companyVerified, isTrue);
      expect(b.payMin, 18000);
      expect(b.isNew, isTrue);
      expect(invitedAsLine(b), 'Invited as your Cook profile');
      expect(invitedAsLine(JobInvitation.fromJson(
              inviteJson(identityLabel: null))),
          'Invited to apply');
    });

    test('apply route preselects the invited identity', () {
      expect(invitationApplyRoute(invite()),
          '/apply/$_jobId?identity=c&from=invitation');
    });
  });

  group('invitations: expiry', () {
    final now = DateTime(2026, 9, 18, 15);
    test('answer by a date', () {
      expect(answerByLabel(DateTime(2026, 10, 3, 18), now), 'Answer by 3 Oct');
      expect(answerByLabel(DateTime(2027, 1, 2), now), 'Answer by 2 Jan 2027');
    });
    test('today and tomorrow', () {
      expect(answerByLabel(DateTime(2026, 9, 18, 23), now), 'Answer by today');
      expect(answerByLabel(DateTime(2026, 9, 19, 1), now),
          'Answer by tomorrow');
    });
    test('only pending and expired invitations show a date', () {
      final exp = JobInvitation.fromJson(
          inviteJson(expiresAt: '2026-09-10T10:00:00')); // local time
      expect(expiryLabel(exp, now), 'Answer by today');
      final ended = JobInvitation.fromJson(inviteJson(
          status: 'expired', expiresAt: '2026-09-10T10:00:00'));
      expect(expiryLabel(ended, now), 'Ended on 10 Sep');
      expect(expiryLabel(invite(status: 'applied'), now), isNull);
      expect(expiryLabel(invite(expiresAt: null), now), isNull);
    });
  });

  group('invitations: decline reason', () {
    test('no reason sends null', () {
      expect(declinePayload('i1', null),
          {'p_invitation': 'i1', 'p_reason': null});
    });
    test('a chip sends its label', () {
      expect(declinePayload('i1', DeclineReason.tooFar)['p_reason'], 'Too far');
      expect(declineReasonText(DeclineReason.payTooLow), 'Pay too low');
      expect(declineReasonText(DeclineReason.notLooking), 'Not looking now');
      // Typed text is ignored unless "Other" is chosen.
      expect(declineReasonText(DeclineReason.tooFar, 'ignored'), 'Too far');
    });
    test('"Other" sends the typed text, tidied and capped at 300', () {
      expect(declineReasonText(DeclineReason.other, '  Found   a job  '),
          'Found a job');
      expect(declineReasonText(DeclineReason.other, '   '), 'Other');
      expect(declineReasonText(DeclineReason.other), 'Other');
      final long = declineReasonText(DeclineReason.other, 'x' * 400)!;
      expect(long.length, 300);
    });
  });

  group('who viewed me', () {
    test('grouped by company, newest first, with identity and count', () {
      final rows = parseProfileViews([
        {
          'company_name': 'Hotel Sagar',
          'company_verified': true,
          'identity_label': 'Cook',
          'views': 2,
          'last_viewed_at': '2026-09-15T10:00:00Z',
        },
        {
          'company_name': 'Swift Couriers',
          'company_verified': false,
          'identity_label': 'Delivery Driver',
          'views': 1,
          'last_viewed_at': '2026-09-17T10:00:00Z',
        },
        {
          'company_name': 'Hotel Sagar',
          'company_verified': true,
          'identity_label': null,
          'views': 1,
          'last_viewed_at': '2026-09-16T10:00:00Z',
        },
      ]);
      final groups = groupProfileViews(rows);
      expect(groups.map((g) => g.companyName),
          ['Swift Couriers', 'Hotel Sagar']);
      expect(groups[1].entries.map(viewedLine),
          ['Your profile', 'Your Cook profile · 2 times']);
      expect(groups[1].totalViews, 3);
      final now = DateTime(2026, 9, 18, 12);
      expect(viewedWhen(DateTime(2026, 9, 18, 8), now), 'Today');
      expect(viewedWhen(DateTime(2026, 9, 17, 23), now), 'Yesterday');
      expect(viewedWhen(DateTime(2026, 9, 14), now), '4 days ago');
      expect(viewedWhen(DateTime(2026, 9, 1), now), '1 Sep');
    });
  });

  group('deeplinks', () {
    test('invitation notifications open the invitation', () {
      expect(workerDeeplink('/invitations/$_inviteId'),
          '/invitations/$_inviteId');
      expect(workerDeeplink('https://omelo.app/invitations/$_inviteId'),
          '/invitations/$_inviteId');
      expect(workerDeeplink('/invitations'), '/invitations');
      expect(workerDeeplink('/invitations/nope'), isNull);
      expect(workerDeeplink('/job/$_jobId'), '/job/$_jobId?from=notification');
      expect(
          AppNotification(
            id: 'n',
            type: 'job_invitation',
            title: 'Hotel Sagar invited you to apply',
            createdAt: DateTime(2026, 9, 18),
            entityType: 'candidate_invitation',
            entityId: _inviteId,
          ).target,
          '/invitations/$_inviteId');
      expect(notificationKind('job_invitation'), NotificationKind.invitation);
    });
  });

  group('apply identity', () {
    final driver = wi('d', 'Delivery Driver', prof: 'p-driver', primary: true);
    final cook = wi('c', 'Cook', prof: 'p-cook');
    final nurse = wi('n', 'Nurse', prof: 'p-nurse', status: 'archived');

    test('the invited identity is the default', () {
      expect(
          pickApplyIdentity([driver, cook],
                  invitedId: 'd', jobProfessionId: 'p-cook')
              ?.id,
          'd');
    });
    test('a tap beats the invitation', () {
      expect(
          pickApplyIdentity([driver, cook], pickedId: 'c', invitedId: 'd')?.id,
          'c');
    });
    test('an archived or unknown invited identity falls back', () {
      expect(
          pickApplyIdentity([driver, cook, nurse],
                  invitedId: 'n', jobProfessionId: 'p-cook')
              ?.id,
          'c');
      expect(pickApplyIdentity([driver, cook], invitedId: 'zzz')?.id, 'd');
    });
    test('invitations need visibility', () {
      expect(invitationsPossible(IdentityVisibility.private), isFalse);
      for (final v in IdentityVisibility.values.skip(1)) {
        expect(invitationsPossible(v), isTrue);
      }
    });
  });

  // -------------------------------------------------------------------------
  group('screens', () {
    late _Rig rig;
    late _FakeInvites invites;

    setUp(() {
      rig = _Rig();
      invites = _FakeInvites();
    });

    Future<void> pumpAt(WidgetTester tester, Size size, Widget screen,
        List<Override> overrides, String location) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          isSignedInProvider.overrideWithValue(true),
          jobEventsProvider.overrideWithValue(rig.events),
          invitationsRepositoryProvider.overrideWithValue(invites),
          ...overrides,
        ],
        child: MaterialApp.router(
          theme: OmeloTheme.light(),
          routerConfig: GoRouter(
            initialLocation: location,
            routes: [
              GoRoute(path: location, builder: (_, __) => screen),
              GoRoute(
                  path: '/identities',
                  builder: (_, __) => const Text('identities hub')),
              GoRoute(
                  path: '/job/:id',
                  builder: (_, s) => Text('job page ${s.uri}')),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    for (final size in const [Size(320, 1800), Size(1400, 1200)]) {
      testWidgets(
          'invitation detail (pending) at ${size.width.toInt()}px: '
          'details, actions, marked viewed', (tester) async {
        await pumpAt(
          tester,
          size,
          const InvitationDetailScreen(invitationId: _inviteId),
          [myInvitationsProvider.overrideWith((_) async => [invite()])],
          '/invitations/$_inviteId',
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Hotel Sagar'), findsOneWidget);
        expect(find.text('Verified'), findsOneWidget);
        expect(find.text('Tandoor cook'), findsOneWidget);
        expect(find.textContaining('18,000'), findsOneWidget);
        expect(find.text('Invited as your Cook profile'), findsOneWidget);
        expect(find.text('Answer by 3 Oct'), findsOneWidget);
        expect(find.textContaining('tandoor skills'), findsOneWidget);
        expect(find.text('Apply now'), findsOneWidget);
        expect(find.text('Not interested'), findsOneWidget);
        expect(invites.viewed, [_inviteId]);
        expect(rig.events.pending.single.toJson(), {
          'job_id': _jobId,
          'event': 'impression',
          'surface': 'invitation',
        });
      });
    }

    testWidgets('already viewed is not marked again', (tester) async {
      await pumpAt(
        tester,
        const Size(400, 1600),
        const InvitationDetailScreen(invitationId: _inviteId),
        [
          myInvitationsProvider.overrideWith(
              (_) async => [invite(viewedAt: '2026-09-17T10:00:00Z')]),
        ],
        '/invitations/$_inviteId',
      );
      expect(invites.viewed, isEmpty);
    });

    testWidgets('not interested: reason chips, then declined', (tester) async {
      await pumpAt(
        tester,
        const Size(400, 1600),
        const InvitationDetailScreen(invitationId: _inviteId),
        [myInvitationsProvider.overrideWith((_) async => [invite()])],
        '/invitations/$_inviteId',
      );
      await tester.tap(find.text('Not interested'));
      await tester.pumpAndSettle();
      for (final r in DeclineReason.values) {
        expect(find.text(r.label), findsOneWidget);
      }
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), ' Moving to Mumbai ');
      await tester.tap(find.text('Send: not interested'));
      await tester.pumpAndSettle();
      expect(invites.declined, [
        {'p_invitation': _inviteId, 'p_reason': 'Moving to Mumbai'}
      ]);
      expect(find.text('Apply now'), findsNothing);
      expect(find.textContaining('not interested. The employer'), findsOneWidget);
    });

    testWidgets('expired: explained, no actions', (tester) async {
      await pumpAt(
        tester,
        const Size(360, 1600),
        const InvitationDetailScreen(invitationId: _inviteId),
        [
          myInvitationsProvider
              .overrideWith((_) async => [invite(status: 'expired')]),
        ],
        '/invitations/$_inviteId',
      );
      expect(find.text('Apply now'), findsNothing);
      expect(find.text('Not interested'), findsNothing);
      expect(find.text('Expired'), findsOneWidget);
      expect(find.textContaining('ended before you answered'), findsOneWidget);
    });

    testWidgets('applied: view application', (tester) async {
      await pumpAt(
        tester,
        const Size(360, 1600),
        const InvitationDetailScreen(invitationId: _inviteId),
        [
          myInvitationsProvider.overrideWith((_) async =>
              [invite(status: 'applied', applicationId: 'a1')]),
        ],
        '/invitations/$_inviteId',
      );
      expect(find.text('View application'), findsOneWidget);
      expect(find.text('Apply now'), findsNothing);
    });

    testWidgets('unknown invitation says so', (tester) async {
      await pumpAt(
        tester,
        const Size(360, 1600),
        const InvitationDetailScreen(invitationId: 'other'),
        [myInvitationsProvider.overrideWith((_) async => [invite()])],
        '/invitations/other',
      );
      expect(find.textContaining('was not found'), findsOneWidget);
    });

    for (final size in const [Size(320, 1600), Size(1400, 1200)]) {
      testWidgets('invitations list at ${size.width.toInt()}px',
          (tester) async {
        await pumpAt(
          tester,
          size,
          const InvitationsScreen(),
          [
            myInvitationsProvider.overrideWith((_) async => [
                  invite(),
                  JobInvitation.fromJson(inviteJson(status: 'declined')
                    ..['id'] = 'x'
                    ..['job_title'] = 'Night cook'),
                ]),
          ],
          '/invitations',
        );
        expect(tester.takeException(), isNull);
        expect(find.text('1 invitation is waiting for your answer.'),
            findsOneWidget);
        expect(find.text('Waiting for you'), findsOneWidget);
        expect(find.text('Not interested'), findsOneWidget);
        expect(find.text('Night cook'), findsOneWidget);
      });
    }

    testWidgets('invitations empty state explains how to get invited',
        (tester) async {
      await pumpAt(
        tester,
        const Size(360, 1400),
        const InvitationsScreen(),
        [myInvitationsProvider.overrideWith((_) async => const [])],
        '/invitations',
      );
      expect(find.text('No invitations yet'), findsOneWidget);
      expect(find.textContaining('Make an identity visible to employers'),
          findsOneWidget);
      await tester.tap(find.text('Choose who can see me'));
      await tester.pumpAndSettle();
      expect(find.text('identities hub'), findsOneWidget);
    });

    for (final size in const [Size(360, 900), Size(1400, 900)]) {
      testWidgets(
          'job page at ${size.width.toInt()}px: records the view with its '
          'surface; body and apply bar both show', (tester) async {
        await pumpAt(
          tester,
          size,
          const JobDetailScreen(
              jobId: 'j1', surface: JobSurface.recommended, rank: 3),
          [
            authRepositoryProvider.overrideWithValue(_SignedInAuth()),
            jobDetailProvider.overrideWith((_, __) async => cookJob()),
            myMatchProvider.overrideWith((_, __) async => null),
            hasAppliedProvider.overrideWith((_, __) async => false),
            savedJobIdsProvider.overrideWith(_NoSavedJobs.new),
          ],
          '/job/j1',
        );
        expect(tester.takeException(), isNull);
        expect(find.text('Tandoor cook'), findsOneWidget);
        expect(find.text('Apply — no resume needed'), findsOneWidget);
        expect(find.byTooltip('Save job'), findsOneWidget);
        expect(rig.events.pending.single.toJson(), {
          'job_id': 'j1',
          'event': 'view',
          'surface': 'recommended',
          'rank': 3,
        });
      });
    }

    testWidgets('job list: impressions only for cards really on screen, '
        'with rank; tap records a click', (tester) async {
      Job job(int n) {
        final j = cookJob().job;
        return Job(
          id: 'job$n',
          title: 'Job number $n',
          companyId: j.companyId,
          companyName: j.companyName,
          companySlug: null,
          companyVerified: true,
          companyResponseHours: null,
          distanceKm: 2,
          locationText: 'Pune',
          payMin: 18000,
          payMax: null,
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
          categorySlug: null,
          professionName: null,
          benefits: const [],
          publishedAt: null,
        );
      }

      await pumpAt(
        tester,
        const Size(400, 800),
        Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 20; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TrackedJobCard(
                      job: job(i + 1), surface: JobSurface.nearby, rank: i + 1),
                ),
            ],
          ),
        ),
        [savedJobIdsProvider.overrideWith(_NoSavedJobs.new)],
        '/list',
      );
      List<String> seen() => [
            for (final e in rig.events.pending)
              if (e.type == JobEventType.impression) e.jobId
          ];
      final first = seen();
      expect(first, isNotEmpty);
      expect(first.length, lessThan(10), reason: 'not the whole list');
      expect(first.first, 'job1');
      expect(rig.events.pending.first.rank, 1);

      await tester.drag(find.byType(ListView), const Offset(0, -2500));
      await tester.pumpAndSettle();
      final after = seen();
      expect(after.length, greaterThan(first.length));
      expect(after.toSet().length, after.length, reason: 'no repeats');

      // Scrolling back does not count them again.
      await tester.drag(find.byType(ListView), const Offset(0, 2500));
      await tester.pumpAndSettle();
      expect(seen().length, after.length);

      await tester.tap(find.text('Job number 1'));
      await tester.pump();
      final click = rig.events.pending.last;
      expect(click.type, JobEventType.click);
      expect(click.toJson(),
          {'job_id': 'job1', 'event': 'click', 'surface': 'nearby', 'rank': 1});
      await tester.pumpAndSettle();
      expect(find.text('job page /job/job1?from=nearby&rank=1'), findsOneWidget);
    });

    testWidgets('apply from an invitation starts on the invited identity',
        (tester) async {
      await pumpAt(
        tester,
        const Size(360, 2400),
        const ApplyScreen(jobId: 'j1', identityId: 'd'),
        [
          authRepositoryProvider.overrideWithValue(_SignedInAuth()),
          jobDetailProvider.overrideWith((_, __) async => cookJob()),
          myIdentitiesProvider.overrideWith((_) async => [
                wi('d', 'Delivery Driver', prof: 'p-driver', primary: true),
                wi('c', 'Cook', prof: 'p-cook'),
              ]),
        ],
        '/apply/j1',
      );
      // The job is a cook job, but the employer invited the driver profile.
      expect(find.text('Employers will see your Delivery Driver profile only'),
          findsOneWidget);
      await tester.tap(find.text('Cook'));
      await tester.pump();
      expect(find.text('Employers will see your Cook profile only'),
          findsOneWidget);
    });

    IdentityProfile profileWith(IdentityVisibility v) =>
        IdentityProfile.fromJson({
          'identity': {
            'id': 'c',
            'label': 'Cook',
            'is_primary': true,
            'status': 'active',
            'discoverability': v.wire,
          },
          'completeness': {'score': 80, 'missing': []},
          'fields': [],
        });

    List<Override> editorOverrides(IdentityVisibility v, {bool allow = true}) =>
        [
          identityProfileProvider.overrideWith((_, __) async => profileWith(v)),
          identitySkillsProvider.overrideWith((_, __) async => const []),
          identityExperiencesProvider.overrideWith((_, __) async => const []),
          identityPreferencesProvider
              .overrideWith((_, __) async => const WorkPreferences()),
          identityPlacesProvider.overrideWith((_, __) async => const []),
          identityEvidenceProvider
              .overrideWith((_, __) async => const IdentityEvidence()),
          allowInvitationsProvider.overrideWith((_, __) async => allow),
        ];

    testWidgets('editor: invitations switch shown when visible, saves',
        (tester) async {
      await pumpAt(
        tester,
        const Size(400, 5000),
        const IdentityEditorScreen(identityId: 'c'),
        editorOverrides(IdentityVisibility.discoverable, allow: false),
        '/identities/c',
      );
      expect(tester.takeException(), isNull);
      final tile = find.widgetWithText(
          SwitchListTile, 'Let employers invite me to apply');
      expect(tile, findsOneWidget);
      expect(tester.widget<SwitchListTile>(tile).value, isFalse);
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
      expect(invites.allow, {'c': true});
      expect(tester.widget<SwitchListTile>(tile).value, isTrue);
    });

    testWidgets('editor: private identity explains invitations need '
        'visibility', (tester) async {
      await pumpAt(
        tester,
        const Size(400, 5000),
        const IdentityEditorScreen(identityId: 'c'),
        editorOverrides(IdentityVisibility.private),
        '/identities/c',
      );
      expect(find.text('Let employers invite me to apply'), findsNothing);
      expect(find.textContaining('Invitations to apply: off while'),
          findsOneWidget);
    });
  });
}
