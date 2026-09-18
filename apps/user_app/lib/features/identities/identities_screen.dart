import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/identity_repository.dart';
import 'identity_widgets.dart';
import 'search_picker.dart';

/// "My work identities" — one profile for each kind of work a person does.
class IdentitiesScreen extends ConsumerWidget {
  const IdentitiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    final hub = ref.watch(identityHubProvider);
    final scheme = Theme.of(context).colorScheme;

    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('My work identities')),
        body: Center(
          child: FilledButton(
            onPressed: () => context.push('/sign-in?next=/identities'),
            child: const Text('Sign in to see your identities'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My work identities')),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(identityHubProvider),
        child: hub.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _Error(
            text: identityError(e),
            onRetry: () => ref.invalidate(identityHubProvider),
          ),
          data: (cards) {
            final full = cards.length >= kMaxWorkIdentities;
            final gutter = Breakpoints.of(context).gutter;
            return ListView(
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 40),
              children: [
                ContentWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Make one profile for each kind of work you do. '
                        'Employers only see the one you apply with.',
                        style: TextStyle(
                            fontSize: 14.5,
                            height: 1.45,
                            color: scheme.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      ResponsiveCardGrid(
                        minCardWidth: 360,
                        children: [
                          for (final c in cards)
                            _IdentityCard(data: c, all: cards),
                        ],
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        onPressed: full
                            ? null
                            : () => showAddIdentitySheet(context, ref,
                                existing: [for (final c in cards) c.identity]),
                        icon: const Icon(Icons.add),
                        label: const Text('Add an identity'),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        full
                            ? 'You have $kMaxWorkIdentities identities, the most '
                                'you can have. Delete one you do not need to '
                                'add another.'
                            : 'You can have up to $kMaxWorkIdentities.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant),
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

class _Error extends StatelessWidget {
  const _Error({required this.text, required this.onRetry});
  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(32),
        children: [
          Text(text, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          Center(
            child: OutlinedButton(
                onPressed: onRetry, child: const Text('Try again')),
          ),
        ],
      );
}

enum _Action { open, makeMain, archive, restore, delete }

class _IdentityCard extends ConsumerStatefulWidget {
  const _IdentityCard({required this.data, required this.all});
  final IdentityCardData data;
  final List<IdentityCardData> all;

  @override
  ConsumerState<_IdentityCard> createState() => _IdentityCardState();
}

class _IdentityCardState extends ConsumerState<_IdentityCard> {
  bool _busy = false;

  WorkIdentity get i => widget.data.identity;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      invalidateIdentities(ref, i.id);
      if (mounted) showSnack(context, done);
    } catch (e) {
      if (mounted) showSnack(context, identityError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onAction(_Action a) async {
    final repo = ref.read(identityRepositoryProvider);
    switch (a) {
      case _Action.open:
        context.push('/identities/${i.id}');
      case _Action.makeMain:
        await _run(() => repo.setPrimary(i.id), '${i.label} is now your main identity.');
      case _Action.archive:
        final ok = await _confirm(
          title: 'Archive ${i.label}?',
          body: 'It will be hidden from employers and you cannot apply with '
              'it. Your applications stay as they are. You can restore it '
              'at any time.',
          action: 'Archive',
        );
        if (ok) await _run(() => repo.archive(i.id), '${i.label} archived.');
      case _Action.restore:
        await _run(() => repo.archive(i.id, archive: false),
            '${i.label} restored. It is private until you change who can see it.');
      case _Action.delete:
        await _delete();
    }
  }

  Future<void> _delete() async {
    final ok = await _confirm(
      title: 'Delete ${i.label}?',
      body: 'Its skills, experience and answers will be removed. This cannot '
          'be undone.',
      action: 'Delete',
      danger: true,
    );
    if (!ok) return;
    setState(() => _busy = true);
    try {
      await ref.read(identityRepositoryProvider).delete(i.id);
      invalidateIdentities(ref);
      if (mounted) showSnack(context, '${i.label} deleted.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      // Typically: it has applications, so it is kept — offer Archive.
      final archive = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Could not delete'),
          content: Text(identityError(e)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Close')),
            if (i.isActive)
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Archive instead')),
          ],
        ),
      );
      if (archive == true) {
        await _run(() => ref.read(identityRepositoryProvider).archive(i.id),
            '${i.label} archived.');
      }
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
    bool danger = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            style: danger
                ? FilledButton.styleFrom(backgroundColor: OmeloTheme.danger)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tip = widget.data.tip;
    final activeCount = widget.all.where((c) => c.identity.isActive).length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy ? null : () => _onAction(_Action.open),
        child: Opacity(
          opacity: i.isArchived ? 0.7 : 1,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompletenessRing(score: widget.data.completeness.score),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(i.label,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 2),
                          Text(i.professionName ?? 'No job type chosen yet',
                              style: TextStyle(
                                  fontSize: 14,
                                  color: scheme.onSurfaceVariant)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (i.isPrimary) const MainBadge(),
                              if (i.isArchived)
                                const OmeloPill('Archived',
                                    icon: Icons.inventory_2_outlined)
                              else
                                VisibilityChip(i.visibility),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _busy
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: SizedBox(
                                width: 20,
                                height: 20,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : PopupMenuButton<_Action>(
                            tooltip: 'More for ${i.label}',
                            onSelected: _onAction,
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                  value: _Action.open, child: Text('Open')),
                              if (i.isActive && !i.isPrimary)
                                const PopupMenuItem(
                                    value: _Action.makeMain,
                                    child: Text('Make main')),
                              if (i.isActive && activeCount > 1)
                                const PopupMenuItem(
                                    value: _Action.archive,
                                    child: Text('Archive')),
                              if (i.isArchived)
                                const PopupMenuItem(
                                    value: _Action.restore,
                                    child: Text('Restore')),
                              if (widget.all.length > 1)
                                const PopupMenuItem(
                                    value: _Action.delete,
                                    child: Text('Delete')),
                            ],
                          ),
                  ],
                ),
                if (tip != null && !i.isArchived) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.lightbulb_outline,
                          size: 18, color: scheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(tip,
                            style: const TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
                if (i.isActive && !i.isPrimary) ...[
                  const SizedBox(height: 6),
                  TextButton.icon(
                    onPressed: _busy ? null : () => _onAction(_Action.makeMain),
                    icon: const Icon(Icons.star_outline),
                    label: const Text('Make main'),
                  ),
                ],
                if (i.isArchived)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextButton.icon(
                      onPressed:
                          _busy ? null : () => _onAction(_Action.restore),
                      icon: const Icon(Icons.unarchive_outlined),
                      label: const Text('Restore'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add an identity
// ---------------------------------------------------------------------------

Future<void> showAddIdentitySheet(
  BuildContext context,
  WidgetRef ref, {
  required List<WorkIdentity> existing,
}) async {
  final id = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 700),
    builder: (_) => _AddIdentitySheet(existing: existing),
  );
  if (id == null) return;
  invalidateIdentities(ref);
  if (context.mounted) context.push('/identities/$id');
}

class _AddIdentitySheet extends ConsumerStatefulWidget {
  const _AddIdentitySheet({required this.existing});
  final List<WorkIdentity> existing;

  @override
  ConsumerState<_AddIdentitySheet> createState() => _AddIdentitySheetState();
}

class _AddIdentitySheetState extends ConsumerState<_AddIdentitySheet> {
  final _name = TextEditingController();
  TaxonomyHit? _profession;
  String? _copyFrom;
  final _copy = <String>{'skills', 'preferences', 'locations'};
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _pickProfession() async {
    final hit = await showSearchPicker(
      context,
      title: 'What kind of work?',
      hint: 'For example: driver, cook, nurse',
      search: ref.read(identityRepositoryProvider).searchProfessions,
    );
    if (hit == null) return;
    setState(() {
      // Fill the name only if the person has not typed their own.
      if (_name.text.trim().isEmpty ||
          _name.text.trim() == _profession?.name) {
        _name.text = hit.name;
      }
      _profession = hit;
    });
  }

  Future<void> _create() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Give it a name, for example "Cook".');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(identityRepositoryProvider).create(
            label: name,
            professionId: _profession?.id,
            copyFrom: _copyFrom,
            copy: _copy.toList(),
          );
      if (mounted) Navigator.pop(context, id);
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
    final sources = widget.existing.where((i) => !i.isArchived).toList();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add an identity',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text('A separate profile for another kind of work.',
                style: TextStyle(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 20),
            const Text('Job type',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _pickProfession,
              icon: const Icon(Icons.work_outline),
              label: Text(_profession?.name ?? 'Choose a job type'),
              style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft),
            ),
            const SizedBox(height: 18),
            const Text('Name',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            TextField(
              controller: _name,
              maxLength: 60,
              textCapitalization: TextCapitalization.words,
              style: const TextStyle(fontSize: 16),
              decoration: const InputDecoration(
                hintText: 'For example: Cook',
                counterText: '',
              ),
            ),
            if (sources.isNotEmpty) ...[
              const SizedBox(height: 18),
              const Text('Start from',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String?>(
                value: _copyFrom,
                isExpanded: true,
                items: [
                  const DropdownMenuItem(
                      value: null, child: Text('Start empty')),
                  for (final s in sources)
                    DropdownMenuItem(value: s.id, child: Text(s.label)),
                ],
                onChanged: _busy ? null : (v) => setState(() => _copyFrom = v),
              ),
              if (_copyFrom != null) ...[
                const SizedBox(height: 6),
                for (final (key, label) in const [
                  ('skills', 'Skills'),
                  ('preferences', 'When and how I want to work'),
                  ('locations', 'Where I want to work'),
                ])
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _copy.contains(key),
                    title: Text(label),
                    onChanged: (on) => setState(
                        () => on == true ? _copy.add(key) : _copy.remove(key)),
                  ),
                Text('Verifications are never copied.',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant)),
              ],
            ],
            const SizedBox(height: 12),
            Text('New identities are private until you choose who can see them.',
                style:
                    TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy ? null : _create,
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }
}
