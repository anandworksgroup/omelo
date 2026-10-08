import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../data/network_repository.dart';

/// "What I see" — the feed preferences, as a sheet off the feed's app bar.
///
/// Four plain switches and the languages the worker reads. The server
/// applies them when it builds the feed; nothing is filtered here, so what
/// the worker turns off never arrives in the first place.
Future<FeedPreferences?> showFeedPreferencesSheet(
  BuildContext context,
  WidgetRef ref,
  FeedPreferences current,
) {
  return showModalBottomSheet<FeedPreferences>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => FeedPreferencesSheet(current: current),
  );
}

class FeedPreferencesSheet extends ConsumerStatefulWidget {
  const FeedPreferencesSheet({super.key, required this.current});
  final FeedPreferences current;

  @override
  ConsumerState<FeedPreferencesSheet> createState() =>
      _FeedPreferencesSheetState();
}

class _FeedPreferencesSheetState extends ConsumerState<FeedPreferencesSheet> {
  late FeedPreferences _p = widget.current;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved =
          await ref.read(networkRepositoryProvider).saveFeedPreferences(_p);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = networkError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final languages = ref.watch(languagesProvider).valueOrNull ?? const [];

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('What I see',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                'Omelo builds your feed with these. Turning something off '
                'means it never arrives, not that it is hidden afterwards.',
                style:
                    TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              _Switch(
                label: 'Jobs people share',
                description: 'Posts that carry an open job.',
                value: _p.showJobs,
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _p = _p.copyWith(showJobs: v)),
              ),
              _Switch(
                label: 'Organizations',
                description: 'Posts written by employers and agencies.',
                value: _p.showOrganizations,
                onChanged: _saving
                    ? null
                    : (v) =>
                        setState(() => _p = _p.copyWith(showOrganizations: v)),
              ),
              _Switch(
                label: 'Career content',
                description: 'Training, skills and advice about your trade.',
                value: _p.showCareerContent,
                onChanged: _saving
                    ? null
                    : (v) =>
                        setState(() => _p = _p.copyWith(showCareerContent: v)),
              ),
              _Switch(
                label: 'What my network is doing',
                description:
                    'New connections, follows and reactions from people you '
                    'know.',
                value: _p.showNetworkActivity,
                onChanged: _saving
                    ? null
                    : (v) => setState(
                        () => _p = _p.copyWith(showNetworkActivity: v)),
              ),
              if (languages.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('Languages I read',
                    style:
                        TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'Leave all of them off to see every language.',
                  style: TextStyle(
                      fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final l in languages)
                      if ((l['code'] ?? '').toString().isNotEmpty)
                        FilterChip(
                          label: Text((l['native_name'] ?? l['name'] ?? l['code'])
                              .toString()),
                          selected: _p.preferredLanguages
                              .contains(l['code'].toString()),
                          onSelected: _saving
                              ? null
                              : (on) => setState(() {
                                    final code = l['code'].toString();
                                    final next = [..._p.preferredLanguages];
                                    if (on) {
                                      if (!next.contains(code)) next.add(code);
                                    } else {
                                      next.remove(code);
                                    }
                                    _p = _p.copyWith(preferredLanguages: next);
                                  }),
                        ),
                  ],
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 14),
                Text(_error!,
                    style: TextStyle(fontSize: 13.5, color: scheme.error)),
              ],
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Saving…' : 'Save'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      value: value,
      onChanged: onChanged,
      contentPadding: EdgeInsets.zero,
      title: Text(label,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
      subtitle: Text(description,
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
    );
  }
}

