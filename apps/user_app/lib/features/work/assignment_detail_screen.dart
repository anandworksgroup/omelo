import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../data/work_repository.dart';
import 'work_widgets.dart';

/// `/work/assignments/:id` — one piece of work. An offer shows the whole
/// agreement (who employs me, where, dates, pay, shifts, extras, overtime,
/// supervisor, check-in) with Accept / Decline. Work that is on shows the
/// next shift, time off and timesheets; finished work shows "Verified by
/// Omelo".
class AssignmentDetailScreen extends ConsumerWidget {
  const AssignmentDetailScreen({super.key, required this.assignmentId});
  final String assignmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForWorkNotices(ref);
    final async = ref.watch(myAssignmentsProvider);
    final now = workNow(ref);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Work details'),
        leading: workBackButton(context, '/work/assignments'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RepresentationMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load this work',
          body: workError(e),
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myAssignmentsProvider),
        ),
        data: (list) {
          final found = list.where((a) => a.id == assignmentId);
          if (found.isEmpty) {
            return RepresentationMessage(
              icon: Icons.search_off,
              title: 'Work not found',
              body: 'This work is not in your list any more.',
              actionLabel: 'See my assignments',
              onAction: () => context.go('/work/assignments'),
            );
          }
          return _Body(assignment: found.first, now: now);
        },
      ),
      bottomNavigationBar: async.valueOrNull == null
          ? null
          : _AnswerBar(
              assignment: async.valueOrNull!
                  .where((a) => a.id == assignmentId)
                  .firstOrNull,
              now: now,
            ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.assignment, required this.now});
  final Assignment assignment;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = assignment;
    final actions = assignmentActions(a, now);
    final scheme = Theme.of(context).colorScheme;
    final gutter = Breakpoints.of(context).gutter;
    final offer = a.status == AssignmentStatus.offered;

    return RefreshIndicator(
      onRefresh: () async {
        invalidateWork(ref);
        try {
          await ref.read(myAssignmentsProvider.future);
        } catch (_) {}
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 40),
        children: [
          ContentWidth.reading(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  a.employerName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  a.title,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    WorkPill(
                      assignmentStatusLabel(a, now),
                      tone: assignmentTone(a, now),
                    ),
                    if (a.employerIsAgency)
                      const OmeloPill(
                        'Through an agency',
                        icon: Icons.handshake_outlined,
                      ),
                    if (a.identityLabel != null)
                      OmeloPill('As your ${a.identityLabel} profile'),
                  ],
                ),
                const SizedBox(height: 12),
                WorkNote(
                  actions.note,
                  tone: a.isOfferOpenAt(now)
                      ? WorkTone.waiting
                      : WorkTone.neutral,
                ),
                if (actions.verified) ...[
                  const SizedBox(height: 10),
                  const VerifiedWorkBanner(),
                ],
                if (a.status.isOngoing) ...[
                  const SizedBox(height: 12),
                  _NextShift(assignment: a, now: now),
                ],
                _Agreement(assignment: a, now: now, expanded: offer),
                if (actions.canRequestLeave || a.status.isOngoing)
                  _LeaveBlock(assignment: a, now: now),
                if (actions.canTimesheet)
                  _TimesheetBlock(assignment: a, now: now),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NextShift extends StatelessWidget {
  const _NextShift({required this.assignment, required this.now});
  final Assignment assignment;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final next = a.nextShift;
    return Card(
      child: ListTile(
        minTileHeight: 60,
        leading: const Icon(Icons.event_outlined, size: 28),
        title: Text(
          next == null
              ? 'No shift planned yet'
              : 'Next shift: ${shiftDayLabel(next, a.timezone, now)}, '
                    '${clockAt(next, a.timezone)}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        subtitle: const Text('See all my shifts'),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/work'),
      ),
    );
  }
}

/// Everything that was agreed, in reading order.
class _Agreement extends StatelessWidget {
  const _Agreement({
    required this.assignment,
    required this.now,
    required this.expanded,
  });
  final Assignment assignment;
  final DateTime now;

  /// Offers show it open; after that it folds away.
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final g = a.agreement;
    final pay = g.pay.rate != null ? g.pay : a.pay;
    final currency = pay.currency;
    final client = a.clientName;
    final dates = datesLine(
      g.startDate ?? a.startDate,
      g.endDate ?? a.endDate,
      now,
    );
    final type = [
      employmentTypeLabel(g.employmentType ?? a.employmentType),
      if (a.workType != null) Fmt.workType(a.workType),
      if (g.hoursPerWeek != null) '${_plain(g.hoursPerWeek!)} hours a week',
    ].where((x) => x.isNotEmpty).join(' · ');
    final frequency = payFrequencyWords(pay.frequency);

