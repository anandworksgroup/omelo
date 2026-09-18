import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/identity_repository.dart';
import 'identity_sections.dart';
import 'identity_widgets.dart';
import 'profile_field_input.dart';
import 'search_picker.dart';

/// `/identities/:id` — everything about one work identity.
class IdentityEditorScreen extends ConsumerStatefulWidget {
  const IdentityEditorScreen({
    super.key,
    required this.identityId,
    this.section,
  });

  final String identityId;

  /// basics | questions | skills | experience | preferences | visibility |
  /// evidence — scrolls there once loaded.
  final String? section;

  @override
  ConsumerState<IdentityEditorScreen> createState() =>
      _IdentityEditorScreenState();
}

class _IdentityEditorScreenState extends ConsumerState<IdentityEditorScreen> {
  static const _sections = [
    ('basics', 'Basics'),
    ('questions', 'Questions'),
    ('skills', 'Skills'),
    ('experience', 'Experience'),
    ('preferences', 'Where and when'),
    ('visibility', 'Who can see it'),
    ('evidence', 'Proof'),
  ];

  final _keys = {for (final s in _sections) s.$1: GlobalKey()};
  bool _scrolledToInitial = false;

  void _scrollTo(String section) {
    final ctx = _keys[section]?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          alignment: 0.02);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(identityProfileProvider(widget.identityId));
    final id = widget.identityId;

