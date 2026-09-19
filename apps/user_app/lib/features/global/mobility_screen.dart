import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/global_repository.dart';
import '../../data/identity_repository.dart' show TaxonomyHit;
import '../../data/invitations.dart' show shortDate;
import '../identities/search_picker.dart';
import '../representations/representation_widgets.dart'
    show RepresentationMessage;
import '../work/work_widgets.dart' show WorkPill, WorkTone, workBackButton;
import 'authorization_editor.dart';
import 'global_widgets.dart';

/// `/mobility` — where I live, where I could work, whether I need a visa,
/// my right to work in each country, and who may see it.
class MobilityScreen extends ConsumerStatefulWidget {
  const MobilityScreen({super.key});

  @override
  ConsumerState<MobilityScreen> createState() => _MobilityScreenState();
}

class _MobilityScreenState extends ConsumerState<MobilityScreen> {
  MobilityProfile? _original;
  MobilityProfile? _draft;
  final _cityNames = <String, String>{};
  bool _saving = false;

  bool get _dirty => _draft != null && _draft != _original;

  void _seed(MyMobility m) {
    _original = m.profile;
    _draft = m.profile;
    final missing =
        m.profile.preferredCityIds.where((id) => !_cityNames.containsKey(id)).toList();
    if (missing.isEmpty) return;
    ref.read(globalRepositoryProvider).citiesByIds(missing).then((hits) {
      if (!mounted) return;
      setState(() {
        for (final h in hits) {
          _cityNames[h.id] = h.name;
        }
      });
    }).catchError((_) {});
  }

  void _edit(MobilityProfile Function(MobilityProfile) f) =>
      setState(() => _draft = f(_draft!));

