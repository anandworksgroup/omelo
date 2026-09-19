import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive.dart';
import '../../data/global_repository.dart';
import '../../data/invitations.dart' show shortDate;
import 'global_widgets.dart';

/// Add or change my right to work in one country.
Future<void> showAuthorizationEditor(
  BuildContext context,
  WidgetRef ref, {
  required List<Country> countries,
  WorkAuthorization? existing,
  Iterable<String> taken = const [],
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      constraints: const BoxConstraints(maxWidth: Breakpoints.readingWidth),
      builder: (_) => AuthorizationEditor(
        countries: countries,
        existing: existing,
        taken: taken.where((c) => c != existing?.country).toList(),
      ),
    );

class AuthorizationEditor extends ConsumerStatefulWidget {
  const AuthorizationEditor({
    super.key,
    required this.countries,
    this.existing,
    this.taken = const [],
  });
  final List<Country> countries;
  final WorkAuthorization? existing;

  /// Countries already on the list (one record per country).
  final List<String> taken;

  @override
  ConsumerState<AuthorizationEditor> createState() =>
      _AuthorizationEditorState();
}

class _AuthorizationEditorState extends ConsumerState<AuthorizationEditor> {
  String? _country;
  WorkAuthStatus? _status;
  DateTime? _from;
  DateTime? _until;
  late final TextEditingController _limits;
  String? _error;
  bool _saving = false;

  bool get _locked => widget.existing?.isVerified ?? false;

  @override
  void initState() {
    super.initState();
    final a = widget.existing;
    _country = a?.country;
    _status = a?.status;
    _from = a?.validFrom;
    _until = a?.expiresOn;
    _limits = TextEditingController(text: a?.restrictions ?? '');
  }

  @override
  void dispose() {
    _limits.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = validateAuthorization(
      country: _country,
      status: _status,
      validFrom: _from,
      expiresOn: _until,
      restrictions: _limits.text,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final repo = ref.read(globalRepositoryProvider);
    // Citizens and permanent residents have no dates.
    final dated = _status!.hasDates;
    final from = dated ? _from : null;
    final until = dated || _locked ? _until : null;
    try {
      final a = widget.existing;
      if (a == null) {
        await repo.addAuthorization(
          country: _country!,
          status: _status!,
          validFrom: from,
          expiresOn: until,
          restrictions: _limits.text,
        );
      } else {
        await repo.updateAuthorization(
          a.id,
          country: _country!,
          status: _status!,
          validFrom: from,
          expiresOn: until,
          restrictions: _limits.text,
        );
      }
      ref.invalidate(myMobilityProvider);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = globalError(e);
        });
      }
    }
  }

  Future<DateTime?> _pickDate(DateTime? initial) {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(now.year - 60),
      lastDate: DateTime(now.year + 30),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final showDates = _status?.hasDates ?? true;
    String fmt(DateTime? d) => d == null ? 'Not set' : shortDate(d, DateTime(0));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.existing == null
                  ? 'Add your right to work'
                  : 'Right to work in ${widget.existing!.displayCountry}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            if (_locked) ...[
              const SizedBox(height: 8),
              Text(
                'Omelo verified this record, so the country, status and end '
                'date cannot be changed. You can still add a start date or '
                'limits, or remove it.',
                style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.flag_outlined),
              title: const Text('Country'),
              subtitle: Text(_country == null
                  ? 'Choose a country'
                  : countryName(_country, widget.countries)),
              trailing: _locked ? null : const Icon(Icons.chevron_right),
              enabled: !_locked,
              onTap: () async {
                final c = await pickCountry(context, widget.countries,
                    exclude: widget.taken);
                if (c != null) setState(() => _country = c.code);
              },
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<WorkAuthStatus>(
              value: _status,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'What lets you work there?',
              ),
              items: [
                for (final s in WorkAuthStatus.values)
                  DropdownMenuItem(value: s, child: Text(s.label)),
              ],
              onChanged: _locked ? null : (s) => setState(() => _status = s),
            ),
            if (_status != null) ...[
              const SizedBox(height: 6),
              Text(_status!.help,
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
            ],
            if (showDates) ...[
              const SizedBox(height: 16),
              ResponsiveFieldRow(children: [
                _DateField(
                  label: 'Valid from',
                  text: fmt(_from),
                  onTap: () async {
                    final d = await _pickDate(_from);
                    if (d != null) setState(() => _from = d);
                  },
                  onClear: _from == null ? null : () => setState(() => _from = null),
                ),
                _DateField(
                  label: 'Valid until',
                  text: fmt(_until),
                  enabled: !_locked,
                  onTap: () async {
                    final d = await _pickDate(_until ?? _from ?? now);
                    if (d != null) setState(() => _until = d);
                  },
                  onClear: _until == null || _locked
                      ? null
                      : () => setState(() => _until = null),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _limits,
              maxLength: WorkAuthorization.maxRestrictions,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Limits (optional)',
                hintText: 'e.g. Healthcare jobs only, 20 hours a week',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 4),
              Text(_error!, style: TextStyle(color: scheme.error)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.text,
    required this.onTap,
    this.onClear,
    this.enabled = true,
  });
  final String label;
  final String text;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool enabled;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            enabled: enabled,
            prefixIcon: const Icon(Icons.event_outlined),
            suffixIcon: onClear == null
                ? null
                : IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear $label',
                  ),
          ),
          child: Text(text, style: const TextStyle(fontSize: 16)),
        ),
      );
}