    return Scaffold(
      appBar: AppBar(
        title: Text(profile.value?.identity.label ?? 'Work identity'),
      ),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(identityError(e), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(identityProfileProvider(id)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (p) {
          if (!_scrolledToInitial && widget.section != null) {
            _scrolledToInitial = true;
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _scrollTo(widget.section!));
          }
          final gutter = Breakpoints.of(context).gutter;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 48),
            child: ContentWidth.reading(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _Header(profile: p, onGo: _scrollTo),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (key, label) in _sections)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ActionChip(
                              label: Text(label),
                              onPressed: () => _scrollTo(key),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (p.identity.isArchived)
                    Container(
                      margin: const EdgeInsets.only(top: 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'This identity is archived. Employers cannot see it '
                        'and you cannot apply with it. Restore it from '
                        'My work identities.',
                        style: TextStyle(height: 1.4),
                      ),
                    ),
                  KeyedSubtree(
                    key: _keys['basics'],
                    child: _BasicsSection(profile: p),
                  ),
                  KeyedSubtree(
                    key: _keys['questions'],
                    child: _QuestionsSection(profile: p),
                  ),
                  KeyedSubtree(
                    key: _keys['skills'],
                    child: SkillsSection(identityId: id),
                  ),
                  KeyedSubtree(
                    key: _keys['experience'],
                    child: ExperienceSection(
                        identityId: id,
                        professionId: p.identity.professionId),
                  ),
                  KeyedSubtree(
                    key: _keys['preferences'],
                    child: PreferencesSection(identityId: id),
                  ),
                  KeyedSubtree(
                    key: _keys['visibility'],
                    child: _VisibilitySection(identity: p.identity),
                  ),
                  KeyedSubtree(
                    key: _keys['evidence'],
                    child: _EvidenceSection(identityId: id),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header({required this.profile, required this.onGo});
  final IdentityProfile profile;
  final ValueChanged<String> onGo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final i = profile.identity;
    final skills =
        ref.watch(identitySkillsProvider(i.id)).value?.length;
    final missing = profile.completeness.missing;
    final tip = completenessTip(missing, skillCount: skills);
    final first = missing.isEmpty
        ? null
        : kCompletenessPriority.firstWhere(missing.contains,
            orElse: () => missing.first);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CompletenessRing(score: profile.completeness.score, size: 60),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(i.label,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              Text(i.professionName ?? 'No job type chosen yet',
                  style: TextStyle(
                      fontSize: 14.5, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                if (i.isPrimary) const MainBadge(),
                VisibilityChip(i.visibility),
              ]),
              if (tip != null && first != null) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft),
                  onPressed: () => onGo(sectionForMissing(first)),
                  icon: const Icon(Icons.lightbulb_outline, size: 18),
                  label: Text(tip, textAlign: TextAlign.left),
                ),
              ] else if (tip == null) ...[
                const SizedBox(height: 8),
                const Text('Your profile is complete.',
                    style: TextStyle(
                        color: OmeloTheme.verified,
                        fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Basics
// ---------------------------------------------------------------------------

class _BasicsSection extends ConsumerStatefulWidget {
  const _BasicsSection({required this.profile});
  final IdentityProfile profile;

  @override
  ConsumerState<_BasicsSection> createState() => _BasicsSectionState();
}

class _BasicsSectionState extends ConsumerState<_BasicsSection> {
  late final _label = TextEditingController();
  late final _headline = TextEditingController();
  late final _about = TextEditingController();
  late final _years = TextEditingController();
  TaxonomyHit? _profession;
  bool _dirty = false;
  bool _busy = false;
  String? _error;

  WorkIdentity get i => widget.profile.identity;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _label.text = i.label;
    _headline.text = i.headline ?? '';
    _about.text = i.about ?? '';
    final m = i.totalExperienceMonths;
    _years.text = m == null
        ? ''
        : (m % 12 == 0 ? '${m ~/ 12}' : (m / 12).toStringAsFixed(1));
    _profession = i.professionId == null
        ? null
        : TaxonomyHit(
            id: i.professionId!,
            name: i.professionName ?? '',
            extra: i.categoryId);
    _dirty = false;
  }

  @override
  void didUpdateWidget(covariant _BasicsSection old) {
    super.didUpdateWidget(old);
    if (!_dirty && !_busy) _load();
  }

  @override
  void dispose() {
    _label.dispose();
    _headline.dispose();
    _about.dispose();
    _years.dispose();
    super.dispose();
  }

  Future<void> _pickProfession() async {
    final hit = await showSearchPicker(
      context,
      title: 'What kind of work?',
      hint: 'For example: electrician, nurse',
      search: ref.read(identityRepositoryProvider).searchProfessions,
    );
    if (hit != null) {
      setState(() {
        _profession = hit;
        _dirty = true;
      });
    }
  }

  Future<void> _save() async {
    int? months;
    final y = _years.text.trim().replaceAll(',', '.');
    if (y.isNotEmpty) {
      final n = num.tryParse(y);
      if (n == null || n < 0 || n > 70) {
        setState(() => _error = 'Years of experience must be between 0 and 70.');
        return;
      }
      months = (n * 12).round();
    }
    if (_label.text.trim().length < 2) {
      setState(() => _error = 'Give this identity a name.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final professionChanged = _profession?.id != i.professionId;
      await ref.read(identityRepositoryProvider).updateBasics(
            i.id,
            label: _label.text,
            professionId: _profession?.id,
            categoryId: professionChanged ? _profession?.extra : i.categoryId,
            headline: _headline.text,
            about: _about.text,
            totalExperienceMonths: months,
          );
      _dirty = false;
      invalidateIdentities(ref, i.id);
      if (mounted) {
        showSnack(
            context,
            professionChanged
                ? 'Saved. The questions below now match your job type.'
                : 'Saved.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = identityError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    void touch(_) {
      if (!_dirty) setState(() => _dirty = true);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Basics'),
        ResponsiveFieldRow(children: [
          _Labeled(
            'Name',
            TextField(
              controller: _label,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(counterText: ''),
              onChanged: touch,
            ),
          ),
          _Labeled(
            'Job type',
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickProfession,
              icon: const Icon(Icons.work_outline),
              style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
              label: Text(
                _profession?.name.isNotEmpty == true
                    ? _profession!.name
                    : 'Choose a job type',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ]),
        const SizedBox(height: 14),
        _Labeled(
          'Headline',
          TextField(
            controller: _headline,
            maxLength: 120,
            decoration: const InputDecoration(
                hintText: 'For example: Cook with 5 years in hotels'),
            onChanged: touch,
          ),
        ),
        const SizedBox(height: 6),
        _Labeled(
          'About you',
          TextField(
            controller: _about,
            maxLines: 5,
            minLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(
                hintText: 'What you are good at, and the work you want'),
            onChanged: touch,
          ),
        ),
        const SizedBox(height: 6),
        _Labeled(
          'Years of experience',
          TextField(
            controller: _years,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                suffixText: 'years', hintText: '0 if this is your first job'),
            onChanged: touch,
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(_error!, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: 14),
        FilledButton(
          onPressed: _busy || !_dirty ? null : _save,
          child: Text(_busy ? 'Saving…' : 'Save basics'),
        ),
      ],
    );
  }
}

class _Labeled extends StatelessWidget {
  const _Labeled(this.label, this.child);
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          child,
        ],
      );
}

// ---------------------------------------------------------------------------
// Adaptive profile questions
// ---------------------------------------------------------------------------

class _QuestionsSection extends ConsumerStatefulWidget {
  const _QuestionsSection({required this.profile});
  final IdentityProfile profile;

  @override
  ConsumerState<_QuestionsSection> createState() => _QuestionsSectionState();
}

class _QuestionsSectionState extends ConsumerState<_QuestionsSection> {
  final _values = <String, Object?>{};
  final _dirty = <String>{};
  var _errors = <String, String>{};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _QuestionsSection old) {
    super.didUpdateWidget(old);
    _sync();
  }

  /// Take server values for every question the person is not editing.
  void _sync() {
    final slugs = widget.profile.fields.map((f) => f.slug).toSet();
    _values.removeWhere((k, _) => !slugs.contains(k));
    _dirty.removeWhere((k) => !slugs.contains(k));
    for (final f in widget.profile.fields) {
      if (!_dirty.contains(f.slug)) {
        _values[f.slug] = decodeFieldValue(f.dataType, f.value);
      }
    }
  }

  Future<void> _save() async {
    final bySlug = {for (final f in widget.profile.fields) f.slug: f};
    final send = <String, Object?>{};
    final errors = <String, String>{};
    for (final slug in _dirty) {
      final f = bySlug[slug];
      if (f == null || inputKindFor(f) == FieldInputKind.unsupported) continue;
      final enc = encodeFieldValue(f, _values[slug]);
      if (enc.ok) {
        send[slug] = enc.value;
      } else {
        errors[slug] = enc.error!;
      }
    }
    if (send.isEmpty) {
      setState(() => _errors = errors);
      return;
    }
    setState(() => _busy = true);
    try {
      final res = await ref
          .read(identityRepositoryProvider)
          .saveProfile(widget.profile.identity.id, send);
      errors.addAll(res.errors);
      _dirty.removeWhere((s) => send.containsKey(s) && !res.errors.containsKey(s));
      invalidateIdentities(ref, widget.profile.identity.id);
      if (mounted) {
        showSnack(
            context,
            errors.isEmpty
                ? 'Answers saved.'
                : 'Some answers need a fix. See the red notes.');
      }
    } catch (e) {
      if (mounted) showSnack(context, identityError(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _errors = errors;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fields = widget.profile.fields;
    final forJob = fields.where((f) => f.scope != 'universal').toList();
    final shared = fields.where((f) => f.scope == 'universal').toList();

    Widget fieldList(List<ProfileField> list) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final f in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 20),
                child: ProfileFieldInput(
                  key: ValueKey('field-${f.slug}'),
                  field: f,
                  value: _values[f.slug],
                  errorText: _errors[f.slug],
                  onChanged: (v) => setState(() {
                    _values[f.slug] = v;
                    _dirty.add(f.slug);
                    _errors.remove(f.slug);
                  }),
                ),
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Questions for your job',
          subtitle: widget.profile.identity.professionId == null
              ? 'Choose a job type above to see the questions employers care about.'
              : 'Employers in this kind of work look for these answers.',
        ),
        if (forJob.isEmpty && widget.profile.identity.professionId != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text('No extra questions for this job type.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
          ),
        fieldList(forJob),
        if (shared.isNotEmpty) ...[
          const Text('About you',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('These answers are the same on all your identities.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 14),
          fieldList(shared),
        ],
        FilledButton(
          onPressed: _busy || _dirty.isEmpty ? null : _save,
          child: Text(_busy
              ? 'Saving…'
              : _dirty.isEmpty
                  ? 'Answers saved'
                  : 'Save answers'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Visibility
// ---------------------------------------------------------------------------

class _VisibilitySection extends ConsumerStatefulWidget {
  const _VisibilitySection({required this.identity});
  final WorkIdentity identity;

  @override
  ConsumerState<_VisibilitySection> createState() =>
      _VisibilitySectionState();
}

class _VisibilitySectionState extends ConsumerState<_VisibilitySection> {
  bool _busy = false;

  Future<void> _set(IdentityVisibility v) async {
    setState(() => _busy = true);
    try {
      await ref
          .read(identityRepositoryProvider)
          .setVisibility(widget.identity.id, v);
      invalidateIdentities(ref, widget.identity.id);
      if (mounted) showSnack(context, 'Now: ${v.title}.');
    } catch (e) {
      if (mounted) showSnack(context, identityError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle('Who can see ${widget.identity.label}',
            subtitle: 'Your other identities are not affected.'),
        VisibilitySelector(
          value: widget.identity.visibility,
          enabled: !_busy && widget.identity.isActive,
          onChanged: _set,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Evidence
// ---------------------------------------------------------------------------

class _EvidenceSection extends ConsumerWidget {
  const _EvidenceSection({required this.identityId});
  final String identityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ev = ref.watch(identityEvidenceProvider(identityId));
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Proof behind your skills',
            subtitle: 'What employers see backing each skill when you apply '
                'with this identity.'),
        ev.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(20),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(identityError(e),
              style: TextStyle(color: scheme.error)),
          data: (e) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(spacing: 8, runSpacing: 8, children: [
                _TrustPill('Email', e.emailVerified),
                _TrustPill('Phone', e.phoneVerified),
                _TrustPill('ID', e.identityVerified),
              ]),
              const SizedBox(height: 14),
              if (e.skills.isEmpty)
                Text('Add skills above to see the proof behind them.',
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              for (final s in e.skills)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(s.name,
                                  style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700)),
                            ),
                            if (s.verified)
                              const Icon(Icons.verified,
                                  color: OmeloTheme.verified, size: 20),
                          ]),
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, runSpacing: 6, children: [
                            for (final item in s.evidence) EvidenceBadge(item),
                          ]),
                          for (final item in s.evidence.where((x) =>
                              x.type == 'verified_employment' ||
                              x.type == 'experience'))
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(item.label,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: scheme.onSurfaceVariant)),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (e.verifiedEmployment.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Verified jobs',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                for (final j in e.verifiedEmployment)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.verified,
                        color: OmeloTheme.verified),
                    title: Text('${j['title'] ?? ''}'),
                    subtitle: Text('${j['employer'] ?? ''}'),
                  ),
              ],
              if (e.licences.isNotEmpty || e.credentials.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Licences and certificates',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                for (final l in [...e.licences, ...e.credentials])
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      l['verified'] == true
                          ? Icons.verified
                          : Icons.badge_outlined,
                      color:
                          l['verified'] == true ? OmeloTheme.verified : null,
                    ),
                    title: Text('${l['name'] ?? ''}'),
                    subtitle: Text(l['verified'] == true
                        ? 'Verified by Omelo'
                        : 'Not verified yet'),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _TrustPill extends StatelessWidget {
  const _TrustPill(this.label, this.ok);
  final String label;
  final bool ok;

  @override
  Widget build(BuildContext context) => OmeloPill(
        ok ? '$label verified' : '$label not verified',
        icon: ok ? Icons.check_circle : Icons.radio_button_unchecked,
        color: ok ? OmeloTheme.verified : null,
      );
}
