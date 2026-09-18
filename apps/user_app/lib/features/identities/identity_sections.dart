import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../../core/theme.dart';
import '../../data/identity_repository.dart';
import 'identity_widgets.dart';
import 'search_picker.dart';

// ---------------------------------------------------------------------------
// Skills
// ---------------------------------------------------------------------------

class SkillsSection extends ConsumerWidget {
  const SkillsSection({super.key, required this.identityId});
  final String identityId;

  void _refresh(WidgetRef ref) {
    ref.invalidate(identitySkillsProvider(identityId));
    invalidateIdentities(ref, identityId);
  }

  Future<void> _add(BuildContext context, WidgetRef ref,
      List<PersonSkill> current) async {
    final repo = ref.read(identityRepositoryProvider);
    final hit = await showSearchPicker(
      context,
      title: 'Add a skill',
      hint: 'For example: driving, cooking, wiring',
      search: repo.searchSkills,
    );
    if (hit == null || !context.mounted) return;
    if (current.any((s) => s.skillId == hit.id)) {
      showSnack(context, '${hit.name} is already on this identity.');
      return;
    }
    final detail = await _showSkillDetail(context, name: hit.name);
    if (detail == null || !context.mounted) return;
    try {
      await repo.addSkill(identityId, hit.id,
          proficiency: detail.proficiency, monthsUsed: detail.monthsUsed);
      _refresh(ref);
    } catch (e) {
      if (context.mounted) {
        showSnack(
            context,
            e is PostgrestException && e.code == '23505'
                ? '${hit.name} is already on this identity.'
                : identityError(e));
      }
    }
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, PersonSkill s) async {
    final detail = await _showSkillDetail(context,
        name: s.name,
        proficiency: s.proficiency,
        monthsUsed: s.monthsUsed,
        canRemove: true);
    if (detail == null || !context.mounted) return;
    final repo = ref.read(identityRepositoryProvider);
    try {
      if (detail.remove) {
        await repo.removeSkill(s.id);
      } else {
        await repo.updateSkill(s.id,
            proficiency: detail.proficiency, monthsUsed: detail.monthsUsed);
      }
      _refresh(ref);
    } catch (e) {
      if (context.mounted) showSnack(context, identityError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skills = ref.watch(identitySkillsProvider(identityId));
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Skills',
            subtitle: 'Add at least 3. Say how good you are and for how long.'),
        skills.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              Text(identityError(e), style: TextStyle(color: scheme.error)),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('No skills yet.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              for (final s in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      minTileHeight: 60,
                      title: Text(s.name,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w700)),
                      subtitle: Text(
                        [
                          if (s.proficiency != null)
                            kProficiencyLabels[s.proficiency] ?? s.proficiency!,
                          if ((s.monthsUsed ?? 0) > 0) monthsLabel(s.monthsUsed),
                          if (s.isShared) 'On all identities',
                        ].join(' · ').ifEmpty('Tap to add your level'),
                      ),
                      trailing: s.isVerified
                          ? const Tooltip(
                              message: 'Verified by Omelo',
                              child: Icon(Icons.verified,
                                  color: OmeloTheme.verified))
                          : const Icon(Icons.edit_outlined),
                      onTap: s.isVerified || s.isShared
                          ? null
                          : () => _edit(context, ref, s),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => _add(context, ref, list),
                icon: const Icon(Icons.add),
                label: const Text('Add a skill'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

class _SkillDetail {
  const _SkillDetail({this.proficiency, this.monthsUsed, this.remove = false});
  final String? proficiency;
  final int? monthsUsed;
  final bool remove;
}

Future<_SkillDetail?> _showSkillDetail(
  BuildContext context, {
  required String name,
  String? proficiency,
  int? monthsUsed,
  bool canRemove = false,
}) {
  return showModalBottomSheet<_SkillDetail>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 700),
    builder: (ctx) {
      var level = proficiency;
      var months = monthsUsed;
      return StatefulBuilder(
        builder: (ctx, setState) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(name,
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 18),
              const Text('How good are you?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in kProficiencyLabels.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    selected: level == e.key,
                    onSelected: (on) =>
                        setState(() => level = on ? e.key : null),
                  ),
              ]),
              const SizedBox(height: 18),
              const Text('How long have you used it?',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final e in {
                  ...kMonthsUsedChoices,
                  if (months != null && !kMonthsUsedChoices.containsKey(months))
                    months!: monthsLabel(months),
                }.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    selected: months == e.key,
                    onSelected: (on) =>
                        setState(() => months = on ? e.key : null),
                  ),
              ]),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pop(
                    ctx, _SkillDetail(proficiency: level, monthsUsed: months)),
                child: const Text('Save'),
              ),
              if (canRemove) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: OmeloTheme.danger),
                  onPressed: () =>
                      Navigator.pop(ctx, const _SkillDetail(remove: true)),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove this skill'),
                ),
              ],
            ],
          ),
        ),
      );
    },
  );
}

