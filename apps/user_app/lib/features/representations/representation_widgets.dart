import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/representations_repository.dart';
import '../invitations/invitation_widgets.dart' show CompanyAvatar;
import '../messages/inbox_providers.dart' show notificationsProvider;

export '../invitations/invitation_widgets.dart' show CompanyAvatar;

/// Agency name with the verified tick, and "Independent recruiter" when it
/// is one person working alone.
class AgencyName extends StatelessWidget {
  const AgencyName({
    super.key,
    required this.name,
    required this.verified,
    this.independent = false,
    this.fontSize = 15,
    this.showWord = false,
  });

  final String name;
  final bool verified;
  final bool independent;
  final double fontSize;

  /// Also write "Verified" next to the tick.
  final bool showWord;

  @override
  Widget build(BuildContext context) {
    final nameRow = Row(
      children: [
        Flexible(
          child: Text(
            name,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w700),
          ),
        ),
        if (verified) ...[
          const SizedBox(width: 5),
          Icon(
            Icons.verified,
            size: fontSize + 1,
            color: OmeloTheme.verified,
            semanticLabel: 'Verified agency',
          ),
          if (showWord) ...[
            const SizedBox(width: 3),
            const Text(
              'Verified',
              style: TextStyle(
                fontSize: 12.5,
                color: OmeloTheme.verified,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ],
    );
    if (!independent) return nameRow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        nameRow,
        const SizedBox(height: 4),
        const OmeloPill('Independent recruiter', icon: Icons.person_outline),
      ],
    );
  }
}

/// Status chip for a representation.
class RepresentationStatusPill extends StatelessWidget {
  const RepresentationStatusPill(this.status, {super.key});
  final RepresentationStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color fg, Color bg, IconData icon) = switch (status) {
      RepresentationStatus.requested => (
        scheme.onPrimaryContainer,
        scheme.primaryContainer,
        Icons.mark_email_unread_outlined,
      ),
      RepresentationStatus.accepted || RepresentationStatus.active => (
        OmeloTheme.verified,
        OmeloTheme.verified.withValues(alpha: 0.12),
        Icons.handshake_outlined,
      ),
      RepresentationStatus.declined || RepresentationStatus.revoked => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
        Icons.do_not_disturb_on_outlined,
      ),
      RepresentationStatus.expired || RepresentationStatus.withdrawn => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHighest,
        Icons.schedule_outlined,
      ),
    };
    return OmeloPill(
      representationStatusLabel(status),
      icon: icon,
      color: fg,
      background: bg,
    );
  }
}

/// "What will be shared": ticked items, then greyed "Not shared" ones.
class ScopeChecklist extends StatelessWidget {
  const ScopeChecklist({super.key, required this.items});
  final List<ScopeItem> items;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shared = items.where((i) => i.shared);
    final notShared = items.where((i) => !i.shared);
    Widget row(ScopeItem i) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            i.shared ? Icons.check_circle : Icons.remove_circle_outline,
            size: 22,
            color: i.shared ? OmeloTheme.verified : scheme.outline,
            semanticLabel: i.shared ? 'Shared' : 'Not shared',
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              i.label,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.35,
                fontWeight: i.shared ? FontWeight.w600 : FontWeight.w400,
                color: i.shared ? null : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (!i.shared)
            Padding(
              padding: const EdgeInsets.only(left: 8, top: 2),
              child: Text(
                'Not shared',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final i in shared) row(i),
        for (final i in notShared) row(i),
      ],
    );
  }
}

