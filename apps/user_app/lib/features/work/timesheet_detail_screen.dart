import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/responsive.dart';
import '../../data/work_repository.dart';
import 'work_widgets.dart';

/// `/work/timesheets/:id` — hours by day, extra time I added, totals and
/// status. A draft can get extra time and be sent; a sent-back one can be
/// fixed and sent again; anything else is read-only.
class TimesheetDetailScreen extends ConsumerWidget {
  const TimesheetDetailScreen({super.key, required this.timesheetId});
  final String timesheetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForWorkNotices(ref);
    final async = ref.watch(timesheetProvider(timesheetId));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Timesheet'),
        leading: workBackButton(context, '/work/timesheets'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(timesheetProvider(timesheetId));
          ref.invalidate(timesheetEntriesProvider(timesheetId));
          try {
            await ref.read(timesheetProvider(timesheetId).future);
          } catch (_) {}
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => RepresentationMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load this timesheet',
            body: workError(e),
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(timesheetProvider(timesheetId)),
          ),
          data: (t) => t == null
              ? RepresentationMessage(
                  icon: Icons.search_off,
                  title: 'Timesheet not found',
                  body: 'It may have been removed.',
                  actionLabel: 'See my timesheets',
                  onAction: () => context.go('/work/timesheets'),
                )
              : _Body(timesheet: t),
        ),
      ),
    );
  }
}

class _Body extends ConsumerStatefulWidget {
  const _Body({required this.timesheet});
  final Timesheet timesheet;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  bool _busy = false;

  void _reload() {
    final id = widget.timesheet.id;
    ref.invalidate(timesheetProvider(id));
    ref.invalidate(timesheetEntriesProvider(id));
    ref.invalidate(myTimesheetsProvider);
  }

