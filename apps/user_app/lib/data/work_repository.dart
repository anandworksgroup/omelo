import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import 'jobs_repository.dart' show supabaseProvider;
import 'work.dart';

export 'work.dart';

final workRepositoryProvider = Provider<WorkRepository>(
  (ref) => WorkRepository(ref.watch(supabaseProvider)),
);

/// My assignments, shifts, time off, timesheets and earnings. Every change
/// goes through an omelo_* function; the server owns the rules. Tables are
/// only read, and only my own rows.
class WorkRepository {
  WorkRepository(this._db);
  final SupabaseClient _db;

  String? get _uid => _db.auth.currentUser?.id;

  // -- Assignments -------------------------------------------------------------

  Future<List<Assignment>> assignments() async {
    if (_uid == null) return const [];
    return parseAssignments(await _db.rpc('omelo_my_assignments'));
  }

  /// 'accepted' | 'active' | 'declined'
  Future<String> respondToAssignment(
    String assignmentId, {
    required bool accept,
    AssignmentDeclineReason? reason,
    String? otherText,
  }) async {
    final res = await _db.rpc(
      'omelo_respond_to_assignment',
      params: respondToAssignmentPayload(
        assignmentId,
        accept: accept,
        reason: reason,
        otherText: otherText,
      ),
    );
    return res?.toString() ?? (accept ? 'accepted' : 'declined');
  }

  // -- Shifts ------------------------------------------------------------------

  /// My shifts from [from] to [to] (server default: yesterday to +14 days).
  Future<List<WorkShift>> work({DateTime? from, DateTime? to}) async {
    if (_uid == null) return const [];
    final res = await _db.rpc(
      'omelo_my_work',
      params: {
        if (from != null) 'p_from': wireDate(from),
        if (to != null) 'p_to': wireDate(to),
      },
    );
    return parseWork(res);
  }

  /// 'assigned' | 'declined'
  Future<String> respondToShift(String shiftWorkerId, bool accept) async {
    final res = await _db.rpc(
      'omelo_respond_to_shift',
      params: respondToShiftPayload(shiftWorkerId, accept),
    );
    return res?.toString() ?? (accept ? 'assigned' : 'declined');
  }

  Future<void> checkIn(
    String shiftWorkerId, {
    required String method,
    double? lat,
    double? lng,
    String? code,
  }) => _db.rpc(
    'omelo_check_in',
    params: checkInPayload(
      shiftWorkerId,
      method: method,
      lat: lat,
      lng: lng,
      code: code,
    ),
  );

  Future<CheckOutResult> checkOut(String shiftWorkerId) async {
    final res = await _db.rpc(
      'omelo_check_out',
      params: {'p_shift_worker': shiftWorkerId},
    );
    return CheckOutResult.fromJson(res);
  }

  Future<List<AttendanceNote>> attendanceNotes(String attendanceId) async {
    final rows = await _db
        .from('attendance_exceptions')
        .select('kind, minutes, status, resolution_note')
        .eq('attendance_id', attendanceId)
        .order('created_at');
    return [
      for (final r in rows)
        AttendanceNote.fromJson(Map<String, dynamic>.from(r)),
    ];
  }

  // -- Leave -------------------------------------------------------------------

  Future<List<LeaveRequest>> leave() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _db
        .from('leave_requests')
        .select(
          'id, assignment_id, leave_type, label, start_date, end_date, '
          'reason, status, review_note, created_at',
        )
        .eq('person_id', uid)
        .order('start_date', ascending: false)
        .limit(200);
    return parseLeave(rows);
  }

  Future<void> requestLeave({
    required String assignmentId,
    required LeaveType type,
    required DateTime start,
    required DateTime end,
    String? reason,
    String? label,
  }) => _db.rpc(
    'omelo_request_leave',
    params: requestLeavePayload(
      assignmentId: assignmentId,
      type: type,
      start: start,
      end: end,
      reason: reason,
      label: label,
    ),
  );

  Future<void> cancelLeave(String leaveId) =>
      _db.rpc('omelo_cancel_leave', params: {'p_leave': leaveId});

  // -- Timesheets --------------------------------------------------------------

  static const _timesheetCols =
      'id, assignment_id, period_start, period_end, status, total_minutes, '
      'regular_minutes, overtime_minutes, days_worked, shifts_worked, '
      'reject_reason, submitted_at';

  Future<List<Timesheet>> timesheets() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _db
        .from('timesheets')
        .select(_timesheetCols)
        .eq('person_id', uid)
        .order('period_start', ascending: false)
        .limit(200);
    return parseTimesheets(rows);
  }

  Future<Timesheet?> timesheet(String id) async {
    final row = await _db
        .from('timesheets')
        .select(_timesheetCols)
        .eq('id', id)
        .maybeSingle();
    if (row == null) return null;
    final list = parseTimesheets([row]);
    return list.isEmpty ? null : list.single;
  }

  Future<List<TimesheetEntry>> entries(String timesheetId) async {
    final rows = await _db
        .from('timesheet_entries')
        .select('id, work_date, minutes, kind, note')
        .eq('timesheet_id', timesheetId)
        .order('work_date');
    return parseTimesheetEntries(rows);
  }

  /// Makes (or refreshes) the timesheet for the period; returns its id.
  Future<String> buildTimesheet(
    String assignmentId,
    DateTime start,
    DateTime end,
  ) async {
    final res = await _db.rpc(
      'omelo_build_timesheet',
      params: buildTimesheetPayload(assignmentId, start, end),
    );
    return res.toString();
  }

  Future<void> addEntry(
    String timesheetId,
    DateTime day,
    int minutes,
    String note,
  ) => _db.rpc(
    'omelo_add_timesheet_entry',
    params: addEntryPayload(timesheetId, day, minutes, note),
  );

  Future<void> removeEntry(String entryId) =>
      _db.rpc('omelo_remove_timesheet_entry', params: {'p_entry': entryId});

  Future<void> submitTimesheet(String timesheetId) =>
      _db.rpc('omelo_submit_timesheet', params: {'p_timesheet': timesheetId});

  // -- Earnings ----------------------------------------------------------------

  Future<List<Earning>> earnings() async {
    if (_uid == null) return const [];
    return parseEarnings(await _db.rpc('omelo_my_earnings'));
  }
}

