import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/responsive.dart';

/// Five destinations, presented differently by window size.
///
/// Phones get a bottom bar — thumb-reachable, always visible, never a drawer
/// (a hidden menu is invisible to a first-time user). Tablets and browsers get
/// a side rail instead, which is the platform convention and frees vertical
/// space that is scarce in landscape.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});
  final Widget child;

  static const _tabs = [
    ('/home', Icons.home_outlined, Icons.home, 'Home'),
    ('/discover', Icons.search_outlined, Icons.search, 'Discover'),
    ('/applications', Icons.assignment_outlined, Icons.assignment, 'Applications'),
    ('/messages', Icons.chat_bubble_outline, Icons.chat_bubble, 'Messages'),
    ('/profile', Icons.person_outline, Icons.person, 'Profile'),
  ];

  int _indexFor(String location) {
    for (var i = 0; i < _tabs.length; i++) {
      if (location.startsWith(_tabs[i].$1)) return i;
    }
    return 1; // Discover is the default landing tab
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.path;
    final index = _indexFor(location);
    final size = Breakpoints.of(context);
    final scheme = Theme.of(context).colorScheme;

    if (!size.usesNavigationRail) {
      return Scaffold(
        body: child,
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: (i) => context.go(_tabs[i].$1),
          destinations: [
            for (final (_, icon, selectedIcon, label) in _tabs)
              NavigationDestination(
                icon: Icon(icon),
                selectedIcon: Icon(selectedIcon),
                label: label,
                tooltip: label,
              ),
          ],
        ),
      );
    }

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: index,
            onDestinationSelected: (i) => context.go(_tabs[i].$1),
            extended: size.usesExtendedRail,
            labelType: size.usesExtendedRail
                ? NavigationRailLabelType.none
                : NavigationRailLabelType.all,
            backgroundColor: scheme.surface,
            leading: Padding(
              padding: EdgeInsets.only(
                top: 16,
                bottom: 8,
                left: size.usesExtendedRail ? 4 : 0,
              ),
              child: size.usesExtendedRail
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Omelo',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: scheme.primary,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    )
                  : Icon(Icons.work_outline, color: scheme.primary),
            ),
            destinations: [
              for (final (_, icon, selectedIcon, label) in _tabs)
                NavigationRailDestination(
                  icon: Icon(icon),
                  selectedIcon: Icon(selectedIcon),
                  label: Text(label),
                ),
            ],
          ),
          VerticalDivider(width: 1, color: scheme.outlineVariant),
          Expanded(child: child),
        ],
      ),
    );
  }
}

/// Screens that are specified but not yet implemented.
///
/// These state plainly what is not built rather than showing a fake UI.
/// A placeholder that looks functional is worse than one that is honest.
class NotBuiltYetScreen extends ConsumerWidget {
  const NotBuiltYetScreen({
    super.key,
    required this.title,
    required this.icon,
    required this.summary,
    required this.specRef,
    this.needsAccount = false,
  });

  final String title;
  final IconData icon;
  final String summary;
  final String specRef;
  final bool needsAccount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final signedIn = ref.watch(isSignedInProvider);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ContentWidth.reading(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
          children: [
            Icon(icon, size: 56, color: scheme.onSurfaceVariant),
            const SizedBox(height: 24),
            Text(
              'Not built yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Text(summary,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.5)),
            const SizedBox(height: 20),
            Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Spec: $specRef',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontFamily: 'monospace',
                        color: scheme.onSurfaceVariant)),
              ),
            ),
            if (needsAccount && !signedIn) ...[
              const SizedBox(height: 28),
              Text(
                'This screen needs an account.',
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 36),
            FilledButton(
              onPressed: () => context.go('/discover'),
              child: const Text('Find work'),
            ),
          ],
        ),
      ),
    );
  }
}