// ---------------------------------------------------------------------------
// Experience
// ---------------------------------------------------------------------------

class ExperienceSection extends ConsumerWidget {
  const ExperienceSection({
    super.key,
    required this.identityId,
    this.professionId,
  });
  final String identityId;
  final String? professionId;

  static String range(Experience x) {
    final f = DateFormat.yMMM();
    final from = x.startedOn == null ? null : f.format(x.startedOn!);
    final to = x.isCurrent
        ? 'now'
        : (x.endedOn == null ? null : f.format(x.endedOn!));
    if (from == null && to == null) return '';
    return '${from ?? '?'} – ${to ?? '?'}';
  }

  Future<void> _open(BuildContext context, WidgetRef ref, [Experience? x]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: 700),
      builder: (_) => _ExperienceForm(
          identityId: identityId, professionId: professionId, existing: x),
    );
    if (saved == true) {
      ref.invalidate(identityExperiencesProvider(identityId));
      invalidateIdentities(ref, identityId);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(identityExperiencesProvider(identityId));
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Work experience',
            subtitle: 'Paid or unpaid, formal or not — it all counts.'),
        list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              Text(identityError(e), style: TextStyle(color: scheme.error)),
          data: (items) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                      'Nothing yet. First job? Set "Years of experience" to 0 '
                      'above instead.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              for (final x in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Card(
                    child: ListTile(
                      minTileHeight: 64,
                      title: Text(x.title,
                          style: const TextStyle(
                              fontSize: 15.5, fontWeight: FontWeight.w700)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text([x.employerName, range(x)]
                              .where((s) => s.isNotEmpty)
                              .join(' · ')),
                          if (x.isVerified)
                            const Padding(
                              padding: EdgeInsets.only(top: 4),
                              child: OmeloPill('Verified by Omelo',
                                  icon: Icons.verified,
                                  color: OmeloTheme.verified),
                            ),
                        ],
                      ),
                      trailing: x.isVerified
                          ? const Icon(Icons.lock_outline)
                          : const Icon(Icons.edit_outlined),
                      onTap: x.isVerified ? null : () => _open(context, ref, x),
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => _open(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add experience'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExperienceForm extends ConsumerStatefulWidget {
  const _ExperienceForm({
    required this.identityId,
    this.professionId,
    this.existing,
  });
  final String identityId;
  final String? professionId;
  final Experience? existing;

  @override
  ConsumerState<_ExperienceForm> createState() => _ExperienceFormState();
}