/// A server refusal in its own words (they are written for workers), or a
/// plain connection message.
String workError(Object e) {
  if (e is PostgrestException && e.message.trim().isNotEmpty) {
    return e.message.trim();
  }
  return 'Could not reach Omelo. Check your internet and try again.';
}

// -- Providers -------------------------------------------------------------------

/// The clock the work screens use. Ticks every 30 seconds so "Check-in
/// opens at …" turns into "Check in" without a reload.
final workNowProvider = StreamProvider.autoDispose<DateTime>((ref) async* {
  yield DateTime.now();
  yield* Stream.periodic(const Duration(seconds: 30), (_) => DateTime.now());
});

/// Now, from [workNowProvider] (the real clock until the first tick).
DateTime workNow(WidgetRef ref) =>
    ref.watch(workNowProvider).valueOrNull ?? DateTime.now();

final myAssignmentsProvider = FutureProvider.autoDispose<List<Assignment>>((
  ref,
) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  final list = await ref.watch(workRepositoryProvider).assignments();
  return sortAssignments(list, DateTime.now());
});

/// My shifts, yesterday to two weeks ahead.
final myWorkProvider = FutureProvider.autoDispose<List<WorkShift>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(workRepositoryProvider).work();
});

/// One shift by its shift id (notification deeplinks use it). Looks in the
/// usual window first, then a wider one for older or later shifts.
final shiftDetailProvider = FutureProvider.autoDispose
    .family<WorkShift?, String>((ref, shiftId) async {
      final near = await ref.watch(myWorkProvider.future);
      for (final s in near) {
        if (s.shiftId == shiftId) return s;
      }
      final today = DateTime.now();
      final wide = await ref
          .watch(workRepositoryProvider)
          .work(
            from: DateTime(today.year, today.month, today.day - 120),
            to: DateTime(today.year, today.month, today.day + 120),
          );
      for (final s in wide) {
        if (s.shiftId == shiftId) return s;
      }
      return null;
    });

final attendanceNotesProvider = FutureProvider.autoDispose
    .family<List<AttendanceNote>, String>(
      (ref, attendanceId) =>
          ref.watch(workRepositoryProvider).attendanceNotes(attendanceId),
    );

final myLeaveProvider = FutureProvider.autoDispose<List<LeaveRequest>>((
  ref,
) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(workRepositoryProvider).leave();
});

final myTimesheetsProvider = FutureProvider.autoDispose<List<Timesheet>>((
  ref,
) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(workRepositoryProvider).timesheets();
});

final timesheetProvider = FutureProvider.autoDispose
    .family<Timesheet?, String>(
      (ref, id) => ref.watch(workRepositoryProvider).timesheet(id),
    );

final timesheetEntriesProvider = FutureProvider.autoDispose
    .family<List<TimesheetEntry>, String>(
      (ref, id) => ref.watch(workRepositoryProvider).entries(id),
    );

final myEarningsProvider = FutureProvider.autoDispose<List<Earning>>((
  ref,
) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(workRepositoryProvider).earnings();
});

/// Offers waiting for me (work offers and extra shifts), for badges. Zero on
/// any failure: a badge must never break a screen.
final pendingWorkCountProvider = Provider.autoDispose<int>((ref) {
  final now = DateTime.now();
  final offers = (ref.watch(myAssignmentsProvider).valueOrNull ?? const [])
      .where((a) => a.isOfferOpenAt(now))
      .length;
  final shifts = (ref.watch(myWorkProvider).valueOrNull ?? const [])
      .where(
        (s) =>
            s.status == ShiftWorkerStatus.offered &&
            !s.isCancelled &&
            s.endsAt.isAfter(now),
      )
      .length;
  return offers + shifts;
});

/// Reload everything work-related after a change.
void invalidateWork(WidgetRef ref) {
  ref.invalidate(myWorkProvider);
  ref.invalidate(myAssignmentsProvider);
  ref.invalidate(shiftDetailProvider);
  ref.invalidate(myLeaveProvider);
  ref.invalidate(myTimesheetsProvider);
  ref.invalidate(timesheetProvider);
  ref.invalidate(timesheetEntriesProvider);
  ref.invalidate(myEarningsProvider);
}
