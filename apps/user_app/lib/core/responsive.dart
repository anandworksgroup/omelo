import 'package:flutter/material.dart';

/// Responsive layout system.
///
/// Breakpoints follow Material 3 window size classes, which map cleanly onto
/// the real device spread: a 5" Android phone, a 6.7" iPhone, a 10" tablet in
/// either orientation, a foldable, and a desktop browser.
///
///   compact   < 600   phones, portrait
///   medium    600-839 small tablets, large phones landscape, foldables
///   expanded  840-1199 tablets landscape, small laptops
///   large     >= 1200 desktop browsers
///
/// Two rules drive every layout decision here:
///
/// 1. **Line length is capped.** Text that runs the full width of a 27" monitor
///    is unreadable. Reading content is constrained to ~700px regardless of
///    how much room there is.
/// 2. **Extra width becomes more columns, not wider rows.** A tablet shows two
///    job cards side by side rather than one very wide one.
enum WindowSize { compact, medium, expanded, large }

extension WindowSizeX on WindowSize {
  bool get isCompact => this == WindowSize.compact;
  bool get isMedium => this == WindowSize.medium;

  /// Phones use a bottom bar; anything wider uses a side rail, which keeps
  /// the thumb-reachable area free and matches platform convention.
  bool get usesNavigationRail => index >= WindowSize.medium.index;

  /// Only the widest layouts get labels always visible beside the rail.
  bool get usesExtendedRail => this == WindowSize.large;

  /// Columns for card grids (jobs, applications).
  int get gridColumns => switch (this) {
        WindowSize.compact => 1,
        WindowSize.medium => 2,
        WindowSize.expanded => 2,
        WindowSize.large => 3,
      };

  /// Columns for dense form fields.
  int get formColumns => this == WindowSize.compact ? 1 : 2;

  double get gutter => switch (this) {
        WindowSize.compact => 16,
        WindowSize.medium => 20,
        _ => 24,
      };
}

class Breakpoints {
  static const medium = 600.0;
  static const expanded = 840.0;
  static const large = 1200.0;

  /// Maximum width for prose and single-column forms.
  static const readingWidth = 700.0;

  /// Maximum width for multi-column grids and dashboards.
  static const contentWidth = 1180.0;

  static WindowSize of(BuildContext context) =>
      fromWidth(MediaQuery.sizeOf(context).width);

  static WindowSize fromWidth(double width) {
    if (width < medium) return WindowSize.compact;
    if (width < expanded) return WindowSize.medium;
    if (width < large) return WindowSize.expanded;
    return WindowSize.large;
  }

  /// True when the window is short enough that vertical space is scarce —
  /// a phone in landscape, or a browser with dev tools open. Large vertical
  /// spacers get trimmed in this case.
  static bool isShort(BuildContext context) =>
      MediaQuery.sizeOf(context).height < 600;
}

/// Centres content and caps its width.
///
/// Use [reading] for text-heavy screens (job detail, apply, profile) and the
/// default for grids and dashboards.
class ContentWidth extends StatelessWidget {
  const ContentWidth({
    super.key,
    required this.child,
    this.maxWidth = Breakpoints.contentWidth,
    this.padding,
  });

  const ContentWidth.reading({
    super.key,
    required this.child,
    this.padding,
  }) : maxWidth = Breakpoints.readingWidth;

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final inner =
        padding == null ? child : Padding(padding: padding!, child: child);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Take the full width up to the cap. Without the explicit width a
        // child that does not expand on its own (an Icon, a Text, a bare
        // SizedBox) collapses to its intrinsic size and the centring looks
        // broken.
        final width = constraints.hasBoundedWidth
            ? (constraints.maxWidth < maxWidth ? constraints.maxWidth : maxWidth)
            : maxWidth;

        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(width: width, child: inner),
        );
      },
    );
  }
}

/// A list that becomes a grid as the window widens.
///
/// Cards keep a sane width instead of stretching, which is what makes a job
/// list readable on a tablet or a desktop browser.
class ResponsiveCardGrid extends StatelessWidget {
  const ResponsiveCardGrid({
    super.key,
    required this.children,
    this.spacing = 12,
    this.minCardWidth = 340,
  });

  final List<Widget> children;
  final double spacing;
  final double minCardWidth;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns =
            (constraints.maxWidth / minCardWidth).floor().clamp(1, 3);

        if (columns == 1) {
          return Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) SizedBox(height: spacing),
              ],
            ],
          );
        }

        // Masonry-free balanced columns: cards vary in height, so distribute
        // round-robin and let each column size itself.
        final buckets = List.generate(columns, (_) => <Widget>[]);
        for (var i = 0; i < children.length; i++) {
          buckets[i % columns].add(children[i]);
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < buckets[c].length; i++) ...[
                      buckets[c][i],
                      if (i != buckets[c].length - 1) SizedBox(height: spacing),
                    ],
                  ],
                ),
              ),
              if (c != columns - 1) SizedBox(width: spacing),
            ],
          ],
        );
      },
    );
  }
}

/// Lays fields out in one column on phones and two on wider windows.
class ResponsiveFieldRow extends StatelessWidget {
  const ResponsiveFieldRow({
    super.key,
    required this.children,
    this.spacing = 14,
  });

  final List<Widget> children;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final size = Breakpoints.of(context);
    if (size.formColumns == 1) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) SizedBox(height: spacing),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i != children.length - 1) SizedBox(width: spacing),
        ],
      ],
    );
  }
}
