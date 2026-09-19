import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/career_repository.dart';
import 'career_widgets.dart';

/// The development plan for one goal: tick steps off, start one, dismiss or
/// restore it, or add your own. Status changes show at once and are saved
/// in the background (a failure puts the step back and says why).
class PlanChecklist extends ConsumerStatefulWidget {
  const PlanChecklist({
    super.key,
    required this.goalId,
    required this.items,
    required this.onChanged,
    this.identityId,
    this.skillNames = const {},
  });

  final String goalId;
  final List<PlanItem> items;

  /// Called after a step was added, so the path reloads.
  final VoidCallback onChanged;
  final String? identityId;

  /// Skill names by id, for opening a test from an assessment step.
  final Map<String, String> skillNames;

  @override
  ConsumerState<PlanChecklist> createState() => _PlanChecklistState();
}

class _PlanChecklistState extends ConsumerState<PlanChecklist> {
  final _overrides = <String, PlanStatus>{};
  bool _showDismissed = false;
  bool _adding = false;

  List<PlanItem> get _items => [
    for (final i in widget.items)
      _overrides.containsKey(i.id) ? i.withStatus(_overrides[i.id]!) : i,
  ];

  @override
  void didUpdateWidget(PlanChecklist old) {
    super.didUpdateWidget(old);
    // Fresh rows from the server replace what was shown optimistically.
    if (!identical(old.items, widget.items)) _overrides.clear();
  }

  Future<void> _setStatus(PlanItem item, PlanStatus s) async {
    final before = _overrides[item.id];
    setState(() => _overrides[item.id] = s);
    try {
      await ref.read(careerRepositoryProvider).setPlanStatus(item.id, s);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (before == null) {
          _overrides.remove(item.id);
        } else {
          _overrides[item.id] = before;
        }
      });
      showCareerSnack(context, careerError(e));
    }
  }

  Future<void> _addStep() async {
    final title = await showDialog<String>(
      context: context,
      builder: (_) => const _AddStepDialog(),
    );
    if (title == null || !mounted) return;
    setState(() => _adding = true);
    try {
      await ref.read(careerRepositoryProvider).addPlanItem(
        goalId: widget.goalId,
        kind: PlanKind.custom,
        title: title,
        position: nextPlanPosition(widget.items),
      );
      widget.onChanged();
      if (mounted) showCareerSnack(context, 'Step added to your plan.');
    } catch (e) {
      if (mounted) showCareerSnack(context, careerError(e));
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  void _open(PlanItem i) {
    if (i.kind == PlanKind.job && i.jobId != null) {
      context.push('/job/${i.jobId}?from=recommended');
    } else if ((i.kind == PlanKind.assessment) && i.skillId != null) {
      openAssessment(
        context,
        skillId: i.skillId!,
        skillName: widget.skillNames[i.skillId] ?? i.title,
        identityId: widget.identityId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = _items;
    final live = items.where((i) => !i.isDismissed).toList();
    final dismissed = items.where((i) => i.isDismissed).toList();
    final p = planProgress(items);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (p.total > 0) ...[
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: p.total == 0 ? 0 : p.done / p.total,
                    minHeight: 6,
                    backgroundColor: scheme.surfaceContainerHighest,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${p.done} of ${p.total} done',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        if (live.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'No steps yet. Add one below, or add a course or job from '
              'this page.',
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            ),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                for (var n = 0; n < live.length; n++) ...[
                  if (n > 0) const Divider(height: 1),
                  _StepRow(
                    item: live[n],
                    onToggle: () =>
                        _setStatus(live[n], toggledStatus(live[n].status)),
                    onStatus: (s) => _setStatus(live[n], s),
                    onOpen: _canOpen(live[n]) ? () => _open(live[n]) : null,
                  ),
                ],
              ],
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: _adding ? null : _addStep,
              icon: const Icon(Icons.add),
              label: Text(_adding ? 'Adding…' : 'Add a step'),
            ),
            if (dismissed.isNotEmpty)
              TextButton(
                onPressed: () => setState(() => _showDismissed = !_showDismissed),
                child: Text(_showDismissed
                    ? 'Hide dismissed steps'
                    : 'Show dismissed steps (${dismissed.length})'),
              ),
          ],
        ),
        if (_showDismissed)
          for (final d in dismissed)
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: Icon(Icons.remove_circle_outline, color: scheme.outline),
              title: Text(
                d.title,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  decoration: TextDecoration.lineThrough,
                ),
              ),
              trailing: TextButton(
                onPressed: () => _setStatus(d, PlanStatus.todo),
                child: const Text('Restore'),
              ),
            ),
      ],
    );
  }

  bool _canOpen(PlanItem i) =>
      (i.kind == PlanKind.job && i.jobId != null) ||
      (i.kind == PlanKind.assessment && i.skillId != null);
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.item,
    required this.onToggle,
    required this.onStatus,
    this.onOpen,
  });

  final PlanItem item;
  final VoidCallback onToggle;
  final ValueChanged<PlanStatus> onStatus;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final i = item;
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 0, 4),
        child: Row(
          children: [
            Checkbox(
              value: i.isDone,
              onChanged: (_) => onToggle(),
              semanticLabel: i.isDone ? 'Mark "${i.title}" not done' : 'Mark "${i.title}" done',
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    i.title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      decoration: i.isDone ? TextDecoration.lineThrough : null,
                      color: i.isDone ? scheme.onSurfaceVariant : null,
                    ),
                  ),
                  if (i.status == PlanStatus.inProgress || onOpen != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Wrap(
                        spacing: 6,
                        children: [
                          if (i.status == PlanStatus.inProgress)
                            OmeloPill(
                              'In progress',
                              color: scheme.onPrimaryContainer,
                              background: scheme.primaryContainer,
                            ),
                          if (onOpen != null)
                            Text(
                              i.kind == PlanKind.job ? 'See the job' : 'Start the test',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: scheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<PlanStatus>(
              tooltip: 'More for this step',
              onSelected: onStatus,
              itemBuilder: (_) => [
                if (i.status != PlanStatus.inProgress && !i.isDone)
                  const PopupMenuItem(
                    value: PlanStatus.inProgress,
                    child: Text('I have started this'),
                  ),
                if (i.isDone || i.status == PlanStatus.inProgress)
                  const PopupMenuItem(value: PlanStatus.todo, child: Text('Not started')),
                const PopupMenuItem(value: PlanStatus.dismissed, child: Text('Dismiss')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AddStepDialog extends StatefulWidget {
  const _AddStepDialog();

  @override
  State<_AddStepDialog> createState() => _AddStepDialogState();
}

class _AddStepDialogState extends State<_AddStepDialog> {
  final _c = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _save() {
    final e = validateStepTitle(_c.text);
    if (e != null) {
      setState(() => _error = e);
      return;
    }
    Navigator.of(context).pop(_c.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Add a step'),
    content: TextField(
      controller: _c,
      autofocus: true,
      maxLength: 200,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        hintText: 'e.g. Ask my supervisor about PLC training',
        errorText: _error,
      ),
      onSubmitted: (_) => _save(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _save, child: const Text('Add')),
    ],
  );
}
