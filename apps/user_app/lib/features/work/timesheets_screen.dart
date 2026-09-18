import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/work_repository.dart';
import 'work_widgets.dart';

/// `/work/timesheets` — my timesheets, newest first, and a way to make one
/// for this week, this month or chosen days. `?assignment=<id>` shows one
/// assignment only.
class TimesheetsScreen extends ConsumerWidget {
  const TimesheetsScreen({super.key, this.assignmentId});
  final String? assignmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForWorkNotices(ref);
    final async = ref.watch(myTimesheetsProvider);
    final assignments =
        ref.watch(myAssignmentsProvider).valueOrNull ?? const <Assignment>[];
    final now = workNow(ref);
    final titles = {for (final a in assignments) a.id: a.title};
    final eligible = assignments
        .where(
          (a) =>
              assignmentActions(a, now).canTimesheet &&
              (assignmentId == null || a.id == assignmentId),
        )
        .toList();

    Future<void> make() async {
      final id = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => NewTimesheetSheet(assignments: eligible, now: now),
      );
      if (id == null || !context.mounted) return;
      ref.invalidate(myTimesheetsProvider);
      context.push(timesheetRoute(id));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Timesheets'),
        leading: workBackButton(context, '/work'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myTimesheetsProvider);
          try {
            await ref.read(myTimesheetsProvider.future);
          } catch (_) {}
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => RepresentationMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load your timesheets',
            body: workError(e),
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(myTimesheetsProvider),
          ),
          data: (all) {
            final list = assignmentId == null
                ? all
                : all.where((t) => t.assignmentId == assignmentId).toList();
            final gutter = Breakpoints.of(context).gutter;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                ContentWidth.reading(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'A timesheet collects the hours from your shifts. '
                        'Check it, add any extra time, then send it for '
                        'approval to get paid.',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.4,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 14),
                      if (eligible.isNotEmpty)
                        FilledButton.icon(
                          onPressed: make,
                          icon: const Icon(Icons.add),
                          label: const Text('Make a timesheet'),
                        ),
                      const SizedBox(height: 16),
                      if (list.isEmpty)
                        Text(
                          'No timesheets yet.',
                          style: TextStyle(
                            fontSize: 15.5,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      for (final t in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _TimesheetCard(
                            timesheet: t,
                            title: titles[t.assignmentId],
                            now: now,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TimesheetCard extends StatelessWidget {
  const _TimesheetCard({
    required this.timesheet,
    required this.title,
    required this.now,
  });
  final Timesheet timesheet;
  final String? title;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final t = timesheet;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(timesheetRoute(t.id)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      periodLine(t.periodStart, t.periodEnd, now),
                      style: const TextStyle(
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (title != null)
                      Text(
                        title!,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '${hoursWords(t.totalMinutes)} · '
                      '${t.shiftsWorked == 1 ? '1 shift' : '${t.shiftsWorked} shifts'}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    WorkPill(
                      timesheetStatusLabel(t.status),
                      tone: timesheetTone(t.status),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pick the work and the days; the server fills in the hours from the
/// shifts. Returns the timesheet id.
class NewTimesheetSheet extends ConsumerStatefulWidget {
  const NewTimesheetSheet({
    super.key,
    required this.assignments,
    required this.now,
  });
  final List<Assignment> assignments;
  final DateTime now;

  @override
  ConsumerState<NewTimesheetSheet> createState() => _NewTimesheetSheetState();
}

class _NewTimesheetSheetState extends ConsumerState<NewTimesheetSheet> {
  late String? _assignment = widget.assignments.isEmpty
      ? null
      : widget.assignments.first.id;
  TimesheetPeriod? _quick = TimesheetPeriod.thisWeek;
  DateTime? _start;
  DateTime? _end;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final (s, e) = timesheetPeriod(TimesheetPeriod.thisWeek, widget.now);
    _start = s;
    _end = e;
  }

  void _pickQuick(TimesheetPeriod p) {
    final (s, e) = timesheetPeriod(p, widget.now);
    setState(() {
      _quick = p;
      _start = s;
      _end = e;
      _error = null;
    });
  }

  Future<void> _pickDates() async {
    final now = widget.now;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _start != null && _end != null
          ? DateTimeRange(start: _start!, end: _end!)
          : null,
      helpText: 'Pick up to $kTimesheetMaxDays days',
    );
    if (range == null) return;
    setState(() {
      _quick = null;
      _start = range.start;
      _end = range.end;
      _error = validateTimesheetPeriod(_start, _end);
    });
  }

  Future<void> _go() async {
    final problem = _assignment == null
        ? 'Pick the work first.'
        : validateTimesheetPeriod(_start, _end);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref
          .read(workRepositoryProvider)
          .buildTimesheet(_assignment!, _start!, _end!);
      if (mounted) Navigator.pop(context, id);
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
    final now = widget.now;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Make a timesheet',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            if (widget.assignments.length > 1) ...[
              DropdownButtonFormField<String>(
                value: _assignment,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Which work?'),
                items: [
                  for (final a in widget.assignments)
                    DropdownMenuItem(
                      value: a.id,
                      child: Text(
                        '${a.title} · ${a.employerName}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _assignment = v),
              ),
              const SizedBox(height: 14),
            ],
            const Text(
              'Which days?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final p in TimesheetPeriod.values)
                  ChoiceChip(
                    label: Text(p.label),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    selected: _quick == p,
                    onSelected: (_) => _pickQuick(p),
                  ),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: const Text('Pick dates'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 8,
                  ),
                  onPressed: _pickDates,
                ),
              ],
            ),
            if (_start != null && _end != null) ...[
              const SizedBox(height: 12),
              Text(
                '${periodLine(_start!, _end!, now)} · '
                '${inclusiveDays(_start!, _end!)} days',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              WorkNote(_error!, tone: WorkTone.warning),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : _go,
              child: Text(_busy ? 'Making it…' : 'Make timesheet'),
            ),
          ],
        ),
      ),
    );
  }
}
