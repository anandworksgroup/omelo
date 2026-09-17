import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/applications/application_detail_screen.dart';
import '../features/applications/applications_screen.dart';
import '../features/apply/apply_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/company/company_screen.dart';
import '../features/discover/discover_screen.dart';
import '../features/discover/job_detail_screen.dart';
import '../features/home/home_screen.dart';
import '../features/meet/meet_screen.dart';
import '../features/messages/messages_screen.dart';
import '../features/messages/thread_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/onboarding_screens.dart';
import '../features/profile/profile_screen.dart';
import '../features/shell/app_shell.dart';
import 'app_state.dart';

/// Deeplink-first routing (A1 §16): every notification must resolve to a
/// screen, so every screen has a real URL.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => const _Boot()),
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
        path: '/sign-in',
        builder: (_, state) =>
            SignInScreen(redirectTo: state.uri.queryParameters['next']),
      ),
      GoRoute(
        path: '/job/:id',
        builder: (_, state) =>
            JobDetailScreen(jobId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/company/:id',
        builder: (_, state) =>
            CompanyScreen(companyId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/apply/:id',
        builder: (_, state) => ApplyScreen(jobId: state.pathParameters['id']!),
      ),
      // Notification deeplinks (`/applications/<id>`) land here. Declared
      // before the shell so it opens full screen, like job detail.
      GoRoute(
        path: '/applications/:id',
        builder: (_, state) => ApplicationDetailScreen(
            applicationId: state.pathParameters['id']!),
      ),
      // Omelo Meet interview rooms (email and in-app "Join Interview" links).
      // Full screen, outside the tab shell. Signed-out visitors sign in first
      // and come straight back here.
      GoRoute(
        path: '/meet/:room',
        redirect: _requireSignIn,
        builder: (_, state) =>
            MeetScreen(roomName: state.pathParameters['room']!),
      ),
      // Job conversations (notification deeplink `/messages/<id>`). Full
      // screen so the composer owns the bottom of the window.
      GoRoute(
        path: '/messages/:id',
        redirect: _requireSignIn,
        builder: (_, state) =>
            ThreadScreen(conversationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/notifications',
        redirect: _requireSignIn,
        builder: (_, __) => const NotificationsScreen(),
      ),
      ShellRoute(
        builder: (_, __, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          GoRoute(
            path: '/discover',
            builder: (_, __) => const DiscoverScreen(),
          ),
          GoRoute(
            path: '/applications',
            builder: (_, __) => const ApplicationsScreen(),
          ),
          GoRoute(
            path: '/messages',
            builder: (_, __) => const MessagesScreen(),
          ),
          GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
        ],
      ),
    ],
  );
});

/// Signed-out visitors sign in first and come straight back to the same link.
String? _requireSignIn(BuildContext _, GoRouterState state) {
  if (Supabase.instance.client.auth.currentUser != null) return null;
  final back = Uri.encodeComponent(state.uri.toString());
  return '/sign-in?next=$back';
}

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