/// Submitted → Reviewing → … → Hired, as a vertical list of steps.
class SubmissionTimeline extends StatelessWidget {
  const SubmissionTimeline({super.key, required this.status});
  final SubmissionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final steps = submissionTimeline(status);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          _StepRow(step: steps[i], last: i == steps.length - 1, scheme: scheme),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.step,
    required this.last,
    required this.scheme,
  });
  final SubmissionStep step;
  final bool last;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String said) = switch (step.state) {
      SubmissionStepState.done => (
        Icons.check_circle,
        OmeloTheme.verified,
        'done',
      ),
      SubmissionStepState.current => (
        Icons.radio_button_checked,
        scheme.primary,
        'now',
      ),
      SubmissionStepState.upcoming => (
        Icons.radio_button_unchecked,
        scheme.outline,
        'not yet',
      ),
      SubmissionStepState.stopped => (
        Icons.cancel_outlined,
        scheme.onSurfaceVariant,
        'ended',
      ),
    };
    final strong =
        step.state == SubmissionStepState.current ||
        step.state == SubmissionStepState.stopped;
    return Semantics(
      label: '${step.label}, $said',
      excludeSemantics: true,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Column(
              children: [
                Icon(icon, size: 24, color: color),
                if (!last)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 2),
                      color: step.state == SubmissionStepState.done
                          ? OmeloTheme.verified.withValues(alpha: 0.5)
                          : scheme.outlineVariant,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: 2, bottom: last ? 0 : 14),
                child: Text(
                  step.label,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
                    color: step.state == SubmissionStepState.upcoming
                        ? scheme.onSurfaceVariant
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One request in a list.
class RepresentationCard extends StatelessWidget {
  const RepresentationCard({
    super.key,
    required this.representation,
    required this.onTap,
  });

  final Representation representation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final r = representation;
    final t = r.terms;
    final now = DateTime.now();
    final status = r.statusAt(now);
    final scheme = Theme.of(context).colorScheme;
    final answerBy = representationAnswerBy(r, now);
    final pay = representationPayLabel(t.pay);
    final place = [
      if (t.location != null) t.location!,
      representationTypeLine(t),
    ].where((s) => s.isNotEmpty).join(' · ');
    final sub = r.submission;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CompanyAvatar(name: t.agencyName, logoUrl: t.agencyLogo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AgencyName(name: t.agencyName, verified: t.agencyVerified),
                    const SizedBox(height: 2),
                    Text(
                      t.position,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        height: 1.25,
                      ),
                    ),
                    Text(
                      'at ${t.clientName}',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (pay != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        pay,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        place,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        RepresentationStatusPill(status),
                        if (sub != null && status.isRepresented)
                          OmeloPill(
                            submissionStatusLabel(sub.status),
                            icon: Icons.send_outlined,
                          ),
                        if (answerBy != null)
                          Text(
                            answerBy,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// Home: "Acme Staffing wants to represent you for Warehouse Associate" —
/// only while some request is waiting. One opens it; several open the list.
class RepresentationsHomeCard extends ConsumerWidget {
  const RepresentationsHomeCard({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A new request notification means a new request.
    ref.listen<int>(
      notificationsProvider.select(
        (s) => s.items
            .where(
              (n) =>
                  n.type == 'representation_request' ||
                  n.type == 'representation_update',
            )
            .length,
      ),
      (_, __) => ref.invalidate(myRepresentationsProvider),
    );
    final pending = ref.watch(pendingRepresentationsProvider);
    if (pending.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final one = pending.length == 1 ? pending.single : null;
    return Padding(
      padding: padding,
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push(
            one == null ? representationsRoute() : '/representations/${one.id}',
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Badge(
                    label: Text('${pending.length}'),
                    child: Icon(
                      Icons.handshake_outlined,
                      size: 30,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          representHomeTitle(pending),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          one == null
                              ? 'See what they are asking and answer.'
                              : 'See what would be shared, then say yes or '
                                    'no.',
                          style: TextStyle(
                            fontSize: 13.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A centred message with an optional button, for empty and error states.
class RepresentationMessage extends StatelessWidget {
  const RepresentationMessage({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
    this.scrollable = true,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: scrollable
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(icon, size: 56, color: scheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15.5, height: 1.45),
                ),
                if (actionLabel != null) ...[
                  const SizedBox(height: 24),
                  FilledButton(onPressed: onAction, child: Text(actionLabel!)),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The promise, in one card: shown on the recruiters screen and the empty
/// list.
class RecruiterPromiseCard extends StatelessWidget {
  const RecruiterPromiseCard({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.verified_user_outlined, color: scheme.primary, size: 28),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'You stay in control',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 4),
                Text(
                  'Recruiters can only put you forward with your yes, for one '
                  'job at a time, for a limited time. You can take your yes '
                  'back until the employer starts looking at you.',
                  style: TextStyle(fontSize: 14.5, height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Submitted by Acme Staffing" on an application an agency sent for me.
/// Nothing when I applied myself (or the list has not loaded).
class SubmittedByLine extends ConsumerWidget {
  const SubmittedByLine({
    super.key,
    required this.applicationId,
    this.padding = const EdgeInsets.only(top: 4),
  });

  final String applicationId;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agency = ref.watch(agencyByApplicationProvider)[applicationId];
    if (agency == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Icon(
            Icons.handshake_outlined,
            size: 16,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Submitted by $agency',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
