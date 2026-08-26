import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/discover/discover_screen.dart';
import '../features/discover/job_detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/onboarding/onboarding_screens.dart';
import '../features/shell/app_shell.dart';
import 'app_state.dart';

/// Deeplink-first routing (A1 §16): every notification must resolve to a
/// screen, so every screen has a real URL.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const _Boot(),
      ),
      GoRoute(
        path: '/onboarding/language',
        builder: (_, __) => const LanguageScreen(),
      ),
      GoRoute(
        path: '/onboarding/country',
        builder: (_, __) => const CountryScreen(),
      ),
      GoRoute(
        path: '/onboarding/welcome',
        builder: (_, __) => const WelcomeScreen(),
      ),
      GoRoute(
        path: '/job/:id',
        builder: (_, state) =>
            JobDetailScreen(jobId: state.pathParameters['id']!),
      ),
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(path: '/discover', builder: (_, __) => const DiscoverScreen()),
          GoRoute(
            path: '/applications',
            builder: (_, __) => const NotBuiltYetScreen(
              title: 'Applications',
              icon: Icons.assignment_outlined,
              summary:
                  'The hiring timeline: every application with its real state, '
                  'the silence state with elapsed time, and honest rejection.',
              specRef: 'A1 §9',
              needsAccount: true,
            ),
          ),
          GoRoute(
            path: '/messages',
            builder: (_, __) => const NotBuiltYetScreen(
              title: 'Messages',
              icon: Icons.chat_bubble_outline,
              summary:
                  'Job-anchored conversations with employers, with structured '
                  'actions, block and report always one tap away.',
              specRef: 'A1 §10',
              needsAccount: true,
            ),
          ),
          GoRoute(
            path: '/profile',
            builder: (_, __) => const NotBuiltYetScreen(
              title: 'My Omelo',
              icon: Icons.person_outline,
              summary:
                  'Your work identity — adaptive profile, documents, licences, '
                  'verification, and up to five kinds of work with separate '
                  'pay, availability and privacy.',
              specRef: 'A1 §11',
              needsAccount: true,
            ),
          ),
        ],
      ),
    ],
  );
});

/// Decides where a cold start lands. Onboarding runs once.
class _Boot extends ConsumerWidget {
  const _Boot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(appPrefsProvider);

    return prefs.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const Scaffold(
        body: Center(child: Text('Something went wrong starting the app.')),
      ),
      data: (p) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          context.go(p.onboarded ? '/discover' : '/onboarding/language');
        });
        return const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
