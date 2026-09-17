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

/// ✓ Applied · ✓ Employer viewed · ✓ Shortlisted · ● Technical Interview ·
/// ○ Offer · ○ Hired — a vertical stepper that reads top to bottom on any
/// screen width.
class ProcessStepper extends StatelessWidget {
  const ProcessStepper({super.key, required this.steps});
  final List<ProcessStep> steps;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          _ProcessStepTile(step: steps[i], last: i == steps.length - 1),
      ],
    );
  }
}

class _ProcessStepTile extends StatelessWidget {
  const _ProcessStepTile({required this.step, required this.last});
  final ProcessStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color color, IconData icon, String spoken) = switch (step.state) {
      ProcessStepState.done => (OmeloTheme.verified, Icons.check_circle, 'done'),
      ProcessStepState.current =>
        (scheme.primary, Icons.radio_button_checked, 'you are here'),
      ProcessStepState.upcoming =>
        (scheme.outline, Icons.radio_button_unchecked, 'still to come'),
      ProcessStepState.skipped =>
        (scheme.onSurfaceVariant, Icons.remove_circle_outline, 'did not happen'),
      ProcessStepState.closed =>
        (scheme.onSurfaceVariant, Icons.do_not_disturb_on, 'closed'),
    };
    final current = step.state == ProcessStepState.current;

    return Semantics(
      label: '${step.label}, $spoken${step.detail == null ? '' : ', ${step.detail}'}',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 28,
              child: Column(
                children: [
                  Icon(icon, size: 24, color: color),
                  if (!last)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: step.state == ProcessStepState.done
                            ? OmeloTheme.verified.withValues(alpha: 0.5)
                            : scheme.outlineVariant,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: last ? 0 : 14, top: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      step.label,
                      style: TextStyle(
                        fontSize: current ? 16 : 15,
                        fontWeight: current ? FontWeight.w800 : FontWeight.w600,
                        color: step.state == ProcessStepState.upcoming
                            ? scheme.onSurfaceVariant
                            : null,
                      ),
                    ),
                    if (step.detail != null)
                      Text(
                        step.detail!,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: current ? scheme.primary : scheme.onSurfaceVariant,
                          fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