class _ExperienceFormState extends ConsumerState<_ExperienceForm> {
  late final _title = TextEditingController(text: widget.existing?.title);
  late final _employer =
      TextEditingController(text: widget.existing?.employerName);
  late final _desc = TextEditingController(text: widget.existing?.description);
  late DateTime? _from = widget.existing?.startedOn;
  late DateTime? _to = widget.existing?.endedOn;
  late bool _current = widget.existing?.isCurrent ?? false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _employer.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<DateTime?> _pick(DateTime? initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(1950),
      lastDate: now,
      initialDatePickerMode: DatePickerMode.year,
    );
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _employer.text.trim().isEmpty) {
      setState(() => _error = 'Add the job and who you worked for.');
      return;
    }
    if (_from != null && _to != null && !_current && _to!.isBefore(_from!)) {
      setState(() => _error = 'The end date is before the start date.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(identityRepositoryProvider).saveExperience(
            widget.identityId,
            id: widget.existing?.id,
            professionId: widget.professionId,
            employerName: _employer.text,
            title: _title.text,
            startedOn: _from,
            endedOn: _to,
            isCurrent: _current,
            description: _desc.text,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = identityError(e);
        });
      }
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(identityRepositoryProvider)
          .deleteExperience(widget.existing!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = identityError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final f = DateFormat.yMMM();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? 'Add experience' : 'Edit experience',
                style:
                    const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 16),
            TextField(
              controller: _title,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Job'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _employer,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                  labelText: 'Who you worked for',
                  hintText: 'A company, a family, or "Self-employed"'),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    final d = await _pick(_from);
                    if (d != null) setState(() => _from = d);
                  },
                  child: Text(_from == null ? 'Started' : f.format(_from!)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _current
                      ? null
                      : () async {
                          final d = await _pick(_to);
                          if (d != null) setState(() => _to = d);
                        },
                  child: Text(_current
                      ? 'Still working here'
                      : (_to == null ? 'Ended' : f.format(_to!))),
                ),
              ),
            ]),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('I still work here'),
              value: _current,
              onChanged: (v) => setState(() => _current = v),
            ),
            TextField(
              controller: _desc,
              maxLines: 4,
              minLines: 2,
              maxLength: 1000,
              decoration:
                  const InputDecoration(labelText: 'What you did (optional)'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Saving…' : 'Save'),
            ),
            if (widget.existing != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style:
                    OutlinedButton.styleFrom(foregroundColor: OmeloTheme.danger),
                onPressed: _busy ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preferences and places
// ---------------------------------------------------------------------------

class PreferencesSection extends ConsumerStatefulWidget {
  const PreferencesSection({super.key, required this.identityId});
  final String identityId;

  @override
  ConsumerState<PreferencesSection> createState() => _PreferencesSectionState();
}

class _PreferencesSectionState extends ConsumerState<PreferencesSection> {
  WorkPreferences? _prefs;
  final _pay = TextEditingController();
  bool _dirty = false;
  bool _busy = false;

  @override
  void dispose() {
    _pay.dispose();
    super.dispose();
  }

  void _adopt(WorkPreferences p) {
    if (_dirty || identical(_prefs, p)) return;
    _prefs = p;
    final a = p.expectedPayAmount;
    final text = a == null
        ? ''
        : (a == a.roundToDouble() ? a.round().toString() : a.toString());
    if (_pay.text != text) _pay.text = text;
  }

  void _change(WorkPreferences p) => setState(() {
        _prefs = p;
        _dirty = true;
      });

  WorkPreferences _copy({
    String? availability,
    List<String>? workTypes,
    List<String>? shiftTypes,
    String? period,
  }) {
    final p = _prefs!;
    return WorkPreferences(
      availability: availability ?? p.availability,
      workTypes: workTypes ?? p.workTypes,
      shiftTypes: shiftTypes ?? p.shiftTypes,
      expectedPayAmount: p.expectedPayAmount,
      expectedPayPeriod: period ?? p.expectedPayPeriod,
      payCurrency: p.payCurrency,
    );
  }

  Future<void> _save() async {
    final raw = _pay.text.trim().replaceAll(',', '');
    final amount = raw.isEmpty ? null : num.tryParse(raw);
    if (raw.isNotEmpty && (amount == null || amount < 0)) {
      showSnack(context, 'Enter the pay as a number.');
      return;
    }
    final p = _prefs!;
    final next = WorkPreferences(
      availability: p.availability,
      workTypes: p.workTypes,
      shiftTypes: p.shiftTypes,
      expectedPayAmount: amount,
      expectedPayPeriod: p.expectedPayPeriod ?? 'month',
      payCurrency: p.payCurrency,
    );
    setState(() => _busy = true);
    try {
      await ref
          .read(identityRepositoryProvider)
          .savePreferences(widget.identityId, next);
      _dirty = false;
      ref.invalidate(identityPreferencesProvider(widget.identityId));
      invalidateIdentities(ref, widget.identityId);
      if (mounted) showSnack(context, 'Saved.');
    } catch (e) {
      if (mounted) showSnack(context, identityError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(identityPreferencesProvider(widget.identityId));
    final scheme = Theme.of(context).colorScheme;

    Widget chips(Map<String, String> labels, List<String> picked,
            ValueChanged<List<String>> onChanged) =>
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in labels.entries)
            FilterChip(
              label: Text(e.value),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              selected: picked.contains(e.key),
              onSelected: (on) => onChanged(on
                  ? [...picked, e.key]
                  : picked.where((x) => x != e.key).toList()),
            ),
        ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('When and how you want to work'),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              Text(identityError(e), style: TextStyle(color: scheme.error)),
          data: (p) {
            _adopt(p);
            final prefs = _prefs!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('When can you start?',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: kAvailabilityLabels.containsKey(prefs.availability)
                      ? prefs.availability
                      : 'immediate',
                  isExpanded: true,
                  items: [
                    for (final e in kAvailabilityLabels.entries)
                      DropdownMenuItem(value: e.key, child: Text(e.value)),
                  ],
                  onChanged: (v) => _change(_copy(availability: v)),
                ),
                const SizedBox(height: 16),
                const Text('Kind of work',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                chips(kWorkTypeLabels, prefs.workTypes,
                    (v) => _change(_copy(workTypes: v))),
                const SizedBox(height: 16),
                const Text('Shifts',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                chips(kShiftLabels, prefs.shiftTypes,
                    (v) => _change(_copy(shiftTypes: v))),
                const SizedBox(height: 16),
                const Text('Pay you are looking for (optional)',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _pay,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                          prefixText: prefs.payCurrency == null
                              ? null
                              : '${prefs.payCurrency} '),
                      onChanged: (_) => setState(() => _dirty = true),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: kPayPeriodLabels
                              .containsKey(prefs.expectedPayPeriod)
                          ? prefs.expectedPayPeriod
                          : 'month',
                      isExpanded: true,
                      items: [
                        for (final e in kPayPeriodLabels.entries)
                          DropdownMenuItem(value: e.key, child: Text(e.value)),
                      ],
                      onChanged: (v) => _change(_copy(period: v)),
                    ),
                  ),
                ]),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy || !_dirty ? null : _save,
                  child: Text(_busy ? 'Saving…' : 'Save'),
                ),
              ],
            );
          },
        ),
        _PlacesBlock(identityId: widget.identityId),
      ],
    );
  }
}