    final rows = <Widget>[
      WorkInfoRow(
        icon: Icons.apartment_outlined,
        label: 'Who employs you',
        value: a.employerIsAgency
            ? '${a.employerName} (agency)'
            : a.employerName,
      ),
      if (client != null && client != a.employerName)
        WorkInfoRow(
          icon: Icons.store_outlined,
          label: 'Where you work',
          value: client,
        ),
      if ((g.location ?? a.location) != null)
        WorkInfoRow(
          icon: Icons.place_outlined,
          label: 'Place',
          value: (g.location ?? a.location)!,
        ),
      if (dates != null)
        WorkInfoRow(
          icon: Icons.date_range_outlined,
          label: 'Dates',
          value: dates,
        ),
      if (type.isNotEmpty)
        WorkInfoRow(icon: Icons.work_outline, label: 'Type', value: type),
      WorkInfoRow(
        icon: Icons.payments_outlined,
        label: 'Pay',
        value: frequency.isEmpty ? payLine(pay) : '${payLine(pay)}\n$frequency',
      ),
      if (g.shifts.isNotEmpty)
        WorkInfoRow(
          icon: Icons.schedule_outlined,
          label: 'Shifts',
          value: [
            for (final s in g.shifts)
              [
                if (s.name != null) s.name!,
                shiftPatternLine(s),
              ].where((x) => x.isNotEmpty).join(': '),
          ].join('\n'),
        ),
      if (g.allowances.isNotEmpty)
        WorkInfoRow(
          icon: Icons.add_card_outlined,
          label: 'Extras and deductions',
          value: [
            for (final x in g.allowances) allowanceLine(x, currency),
          ].join('\n'),
        ),
      if (g.overtime != null)
        WorkInfoRow(
          icon: Icons.more_time,
          label: 'Overtime',
          value: overtimeLine(g.overtime!),
        ),
      if (g.supervisor != null)
        WorkInfoRow(
          icon: Icons.person_outline,
          label: 'Supervisor',
          value: g.supervisor!,
        ),
      WorkInfoRow(
        icon: Icons.touch_app_outlined,
        label: checkInMethodTitle(g.checkIn),
        value: checkInMethodHelp(g.checkIn),
      ),
    ];

    if (expanded) {
      return WorkSection(
        title: 'The offer',
        child: Column(children: rows),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          minTileHeight: 60,
          title: const Text(
            'Your agreement',
            style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(payLine(pay)),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          children: rows,
        ),
      ),
    );
  }
}

String _plain(num n) =>
    n == n.roundToDouble() ? n.round().toString() : n.toString();

class _LeaveBlock extends ConsumerWidget {
  const _LeaveBlock({required this.assignment, required this.now});
  final Assignment assignment;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = assignment;
    final all = ref.watch(myLeaveProvider).valueOrNull ?? const [];
    final mine = all.where((l) => l.assignmentId == a.id).take(3).toList();
    final canAsk = assignmentActions(a, now).canRequestLeave;
    return WorkSection(
      title: 'Time off',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (mine.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'No time off asked for yet.',
                style: TextStyle(
                  fontSize: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final l in mine)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.beach_access_outlined),
              title: Text(l.title),
              subtitle: Text(leaveDaysLine(l.startDate, l.endDate, now)),
              trailing: WorkPill(
                leaveStatusLabel(l.status),
                tone: leaveTone(l.status),
              ),
              onTap: () =>
                  context.push(workListRoute('/work/leave', assignment: a.id)),
            ),
          if (canAsk)
            OutlinedButton.icon(
              onPressed: () =>
                  context.push(workListRoute('/work/leave', assignment: a.id)),
              icon: const Icon(Icons.add),
              label: const Text('Ask for time off'),
            ),
        ],
      ),
    );
  }
}

class _TimesheetBlock extends ConsumerWidget {
  const _TimesheetBlock({required this.assignment, required this.now});
  final Assignment assignment;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = assignment;
    final all = ref.watch(myTimesheetsProvider).valueOrNull ?? const [];
    final mine = all.where((t) => t.assignmentId == a.id).take(3).toList();
    return WorkSection(
      title: 'Timesheets',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in mine)
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 56,
              leading: const Icon(Icons.schedule_outlined),
              title: Text(periodLine(t.periodStart, t.periodEnd, now)),
              subtitle: Text(hoursWords(t.totalMinutes)),
              trailing: WorkPill(
                timesheetStatusLabel(t.status),
                tone: timesheetTone(t.status),
              ),
              onTap: () => context.push(timesheetRoute(t.id)),
            ),
          OutlinedButton.icon(
            onPressed: () => context.push(
              workListRoute('/work/timesheets', assignment: a.id),
            ),
            icon: const Icon(Icons.schedule_outlined),
            label: Text(mine.isEmpty ? 'Make a timesheet' : 'All timesheets'),
          ),
        ],
      ),
    );
  }
}

