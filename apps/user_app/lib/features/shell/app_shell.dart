import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';

/// Five permanent tabs (A1 §2.1). Never collapsed into a drawer — a hidden
/// menu is invisible to a first-time user.
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
      body: ListView(
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
              'This screen needs an account. Phone sign-in is the next build step.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 36),
          FilledButton(
            onPressed: () => context.go('/discover'),
            child: const Text('Find work'),
          ),
        ],
      ),
    );
  }
}
