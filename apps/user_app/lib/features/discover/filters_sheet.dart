import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../data/jobs_repository.dart';
import 'discover_controller.dart';

Future<void> showFiltersSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => const _FiltersSheet(),
  );
}

class _FiltersSheet extends ConsumerStatefulWidget {
  const _FiltersSheet();

  @override
  ConsumerState<_FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends ConsumerState<_FiltersSheet> {
  late JobFilters _draft;

  static const _workTypes = [
    ('full_time', 'Full-time'),
    ('part_time', 'Part-time'),
    ('daily_wage', 'Daily wage'),
    ('gig', 'Gig work'),
    ('contract', 'Contract'),
    ('temporary', 'Temporary'),
    ('internship', 'Internship'),
    ('apprenticeship', 'Apprenticeship'),
  ];

  static const _shifts = [
    ('day', 'Day'),
    ('evening', 'Evening'),
    ('night', 'Night'),
    ('early_morning', 'Early morning'),
    ('rotating', 'Rotating'),
    ('split', 'Split'),
    ('flexible', 'Flexible'),
  ];

  /// Pay filter thinks in monthly equivalents so a daily-wage job and a
  /// salaried job can be compared. Server-side `omelo_pay_monthly` does the
  /// conversion; this is only the UI scale.
  static const _paySteps = [0, 10000, 15000, 20000, 25000, 30000, 40000, 50000];

  @override
  void initState() {
    super.initState();
    _draft = ref.read(filtersProvider);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categories = ref.watch(categoriesProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
            child: Row(
              children: [
                const Text('Filters',
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(() => _draft = const JobFilters()),
                  child: const Text('Clear all'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                _section('Distance'),
                Text(
                  'Within ${_draft.radiusKm} km',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Slider(
                  value: _draft.radiusKm.toDouble(),
                  min: 2,
                  max: 100,
                  divisions: 49,
                  label: '${_draft.radiusKm} km',
                  onChanged: (v) =>
                      setState(() => _draft = _draft.copyWith(radiusKm: v.round())),
                ),
                Text(
                  'Distance is often the deciding factor. A job you cannot '
                  'reach is not a job.',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),

                _section('Minimum pay'),
                Text(
                  _draft.minPayMonthly == null
                      ? 'Any pay'
                      : '${Fmt.pay(min: _draft.minPayMonthly, currency: "INR", period: "month")} or more',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Compared as a monthly figure, so daily and hourly jobs '
                  'are included fairly.',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in _paySteps)
                      ChoiceChip(
                        label: Text(p == 0
                            ? 'Any'
                            : Fmt.pay(
                                min: p, currency: 'INR', period: 'month')),
                        selected: p == 0
                            ? _draft.minPayMonthly == null
                            : _draft.minPayMonthly == p,
                        onSelected: (_) => setState(() => _draft = p == 0
                            ? _draft.copyWith(clearPay: true)
                            : _draft.copyWith(minPayMonthly: p)),
                      ),
                  ],
                ),

                _section('Type of work'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (value, label) in _workTypes)
                      FilterChip(
                        label: Text(label),
                        showCheckmark: false,
                        selected: (_draft.workTypes ?? const []).contains(value),
                        onSelected: (sel) => setState(() {
                          final next = [...(_draft.workTypes ?? const <String>[])];
                          sel ? next.add(value) : next.remove(value);
                          _draft = _draft.copyWith(workTypes: next);
                        }),
                      ),
                  ],
                ),

                _section('Shift'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (value, label) in _shifts)
                      FilterChip(
                        label: Text(label),
                        showCheckmark: false,
                        selected: (_draft.shiftTypes ?? const []).contains(value),
                        onSelected: (sel) => setState(() {
                          final next = [...(_draft.shiftTypes ?? const <String>[])];
                          sel ? next.add(value) : next.remove(value);
                          _draft = _draft.copyWith(shiftTypes: next);
                        }),
                      ),
                  ],
                ),

                _section('Experience'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _draft.noExperienceOnly,
                  onChanged: (v) => setState(
                      () => _draft = _draft.copyWith(noExperienceOnly: v)),
                  title: const Text('Only jobs that need no experience'),
                  subtitle: const Text(
                      'Useful if this is your first job, or you are changing work'),
                ),

                _section('Category'),
                categories.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: LinearProgressIndicator(),
                  ),
                  error: (_, __) => const Text('Could not load categories'),
                  data: (cats) => Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('All'),
                        selected: _draft.categoryId == null,
                        onSelected: (_) => setState(
                            () => _draft = _draft.copyWith(clearCategory: true)),
                      ),
                      for (final c in cats)
                        ChoiceChip(
                          label: Text(c.name),
                          selected: _draft.categoryId == c.id,
                          onSelected: (_) => setState(() => _draft =
                              _draft.categoryId == c.id
                                  ? _draft.copyWith(clearCategory: true)
                                  : _draft.copyWith(categoryId: c.id)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    ref.read(filtersProvider.notifier).state = _draft;
                    Navigator.of(context).pop();
                  },
                  child: const Text('Show jobs'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 10),
        child: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      );
}