class _PlacesBlock extends ConsumerWidget {
  const _PlacesBlock({required this.identityId});
  final String identityId;

  static const _radii = [5, 10, 25, 50];

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final repo = ref.read(identityRepositoryProvider);
    final place = await showSearchPicker(
      context,
      title: 'Where do you want to work?',
      hint: 'Type a city or area',
      search: repo.searchPlaces,
      searchWhenEmpty: false,
      emptyText: 'No place found. Try the nearest city.',
    );
    if (place == null || !context.mounted) return;
    final radius = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('How far from ${place.name}?',
                  style: const TextStyle(
                      fontSize: 19, fontWeight: FontWeight.w800)),
              const SizedBox(height: 14),
              for (final r in _radii)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(ctx, r),
                    child: Text('Up to $r km'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (radius == null || !context.mounted) return;
    try {
      await repo.addPlace(identityId, place, radiusKm: radius);
      ref.invalidate(identityPlacesProvider(identityId));
      invalidateIdentities(ref, identityId);
    } catch (e) {
      if (context.mounted) showSnack(context, identityError(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final places = ref.watch(identityPlacesProvider(identityId));
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Where you want to work'),
        places.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) =>
              Text(identityError(e), style: TextStyle(color: scheme.error)),
          data: (list) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final p in list)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: 56,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(p.name),
                  subtitle:
                      p.radiusKm == null ? null : Text('Up to ${p.radiusKm} km'),
                  trailing: IconButton(
                    tooltip: 'Remove ${p.name}',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      try {
                        await ref
                            .read(identityRepositoryProvider)
                            .removePlace(p.id);
                        ref.invalidate(identityPlacesProvider(identityId));
                        invalidateIdentities(ref, identityId);
                      } catch (e) {
                        if (context.mounted) {
                          showSnack(context, identityError(e));
                        }
                      }
                    },
                  ),
                ),
              OutlinedButton.icon(
                onPressed: () => _add(context, ref),
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Add a place'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
