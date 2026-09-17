import 'package:flutter_test/flutter_test.dart';
import 'package:omelo_user_app/data/hiring.dart';

void main() {
  final now = DateTime(2026, 9, 17, 10, 0);

  ApplicationSummary app(
    String state, {
    String company = 'Fresh Mart',
    String? rejectionReason,
    List<Interview> interviews = const [],
    List<Offer> offers = const [],
  }) =>
      ApplicationSummary(
        id: 'a1',
        jobId: 'j1',
        jobTitle: 'Delivery driver',
        companyName: company,
        state: state,
        appliedAt: now.subtract(const Duration(days: 2)),
        lastActivityAt: now.subtract(const Duration(days: 1)),
        rejectionReason: rejectionReason,
        interviews: interviews,
        offers: offers,
      );

  Interview interview({DateTime? at, DateTime? confirmedAt, String status = 'scheduled'}) =>
      Interview(
        id: 'i1',
        applicationId: 'a1',
        type: 'in_person',
        status: status,
        scheduledAt: at ?? DateTime(2026, 9, 20, 15, 30),
        durationMinutes: 30,
        candidateConfirmedAt: confirmedAt,
      );

  Offer offer({String status = 'sent', DateTime? expires, DateTime? start}) => Offer(
        id: 'o1',
        applicationId: 'a1',
        status: status,
        payAmount: 18000,
        payPeriod: 'month',
        payCurrency: 'INR',
        startDate: start,
        expiresAt: expires,
        sentAt: now.subtract(const Duration(hours: 3)),
      );

  group('next step — the worker never wonders what happened', () {
    test('applied waits for the company to view', () {
      final s = HiringCopy.nextStep(app('applied'), now);
      expect(s.text, 'Next: waiting for Fresh Mart to view');
      expect(s.needsAction, isFalse);
    });

    test('viewed says the company is reviewing', () {
      expect(HiringCopy.nextStep(app('viewed'), now).text,
          'Next: Fresh Mart is reviewing');
    });

    test('shortlisted, screening and assessment say they may contact you', () {
      for (final st in ['shortlisted', 'screening', 'assessment']) {
        expect(HiringCopy.nextStep(app(st), now).text,
            'Next: Fresh Mart may contact you');
      }
    });

    test('missing company name never renders an empty gap', () {
      expect(HiringCopy.nextStep(app('applied', company: ''), now).text,
          'Next: waiting for the employer to view');
    });

    test('unconfirmed upcoming interview needs action', () {
      final s = HiringCopy.nextStep(
          app('interview', interviews: [interview()]), now);
      expect(s.text, 'Next: confirm your interview on Sun 20 Sep');
      expect(s.needsAction, isTrue);
    });

    test('confirmed interview says when to attend', () {
      final s = HiringCopy.nextStep(
          app('interview', interviews: [interview(confirmedAt: now)]), now);
      expect(s.text, 'Next: attend interview Sun 20 Sep, 3:30 PM');
      expect(s.needsAction, isFalse);
    });

    test('past or cancelled interviews do not ask for confirmation', () {
      final past = interview(at: DateTime(2026, 9, 10, 9));
      final cancelled = interview(status: 'cancelled');
      final s = HiringCopy.nextStep(
          app('interview', interviews: [past, cancelled]), now);
      expect(s.needsAction, isFalse);
    });

    test('open offer asks for a response by the expiry date', () {
      final s = HiringCopy.nextStep(
          app('offer', offers: [offer(expires: DateTime(2026, 9, 24, 18))]),
          now);
      expect(s.text, 'Next: respond to your offer by Thu 24 Sep');
      expect(s.needsAction, isTrue);
    });

    test('expired offer is not an action', () {
      final s = HiringCopy.nextStep(
          app('offer', offers: [offer(expires: DateTime(2026, 9, 16))]), now);
      expect(s.needsAction, isFalse);
      expect(s.text, 'Your offer has expired.');
    });

    test('hired shows start date and verified history', () {
      final s = HiringCopy.nextStep(
          app('hired',
              offers: [offer(status: 'accepted', start: DateTime(2026, 10, 1))]),
          now);
      expect(s.text,
          'Hired — starts Thu 1 Oct. Added to your verified work history.');
      expect(s.tone, StepTone.good);
    });

    test('rejected shows the reason, or says none was given', () {
      expect(
          HiringCopy.nextStep(
                  app('rejected', rejectionReason: 'Role filled'), now)
              .text,
          'Not moving forward: Role filled');
      expect(HiringCopy.nextStep(app('rejected'), now).text,
          'Not moving forward. Fresh Mart did not give a reason.');
    });

    test('withdrawn and declined are plain closed text', () {
      expect(HiringCopy.nextStep(app('withdrawn'), now).tone, StepTone.closed);
      expect(HiringCopy.nextStep(app('declined_by_candidate'), now).text,
          'You turned down this offer.');
    });
  });

  test('sections put action first and closed last', () {
    final s = HiringCopy.sections([
      app('applied'),
      app('interview', interviews: [interview()]),
      app('hired'),
      app('rejected'),
    ], now);
    expect(s.needsAction.single.state, 'interview');
    expect(s.active.single.state, 'applied');
    expect(s.hired.single.state, 'hired');
    expect(s.closed.single.state, 'rejected');
  });

  test('status labels are plain words', () {
    expect(HiringCopy.statusLabel('declined_by_candidate'), 'You declined');
    expect(HiringCopy.statusLabel('rejected'), 'Not selected');
  });

  group('timeline events from the worker side', () {
    ApplicationEvent ev(String type,
            {String actor = 'recruiter',
            String? to,
            String? reason,
            Map<String, dynamic> meta = const {}}) =>
        ApplicationEvent(
            eventType: type,
            actorType: actor,
            toState: to,
            reason: reason,
            metadata: meta);

    String? title(ApplicationEvent e) => HiringCopy.event(e, 'Fresh Mart')?.title;

    test('covers the main path', () {
      expect(title(ev('created', actor: 'candidate')), 'You applied');
      expect(title(ev('viewed')), 'Fresh Mart viewed your application');
      expect(title(ev('shortlisted')), 'You were shortlisted');
      expect(title(ev('interview_scheduled')), 'Interview scheduled');
      expect(title(ev('interview_scheduled', meta: {'confirmed': true})),
          'You confirmed the interview');
      expect(title(ev('offer_extended')), 'Offer received');
      expect(title(ev('offer_responded', meta: {'status': 'accepted'})),
          'You accepted the offer');
      expect(title(ev('decision_made', to: 'hired')), 'Hired');
      expect(title(ev('decision_made', to: 'rejected', reason: 'Role filled')),
          'Not moving forward — Role filled');
    });

    test('duplicate decline decision is skipped', () {
      expect(HiringCopy.event(ev('decision_made', to: 'declined_by_candidate'), 'X'),
          isNull);
    });
  });

  group('match explanations', () {
    final m = MatchResult.fromJson({
      'score': 72,
      'eligible': true,
      'gate_failures': [],
      'strengths': [
        {'factor': 'licence_coverage', 'weight': 0.2, 'text': 'No licence required'},
        {'factor': 'distance_fit', 'weight': 0.1, 'text': '3 km away'},
        {'factor': 'profession_fit', 'weight': 0.3, 'text': 'Same profession: Driver'},
      ],
      'gaps': [],
      'unknowns': [
        {'factor': 'shift_fit', 'weight': 0.05, 'text': 'Shift preference not set'},
        {'factor': 'pay_fit', 'weight': 0.1, 'text': 'Pay not shown on the job'},
      ],
      'missing_skills': [],
    });

    test('strengths are ordered by weight and skip vacuous ones', () {
      expect(HiringCopy.topStrengths(m).map((s) => s.text).toList(),
          ['Same profession: Driver', '3 km away']);
    });

    test('unknowns become tips the worker can act on', () {
      expect(HiringCopy.tips(m),
          ['Add your shift preference to improve matches']);
    });

    test('tolerates a missing or malformed payload', () {
      final empty = MatchResult.fromJson(null);
      expect(empty.score, 0);
      expect(empty.strengths, isEmpty);
    });
  });
}