  Future<void> _run(Future<void> Function() job, String done) async {
    setState(() => _busy = true);
    try {
      await job();
      _reload();
      if (mounted) showWorkSnack(context, done);
    } catch (e) {
      if (mounted) showWorkSnack(context, workError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rebuild(String done) {
    final t = widget.timesheet;
    return _run(
      () => ref
          .read(workRepositoryProvider)
          .buildTimesheet(t.assignmentId, t.periodStart, t.periodEnd),
      done,
    );
  }

  Future<void> _submit() async {
    final t = widget.timesheet;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send for approval?'),
        content: Text(
          'You will send ${hoursWords(t.totalMinutes)} for your supervisor '
          'to check. You cannot change it after sending.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _run(
      () => ref.read(workRepositoryProvider).submitTimesheet(t.id),
      'Sent for approval.',
    );
  }

  Future<void> _addTime() async {
    final added = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ExtraTimeSheet(timesheet: widget.timesheet),
    );
    if (added == true) {
      _reload();
      if (mounted) showWorkSnack(context, 'Extra time added.');
    }
  }

  Future<void> _remove(TimesheetEntry e) => _run(
    () => ref.read(workRepositoryProvider).removeEntry(e.id),
    'Extra time removed.',
  );

  @override
  Widget build(BuildContext context) {
    final t = widget.timesheet;
    final now = workNow(ref);
    final actions = timesheetActions(t);
    final entries = ref.watch(timesheetEntriesProvider(t.id));
    final assignments = ref.watch(myAssignmentsProvider).valueOrNull ?? const [];
    final title = assignments
        .where((a) => a.id == t.assignmentId)
        .map((a) => '${a.title} · ${a.employerName}')
        .firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    final gutter = Breakpoints.of(context).gutter;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 40),
      children: [
        ContentWidth.reading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                periodLine(t.periodStart, t.periodEnd, now),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (title != null)
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: WorkPill(
                  timesheetStatusLabel(t.status),
                  tone: timesheetTone(t.status),
                ),
              ),
              const SizedBox(height: 12),
              WorkNote(
                actions.note,
                tone: t.status == TimesheetStatus.rejected
                    ? WorkTone.warning
                    : WorkTone.neutral,
                icon: t.status == TimesheetStatus.locked
                    ? Icons.lock_outline
                    : null,
              ),
              const SizedBox(height: 14),
              _Totals(timesheet: t),
              WorkSection(
                title: 'Day by day',
                child: entries.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text(workError(e)),
                  data: (list) {
                    final days = entriesByDay(list);
                    if (days.isEmpty) {
                      return Text(
                        'No hours yet. Finished shifts in these days show '
                        'up here.',
                        style: TextStyle(
                          fontSize: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final d in days)
                          _DayCard(
                            day: d,
                            canRemove: actions.canAddTime && !_busy,
                            onRemove: _remove,
                          ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              if (actions.canAddTime)
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addTime,
                  icon: const Icon(Icons.more_time),
                  label: const Text('Add extra time'),
                ),
              if (actions.canRefresh) ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _rebuild('Updated from your shifts.'),
                  icon: const Icon(Icons.refresh),
                  label: const Text('Update from my shifts'),
                ),
              ],
              if (actions.canSubmit) ...[
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _busy ? null : _submit,
                  icon: const Icon(Icons.send),
                  label: const Text('Send for approval'),
                ),
              ],
              if (actions.canReopen)
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _rebuild(
                          'Ready to fix. Check the hours, then send it again.',
                        ),
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Fix and send again'),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.timesheet});
  final Timesheet timesheet;

  @override
  Widget build(BuildContext context) {
    final t = timesheet;
    final scheme = Theme.of(context).colorScheme;
    Widget cell(String label, String value) => Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        cell('Total', hoursWords(t.totalMinutes)),
        cell('Regular', hoursWords(t.regularMinutes)),
        if (t.overtimeMinutes > 0) cell('Overtime', hoursWords(t.overtimeMinutes)),
        cell('Days', '${t.daysWorked}'),
        cell('Shifts', '${t.shiftsWorked}'),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.canRemove,
    required this.onRemove,
  });
  final TimesheetDay day;
  final bool canRemove;
  final Future<void> Function(TimesheetEntry) onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('EEE d MMM').format(day.day),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    hoursWords(day.minutes),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            for (final e in day.entries)
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Row(
                  children: [
                    Icon(
                      switch (e.kind) {
                        'manual' => Icons.more_time,
                        'leave' => Icons.beach_access_outlined,
                        _ => Icons.work_outline,
                      },
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        [
                          '${entryKindLabel(e.kind)} · ${hoursWords(e.minutes)}',
                          ?e.note,
                        ].join('\n'),
                        style: const TextStyle(fontSize: 14.5, height: 1.35),
                      ),
                    ),
                    if (e.isMine && canRemove)
                      IconButton(
                        tooltip: 'Remove this extra time',
                        style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => onRemove(e),
                        icon: const Icon(Icons.close),
                      )
                    else
                      const SizedBox(width: 8),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Extra time for one day of the timesheet, with a note saying what it was
/// for.
class ExtraTimeSheet extends ConsumerStatefulWidget {
  const ExtraTimeSheet({super.key, required this.timesheet});
  final Timesheet timesheet;

  @override
  ConsumerState<ExtraTimeSheet> createState() => _ExtraTimeSheetState();
}

class _ExtraTimeSheetState extends ConsumerState<ExtraTimeSheet> {
  late DateTime _day;
  int? _minutes;
  final _custom = TextEditingController();
  final _note = TextEditingController();
  bool _busy = false;
  String? _error;

  static const _quick = [30, 60, 120, 240, 480];

  @override
  void initState() {
    super.initState();
    final t = widget.timesheet;
    final today = DateTime.now();
    final d = DateTime(today.year, today.month, today.day);
    _day = d.isBefore(t.periodStart) || d.isAfter(t.periodEnd)
        ? t.periodStart
        : d;
  }

  @override
  void dispose() {
    _custom.dispose();
    _note.dispose();
    super.dispose();
  }

  List<DateTime> get _days {
    final t = widget.timesheet;
    final n = inclusiveDays(t.periodStart, t.periodEnd);
    return [
      for (var i = 0; i < n; i++)
        DateTime(t.periodStart.year, t.periodStart.month, t.periodStart.day + i),
    ];
  }

  Future<void> _save() async {
    final minutes = _custom.text.trim().isEmpty
        ? _minutes
        : parseDurationInput(_custom.text);
    final problem = validateExtraTime(minutes, _note.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(workRepositoryProvider)
          .addEntry(widget.timesheet.id, _day, minutes!, _note.text);
      if (mounted) Navigator.pop(context, true);
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
              'Add extra time',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            const Text(
              'For time you worked that is not in your shifts. Your '
              'supervisor checks it.',
              style: TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<DateTime>(
              value: _day,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Day'),
              items: [
                for (final d in _days)
                  DropdownMenuItem(
                    value: d,
                    child: Text(DateFormat('EEE d MMM').format(d)),
                  ),
              ],
              onChanged: (v) => setState(() => _day = v ?? _day),
            ),
            const SizedBox(height: 14),
            const Text(
              'How long?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in _quick)
                  ChoiceChip(
                    label: Text(hoursWords(m)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    selected: _minutes == m && _custom.text.trim().isEmpty,
                    onSelected: (_) => setState(() {
                      _minutes = m;
                      _custom.clear();
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _custom,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Or type the hours',
                hintText: 'e.g. 1:30 or 1.5',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _note,
              maxLength: kEntryNoteMax,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'What was it for?',
                hintText: 'e.g. Stayed late to finish unloading',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              WorkNote(_error!, tone: WorkTone.warning),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Adding…' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }
}