/// Accept / Decline, fixed at the bottom while an offer is open.
class _AnswerBar extends ConsumerWidget {
  const _AnswerBar({required this.assignment, required this.now});
  final Assignment? assignment;
  final DateTime now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final a = assignment;
    if (a == null) return const SizedBox.shrink();
    final actions = assignmentActions(a, now);
    if (!actions.canAccept && !actions.canDecline) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;

    Future<void> accept() async {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => AcceptAssignmentSheet(assignment: a, now: now),
      );
      if (ok == true) invalidateWork(ref);
    }

    Future<void> decline() async {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => DeclineAssignmentSheet(assignment: a),
      );
      if (ok == true) invalidateWork(ref);
    }

    return Material(
      color: scheme.surface,
      elevation: 6,
      child: SafeArea(
        top: false,
        // Centred and capped, but only as tall as the buttons.
        child: Center(
          heightFactor: 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: Breakpoints.readingWidth,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: decline,
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: accept,
                      child: const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Say yes to this work?" — restates who, where, when and pay.
class AcceptAssignmentSheet extends ConsumerStatefulWidget {
  const AcceptAssignmentSheet({
    super.key,
    required this.assignment,
    required this.now,
  });
  final Assignment assignment;
  final DateTime now;

  @override
  ConsumerState<AcceptAssignmentSheet> createState() =>
      _AcceptAssignmentSheetState();
}

class _AcceptAssignmentSheetState extends ConsumerState<AcceptAssignmentSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final res = await ref
          .read(workRepositoryProvider)
          .respondToAssignment(widget.assignment.id, accept: true);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.pop(context, true);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(acceptedMessage(res, widget.assignment, widget.now)),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = workError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.assignment;
    final dates = datesLine(a.startDate, a.endDate, widget.now);
    final frequency = payFrequencyWords(a.pay.frequency);
    final place = [
      if (a.clientName != null && a.clientName != a.employerName) a.clientName!,
      ?a.location,
    ].join(', ');
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Say yes to this work?',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Text(
              [
                'You will work for ${a.employerName} as ${a.title}'
                    '${place.isEmpty ? '' : ' at $place'}.',
                ?(dates == null ? null : 'Dates: $dates.'),
                'Pay: ${payLine(a.pay)}'
                    '${frequency.isEmpty ? '' : ' · $frequency'}.',
              ].join('\n'),
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              WorkNote(_error!, tone: WorkTone.warning),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _go,
              child: Text(_busy ? 'Sending…' : 'Yes, I accept'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Not yet'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "No thanks" with a reason chip (optional).
class DeclineAssignmentSheet extends ConsumerStatefulWidget {
  const DeclineAssignmentSheet({super.key, required this.assignment});
  final Assignment assignment;

  @override
  ConsumerState<DeclineAssignmentSheet> createState() =>
      _DeclineAssignmentSheetState();
}

class _DeclineAssignmentSheetState
    extends ConsumerState<DeclineAssignmentSheet> {
  AssignmentDeclineReason? _reason;
  final _other = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(workRepositoryProvider)
          .respondToAssignment(
            widget.assignment.id,
            accept: false,
            reason: _reason,
            otherText: _other.text,
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.pop(context, true);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('You said no. The employer has been told.'),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = workError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Say no to this work?',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              'Why? (optional — it helps them send better offers)',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in AssignmentDeclineReason.values)
                  ChoiceChip(
                    label: Text(r.label),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    selected: _reason == r,
                    onSelected: (on) => setState(() => _reason = on ? r : null),
                  ),
              ],
            ),
            if (_reason == AssignmentDeclineReason.other) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _other,
                maxLength: kWorkReasonMax,
                decoration: const InputDecoration(hintText: 'Tell them why'),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              WorkNote(_error!, tone: WorkTone.warning),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _go,
              child: Text(_busy ? 'Sending…' : 'Say no'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context, false),
              child: const Text('Go back'),
            ),
          ],
        ),
      ),
    );
  }
}
