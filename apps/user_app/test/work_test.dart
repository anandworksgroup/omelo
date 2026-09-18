import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omelo_user_app/core/app_state.dart';
import 'package:omelo_user_app/core/router.dart' show workRoutes;
import 'package:omelo_user_app/core/theme.dart';
import 'package:omelo_user_app/data/identity_repository.dart';
import 'package:omelo_user_app/data/messaging.dart';
import 'package:omelo_user_app/data/work_repository.dart';
import 'package:omelo_user_app/features/identities/availability_block.dart';
import 'package:omelo_user_app/features/work/assignment_detail_screen.dart';
import 'package:omelo_user_app/features/work/assignments_screen.dart';
import 'package:omelo_user_app/features/work/earnings_screen.dart';
import 'package:omelo_user_app/features/work/leave_screen.dart';
import 'package:omelo_user_app/features/work/shift_detail_screen.dart';
import 'package:omelo_user_app/features/work/timesheet_detail_screen.dart';
import 'package:omelo_user_app/features/work/timesheets_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const _shiftId = '11111111-2222-4333-8444-555555555555';
const _swId = '22222222-3333-4444-8555-666666666666';
const _asgId = '33333333-4444-4555-8666-777777777777';
const _tsId = '44444444-5555-4666-8777-888888888888';

/// 10:00 PM – 06:00 AM in India (UTC+5:30).
final _start = DateTime.utc(2026, 9, 20, 16, 30);
final _end = DateTime.utc(2026, 9, 21, 0, 30);

Map<String, dynamic> shiftJson({
  String shiftId = _shiftId,
  String swId = _swId,
  String status = 'assigned',
  String shiftStatus = 'scheduled',
  DateTime? start,
  DateTime? end,
  String tz = 'Asia/Kolkata',
  String method = 'app',
  Map<String, dynamic>? attendance,
}) => {
  'shift_worker_id': swId,
  'shift_id': shiftId,
  'assignment_id': _asgId,
  'status': status,
  'shift_status': shiftStatus,
  'starts_at': (start ?? _start).toIso8601String(),
  'ends_at': (end ?? _end).toIso8601String(),
  'timezone': tz,
  'break_minutes': 30,
  'kind': 'regular',
  'shift_type': 'night',
  'title': 'Warehouse Associate',
  'location': 'Gate 3, Bhiwandi Hub',
  'employer': 'Acme Staffing',
  'client': 'BlueDart Warehouse',
  'supervisor': {'name': 'Ravi Kumar', 'phone': '+91 98765 43210'},
  'instructions': 'Bring safety shoes.',
  'pay': {'rate': 650, 'period': 'day', 'currency': 'INR'},
  'check_in_method': method,
  'attendance': attendance,
};

WorkShift shift({
  String status = 'assigned',
  String shiftStatus = 'scheduled',
  String method = 'app',
  Map<String, dynamic>? attendance,
  String tz = 'Asia/Kolkata',
}) => WorkShift.fromJson(
  shiftJson(
    status: status,
    shiftStatus: shiftStatus,
    method: method,
    attendance: attendance,
    tz: tz,
  ),
);

Map<String, dynamic> assignmentJson({
  String id = _asgId,
  String status = 'offered',
  String? offerExpiresAt = '2026-09-25T12:00:00Z',
  bool verified = false,
  String? endDate,
}) => {
  'id': id,
  'status': status,
  'title': 'Warehouse Associate',
  'start_date': '2026-10-01',
  'end_date': endDate,
  'location': 'Bhiwandi Hub',
  'timezone': 'Asia/Kolkata',
  'employment_type': 'temporary',
  'work_type': 'full_time',
  'pay': {
    'rate': 650,
    'period': 'day',
    'frequency': 'weekly',
    'currency': 'INR',
  },
  'agreement': {
    'employer': 'Acme Staffing',
    'client': 'BlueDart Warehouse',
    'title': 'Warehouse Associate',
    'location': 'Bhiwandi Hub',
    'start_date': '2026-10-01',
    'employment_type': 'temporary',
    'pay': {
      'rate': 650,
      'period': 'day',
      'frequency': 'weekly',
      'currency': 'INR',
    },
    'hours_per_week': 48,
    'shifts': [
      {
        'name': 'Night',
        'days': [1, 2, 3, 4, 5],
        'start': '22:00:00',
        'end': '06:00:00',
        'break_minutes': 30,
      },
    ],
    'supervisor': 'Ravi Kumar',
    'check_in': 'qr',
    'allowances': [
      {
        'kind': 'allowance',
        'name': 'Night allowance',
        'amount': 100,
        'basis': 'per_shift',
      },
    ],
    'overtime': {
      'name': 'Standard',
      'multiplier': 1.5,
      'daily_threshold_minutes': 480,
      'weekly_threshold_minutes': 2880,
    },
  },
  'offer_expires_at': offerExpiresAt,
  'end_reason': null,
  'employer': 'Acme Staffing',
  'employer_is_agency': true,
  'client': 'BlueDart Warehouse',
  'identity_label': 'Warehouse Worker',
  'next_shift': null,
  'verified_experience': verified,
};

Assignment assignment({
  String status = 'offered',
  String? offerExpiresAt = '2026-09-25T12:00:00Z',
  bool verified = false,
  String? endDate,
}) => Assignment.fromJson(
  assignmentJson(
    status: status,
    offerExpiresAt: offerExpiresAt,
    verified: verified,
    endDate: endDate,
  ),
);

Timesheet timesheet({String status = 'draft', String? reason}) =>
    Timesheet.fromJson({
      'id': _tsId,
      'assignment_id': _asgId,
      'period_start': '2026-09-14',
      'period_end': '2026-09-20',
      'status': status,
      'total_minutes': 2760,
      'regular_minutes': 2700,
      'overtime_minutes': 60,
      'days_worked': 6,
      'shifts_worked': 6,
      'reject_reason': reason,
    });

