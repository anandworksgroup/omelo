import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/responsive.dart';
import '../../data/work_repository.dart';
import 'work_widgets.dart';

/// `/work/leave` — ask for time off, see what was decided, cancel a request
/// that is still waiting. `?assignment=<id>` starts a request for that work.
class LeaveScreen extends ConsumerWidget {
  const LeaveScreen({super.key, this.assignmentId});
  final String? assignmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForWorkNotices(ref);
    final async = ref.watch(myLeaveProvider);
    final assignments =
        ref.watch(myAssignmentsProvider).valueOrNull ?? const <Assignment>[];
    final now = workNow(ref);
    final titles = {for (final a in assignments) a.id: a.title};
    final eligible = assignments
        .where((a) => assignmentActions(a, now).canRequestLeave)
        .toList();

    Future<void> ask() async {
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => LeaveRequestSheet(
          assignments: eligible,
          initialAssignment: assignmentId,
          now: now,
        ),
      );
      if (ok == true) {
        ref.invalidate(myLeaveProvider);
        if (context.mounted) {
          showWorkSnack(context, 'Request sent. You will be told the answer.');
        }
      }
    }

    Future<void> cancel(LeaveRequest l) async {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cancel this request?'),
          content: Text(
            '${l.title} · ${leaveDaysLine(l.startDate, l.endDate, now)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keep it'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel request'),
            ),
          ],
        ),
      );
      if (go != true) return;
      try {
        await ref.read(workRepositoryProvider).cancelLeave(l.id);
        ref.invalidate(myLeaveProvider);
        if (context.mounted) showWorkSnack(context, 'Request cancelled.');
      } catch (e) {
        if (context.mounted) showWorkSnack(context, workError(e));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Time off'),
        leading: workBackButton(context, '/work'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myLeaveProvider);
          try {
            await ref.read(myLeaveProvider.future);
          } catch (_) {}
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => RepresentationMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load your time off',
            body: workError(e),
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(myLeaveProvider),
          ),
          data: (list) {
            final gutter = Breakpoints.of(context).gutter;
            final scheme = Theme.of(context).colorScheme;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                ContentWidth.reading(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (eligible.isNotEmpty)
                        FilledButton.icon(
                          onPressed: ask,
                          icon: const Icon(Icons.add),
                          label: const Text('Ask for time off'),
                        )
                      else
                        Text(
                          'You can ask for time off once you have accepted '
                          'work.',
                          style: TextStyle(
                            fontSize: 15,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 16),
                      if (list.isEmpty)
                        Text(
                          'No requests yet.',
                          style: TextStyle(
                            fontSize: 15.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      for (final l in list)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _LeaveCard(
                            leave: l,
                            workTitle: titles[l.assignmentId],
                            now: now,
                            onCancel: () => cancel(l),
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

class _LeaveCard extends StatelessWidget {
  const _LeaveCard({
    required this.leave,
    required this.workTitle,
    required this.now,
    required this.onCancel,
  });
  final LeaveRequest leave;
  final String? workTitle;
  final DateTime now;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l = leave;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l.title,
                        style: const TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        leaveDaysLine(l.startDate, l.endDate, now),
                        style: const TextStyle(fontSize: 15),
                      ),
                      if (workTitle != null)
                        Text(
                          workTitle!,
                          style: TextStyle(
                            fontSize: 13.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                WorkPill(leaveStatusLabel(l.status), tone: leaveTone(l.status)),
              ],
            ),
            if (l.reason != null) ...[
              const SizedBox(height: 6),
              Text(
                l.reason!,
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
            ],
            if (l.reviewNote != null) ...[
              const SizedBox(height: 8),
              WorkNote(
                'Note from your employer: ${l.reviewNote}',
                icon: Icons.chat_bubble_outline,
              ),
            ],
            if (l.canCancel) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: onCancel,
                child: const Text('Cancel request'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Type, the local name for it (optional), the days and a reason.
class LeaveRequestSheet extends ConsumerStatefulWidget {
  const LeaveRequestSheet({
    super.key,
    required this.assignments,
    required this.now,
    this.initialAssignment,
  });
  final List<Assignment> assignments;
  final DateTime now;
  final String? initialAssignment;

  @override
  ConsumerState<LeaveRequestSheet> createState() => _LeaveRequestSheetState();
}

class _LeaveRequestSheetState extends ConsumerState<LeaveRequestSheet> {
  late String? _assignment =
      widget.assignments.any((a) => a.id == widget.initialAssignment)
      ? widget.initialAssignment
      : (widget.assignments.isEmpty ? null : widget.assignments.first.id);
  LeaveType _type = LeaveType.paid;
  DateTime? _start;
  DateTime? _end;
  final _label = TextEditingController();
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _label.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pick({required bool first}) async {
    final now = widget.now;
    final initial = (first ? _start : _end) ?? _start ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: first ? 'First day off' : 'Last day off',
    );
    if (d == null) return;
    setState(() {
      if (first) {
        _start = d;
        if (_end == null || _end!.isBefore(d)) _end = d;
      } else {
        _end = d;
      }
      _error = null;
    });
  }

  Future<void> _send() async {
    final problem = _assignment == null
        ? 'Pick the work first.'
        : validateLeaveDates(_start, _end);
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
          .requestLeave(
            assignmentId: _assignment!,
            type: _type,
            start: _start!,
            end: _end!,
            reason: _reason.text,
            label: _label.text,
          );
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
    final fmt = DateFormat('EEE d MMM yyyy');
    Widget dateButton(String label, DateTime? value, bool first) => Expanded(
      child: OutlinedButton(
        onPressed: () => _pick(first: first),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: const TextStyle(fontSize: 12.5)),
            Text(
              value == null ? 'Pick' : fmt.format(value),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );

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
              'Ask for time off',
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
              'What kind?',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final t in LeaveType.values)
                  ChoiceChip(
                    label: Text(t.label),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    selected: _type == t,
                    onSelected: (_) => setState(() => _type = t),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _label,
              maxLength: kLeaveLabelMax,
              decoration: const InputDecoration(
                labelText: 'Name used where you work (optional)',
                hintText: 'e.g. Casual leave, Annual leave',
                counterText: '',
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                dateButton('First day', _start, true),
                const SizedBox(width: 10),
                dateButton('Last day', _end, false),
              ],
            ),
            if (_start != null && _end != null && !_end!.isBefore(_start!))
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  leaveDaysLine(_start!, _end!, widget.now),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _reason,
              maxLength: kLeaveReasonMax,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              WorkNote(_error!, tone: WorkTone.warning),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: Text(_busy ? 'Sending…' : 'Send request'),
            ),
          ],
        ),
      ),
    );
  }
}