  Future<void> _save() async {
    final d = _draft;
    if (d == null) return;
    final problem = validateMobility(d);
    if (problem != null) {
      showGlobalSnack(context, problem);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref.read(globalRepositoryProvider).saveMobility(d);
      if (!mounted) return;
      setState(() {
        _original = saved;
        _draft = saved;
      });
      ref.invalidate(myMobilityProvider);
      showGlobalSnack(context, 'Saved.');
    } catch (e) {
      if (mounted) showGlobalSnack(context, globalError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(myMobilityProvider);
    final countries = ref.watch(countriesProvider).valueOrNull ?? const <Country>[];

    final data = async.valueOrNull;
    if (data != null && _draft == null) _seed(data);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Global mobility'),
        leading: workBackButton(context, '/profile'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RepresentationMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load your mobility details',
          body: globalError(e),
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myMobilityProvider),
        ),
        data: (m) => _body(context, m, countries),
      ),
      bottomNavigationBar: _draft == null
          ? null
          : SafeArea(
              child: Center(
                heightFactor: 1,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: Breakpoints.readingWidth),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _saving || !_dirty ? null : _save,
                        child: Text(_saving
                            ? 'Saving…'
                            : _dirty
                                ? 'Save changes'
                                : 'Saved'),
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _body(BuildContext context, MyMobility m, List<Country> countries) {
    final d = _draft ?? m.profile;
    final gutter = Breakpoints.of(context).gutter;
    final scheme = Theme.of(context).colorScheme;
    final home = countries.where((c) => c.code == d.currentCountry).firstOrNull;

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
      children: [
        ContentWidth.reading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Tell employers in other countries where you are and where you '
                'could work. You decide who sees your right-to-work details.',
                style: TextStyle(
                    fontSize: 14.5, height: 1.4, color: scheme.onSurfaceVariant),
              ),

              _Section('Where you are'),
              ResponsiveFieldRow(children: [
                _PickerField(
                  label: 'Country you live in',
                  value: d.currentCountry == null
                      ? null
                      : countryName(d.currentCountry, countries),
                  icon: Icons.home_outlined,
                  onTap: () async {
                    final c = await pickCountry(context, countries,
                        title: 'Country you live in');
                    if (c == null) return;
                    _edit((p) => p.copyWith(
                          currentCountry: () => c.code,
                          timezone: p.timezone == null && c.timezone != null
                              ? () => c.timezone
                              : null,
                        ));
                  },
                  onClear: d.currentCountry == null
                      ? null
                      : () => _edit((p) => p.copyWith(currentCountry: () => null)),
                ),
                _PickerField(
                  label: 'Time zone',
                  value: d.timezone?.replaceAll('_', ' '),
                  icon: Icons.schedule,
                  onTap: () async {
                    final z = await pickTimeZone(context,
                        suggested: [?home?.timezone]);
                    if (z != null) _edit((p) => p.copyWith(timezone: () => z));
                  },
                  onClear: d.timezone == null
                      ? null
                      : () => _edit((p) => p.copyWith(timezone: () => null)),
                ),
              ]),
              const SizedBox(height: 14),
              const _Label('Citizenship'),
              CountryChips(
                codes: d.citizenships,
                countries: countries,
                max: MobilityProfile.maxCitizenships,
                addLabel: 'Add citizenship',
                pickerTitle: 'Your citizenship',
                onChanged: (v) => _edit((p) => p.copyWith(citizenships: v)),
              ),

              _Section('How you want to work'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final r in RemotePreference.values)
                    ChoiceChip(
                      label: Text(r.label),
                      tooltip: r.help,
                      selected: d.remotePreference == r,
                      onSelected: (_) =>
                          _edit((p) => p.copyWith(remotePreference: r)),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const _Label('Countries you could work in (including from home)'),
              CountryChips(
                codes: d.countriesWillingToWork,
                countries: countries,
                max: MobilityProfile.maxWillingCountries,
                addLabel: 'Add country',
                pickerTitle: 'A country you could work in',
                onChanged: (v) =>
                    _edit((p) => p.copyWith(countriesWillingToWork: v)),
              ),

              _Section('Moving for work'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('I\'m open to moving to another country or city'),
                value: d.openToRelocation,
                onChanged: (v) => _edit((p) => p.copyWith(openToRelocation: v)),
              ),
              if (d.openToRelocation) ...[
                const _Label('Where would you move?'),
                CountryChips(
                  codes: d.preferredCountries,
                  countries: countries,
                  max: MobilityProfile.maxPreferredCountries,
                  addLabel: 'Add country',
                  pickerTitle: 'A country you would move to',
                  onChanged: (v) =>
                      _edit((p) => p.copyWith(preferredCountries: v)),
                ),
                const SizedBox(height: 12),
                const _Label('Cities you prefer (optional)'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final id in d.preferredCityIds)
                      InputChip(
                        label: Text(_cityNames[id] ?? 'City'),
                        onDeleted: () => _edit((p) => p.copyWith(
                            preferredCityIds: [...p.preferredCityIds]..remove(id))),
                      ),
                    if (d.preferredCityIds.length <
                        MobilityProfile.maxPreferredCities)
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: const Text('Add city'),
                        onPressed: () => _addCity(context, d, countries),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('I need help to move'),
                  subtitle: const Text('Travel, housing or visa costs'),
                  value: d.relocationAssistanceRequired,
                  onChanged: (v) => _edit(
                      (p) => p.copyWith(relocationAssistanceRequired: v)),
                ),
                _PickerField(
                  label: 'Earliest date you could move',
                  value: d.earliestRelocationDate == null
                      ? null
                      : shortDate(d.earliestRelocationDate!, DateTime(0)),
                  icon: Icons.event_outlined,
                  onTap: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: d.earliestRelocationDate ?? now,
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 5),
                    );
                    if (picked != null) {
                      _edit((p) => p.copyWith(earliestRelocationDate: () => picked));
                    }
                  },
                  onClear: d.earliestRelocationDate == null
                      ? null
                      : () => _edit(
                          (p) => p.copyWith(earliestRelocationDate: () => null)),
                ),
              ],