Earning earning({
  String currency = 'INR',
  String status = 'paid',
  List<Map<String, dynamic>> payments = const [],
  num gross = 24000,
  String periodEnd = '2026-09-20',
}) => Earning.fromJson({
  'id': 'e-$currency-$periodEnd',
  'period_start': '2026-09-14',
  'period_end': periodEnd,
  'currency': currency,
  'base': 23000,
  'overtime': 800,
  'allowances': 600,
  'bonus': 0,
  'deductions': 200,
  'adjustments': -200,
  'gross': gross,
  'status': status,
  'title': 'Warehouse Associate',
  'employer': 'Acme Staffing',
  'lines': [
    {
      'kind': 'base',
      'description': 'Regular hours',
      'quantity': 46,
      'unit': 'hour',
      'rate': 500,
      'amount': 23000,
    },
    {
      'kind': 'deduction',
      'description': 'Uniform',
      'amount': 200,
      'reason': 'Uniform deposit',
    },
    {
      'kind': 'adjustment',
      'description': 'Correction',
      'amount': -200,
      'reason': 'Paid twice for 14 Sep',
    },
  ],
  'payments': payments,
});

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class _FakeWork implements WorkRepository {
  final calls = <String, Object?>{};
  Object? checkInError;

  @override
  Future<List<WorkShift>> work({DateTime? from, DateTime? to}) async =>
      const [];

  @override
  Future<List<AttendanceNote>> attendanceNotes(String attendanceId) async =>
      const [];

  @override
  Future<void> checkIn(
    String shiftWorkerId, {
    required String method,
    double? lat,
    double? lng,
    String? code,
  }) async {
    if (checkInError != null) throw checkInError!;
    calls['checkIn'] = checkInPayload(
      shiftWorkerId,
      method: method,
      lat: lat,
      lng: lng,
      code: code,
    );
  }

  @override
  Future<String> respondToAssignment(
    String assignmentId, {
    required bool accept,
    AssignmentDeclineReason? reason,
    String? otherText,
  }) async {
    calls['respond'] = respondToAssignmentPayload(
      assignmentId,
      accept: accept,
      reason: reason,
      otherText: otherText,
    );
    return accept ? 'accepted' : 'declined';
  }

  @override
  Future<String> respondToShift(String shiftWorkerId, bool accept) async {
    calls['shift'] = respondToShiftPayload(shiftWorkerId, accept);
    return accept ? 'assigned' : 'declined';
  }

  @override
  Future<void> submitTimesheet(String timesheetId) async =>
      calls['submit'] = timesheetId;

  @override
  Future<void> cancelLeave(String leaveId) async => calls['cancel'] = leaveId;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIdentities implements IdentityRepository {
  Map<String, Object?>? saved;

  @override
  Future<void> saveAvailability(String identityId, WorkAvailability a) async =>
      saved = a.toRow();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------

void main() {
  group('time zones', () {
    test('shift times are shown in the site time zone', () {
      expect(
        shiftTimeRange(_start, _end, 'Asia/Kolkata'),
        '10:00 PM – 06:00 AM',
      );
      // British Summer Time (UTC+1).
      expect(
        shiftTimeRange(_start, _end, 'Europe/London'),
        '05:30 PM – 01:30 AM',
      );
      // Eastern Daylight Time (UTC-4).
      expect(
        shiftTimeRange(_start, _end, 'America/New_York'),
        '12:30 PM – 08:30 PM',
      );
      // Winter time in Berlin (UTC+1).
      expect(clockAt(DateTime.utc(2026, 12, 1, 8), 'Europe/Berlin'), '09:00 AM');
      expect(clockAt(DateTime.utc(2026, 7, 1, 8), 'Europe/Berlin'), '10:00 AM');
    });

    test('unknown zone falls back to the phone clock', () {
      final at = DateTime.utc(2026, 9, 20, 16, 30);
      final local = at.toLocal();
      final expected =
          '${(local.hour % 12 == 0 ? 12 : local.hour % 12).toString().padLeft(2, '0')}'
          ':${local.minute.toString().padLeft(2, '0')} '
          '${local.hour < 12 ? 'AM' : 'PM'}';
      expect(clockAt(at, 'Mars/Olympus'), expected);
      expect(clockAt(at, null), expected);
      expect(zoneOf('Mars/Olympus'), isNull);
    });

    test('Today / Tomorrow follow the site date, not UTC', () {
      // 20:00 UTC on 19 Sep is already 01:30 on 20 Sep in India.
      final now = DateTime.utc(2026, 9, 19, 20);
      expect(shiftDayLabel(_start, 'Asia/Kolkata', now), 'Today');
      expect(shiftDayLabel(_start, 'UTC', now), 'Tomorrow');
      expect(
        shiftDayLabel(DateTime.utc(2026, 9, 24, 8), 'Asia/Kolkata', now),
        'Thu 24 Sep',
      );
    });

    test('zone note only when the site clock differs from the phone', () {
      final note = zoneNote(_start, 'Asia/Kolkata');
      final sameAsPhone =
          _start.toLocal().timeZoneOffset ==
          const Duration(hours: 5, minutes: 30);
      expect(note == null, sameAsPhone);
      if (note != null) {
        expect(note, 'Times are local to the site (Asia/Kolkata)');
      }
      expect(zoneNote(_start, null), isNull);
    });

    test('hours in words', () {
      expect(hoursWords(450), '7 h 30 min');
      expect(hoursWords(480), '8 h');
      expect(hoursWords(45), '45 min');
      expect(hoursWords(-5), '0 min');
    });
  });

  group('money and pay', () {
    test('each record in its own currency', () {
      expect(money(120000, 'INR'), '₹1,20,000');
      expect(money(1234.5, 'EUR'), '€1,234.50');
      expect(money(18, 'USD'), r'$18');
      expect(money(980.25, 'GBP'), '£980.25');
      expect(money(1500, 'gbp'), '£1,500');
      expect(money(1200, null), '1,200');
      expect(signedMoney(-200, 'INR'), '−₹200');
    });

    test('pay period wording', () {
      WorkPay p(num rate, String period, String cur) =>
          WorkPay(rate: rate, period: period, currency: cur);
      expect(payLine(p(14.5, 'hour', 'EUR')), '€14.50 per hour');
      expect(payLine(p(650, 'day', 'INR')), '₹650 per day');
      expect(payLine(p(22000, 'month', 'INR')), '₹22,000 per month');
      expect(payLine(p(900, 'week', 'GBP')), '£900 per week');
      expect(payLine(p(200, 'per_task', 'USD')), r'$200 per task');
      expect(payLine(const WorkPay()), 'Pay not set');
      expect(payFrequencyWords('weekly'), 'Paid every week');
      expect(payFrequencyWords('biweekly'), 'Paid every 2 weeks');
      expect(payFrequencyWords('per_shift'), 'Paid after each shift');
    });

    test('agreement lines', () {
      final a = assignment();
      final g = a.agreement;
      expect(g.employer, 'Acme Staffing');
      expect(shiftPatternLine(g.shifts.single),
          'Mon–Fri · 10:00 PM – 06:00 AM · 30 min break');
      expect(allowanceLine(g.allowances.single, 'INR'),
          'Night allowance · ₹100 per shift');
      expect(overtimeLine(g.overtime!),
          '1.5× pay after 8 h a day or 48 h a week');
      expect(daysLabel([6, 7]), 'Sat, Sun');
      expect(daysLabel([1, 2, 3, 5]), 'Mon–Wed, Fri');
      expect(daysLabel([1, 2, 3, 4, 5, 6, 7]), 'Every day');
      expect(checkInMethodTitle('employer'),
          'Your supervisor records your arrival');
    });
  });

  group('check-in window', () {
    final opens = _start.subtract(const Duration(minutes: 60));

    test('not open until 60 minutes before the start', () {
      final s = shift();
      final early = opens.subtract(const Duration(minutes: 1));
      final st = checkInState(s, early);
      expect(st.phase, CheckInPhase.notOpenYet);
      expect(st.canCheckIn, isFalse);
      expect(checkInButton(st, s, early).label,
          'Check-in opens at 09:00 PM');
      expect(checkInButton(st, s, early).action, isNull);
    });

    test('open from 60 minutes before until the end', () {
      final s = shift();
      for (final now in [opens, _start, _end]) {
        final st = checkInState(s, now);
        expect(st.phase, CheckInPhase.open, reason: '$now');
        expect(checkInButton(st, s, now).label, 'Check in');
        expect(checkInButton(st, s, now).action, 'check_in');
      }
      final late = _end.add(const Duration(minutes: 1));
      expect(checkInState(s, late).phase, CheckInPhase.missed);
      expect(checkInButton(checkInState(s, late), s, late).label,
          'Check-in closed');
    });

    test('checked in: check out, with the time in the site zone', () {
      final s = shift(attendance: {
        'id': 'a1',
        'check_in_at': '2026-09-20T17:07:00Z',
        'status': 'checked_in',
        'review_status': 'pending',
      });
      final now = DateTime.utc(2026, 9, 20, 20);
      final st = checkInState(s, now);
      expect(st.phase, CheckInPhase.checkedIn);
      final b = checkInButton(st, s, now);
      expect(b.label, 'Check out');
      expect(b.action, 'check_out');
      expect(b.detail, 'Checked in at 10:37 PM · Needs review');
      expect(attendanceReviewLine(s.attendance),
          'Late arrival recorded — your supervisor will review it');
      // Check-out closes 6 hours after the end.
      final after = _end.add(const Duration(hours: 6, minutes: 1));
      expect(checkInState(s, after).phase, CheckInPhase.checkOutClosed);
    });

    test('done shows the worked time and review state', () {
      final s = shift(status: 'completed', attendance: {
        'id': 'a1',
        'check_in_at': '2026-09-20T16:30:00Z',
        'check_out_at': '2026-09-21T00:30:00Z',
        'status': 'early_departure',
        'review_status': 'pending',
        'worked_minutes': 450,
      });
      final st = checkInState(s, _end);
      expect(st.phase, CheckInPhase.done);
      final b = checkInButton(st, s, _end);
      expect(b.label, 'Done · 7 h 30 min');
      expect(b.detail, 'Needs review');
      expect(attendanceReviewLine(s.attendance),
          'Early finish recorded — your supervisor will review it');
      expect(
        attendanceReviewLine(const Attendance(id: 'x', reviewStatus: 'approved')),
        'Your supervisor approved this time',
      );
      for (final line in [
        attendanceReviewLine(s.attendance)!,
        attendanceNoteLine(const AttendanceNote(kind: 'late', minutes: 12)),
      ]) {
        expect(line.toLowerCase(), isNot(contains('penalty')));
      }
      expect(attendanceNoteLine(const AttendanceNote(kind: 'late', minutes: 12)),
          'Late arrival (12 min) — your supervisor will review it');
    });

    test('supervisor, offered, cancelled and leave have no button', () {
      expect(checkInState(shift(method: 'employer'), _start).phase,
          CheckInPhase.supervisor);
      expect(
        checkInButton(checkInState(shift(method: 'employer'), _start),
                shift(method: 'employer'), _start)
            .label,
        'Your supervisor records your arrival',
      );
      expect(checkInState(shift(status: 'offered'), _start).phase,
          CheckInPhase.offered);
      expect(checkInState(shift(shiftStatus: 'cancelled'), _start).phase,
          CheckInPhase.cancelled);
      expect(checkInState(shift(status: 'on_leave'), _start).phase,
          CheckInPhase.onLeave);
    });

    test('payloads: QR sends the code, app sends no location', () {
      expect(checkInPayload('w', method: 'app'),
          {'p_shift_worker': 'w', 'p_method': 'app'});
      expect(checkInPayload('w', method: 'qr', code: ' 123456 '),
          {'p_shift_worker': 'w', 'p_method': 'qr', 'p_code': '123456'});
      expect(
        checkInPayload('w', method: 'geofence', lat: 19.3, lng: 73.1),
        {'p_shift_worker': 'w', 'p_method': 'geofence', 'p_lat': 19.3,
          'p_lng': 73.1},
      );
      expect(isValidShiftCode('123456'), isTrue);
      expect(isValidShiftCode('12345'), isFalse);
      expect(isValidShiftCode('12a456'), isFalse);
      expect(
        checkOutMessage(const CheckOutResult(workedMinutes: 450, needsReview: true)),
        'Checked out · 7 h 30 min worked. Your supervisor will review this '
        'shift.',
      );
    });

    test('overview: today, offers and coming up', () {
      final now = DateTime.utc(2026, 9, 20, 16);
      final list = parseWork([
        shiftJson(),
        shiftJson(
          shiftId: 'b',
          swId: 'b',
          start: DateTime.utc(2026, 9, 21, 16, 30),
          end: DateTime.utc(2026, 9, 22, 0, 30),
        ),
        shiftJson(
          shiftId: 'c',
          swId: 'c',
          status: 'offered',
          start: DateTime.utc(2026, 9, 22, 3, 30),
          end: DateTime.utc(2026, 9, 22, 11, 30),
        ),
        {'bad': 'row'},
      ]);
      final o = workOverview(list, now);
      expect(o.today.map((s) => s.shiftWorkerId), [_swId]);
      expect(o.upcoming.map((s) => s.shiftWorkerId), ['b']);
      expect(o.offers.map((s) => s.shiftWorkerId), ['c']);
    });
  });

  group('statuses, labels and actions', () {
    final now = DateTime(2026, 9, 20, 12);

    test('assignments', () {
      final offer = assignment();
      expect(assignmentStatusLabel(offer, now), 'New offer');
      final act = assignmentActions(offer, now);
      expect(act.canAccept && act.canDecline, isTrue);
      expect(act.canRequestLeave, isFalse);

      final ended = assignment(offerExpiresAt: '2026-09-19T00:00:00Z');
      expect(assignmentStatusLabel(ended, now), 'Offer ended');
      expect(assignmentActions(ended, now).canAccept, isFalse);

      final active = assignment(status: 'active');
      expect(assignmentStatusLabel(active, now), 'Working');
      expect(assignmentActions(active, now).canRequestLeave, isTrue);
      expect(assignmentActions(active, now).canTimesheet, isTrue);

      final done = assignment(status: 'completed', verified: true,
          endDate: '2026-12-31');
      expect(assignmentStatusLabel(done, now), 'Finished');
      expect(assignmentActions(done, now).verified, isTrue);
      expect(assignmentActions(done, now).canRequestLeave, isFalse);

      expect(assignmentStatusLabel(assignment(status: 'terminated'), now),
          'Ended early');
      expect(
        sortAssignments([active, done, offer], now).map((a) => a.status),
        [AssignmentStatus.offered, AssignmentStatus.active,
          AssignmentStatus.completed],
      );
      expect(
        respondToAssignmentPayload('a', accept: false,
            reason: AssignmentDeclineReason.other, otherText: '  too   late '),
        {'p_assignment': 'a', 'p_accept': false, 'p_reason': 'too late'},
      );
      expect(respondToAssignmentPayload('a', accept: true),
          {'p_assignment': 'a', 'p_accept': true});
    });

    test('timesheets', () {
      final draft = timesheetActions(timesheet());
      expect(draft.canAddTime && draft.canSubmit && draft.canRefresh, isTrue);
      final rejected =
          timesheetActions(timesheet(status: 'rejected', reason: 'Missing Sat'));
      expect(rejected.canReopen, isTrue);
      expect(rejected.note, contains('Missing Sat'));
      for (final s in ['submitted', 'under_review', 'approved', 'locked']) {
        expect(timesheetActions(timesheet(status: s)).isReadOnly, isTrue,
            reason: s);
      }
      expect(timesheetStatusLabel(TimesheetStatus.fromWire('under_review')),
          'Being checked');
      expect(timesheetStatusLabel(TimesheetStatus.locked), 'Closed');
      expect(timesheetStatusLabel(TimesheetStatus.rejected), 'Sent back');
    });

    test('timesheet periods and extra time', () {
      final today = DateTime(2026, 9, 17); // Thursday
      expect(timesheetPeriod(TimesheetPeriod.thisWeek, today),
          (DateTime(2026, 9, 14), DateTime(2026, 9, 20)));
      expect(timesheetPeriod(TimesheetPeriod.lastWeek, today),
          (DateTime(2026, 9, 7), DateTime(2026, 9, 13)));
      expect(timesheetPeriod(TimesheetPeriod.thisMonth, today),
          (DateTime(2026, 9, 1), DateTime(2026, 9, 30)));
      expect(timesheetPeriod(TimesheetPeriod.lastMonth, DateTime(2026, 1, 5)),
          (DateTime(2025, 12, 1), DateTime(2025, 12, 31)));
      expect(validateTimesheetPeriod(DateTime(2026, 8, 1), DateTime(2026, 8, 31)),
          isNull);
      expect(validateTimesheetPeriod(DateTime(2026, 8, 1), DateTime(2026, 9, 1)),
          'A timesheet can cover up to 31 days.');
      expect(parseDurationInput('1:30'), 90);
      expect(parseDurationInput('1.5'), 90);
      expect(parseDurationInput('2h'), 120);
      expect(parseDurationInput('45m'), 45);
      expect(parseDurationInput('abc'), isNull);
      expect(validateExtraTime(60, 'ok'), 'Say what the extra time was for.');
      expect(validateExtraTime(60, 'Stayed late'), isNull);
      expect(validateExtraTime(0, 'Stayed late'), 'Enter how long you worked.');
      expect(addEntryPayload('t', DateTime(2026, 9, 15), 60, ' Unloading '), {
        'p_timesheet': 't',
        'p_work_date': '2026-09-15',
        'p_minutes': 60,
        'p_note': 'Unloading',
      });
      final days = entriesByDay(parseTimesheetEntries([
        {'id': '1', 'work_date': '2026-09-15', 'minutes': 480, 'kind': 'regular'},
        {'id': '2', 'work_date': '2026-09-14', 'minutes': 480, 'kind': 'regular'},
        {'id': '3', 'work_date': '2026-09-15', 'minutes': 60, 'kind': 'manual',
          'note': 'Stayed late'},
      ]));
      expect(days.map((d) => d.minutes), [480, 540]);
      expect(days.last.entries.where((e) => e.isMine).single.id, '3');
    });

    test('earnings: statuses, payment line, breakdown, month totals', () {
      expect(earningStatusLabel(EarningStatus.calculated), 'Being checked');
      expect(earningStatusLabel(EarningStatus.fromWire('processing')),
          'On its way');
      expect(paymentLine(earning(status: 'approved'), now), 'Pending');
      expect(
        paymentLine(earning(status: 'scheduled', payments: [
          {'amount': 24000, 'status': 'scheduled', 'scheduled_for': '2026-10-21'},
        ]), now),
        'Scheduled for 21 Oct',
      );
      expect(
        paymentLine(earning(payments: [
          {'amount': 24000, 'status': 'paid',
            'paid_at': '2026-09-22T10:00:00Z', 'reference': 'UTR123'},
        ]), now),
        'Paid 22 Sep · UTR123',
      );
      final rows = earningBreakdown(earning());
      expect(rows.map((r) => r.label),
          ['Base pay', 'Overtime', 'Allowances', 'Deductions', 'Adjustments']);
      expect(rows[3].amount, -200);
      expect(rows[3].reasons, ['Uniform deposit']);
      expect(rows[4].reasons, ['Paid twice for 14 Sep']);
      expect(earningLineMath(earning().lines.first, 'INR'), '46 hours × ₹500');

      final totals = monthlyTotals([
        earning(),
        earning(periodEnd: '2026-09-07', gross: 6000),
        earning(currency: 'EUR', gross: 1234.5),
        earning(periodEnd: '2026-08-31', gross: 1000),
      ]);
      expect(totals.map((t) => '${t.month.month} ${t.currency} ${t.gross}'),
          ['9 EUR 1234.5', '9 INR 30000', '8 INR 1000']);
    });

    test('leave', () {
      final list = parseLeave([
        {'id': 'l1', 'assignment_id': 'a', 'leave_type': 'sick',
          'start_date': '2026-09-01', 'end_date': '2026-09-01',
          'status': 'approved', 'review_note': 'Get well'},
        {'id': 'l2', 'assignment_id': 'a', 'leave_type': 'paid',
          'label': 'Casual leave', 'start_date': '2026-10-21',
          'end_date': '2026-10-23', 'status': 'requested'},
      ]);
      expect(list.first.id, 'l2'); // pending first
      expect(list.first.title, 'Casual leave');
      expect(list.first.canCancel, isTrue);
      expect(list.last.title, 'Sick');
      expect(leaveStatusLabel(list.last.status), 'Approved');
      expect(leaveDaysLine(list.first.startDate, list.first.endDate, now),
          '21 Oct – 23 Oct · 3 days');
      expect(validateLeaveDates(DateTime(2026, 9, 3), DateTime(2026, 9, 2)),
          'The last day is before the first day.');
      expect(
        requestLeavePayload(assignmentId: 'a', type: LeaveType.personal,
            start: DateTime(2026, 10, 21), end: DateTime(2026, 10, 23),
            reason: ' ', label: 'Casual leave'),
        {'p_assignment': 'a', 'p_type': 'personal', 'p_start': '2026-10-21',
          'p_end': '2026-10-23', 'p_reason': null, 'p_label': 'Casual leave'},
      );
    });
  });

  group('availability', () {
    test('days are 1..7, sorted, unique, from JSON or Postgres text', () {
      expect(parseDays([7, 1, 1, 9, '3']), [1, 3, 7]);
      expect(parseDays('{5,1,2}'), [1, 2, 5]);
      expect(parseDays(null), isEmpty);
    });

    test('row round trip', () {
      final a = WorkAvailability.fromRow({
        'available_from': '2026-10-01',
        'available_until': null,
        'preferred_days': [6, 7],
        'preferred_start_time': '08:00:00',
        'preferred_end_time': '16:30:00',
        'max_weekly_hours': 40,
        'max_travel_km': 15,
      });
      expect(a.preferredStart, '08:00');
      expect(a.toRow(), {
        'available_from': '2026-10-01',
        'available_until': null,
        'preferred_days': [6, 7],
        'preferred_start_time': '08:00',
        'preferred_end_time': '16:30',
        'max_weekly_hours': 40,
        'max_travel_km': 15,
      });
      expect(validateAvailability(a), isNull);
      expect(
        validateAvailability(a.copyWith(
            availableUntil: () => DateTime(2026, 9, 1))),
        '"Available until" is before "Available from".',
      );
      expect(validateAvailability(a.copyWith(maxTravelKm: () => 5000)),
          isNotNull);
      expect(validateAvailability(a.copyWith(preferredEnd: () => null)),
          'Pick both a start and an end time, or neither.');
    });
  });

  group('notification deeplinks', () {
    AppNotification n(String type, {String? link, String? entity,
            String? id}) =>
        AppNotification(
          id: 'n',
          type: type,
          title: 'Update',
          createdAt: DateTime(2026, 9, 19),
          deeplink: link,
          entityType: entity,
          entityId: id,
        );

    test('work links map to worker screens', () {
      expect(workerDeeplink('/work/shifts/$_shiftId'), '/work/shifts/$_shiftId');
      expect(workerDeeplink('https://omelo.app/work/assignments/$_asgId'),
          '/work/assignments/$_asgId');
      expect(workerDeeplink('/work/timesheets/$_tsId'), '/work/timesheets/$_tsId');
      expect(workerDeeplink('/work/earnings'), '/work/earnings');
      expect(workerDeeplink('/work/leave'), '/work/leave');
      expect(workerDeeplink('/work'), '/work');
      expect(workerDeeplink('/work/shifts/nope'), isNull);
      expect(workerDeeplink('/work/payroll'), isNull);
      expect(workerDeeplink('/dashboard/workforce/approvals'), isNull);
      expect(notificationKind('shift_update'), NotificationKind.work);
      expect(notificationKind('work_update'), NotificationKind.work);
    });

    test('entity fallback only without a link', () {
      expect(n('shift_update', entity: 'shift', id: _shiftId).target,
          '/work/shifts/$_shiftId');
      expect(n('work_update', entity: 'earning', id: _tsId).target,
          '/work/earnings');
      expect(n('work_update', entity: 'leave_request', id: _tsId).target,
          '/work/leave');
      // A team notice points at the employer dashboard: not a worker screen.
      expect(n('work_update', link: '/dashboard/workforce/approvals',
              entity: 'timesheet', id: _tsId).target, isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('screens', () {
    late _FakeWork work;
    setUp(() => work = _FakeWork());
    final now = DateTime.utc(2026, 9, 20, 16);

    List<Override> base({
      List<WorkShift>? shifts,
      List<Assignment>? assignments,
    }) => [
      isSignedInProvider.overrideWithValue(true),
      currentUserProvider.overrideWithValue(null),
      workRepositoryProvider.overrideWithValue(work),
      workNowProvider.overrideWith((_) => Stream.value(now)),
      myWorkProvider.overrideWith((_) async => shifts ?? [shift()]),
      myAssignmentsProvider.overrideWith(
        (_) async => assignments ?? [assignment(status: 'active')],
      ),
      myLeaveProvider.overrideWith((_) async => const []),
      myTimesheetsProvider.overrideWith((_) async => const []),
      myEarningsProvider.overrideWith((_) async => const []),
    ];

    Future<void> pumpAt(
      WidgetTester tester,
      Size size,
      String location,
      List<Override> overrides,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp.router(
            theme: OmeloTheme.light(),
            routerConfig: GoRouter(
              initialLocation: location,
              routes: [
                ...workRoutes(),
                GoRoute(path: '/discover', builder: (_, __) => const Text('discover')),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    for (final size in const [Size(320, 2400), Size(1400, 1600)]) {
      testWidgets('my work at ${size.width.toInt()}px', (tester) async {
        await pumpAt(tester, size, '/work', base(
          shifts: parseWork([
            shiftJson(),
            shiftJson(shiftId: 'b', swId: 'b',
                start: DateTime.utc(2026, 9, 21, 16, 30),
                end: DateTime.utc(2026, 9, 22, 0, 30)),
            shiftJson(shiftId: 'c', swId: 'c', status: 'offered',
                start: DateTime.utc(2026, 9, 22, 3, 30),
                end: DateTime.utc(2026, 9, 22, 11, 30)),
          ]),
          assignments: [assignment(offerExpiresAt: '2026-09-25T12:00:00Z')],
        ));
        expect(tester.takeException(), isNull);
        expect(find.text('Acme Staffing offered you work'), findsOneWidget);
        expect(find.text('10:00 PM – 06:00 AM'), findsWidgets);
        expect(find.text('Check in'), findsOneWidget);
        expect(find.text('Extra shifts offered'), findsOneWidget);
        expect(find.text('Accept'), findsOneWidget);
        expect(find.text('Tomorrow'), findsOneWidget);
        expect(find.text('Timesheets'), findsOneWidget);
        expect(find.text('Earnings'), findsOneWidget);
        expect(find.text('Time off'), findsOneWidget);
      });
    }

    testWidgets('check in on the app, then accept an extra shift', (tester) async {
      await pumpAt(tester, const Size(400, 2400), '/work', base(
        shifts: parseWork([
          shiftJson(),
          shiftJson(shiftId: 'c', swId: 'c', status: 'offered',
              start: DateTime.utc(2026, 9, 22, 3, 30),
              end: DateTime.utc(2026, 9, 22, 11, 30)),
        ]),
      ));
      await tester.tap(find.text('Check in'));
      await tester.pumpAndSettle();
      expect(work.calls['checkIn'],
          {'p_shift_worker': _swId, 'p_method': 'app'});
      expect(find.text('Checked in. Have a good shift.'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(work.calls['shift'], {'p_shift_worker': 'c', 'p_accept': true});
    });

    testWidgets('a refused check-in shows the server words', (tester) async {
      work.checkInError = const PostgrestException(
        message: 'Check-in opens 60 minutes before the shift starts and '
            'closes when it ends',
      );
      await pumpAt(tester, const Size(400, 2400), '/work', base());
      await tester.tap(find.text('Check in'));
      await tester.pumpAndSettle();
      expect(work.calls['checkIn'], isNull);
      expect(find.textContaining('Check-in opens 60 minutes'), findsOneWidget);
    });

    testWidgets('shift detail: QR code check-in and supervisor', (tester) async {
      await pumpAt(tester, const Size(360, 3000), '/work/shifts/$_shiftId',
          base(shifts: [shift(method: 'qr')]));
      expect(tester.takeException(), isNull);
      expect(find.byType(ShiftDetailScreen), findsOneWidget);
      expect(find.text('Check in with a code'), findsOneWidget);
      expect(find.text('Ravi Kumar · +91 98765 43210'), findsOneWidget);
      expect(find.byTooltip('Call Ravi Kumar'), findsOneWidget);
      expect(find.text('Bring safety shoes.'), findsOneWidget);
      expect(find.text('₹650 per day'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);

      await tester.tap(find.text('Check in'));
      // The button shows a spinner while the code sheet is open.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Enter the check-in code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '123456');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Check in').last);
      await tester.pumpAndSettle();
      expect(work.calls['checkIn'],
          {'p_shift_worker': _swId, 'p_method': 'qr', 'p_code': '123456'});
    });

    testWidgets('unknown shift says so', (tester) async {
      await pumpAt(tester, const Size(400, 1200), '/work/shifts/$_tsId',
          base(shifts: const []));
      expect(find.text('Shift not found'), findsOneWidget);
    });

    for (final size in const [Size(320, 3200), Size(1400, 2000)]) {
      testWidgets('offer shows the whole agreement at ${size.width.toInt()}px',
          (tester) async {
        await pumpAt(tester, size, '/work/assignments/$_asgId',
            base(assignments: [assignment()]));
        expect(tester.takeException(), isNull);
        expect(find.text('Acme Staffing (agency)'), findsOneWidget);
        expect(find.text('BlueDart Warehouse'), findsOneWidget);
        expect(find.text('₹650 per day\nPaid every week'), findsOneWidget);
        expect(find.text('Night: Mon–Fri · 10:00 PM – 06:00 AM · 30 min break'),
            findsOneWidget);
        expect(find.text('Night allowance · ₹100 per shift'), findsOneWidget);
        expect(find.text('1.5× pay after 8 h a day or 48 h a week'),
            findsOneWidget);
        expect(find.text('Ravi Kumar'), findsOneWidget);
        expect(find.text('Check in with a code'), findsOneWidget);
        expect(find.text('Accept'), findsOneWidget);
        expect(find.text('Decline'), findsOneWidget);
      });
    }

    testWidgets('accept restates the terms', (tester) async {
      await pumpAt(tester, const Size(400, 2400), '/work/assignments/$_asgId',
          base(assignments: [assignment()]));
      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(find.text('Say yes to this work?'), findsOneWidget);
      expect(find.textContaining('Pay: ₹650 per day · Paid every week.'),
          findsOneWidget);
      await tester.tap(find.text('Yes, I accept'));
      await tester.pumpAndSettle();
      expect(work.calls['respond'], {'p_assignment': _asgId, 'p_accept': true});
      expect(find.textContaining('You said yes. You start on 1 Oct'),
          findsOneWidget);
    });

    testWidgets('decline with a reason chip', (tester) async {
      await pumpAt(tester, const Size(400, 2400), '/work/assignments/$_asgId',
          base(assignments: [assignment()]));
      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pay too low'));
      await tester.pump();
      await tester.tap(find.text('Say no'));
      await tester.pumpAndSettle();
      expect(work.calls['respond'], {
        'p_assignment': _asgId,
        'p_accept': false,
        'p_reason': 'Pay too low',
      });
    });

    testWidgets('finished work: Verified by Omelo', (tester) async {
      await pumpAt(tester, const Size(400, 2400), '/work/assignments/$_asgId',
          base(assignments: [
            assignment(status: 'completed', verified: true,
                endDate: '2026-09-15'),
          ]));
      expect(find.textContaining('Verified by Omelo'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Your agreement'), findsOneWidget);
    });

    testWidgets('assignments list', (tester) async {
      await pumpAt(tester, const Size(320, 2000), '/work/assignments',
          base(assignments: [
            assignment(status: 'completed', verified: true),
            assignment(),
          ]));
      expect(tester.takeException(), isNull);
      expect(find.byType(AssignmentsScreen), findsOneWidget);
      expect(find.text('New offer'), findsOneWidget);
      expect(find.text('Verified by Omelo'), findsOneWidget);
    });

    Override tsOf(Timesheet t) =>
        timesheetProvider.overrideWith((_, __) async => t);
    final entries = timesheetEntriesProvider.overrideWith(
      (_, __) async => parseTimesheetEntries([
        {'id': '1', 'work_date': '2026-09-15', 'minutes': 480, 'kind': 'regular'},
        {'id': '2', 'work_date': '2026-09-15', 'minutes': 60, 'kind': 'manual',
          'note': 'Stayed late to unload'},
      ]),
    );

    testWidgets('draft timesheet: add time and send', (tester) async {
      await pumpAt(tester, const Size(360, 2600), '/work/timesheets/$_tsId',
          [...base(), tsOf(timesheet()), entries]);
      expect(tester.takeException(), isNull);
      expect(find.text('46 h'), findsOneWidget);
      expect(find.text('Tue 15 Sep'), findsOneWidget);
      expect(find.text('9 h'), findsOneWidget);
      expect(find.text('Extra time · 1 h\nStayed late to unload'), findsOneWidget);
      expect(find.byTooltip('Remove this extra time'), findsOneWidget);
      expect(find.text('Add extra time'), findsOneWidget);
      await tester.tap(find.text('Send for approval'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send'));
      await tester.pumpAndSettle();
      expect(work.calls['submit'], _tsId);
    });

    testWidgets('locked timesheet is read-only', (tester) async {
      await pumpAt(tester, const Size(360, 2600), '/work/timesheets/$_tsId',
          [...base(), tsOf(timesheet(status: 'locked')), entries]);
      expect(find.textContaining('Closed. This timesheet has been paid'),
          findsOneWidget);
      expect(find.text('Add extra time'), findsNothing);
      expect(find.text('Send for approval'), findsNothing);
      expect(find.byTooltip('Remove this extra time'), findsNothing);
    });

    testWidgets('sent-back timesheet shows the reason', (tester) async {
      await pumpAt(tester, const Size(360, 2600), '/work/timesheets/$_tsId', [
        ...base(),
        tsOf(timesheet(status: 'rejected', reason: 'Saturday is missing')),
        entries,
      ]);
      expect(find.textContaining('Saturday is missing'), findsOneWidget);
      expect(find.text('Fix and send again'), findsOneWidget);
    });

    testWidgets('timesheets list offers to make one', (tester) async {
      await pumpAt(tester, const Size(320, 2000), '/work/timesheets', [
        ...base(),
        myTimesheetsProvider.overrideWith((_) async => [timesheet()]),
      ]);
      expect(find.byType(TimesheetsScreen), findsOneWidget);
      expect(find.text('Make a timesheet'), findsOneWidget);
      expect(find.text('Not sent yet'), findsOneWidget);
      await tester.tap(find.text('Make a timesheet'));
      await tester.pumpAndSettle();
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('Pick dates'), findsOneWidget);
    });

    for (final size in const [Size(320, 2400), Size(1400, 1600)]) {
      testWidgets('earnings at ${size.width.toInt()}px', (tester) async {
        await pumpAt(tester, size, '/work/earnings', [
          ...base(),
          myEarningsProvider.overrideWith((_) async => [
            earning(payments: [
              {'amount': 24000, 'status': 'scheduled',
                'scheduled_for': '2026-10-21'},
            ], status: 'scheduled'),
            earning(currency: 'EUR', gross: 1234.5, status: 'paid', payments: [
              {'amount': 1234.5, 'status': 'paid',
                'paid_at': '2026-09-22T10:00:00Z', 'reference': 'SEPA-9'},
            ]),
          ]),
        ]);
        expect(tester.takeException(), isNull);
        expect(find.byType(EarningsScreen), findsOneWidget);
        expect(find.text('September 2026'), findsOneWidget);
        expect(find.text('€1,234.50 + ₹24,000'), findsOneWidget);
        expect(find.text('₹24,000'), findsOneWidget);
        expect(find.text('€1,234.50'), findsOneWidget);
        expect(find.text('Scheduled for 21 Oct'), findsOneWidget);
        expect(find.text('Paid 22 Sep · SEPA-9'), findsOneWidget);
      });
    }

    testWidgets('time off: list and cancel a waiting request', (tester) async {
      await pumpAt(tester, const Size(360, 2000), '/work/leave', [
        ...base(),
        myLeaveProvider.overrideWith((_) async => parseLeave([
          {'id': 'l2', 'assignment_id': _asgId, 'leave_type': 'paid',
            'label': 'Casual leave', 'start_date': '2026-10-21',
            'end_date': '2026-10-23', 'status': 'requested'},
          {'id': 'l1', 'assignment_id': _asgId, 'leave_type': 'sick',
            'start_date': '2026-09-01', 'end_date': '2026-09-01',
            'status': 'approved', 'review_note': 'Get well'},
        ])),
      ]);
      expect(tester.takeException(), isNull);
      expect(find.byType(LeaveScreen), findsOneWidget);
      expect(find.text('Ask for time off'), findsOneWidget);
      expect(find.text('Casual leave'), findsOneWidget);
      expect(find.text('Note from your employer: Get well'), findsOneWidget);
      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel request'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel request'));
      await tester.pumpAndSettle();
      expect(work.calls['cancel'], 'l2');

      await tester.tap(find.text('Ask for time off'));
      await tester.pumpAndSettle();
      for (final t in LeaveType.values) {
        expect(find.text(t.label), findsWidgets);
      }
      expect(find.text('Name used where you work (optional)'), findsOneWidget);
    });

    testWidgets('every work notification opens the right screen', (tester) async {
      final cases = <String, Type>{
        '/work/shifts/$_shiftId': ShiftDetailScreen,
        '/work/assignments/$_asgId': AssignmentDetailScreen,
        '/work/timesheets/$_tsId': TimesheetDetailScreen,
        '/work/earnings': EarningsScreen,
        '/work/leave': LeaveScreen,
      };
      for (final e in cases.entries) {
        final target = AppNotification(
          id: 'n',
          type: 'work_update',
          title: 'Update',
          createdAt: DateTime(2026, 9, 19),
          deeplink: e.key,
        ).target!;
        await pumpAt(tester, const Size(400, 1600), target,
            [...base(), tsOf(timesheet()), entries]);
        expect(find.byType(e.value), findsOneWidget, reason: e.key);
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('availability block saves days and limits', (tester) async {
      final ids = _FakeIdentities();
      tester.view.physicalSize = const Size(360, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          identityRepositoryProvider.overrideWithValue(ids),
          identityAvailabilityProvider.overrideWith(
            (_, __) async => const WorkAvailability(preferredDays: [6]),
          ),
        ],
        child: MaterialApp(
          theme: OmeloTheme.light(),
          home: const Scaffold(
            body: SingleChildScrollView(
              child: AvailabilityBlock(identityId: 'c'),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Mon'));
      await tester.pump();
      await tester.tap(find.text('Sat'));
      await tester.pump();
      await tester.enterText(
          find.widgetWithText(TextField, 'Most hours a week'), '40');
      await tester.enterText(
          find.widgetWithText(TextField, 'Most travel (km)'), '12');
      await tester.pump();
      await tester.tap(find.text('Save availability'));
      await tester.pumpAndSettle();
      expect(ids.saved, {
        'available_from': null,
        'available_until': null,
        'preferred_days': [1],
        'preferred_start_time': null,
        'preferred_end_time': null,
        'max_weekly_hours': 40,
        'max_travel_km': 12,
      });
    });
  });
}

