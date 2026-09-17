import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/hiring.dart';

/// Shared pieces for the Application Center and application detail.

Color toneColor(BuildContext context, StepTone tone) {
  final scheme = Theme.of(context).colorScheme;
  return switch (tone) {
    StepTone.action => OmeloTheme.warning,
    StepTone.good => OmeloTheme.verified,
    StepTone.waiting => scheme.primary,
    StepTone.closed => scheme.onSurfaceVariant,
  };
}

IconData toneIcon(StepTone tone) => switch (tone) {
      StepTone.action => Icons.error_outline,
      StepTone.good => Icons.check_circle_outline,
      StepTone.waiting => Icons.schedule,
      StepTone.closed => Icons.do_not_disturb_on_outlined,
    };

class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = switch (state) {
      'hired' || 'offer' => OmeloTheme.verified,
      'rejected' ||
      'withdrawn' ||
      'expired' ||
      'declined_by_candidate' =>
        scheme.onSurfaceVariant,
      _ => scheme.primary,
    };
    return Semantics(
      label: 'Status: ${HiringCopy.statusLabel(state)}',
      child: OmeloPill(
        HiringCopy.statusLabel(state),
        color: color,
        background: color.withValues(alpha: 0.10),
      ),
    );
  }
}

/// The "Next:" line. Highlighted when the worker has to do something.
class NextStepLine extends StatelessWidget {
  const NextStepLine({super.key, required this.step, this.large = false});
  final NextStep step;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = toneColor(context, step.tone);
    final highlight = step.needsAction || large;
    final text = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(toneIcon(step.tone), size: large ? 22 : 18, color: color),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            step.text,
            style: TextStyle(
              fontSize: large ? 16 : 14.5,
              height: 1.35,
              fontWeight: step.needsAction || large
                  ? FontWeight.w700
                  : FontWeight.w500,
              color: step.tone == StepTone.closed
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : null,
            ),
          ),
        ),
      ],
    );
    if (!highlight) return text;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(large ? 14 : 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: text,
    );
  }
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          ),
          if (trailing != null) trailing!,
        ],
      );
}