              _Section('Visa sponsorship'),
              const _Label('Do you need an employer to sponsor a visa?'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final v in const [true, false, null])
                    ChoiceChip(
                      label: Text(sponsorshipNeedLabel(v)),
                      selected: d.requiresSponsorship == v,
                      onSelected: (_) =>
                          _edit((p) => p.copyWith(requiresSponsorship: () => v)),
                    ),
                ],
              ),

              _Section('Who sees your right to work'),
              VisibilityChooser(
                value: d.visibility,
                onChanged: (v) => _edit((p) => p.copyWith(visibility: v)),
              ),

              _Section('Your right to work'),
              Text(
                'Add each country where you can work, or need a visa. Only you '
                'see these details unless you choose otherwise above.',
                style: TextStyle(
                    fontSize: 13.5, height: 1.4, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (final a in m.authorizations)
                AuthorizationCard(
                  authorization: a,
                  onEdit: () => showAuthorizationEditor(context, ref,
                      countries: countries,
                      existing: a,
                      taken: m.authorizations.map((x) => x.country)),
                  onDelete: () => _delete(context, a),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () => showAuthorizationEditor(context, ref,
                      countries: countries,
                      taken: m.authorizations.map((x) => x.country)),
                  icon: const Icon(Icons.add),
                  label: const Text('Add a country'),
                ),
              ),
              const SizedBox(height: 20),
              TextButton.icon(
                onPressed: () => context.push('/jobs/global'),
                icon: const Icon(Icons.public),
                label: const Text('See jobs worldwide'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addCity(
      BuildContext context, MobilityProfile d, List<Country> countries) async {
    final repo = ref.read(globalRepositoryProvider);
    final TaxonomyHit? hit = await showSearchPicker(
      context,
      title: 'A city you would move to',
      hint: 'City name',
      searchWhenEmpty: false,
      search: (q) async {
        final hits = await repo.searchCities(q, countries: d.preferredCountries);
        return [
          for (final h in hits)
            if (!d.preferredCityIds.contains(h.id))
              TaxonomyHit(
                id: h.id,
                name: h.extra == null
                    ? h.name
                    : '${h.name}, ${countryName(h.extra, countries)}',
                extra: h.extra,
              ),
        ];
      },
    );
    if (hit == null) return;
    setState(() => _cityNames[hit.id] = hit.name.split(',').first);
    _edit((p) => p.copyWith(preferredCityIds: [...p.preferredCityIds, hit.id]));
  }

  Future<void> _delete(BuildContext context, WorkAuthorization a) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Remove ${a.displayCountry}?'),
        content: const Text(
            'Your right-to-work details for this country will be deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(globalRepositoryProvider).deleteAuthorization(a.id);
      ref.invalidate(myMobilityProvider);
      if (context.mounted) showGlobalSnack(context, 'Removed.');
    } catch (e) {
      if (context.mounted) showGlobalSnack(context, globalError(e));
    }
  }
}

/// The four choices for who sees work-authorization details, each explained.
class VisibilityChooser extends StatelessWidget {
  const VisibilityChooser({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final AuthorizationVisibility value;
  final ValueChanged<AuthorizationVisibility> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
        children: [
          for (final v in AuthorizationVisibility.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: v == value
                    ? scheme.primaryContainer.withValues(alpha: 0.45)
                    : scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(12),
                child: RadioListTile<AuthorizationVisibility>(
                  value: v,
                  groupValue: value,
                  onChanged: (x) {
                    if (x != null) onChanged(x);
                  },
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  title: Text(
                    v == AuthorizationVisibility.standard
                        ? '${v.title} (recommended)'
                        : v.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(v.explanation,
                        style: const TextStyle(height: 1.35)),
                  ),
                ),
              ),
            ),
        ],
    );
  }
}

class AuthorizationCard extends StatelessWidget {
  const AuthorizationCard({
    super.key,
    required this.authorization,
    required this.onEdit,
    required this.onDelete,
  });
  final WorkAuthorization authorization;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final a = authorization;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final dates = authorizationDatesLine(a, now);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.displayCountry,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(a.status.label, style: const TextStyle(fontSize: 14.5)),
                  if (dates != null)
                    Text(dates,
                        style: TextStyle(
                            fontSize: 13,
                            color: a.isExpiredAt(now)
                                ? scheme.error
                                : scheme.onSurfaceVariant)),
                  if (a.restrictions != null)
                    Text('Limits: ${a.restrictions}',
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (a.isVerified)
                      const WorkPill('Verified by Omelo',
                          tone: WorkTone.good, icon: Icons.verified),
                    if (a.requiresSponsorship)
                      const WorkPill('Needs sponsorship', tone: WorkTone.warning),
                    if (a.hasDocument)
                      const WorkPill('Document attached',
                          icon: Icons.attach_file),
                  ]),
                ],
              ),
            ),
            IconButton(
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit ${a.displayCountry}',
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Remove ${a.displayCountry}',
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 26, bottom: 10),
        child: Text(text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}

/// A read-only field that opens a picker.
class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.onClear,
  });
  final String label;
  final String? value;
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon),
            suffixIcon: onClear == null
                ? const Icon(Icons.arrow_drop_down)
                : IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear $label',
                  ),
          ),
          child: Text(value ?? 'Not set',
              style: const TextStyle(fontSize: 16),
              overflow: TextOverflow.ellipsis),
        ),
      );
}
