/// The pieces every screen is built from.
///
/// These existed thirty-two times over, written slightly differently each
/// time: a column with an icon and some grey text for "nothing here", a
/// spinner in the middle of a blank page for "loading". One of each, here,
/// so a worker sees the same thing wherever they are in the app.
library;

import 'package:flutter/material.dart';

import 'theme.dart';

/// Nothing to show — and what to do about it.
///
/// An empty screen is a dead end unless it says why it is empty and what
/// would fill it. [body] is that sentence; keep it concrete.
class OmeloEmptyState extends StatelessWidget {
  const OmeloEmptyState({
    super.key,
    required this.title,
    this.body,
    this.icon,
    this.action,
    this.compact = false,
  });

  final String title;
  final String? body;
  final IconData? icon;

  /// The one thing to do next, if there is one.
  final Widget? action;

  /// Inside a card or a tab rather than filling a screen.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: OmeloTheme.gapXl,
          vertical: compact ? OmeloTheme.gapXl : 48,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Container(
                padding: const EdgeInsets.all(OmeloTheme.gapLg),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 28, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: OmeloTheme.gapLg),
            ],
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (body != null) ...[
              const SizedBox(height: OmeloTheme.gapSm),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Text(
                  body!,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: OmeloTheme.gapXl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A whole screen that has nothing on it yet, or could not load.
///
/// Scrollable by default so a pull-to-refresh still works on a screen with
/// nothing in it — which is exactly the screen someone most wants to retry.
class OmeloMessage extends StatelessWidget {
  const OmeloMessage({
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
    return ListView(
      physics: scrollable
          ? const AlwaysScrollableScrollPhysics()
          : const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
      children: [
        OmeloEmptyState(
          icon: icon,
          title: title,
          body: body,
          action: actionLabel == null
              ? null
              : FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ),
      ],
    );
  }
}

/// Something went wrong, said plainly, with the way back.
class OmeloErrorState extends StatelessWidget {
  const OmeloErrorState({
    super.key,
    this.title = 'That did not load',
    this.message,
    this.onRetry,
  });

  final String title;
  final String? message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return OmeloMessage(
      icon: Icons.cloud_off_outlined,
      title: title,
      body: message ??
          'Check your connection and try again. Nothing you have done has been lost.',
      actionLabel: onRetry == null ? null : 'Try again',
      onAction: onRetry,
    );
  }
}

/// A grey block standing in for a line of text or an avatar while it loads.
///
/// A skeleton of the thing that is coming beats a spinner on an empty page:
/// it says what is about to be there and keeps the layout from jumping when
/// it arrives.
class OmeloSkeleton extends StatefulWidget {
  const OmeloSkeleton({
    super.key,
    this.width,
    this.height = 12,
    this.radius = OmeloTheme.radiusSm,
    this.shape = BoxShape.rectangle,
  });

  /// A circle, for an avatar placeholder.
  const OmeloSkeleton.circle({super.key, required double size})
      : width = size,
        height = size,
        radius = 0,
        shape = BoxShape.circle;

  final double? width;
  final double height;
  final double radius;
  final BoxShape shape;

  @override
  State<OmeloSkeleton> createState() => _OmeloSkeletonState();
}

class _OmeloSkeletonState extends State<OmeloSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = scheme.surfaceContainerHighest;
    final highlight = Color.alphaBlend(
      scheme.surface.withValues(alpha: 0.55),
      base,
    );
    // Someone who has asked for less motion gets a plain block.
    if (MediaQuery.disableAnimationsOf(context)) {
      return _box(base, null);
    }
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final t = _c.value * 2 - 1; // -1 .. 1
        return _box(
          base,
          LinearGradient(
            begin: Alignment(t - 0.6, 0),
            end: Alignment(t + 0.6, 0),
            colors: [base, highlight, base],
          ),
        );
      },
    );
  }

  Widget _box(Color base, Gradient? gradient) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base,
          gradient: gradient,
          shape: widget.shape,
          borderRadius: widget.shape == BoxShape.circle
              ? null
              : BorderRadius.circular(widget.radius),
        ),
      );
}

/// Several card-shaped placeholders, for a list that is still loading.
class OmeloSkeletonList extends StatelessWidget {
  const OmeloSkeletonList({
    super.key,
    this.count = 4,
    this.hasAvatar = true,
    this.padding = const EdgeInsets.all(OmeloTheme.gapLg),
  });

  final int count;
  final bool hasAvatar;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      itemCount: count,
      separatorBuilder: (_, __) => const SizedBox(height: OmeloTheme.gapMd),
      itemBuilder: (_, __) => const _SkeletonCard(),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(OmeloTheme.gapLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const OmeloSkeleton.circle(size: 40),
                  const SizedBox(width: OmeloTheme.gapMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        OmeloSkeleton(width: 150),
                        SizedBox(height: OmeloTheme.gapSm),
                        OmeloSkeleton(width: 100, height: 10),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: OmeloTheme.gapLg),
              const OmeloSkeleton(width: double.infinity, height: 10),
              const SizedBox(height: OmeloTheme.gapSm),
              const OmeloSkeleton(width: 220, height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// A heading above a group, with an optional action on the right.
class OmeloSectionHeader extends StatelessWidget {
  const OmeloSectionHeader(this.title, {super.key, this.action, this.padding});

  final String title;
  final Widget? action;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding ??
          const EdgeInsets.only(bottom: OmeloTheme.gapSm, top: OmeloTheme.gapXs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.8,
              ),
            ),
          ),
          if (action != null) action!,
        ],
      ),
    );
  }
}

/// A bar for a proportion: a match score, a profile's completeness, how far
/// through an assessment someone is.
class OmeloMeter extends StatelessWidget {
  const OmeloMeter({
    super.key,
    required this.value,
    this.color,
    this.height = 6,
    this.semanticLabel,
  });

  /// 0..1. Values outside that are clamped rather than overflowing the track.
  final double value;
  final Color? color;
  final double height;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      value: '${(value.clamp(0, 1) * 100).round()}%',
      child: ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: LinearProgressIndicator(
          value: value.clamp(0, 1),
          minHeight: height,
          backgroundColor: scheme.surfaceContainerHighest,
          valueColor: AlwaysStoppedAnimation(color ?? scheme.primary),
        ),
      ),
    );
  }
}
