import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/career_repository.dart';
import '../../data/global_repository.dart' show Country, countriesProvider;
import '../../data/identity_repository.dart'
    show TaxonomyHit, identityRepositoryProvider;
import '../../data/work.dart' show payPeriodWords;
import '../../data/invitations.dart' show shortDate;
import '../global/global_widgets.dart' show CountryChips;
import '../identities/search_picker.dart';
import 'career_widgets.dart';

/// Picks a target role from the profession list.
Future<TaxonomyHit?> pickProfession(BuildContext context, WidgetRef ref) =>
    showSearchPicker(
      context,
      title: 'Choose the role you are aiming for',
      hint: 'Role, e.g. Industrial Electrician',
      search: (q) => ref.read(identityRepositoryProvider).searchProfessions(q),
    );

/// Opens the goal form. Returns the saved goal, or null when cancelled.
Future<CareerGoal?> showGoalEditor(
  BuildContext context, {
  required GoalDraft initial,
}) => showModalBottomSheet<CareerGoal>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  showDragHandle: true,
  builder: (_) => GoalEditorSheet(initial: initial),
);

class GoalEditorSheet extends ConsumerStatefulWidget {
  const GoalEditorSheet({super.key, required this.initial});
  final GoalDraft initial;

  @override
  ConsumerState<GoalEditorSheet> createState() => _GoalEditorSheetState();
}

class _GoalEditorSheetState extends ConsumerState<GoalEditorSheet> {
  late String? _professionId = widget.initial.professionId;
  late String? _professionName = widget.initial.professionName;
  late List<String> _countries = widget.initial.targetCountries;
  late final _pay = TextEditingController(
    text: widget.initial.targetPayAmount?.toString() ?? '',
  );
  late String _period = widget.initial.targetPayPeriod ?? 'month';
  late String? _currency = widget.initial.targetCurrency;
  late DateTime? _date = widget.initial.targetDate;
  late final _note = TextEditingController(text: widget.initial.goalText ?? '');
  late bool _plan = widget.initial.generatePlan;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.initial.id == null;

  @override
  void dispose() {
    _pay.dispose();
    _note.dispose();
    super.dispose();
  }

  /// The currency a worker most likely means: the one target country's,
  /// else her home country's.
  String? _suggestedCurrency(List<Country> countries) {
    String? cur(String? code) =>
        countries.where((c) => c.code == code).firstOrNull?.currency;
    if (_countries.length == 1) return cur(_countries.single);
    return cur(ref.read(homeCountryProvider));
  }

  GoalDraft _draft(List<Country> countries) {
    final amount = parseAmount(_pay.text);
    return GoalDraft(
      id: widget.initial.id,
      workIdentityId: widget.initial.workIdentityId,
      professionId: _professionId,
      professionName: _professionName,
      goalText: _note.text,
      targetCountries: _countries,
      targetPayAmount: amount,
      targetPayPeriod: _period,
      targetCurrency: amount == null ? null : (_currency ?? _suggestedCurrency(countries)),
      targetDate: _date,
      generatePlan: _plan,
    );
  }

  Future<void> _save(List<Country> countries) async {
    if (_pay.text.trim().isNotEmpty && parseAmount(_pay.text) == null) {
      setState(() => _error = 'Write the target pay as a number, e.g. 30000.');
      return;
    }
    final d = _draft(countries);
    final problem = validateGoal(d, now: ref.read(careerClockProvider)());
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref.read(careerRepositoryProvider).saveGoal(d);
      if (mounted) Navigator.of(context).pop(saved);
    } catch (e) {
      if (mounted) setState(() => _error = careerError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickCurrency(List<Country> countries) async {
    final codes = {
      for (final c in countries)
        if (c.currency != null) c.currency!,
    }.toList()
      ..sort();
    final hit = await showSearchPicker(
      context,
      title: 'Currency',
      hint: 'Code, e.g. EUR',
      search: (q) async => [
        for (final c in codes)
          if (q.trim().isEmpty || c.toLowerCase().contains(q.trim().toLowerCase()))
            TaxonomyHit(id: c, name: c),
      ],
    );
    if (hit != null) setState(() => _currency = hit.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final countries = ref.watch(countriesProvider).valueOrNull ?? const <Country>[];
    final now = ref.watch(careerClockProvider)();
    final currency = _currency ?? _suggestedCurrency(countries);
    final inset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Center(
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(
                _isNew ? 'Set a career goal' : 'Edit your goal',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),
              const _Label('Role you are aiming for'),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: Text(
                    _professionName ?? 'Choose a role',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: _professionName == null ? scheme.primary : null,
                    ),
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () async {
                    final hit = await pickProfession(context, ref);
                    if (hit != null) {
                      setState(() {
                        _professionId = hit.id;
                        _professionName = hit.name;
                      });
                    }
                  },
                ),
              ),
              const SizedBox(height: 16),
              const _Label('Countries you want to work in (optional)'),
              CountryChips(
                codes: _countries,
                countries: countries,
                max: 5,
                addLabel: 'Add country',
                pickerTitle: 'Where do you want to work?',
                onChanged: (v) => setState(() => _countries = v),
              ),
              const SizedBox(height: 16),
              const _Label('Target pay (optional)'),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _pay,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        hintText: 'Amount',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      value: _period,
                      isExpanded: true,
                      decoration: const InputDecoration(border: OutlineInputBorder()),
                      items: [
                        for (final p in kGoalPayPeriods)
                          DropdownMenuItem(value: p, child: Text(payPeriodWords(p))),
                      ],
                      onChanged: (v) => setState(() => _period = v ?? 'month'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    height: 56,
                    child: OutlinedButton(
                      onPressed: () => _pickCurrency(countries),
                      child: Text(currency ?? 'Currency'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const _Label('Target date (optional)'),
              Row(
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.event_outlined),
                    label: Text(_date == null ? 'Choose a date' : shortDate(_date!, now)),
                    onPressed: () async {
                      final today = DateTime(now.year, now.month, now.day);
                      final d = await showDatePicker(
                        context: context,
                        initialDate: _date != null && !_date!.isBefore(today)
                            ? _date!
                            : today.add(const Duration(days: 365)),
                        firstDate: today,
                        lastDate: DateTime(now.year + 15),
                      );
                      if (d != null) setState(() => _date = d);
                    },
                  ),
                  if (_date != null)
                    IconButton(
                      tooltip: 'Clear the date',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _date = null),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const _Label('Note to yourself (optional)'),
              TextField(
                controller: _note,
                maxLength: 500,
                maxLines: 3,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'e.g. Move to a factory job with day shifts',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_isNew)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _plan,
                  onChanged: (v) => setState(() => _plan = v),
                  title: const Text('Make a plan from my skill gap'),
                  subtitle: const Text('One step for each skill to build. You can change it.'),
                ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: scheme.error, fontWeight: FontWeight.w600)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : () => _save(countries),
                child: Text(_saving ? 'Saving…' : (_isNew ? 'Set my goal' : 'Save changes')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
  );
}
