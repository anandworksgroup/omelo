import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/identity_repository.dart';
import '../../data/work.dart';
import 'identity_widgets.dart';

/// Release 5: when this identity is free to work — dates, days, hours, how
/// many hours a week and how far to travel. Employers see how well their
/// shifts fit; nothing here is required.
class AvailabilityBlock extends ConsumerStatefulWidget {
  const AvailabilityBlock({super.key, required this.identityId});
  final String identityId;

  @override
  ConsumerState<AvailabilityBlock> createState() => _AvailabilityBlockState();
}

class _AvailabilityBlockState extends ConsumerState<AvailabilityBlock> {
  WorkAvailability? _a;
  final _hours = TextEditingController();
  final _km = TextEditingController();
  bool _dirty = false;
  bool _busy = false;

  @override
  void dispose() {
    _hours.dispose();
    _km.dispose();
    super.dispose();
  }

  void _adopt(WorkAvailability a) {
    if (_dirty || identical(_a, a)) return;
    _a = a;
    _hours.text = a.maxWeeklyHours?.toString() ?? '';
    _km.text = a.maxTravelKm?.toString() ?? '';
  }

  void _change(WorkAvailability a) => setState(() {
    _a = a;
    _dirty = true;
  });

  Future<void> _pickDate({required bool from}) async {
    final a = _a!;
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: (from ? a.availableFrom : a.availableUntil) ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3, 12, 31),
      helpText: from ? 'Available from' : 'Available until',
    );
    if (d == null) return;
    _change(
      from
          ? a.copyWith(availableFrom: () => d)
          : a.copyWith(availableUntil: () => d),
    );
  }

  Future<void> _pickTime({required bool start}) async {
    final a = _a!;
    final cur = parseHm(start ? a.preferredStart : a.preferredEnd);
    final t = await showTimePicker(
      context: context,
      initialTime: cur == null
          ? TimeOfDay(hour: start ? 9 : 17, minute: 0)
          : TimeOfDay(hour: cur.$1, minute: cur.$2),
      helpText: start ? 'Start after' : 'Finish by',
    );
    if (t == null) return;
    final v = hhmm('${t.hour}:${t.minute.toString().padLeft(2, '0')}');
    _change(
      start
          ? a.copyWith(preferredStart: () => v)
          : a.copyWith(preferredEnd: () => v),
    );
  }

  Future<void> _save() async {
    int? whole(String text) {
      final t = text.trim();
      return t.isEmpty ? null : int.tryParse(t);
    }

    final next = _a!.copyWith(
      maxWeeklyHours: () => whole(_hours.text),
      maxTravelKm: () => whole(_km.text),
    );
    final problem = validateAvailability(next);
    if (problem != null) {
      showSnack(context, problem);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(identityRepositoryProvider)
          .saveAvailability(widget.identityId, next);
      _dirty = false;
      ref.invalidate(identityAvailabilityProvider(widget.identityId));
      if (mounted) showSnack(context, 'Saved.');
    } catch (e) {
      if (mounted) showSnack(context, identityError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(identityAvailabilityProvider(widget.identityId));
    final scheme = Theme.of(context).colorScheme;
    final fmt = DateFormat('d MMM yyyy');
    const label = TextStyle(fontSize: 15, fontWeight: FontWeight.w700);

    Widget pickButton(String title, String? value, VoidCallback onTap,
            VoidCallback? onClear) =>
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onTap,
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 12.5)),
                      Text(
                        value ?? 'Any',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
              if (onClear != null)
                IconButton(
                  tooltip: 'Clear $title',
                  style:
                      IconButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: onClear,
                  icon: const Icon(Icons.close, size: 20),
                ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle(
          'When you are free to work',
          subtitle: 'Optional. Helps employers offer you shifts that fit.',
        ),
        async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(
            'Could not load your availability. ${identityError(e)}',
            style: TextStyle(color: scheme.error),
          ),
          data: (v) {
            _adopt(v);
            final a = _a!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Dates', style: label),
                const SizedBox(height: 8),
                Row(
                  children: [
                    pickButton(
                      'Available from',
                      a.availableFrom == null
                          ? null
                          : fmt.format(a.availableFrom!),
                      () => _pickDate(from: true),
                      a.availableFrom == null
                          ? null
                          : () => _change(
                              a.copyWith(availableFrom: () => null)),
                    ),
                    const SizedBox(width: 8),
                    pickButton(
                      'Until',
                      a.availableUntil == null
                          ? null
                          : fmt.format(a.availableUntil!),
                      () => _pickDate(from: false),
                      a.availableUntil == null
                          ? null
                          : () => _change(
                              a.copyWith(availableUntil: () => null)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Days you like to work', style: label),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(kDayShort[d - 1],
                            semanticsLabel: kDayLong[d - 1]),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 8),
                        selected: a.preferredDays.contains(d),
                        onSelected: (on) => _change(a.copyWith(
                          preferredDays: cleanDays(on
                              ? [...a.preferredDays, d]
                              : a.preferredDays.where((x) => x != d)),
                        )),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                const Text('Hours you like to work', style: label),
                const SizedBox(height: 8),
                Row(
                  children: [
                    pickButton(
                      'From',
                      a.preferredStart == null
                          ? null
                          : wallClock(a.preferredStart),
                      () => _pickTime(start: true),
                      a.preferredStart == null
                          ? null
                          : () => _change(a.copyWith(
                              preferredStart: () => null,
                              preferredEnd: () => null)),
                    ),
                    const SizedBox(width: 8),
                    pickButton(
                      'To',
                      a.preferredEnd == null ? null : wallClock(a.preferredEnd),
                      () => _pickTime(start: false),
                      null,
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _hours,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(3),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Most hours a week',
                        ),
                        onChanged: (_) => setState(() => _dirty = true),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _km,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Most travel (km)',
                        ),
                        onChanged: (_) => setState(() => _dirty = true),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _busy || !_dirty ? null : _save,
                  child: Text(_busy ? 'Saving…' : 'Save availability'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}
