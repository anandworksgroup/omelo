import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../data/identity_repository.dart';

/// Profile strength as a ring with the number inside.
class CompletenessRing extends StatelessWidget {
  const CompletenessRing({super.key, required this.score, this.size = 52});
  final int score;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = score >= 80
        ? OmeloTheme.verified
        : score >= kNudgeBelowScore
            ? scheme.primary
            : OmeloTheme.warning;
    return Semantics(
      label: 'Profile $score percent complete',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: score / 100,
                strokeWidth: 5,
                backgroundColor: scheme.surfaceContainerHighest,
                color: color,
              ),
            ),
            ExcludeSemantics(
              child: Text('$score%',
                  style: TextStyle(
                      fontSize: size * 0.26, fontWeight: FontWeight.w800)),
            ),
          ],
        ),
      ),
    );
  }
}

IconData visibilityIcon(IdentityVisibility v) => switch (v) {
      IdentityVisibility.private => Icons.lock_outline,
      IdentityVisibility.matchedOnly => Icons.handshake_outlined,
      IdentityVisibility.discoverable => Icons.verified_outlined,
      IdentityVisibility.recruiters => Icons.groups_outlined,
      IdentityVisibility.public => Icons.public,
    };

class VisibilityChip extends StatelessWidget {
  const VisibilityChip(this.visibility, {super.key});
  final IdentityVisibility visibility;

  @override
  Widget build(BuildContext context) => OmeloPill(
        visibility.title,
        icon: visibilityIcon(visibility),
        color: visibility == IdentityVisibility.public
            ? OmeloTheme.warning
            : null,
      );
}

class MainBadge extends StatelessWidget {
  const MainBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return OmeloPill('Main',
        icon: Icons.star,
        color: scheme.onPrimaryContainer,
        background: scheme.primaryContainer);
  }
}

/// The five visibility levels, each with one plain sentence.
class VisibilitySelector extends StatelessWidget {
  const VisibilitySelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final IdentityVisibility value;
  final ValueChanged<IdentityVisibility> onChanged;
  final bool enabled;

  Future<void> _pick(BuildContext context, IdentityVisibility v) async {
    if (v == value) return;
    final warning = v.warning;
    if (warning != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.public, color: OmeloTheme.warning),
          title: const Text('Make this public?'),
          content: Text(warning),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep it as it is')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Make public')),
          ],
        ),
      );
      if (ok != true) return;
    }
    onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final v in IdentityVisibility.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: enabled ? () => _pick(context, v) : null,
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: v == value
                      ? scheme.primaryContainer.withValues(alpha: 0.5)
                      : null,
                  border: Border.all(
                    color: v == value ? scheme.primary : scheme.outlineVariant,
                    width: v == value ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      v == value
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: v == value ? scheme.primary : scheme.outline,
                    ),
                    const SizedBox(width: 12),
                    Icon(visibilityIcon(v), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(v.title,
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(v.description,
                              style: TextStyle(
                                  fontSize: 13,
                                  height: 1.35,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        Text(kVisibilitySearchNote,
            style: TextStyle(
                fontSize: 12.5, height: 1.4, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class EvidenceBadge extends StatelessWidget {
  const EvidenceBadge(this.item, {super.key});
  final EvidenceItem item;

  static IconData iconFor(String type) => switch (type) {
        'verified_employment' => Icons.verified,
        'employer_verified' => Icons.business_center_outlined,
        'assessment' => Icons.fact_check_outlined,
        'experience' => Icons.schedule,
        'project' => Icons.build_outlined,
        _ => Icons.person_outline,
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: item.label,
      child: OmeloPill(
        evidenceBadge(item.type),
        icon: iconFor(item.type),
        color: item.verified ? OmeloTheme.verified : scheme.onSurfaceVariant,
        background: item.verified
            ? OmeloTheme.verified.withValues(alpha: 0.12)
            : null,
      ),
    );
  }
}

/// "Complete your Cook profile to get better matches" — Home and Discover.
/// Shows nothing when signed out, when the main identity is strong enough,
/// or if anything fails.
class IdentityNudgeCard extends ConsumerWidget {
  const IdentityNudgeCard({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final main = ref.watch(mainIdentityNudgeProvider).value;
    if (main == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/identities/${main.id}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CompletenessRing(score: main.completenessScore, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nudgeTitle(main),
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text('A few more details help employers say yes.',
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section title used on the identity screens.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing, this.subtitle});
  final String text;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 28, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!,
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.35,
                          color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

void showSnack(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}
