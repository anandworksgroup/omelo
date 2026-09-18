import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../data/identity.dart';

/// One adaptive profile question, rendered with the widget its data type
/// calls for (see [inputKindFor]). The value is the decoded widget value
/// (see [decodeFieldValue]); [onChanged] reports the new one.
class ProfileFieldInput extends StatelessWidget {
  const ProfileFieldInput({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  final ProfileField field;
  final Object? value;
  final ValueChanged<Object?> onChanged;
  final String? errorText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kind = inputKindFor(field);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (kind != FieldInputKind.toggle) ...[
          _Label(field: field),
          const SizedBox(height: 8),
        ],
        _input(context, kind),
        if (errorText != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: scheme.error),
              const SizedBox(width: 6),
              Expanded(
                child: Text(errorText!,
                    style: TextStyle(color: scheme.error, fontSize: 13)),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _input(BuildContext context, FieldInputKind kind) {
    final scheme = Theme.of(context).colorScheme;
    switch (kind) {
      case FieldInputKind.text:
      case FieldInputKind.longText:
        return _TextInput(
          key: ValueKey('text-${field.slug}'),
          initial: (value as String?) ?? '',
          maxLines: kind == FieldInputKind.longText ? 5 : 1,
          maxLength: kind == FieldInputKind.longText ? 2000 : 300,
          onChanged: onChanged,
        );
      case FieldInputKind.number:
        return _TextInput(
          key: ValueKey('number-${field.slug}'),
          initial: _numText(value),
          number: true,
          suffix: field.unit ?? (field.dataType == 'years' ? 'years' : null),
          onChanged: onChanged,
        );
      case FieldInputKind.toggle:
        final v = value as bool?;
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: SwitchListTile(
            value: v ?? false,
            onChanged: onChanged,
            title: _Label(field: field, dense: true),
            subtitle: v == null
                ? Row(
                    children: [
                      const Text('Not answered yet'),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: () => onChanged(false),
                        child: const Text('Answer No'),
                      ),
                    ],
                  )
                : Text(v ? 'Yes' : 'No'),
          ),
        );
      case FieldInputKind.segmented:
        final v = value as String?;
        return SizedBox(
          width: double.infinity,
          child: SegmentedButton<String>(
            emptySelectionAllowed: true,
            showSelectedIcon: false,
            style: const ButtonStyle(
              minimumSize: WidgetStatePropertyAll(Size(0, 52)),
            ),
            segments: [
              for (final o in field.options)
                ButtonSegment(value: o, label: Text(o)),
            ],
            selected: v == null ? const {} : {v},
            onSelectionChanged: (s) => onChanged(s.isEmpty ? null : s.first),
          ),
        );
      case FieldInputKind.radio:
        final v = value as String?;
        return Container(
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              for (final o in field.options)
                RadioListTile<String>(
                  value: o,
                  groupValue: v,
                  toggleable: true,
                  title: Text(o, style: const TextStyle(fontSize: 15)),
                  onChanged: onChanged,
                ),
            ],
          ),
        );
      case FieldInputKind.chips:
        final picked = (value as List?)?.cast<String>() ?? const <String>[];
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final o in field.options)
              FilterChip(
                label: Text(o, style: const TextStyle(fontSize: 14.5)),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                selected: picked.contains(o),
                onSelected: (on) => onChanged(on
                    ? [...picked, o]
                    : picked.where((p) => p != o).toList()),
              ),
          ],
        );
      case FieldInputKind.tags:
        return _TagsInput(
          key: ValueKey('tags-${field.slug}'),
          items: (value as List?)?.cast<String>() ?? const <String>[],
          onChanged: onChanged,
        );
      case FieldInputKind.date:
        final d = value as DateTime?;
        return Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.calendar_today_outlined),
                label: Text(d == null
                    ? 'Choose a date'
                    : DateFormat.yMMMd().format(d)),
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: d ?? now,
                    firstDate: DateTime(1950),
                    lastDate: DateTime(now.year + 20),
                  );
                  if (picked != null) onChanged(picked);
                },
              ),
            ),
            if (d != null)
              IconButton(
                tooltip: 'Clear',
                icon: const Icon(Icons.close),
                onPressed: () => onChanged(null),
              ),
          ],
        );
      case FieldInputKind.unsupported:
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            field.dataType == 'file'
                ? 'You will be able to add a document here soon.'
                : 'This question cannot be answered in the app yet.',
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
          ),
        );
    }
  }

  static String _numText(Object? v) {
    if (v == null) return '';
    if (v is num) {
      return v == v.roundToDouble() ? v.round().toString() : v.toString();
    }
    return v.toString();
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.field, this.dense = false});
  final ProfileField field;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: field.label),
            if (field.isRequired)
              TextSpan(
                text: '  Required',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.error),
              ),
          ]),
          style: TextStyle(
              fontSize: dense ? 15 : 15.5, fontWeight: FontWeight.w700),
        ),
        if (field.helpText != null && field.helpText!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(field.helpText!,
              style: TextStyle(
                  fontSize: 13, height: 1.35, color: scheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

class _TextInput extends StatefulWidget {
  const _TextInput({
    super.key,
    required this.initial,
    required this.onChanged,
    this.maxLines = 1,
    this.maxLength,
    this.number = false,
    this.suffix,
  });

  final String initial;
  final ValueChanged<Object?> onChanged;
  final int maxLines;
  final int? maxLength;
  final bool number;
  final String? suffix;

  @override
  State<_TextInput> createState() => _TextInputState();
}

class _TextInputState extends State<_TextInput> {
  late final _ctl = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctl,
      maxLines: widget.maxLines,
      minLines: 1,
      maxLength: widget.number ? null : widget.maxLength,
      keyboardType: widget.number
          ? const TextInputType.numberWithOptions(decimal: true)
          : (widget.maxLines > 1 ? TextInputType.multiline : TextInputType.text),
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        suffixText: widget.suffix,
        counterText: widget.maxLines > 1 ? null : '',
      ),
      onChanged: widget.onChanged,
    );
  }
}

/// Free-text list: type an item, press Add (or Enter); tap x to remove.
/// Up to 20 items of 1-80 characters, no repeats (the server enforces the same).
class _TagsInput extends StatefulWidget {
  const _TagsInput({super.key, required this.items, required this.onChanged});

  final List<String> items;
  final ValueChanged<Object?> onChanged;

  @override
  State<_TagsInput> createState() => _TagsInputState();
}

class _TagsInputState extends State<_TagsInput> {
  static const _maxItems = 20;
  final _ctrl = TextEditingController();
  String? _hint;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _add() {
    final t = _ctrl.text.trim();
    if (t.isEmpty) return;
    if (widget.items.any((i) => i.toLowerCase() == t.toLowerCase())) {
      setState(() => _hint = 'Already added');
      return;
    }
    if (widget.items.length >= _maxItems) {
      setState(() => _hint = 'You can add up to $_maxItems');
      return;
    }
    _ctrl.clear();
    setState(() => _hint = null);
    widget.onChanged([...widget.items, t]);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.items.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final i in widget.items)
                InputChip(
                  label: Text(i, style: const TextStyle(fontSize: 14.5)),
                  onDeleted: () {
                    final rest = widget.items.where((x) => x != i).toList();
                    widget.onChanged(rest.isEmpty ? null : rest);
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _ctrl,
                maxLength: 80,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _add(),
                decoration: InputDecoration(
                  hintText: 'Type and press Add',
                  errorText: _hint,
                  counterText: '',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              height: 52,
              child: FilledButton.tonal(onPressed: _add, child: const Text('Add')),
            ),
          ],
        ),
      ],
    );
  }
}
