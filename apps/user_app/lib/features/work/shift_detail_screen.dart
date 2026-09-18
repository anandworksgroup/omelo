import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/work_repository.dart';
import 'work_widgets.dart';

/// `/work/shifts/:id` — one shift (notification deeplinks use the shift
/// id): when and where, the supervisor, pay, instructions, how to check in
/// and what was recorded.
class ShiftDetailScreen extends ConsumerWidget {
  const ShiftDetailScreen({super.key, required this.shiftId});
  final String shiftId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForWorkNotices(ref);
    final async = ref.watch(shiftDetailProvider(shiftId));
    final now = workNow(ref);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Shift'),
        leading: workBackButton(context, '/work'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          invalidateWork(ref);
          try {
            await ref.read(shiftDetailProvider(shiftId).future);
          } catch (_) {}
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => RepresentationMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load this shift',
            body: workError(e),
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(shiftDetailProvider(shiftId)),
          ),
          data: (s) {
            if (s == null) {
              return RepresentationMessage(
                icon: Icons.event_busy_outlined,
                title: 'Shift not found',
                body:
                    'This shift is no longer in your list. It may have been '
                    'moved or removed.',
                actionLabel: 'Open My work',
                onAction: () => context.go('/work'),
              );
            }
            return _Body(shift: s, now: now);
          },
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.shift, required this.now});
  final WorkShift shift;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = shift;
    final scheme = Theme.of(context).colorScheme;
    final gutter = Breakpoints.of(context).gutter;
    final zone = zoneNote(s.startsAt, s.timezone);
    final name = shiftNameLine(s);
    final att = s.attendance;
    final sup = s.supervisor;
    final offered = s.status == ShiftWorkerStatus.offered && !s.isCancelled;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 40),
      children: [
        ContentWidth.reading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                shiftDayLabel(s.startsAt, s.timezone, now),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
              Text(
                shiftTimeRange(s.startsAt, s.endsAt, s.timezone),
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (zone != null)
                Text(
                  zone,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                s.title,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                shiftEmployerLine(s),
                style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
              ),
              if (name.isNotEmpty || s.isCancelled || offered) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (name.isNotEmpty) OmeloPill(name),
                    if (s.isCancelled)
                      const WorkPill('Cancelled', tone: WorkTone.warning),
                    if (offered)
                      const WorkPill(
                        'Extra shift offered',
                        tone: WorkTone.waiting,
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              if (offered)
                ShiftOfferCard(shift: s, now: now)
              else
                CheckInPanel(shift: s, now: now),

              WorkSection(
                title: 'How to check in',
                child: WorkInfoRow(
                  icon: switch (s.checkInMethod) {
                    'qr' => Icons.pin_outlined,
                    'geofence' => Icons.my_location,
                    'employer' => Icons.badge_outlined,
                    _ => Icons.touch_app_outlined,
                  },
                  label: checkInMethodTitle(s.checkInMethod),
                  value: checkInMethodHelp(s.checkInMethod),
                ),
              ),

              WorkSection(
                title: 'Details',
                child: Column(
                  children: [
                    if (s.location != null)
                      WorkInfoRow(
                        icon: Icons.place_outlined,
                        label: 'Where',
                        value: s.location!,
                      ),
                    WorkInfoRow(
                      icon: Icons.login,
                      label: 'Starts',
                      value:
                          '${shiftDayLabel(s.startsAt, s.timezone, now)}, '
                          '${clockAt(s.startsAt, s.timezone)}',
                    ),
                    WorkInfoRow(
                      icon: Icons.logout,
                      label: 'Ends',
                      value:
                          '${shiftDayLabel(s.endsAt, s.timezone, now)}, '
                          '${clockAt(s.endsAt, s.timezone)}',
                    ),
                    WorkInfoRow(
                      icon: Icons.free_breakfast_outlined,
                      label: 'Break',
                      value: s.breakMinutes > 0
                          ? hoursWords(s.breakMinutes)
                          : 'No set break',
                    ),
                    if (s.pay.rate != null)
                      WorkInfoRow(
                        icon: Icons.payments_outlined,
                        label: 'Pay',
                        value: payLine(s.pay),
                      ),
                    if (sup != null)
                      WorkInfoRow(
                        icon: Icons.person_outline,
                        label: 'Supervisor',
                        value: [?sup.name, ?sup.phone].join(' · '),
                        trailing: sup.phone == null
                            ? null
                            : IconButton.filledTonal(
                                tooltip: 'Call ${sup.name ?? 'supervisor'}',
                                iconSize: 24,
                                style: IconButton.styleFrom(
                                  minimumSize: const Size(52, 52),
                                ),
                                onPressed: () =>
                                    callNumber(context, sup.phone!),
                                icon: const Icon(Icons.call),
                              ),
                      ),
                  ],
                ),
              ),

              if (s.instructions != null)
                WorkSection(
                  title: 'Instructions',
                  child: Text(
                    s.instructions!,
                    style: const TextStyle(fontSize: 15.5, height: 1.45),
                  ),
                ),

              if (att != null && att.checkInAt != null)
                WorkSection(
                  title: 'Your time',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      WorkInfoRow(
                        icon: Icons.login,
                        label: 'Checked in',
                        value: clockAt(att.checkInAt!, s.timezone),
                      ),
                      if (att.checkOutAt != null)
                        WorkInfoRow(
                          icon: Icons.logout,
                          label: 'Checked out',
                          value: clockAt(att.checkOutAt!, s.timezone),
                        ),
                      if (att.workedMinutes != null)
                        WorkInfoRow(
                          icon: Icons.timer_outlined,
                          label: 'Worked',
                          value: hoursWords(att.workedMinutes!),
                        ),
                      _AttendanceNotes(attendanceId: att.id),
                    ],
                  ),
                ),

              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => context.push(assignmentRoute(s.assignmentId)),
                icon: const Icon(Icons.description_outlined),
                label: const Text('See the work agreement'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Late arrival, early finish … and what the supervisor decided.
class _AttendanceNotes extends ConsumerWidget {
  const _AttendanceNotes({required this.attendanceId});
  final String attendanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notes =
        ref.watch(attendanceNotesProvider(attendanceId)).valueOrNull ??
        const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: WorkNote(
              [
                attendanceNoteLine(n),
                ?n.resolutionNote,
              ].join('. '),
              tone: n.status == 'pending' ? WorkTone.waiting : WorkTone.neutral,
              icon: Icons.rate_review_outlined,
            ),
          ),
      ],
    );
  }
}
