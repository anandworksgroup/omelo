import 'package:flutter_test/flutter_test.dart';
import 'package:omelo_user_app/data/hiring.dart';

void main() {
  final now = DateTime(2026, 9, 17, 10, 0);

  ApplicationSummary app(
    String state, {
    DateTime? viewedAt,
    List<Interview> interviews = const [],
    List<Offer> offers = const [],
  }) =>
      ApplicationSummary(
        id: 'a1',
        jobId: 'j1',
        jobTitle: 'Delivery driver',
        companyName: 'Fresh Mart',
        state: state,
        appliedAt: now.subtract(const Duration(days: 5)),
        firstViewedAt: viewedAt,
        interviews: interviews,
        offers: offers,
      );

  Interview round(int n, String status, {String? name, DateTime? at}) =>
      Interview(
        id: 'i$n-$status',
        applicationId: 'a1',
        type: 'video',
        status: status,
        round: n,
        roundName: name,
        meetingMode: 'omelo_meet',
        scheduledAt: at ?? DateTime(2026, 9, 18, 11, 0),
        durationMinutes: 30,
      );

  const planned = [
    PlannedRound(position: 1, name: 'Technical Interview'),
    PlannedRound(position: 2, name: 'Hiring Manager'),
  ];

  String render(List<ProcessStep> steps) => steps
      .map((s) => '${switch (s.state) {
            ProcessStepState.done => '✓',
            ProcessStepState.current => '●',
            ProcessStepState.upcoming => '○',
            ProcessStepState.skipped => '–',
            ProcessStepState.closed => '✕',
          }} ${s.label}')
      .join(' · ');

  int currentCount(List<ProcessStep> s) =>
      s.where((x) => x.state == ProcessStepState.current).length;

  test('just applied: waiting for the employer to view', () {
    final s = HiringProcess.steps(app('applied'),
        plannedRounds: planned, now: now);
    expect(render(s),
        '✓ Applied · ● Employer viewed · ○ Shortlisted · '
        '○ Technical Interview · ○ Hiring Manager · ○ Offer · ○ Hired');
  });

  test('shortlisted with no interview planned stays at Shortlisted', () {
    final s = HiringProcess.steps(app('shortlisted', viewedAt: now), now: now);
    expect(render(s),
        '✓ Applied · ✓ Employer viewed · ● Shortlisted · ○ Offer · ○ Hired');
  });

  test('round 1 booked is current; planned round 2 is upcoming', () {
    final s = HiringProcess.steps(
      app('interview', interviews: [round(1, 'scheduled', name: 'Technical Interview')]),
      plannedRounds: planned,
      now: now,
    );
    expect(render(s),
        '✓ Applied · ✓ Employer viewed · ✓ Shortlisted · '
        '● Technical Interview · ○ Hiring Manager · ○ Offer · ○ Hired');
    expect(s[3].detail, 'Fri 18 Sep, 11:00 AM');
    expect(s[4].detail, HiringProcess.notScheduled);
    expect(currentCount(s), 1);
  });

  test('round 1 done, round 2 not booked yet: round 2 is next', () {
    final s = HiringProcess.steps(
      app('interview', interviews: [round(1, 'completed', name: 'Technical Interview')]),
      plannedRounds: planned,
      now: now,
    );
    expect(render(s),
        '✓ Applied · ✓ Employer viewed · ✓ Shortlisted · '
        '✓ Technical Interview · ● Hiring Manager · ○ Offer · ○ Hired');
  });

  test('all rounds done: final review', () {
    final s = HiringProcess.steps(
      app('interview', interviews: [
        round(1, 'completed', name: 'Technical Interview'),
        round(2, 'completed', name: 'Hiring Manager'),
      ]),
      plannedRounds: planned,
      now: now,
    );
    expect(render(s),
        '✓ Applied · ✓ Employer viewed · ✓ Shortlisted · '
        '✓ Technical Interview · ✓ Hiring Manager · ● Offer · ○ Hired');
    expect(s[5].detail, HiringProcess.finalReview);
  });

  test('without planned rounds, scheduled interviews still make steps', () {
    final s = HiringProcess.steps(
      app('interview', interviews: [round(1, 'completed'), round(2, 'scheduled')]),
      now: now,
    );
    expect(render(s),
        '✓ Applied · ✓ Employer viewed · ✓ Shortlisted · '
        '✓ Interview round 1 · ● Interview round 2 · ○ Offer · ○ Hired');
  });

  test('a cancelled round booked again shows the new booking', () {
    final s = HiringProcess.steps(
      app('interview', interviews: [
        round(1, 'cancelled', at: DateTime(2026, 9, 16, 10)),
        round(1, 'rescheduled', name: 'Technical Interview'),
      ]),
      now: now,
    );
    expect(s[3].state, ProcessStepState.current);
  });

  test('offer stage: offer is current', () {
    final s = HiringProcess.steps(
      app('offer', interviews: [round(1, 'completed')]),
      now: now,
    );
    expect(render(s).endsWith('● Offer · ○ Hired'), isTrue);
    expect(currentCount(s), 1);
  });

  test('hired: everything done, nothing current', () {
    final s = HiringProcess.steps(
      app('hired', interviews: [round(1, 'completed')]),
      plannedRounds: planned,
      now: now,
    );
    expect(s.every((x) => x.state != ProcessStepState.current), isTrue);
    expect(s.last.state, ProcessStepState.done);
    expect(s[s.length - 2].state, ProcessStepState.done);
  });

  test('rejected after an interview ends with a closed step', () {
    final s = HiringProcess.steps(
      app('rejected', interviews: [round(1, 'completed')]),
      events: [
        ApplicationEvent(
            eventType: 'stage_changed', actorType: 'recruiter', toState: 'viewed'),
      ],
      now: now,
    );
    expect(render(s),
        '✓ Applied · ✓ Employer viewed · ✓ Shortlisted · '
        '✓ Interview round 1 · ✕ Not selected');
    expect(currentCount(s), 0);
  });

  test('missed round is marked, not done', () {
    final s = HiringProcess.steps(
      app('interview', interviews: [round(1, 'no_show_candidate')]),
      now: now,
    );
    expect(s[3].state, ProcessStepState.skipped);
    expect(s[3].detail, 'Missed');
    expect(currentCount(s), 1);
  });
}
