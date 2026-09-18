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
import '../features/identities/identities_screen.dart';
import '../features/identities/identity_editor_screen.dart';
import '../features/invitations/invitation_detail_screen.dart';
import '../features/invitations/invitations_screen.dart';
import '../features/meet/meet_screen.dart';
import '../features/messages/messages_screen.dart';
import '../features/messages/thread_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/onboarding_screens.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/profile_views_screen.dart';
import '../features/representations/recruiters_screen.dart';
import '../features/representations/representation_detail_screen.dart';
import '../features/representations/representations_screen.dart';
import '../features/saved/saved_jobs_screen.dart';
import '../features/settings/reset_password_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/app_shell.dart';
import '../data/job_events.dart' show JobSurface;
import 'app_state.dart';
import 'auth_links.dart';

/// Deeplink-first routing (A1 §16): every notification must resolve to a
/// screen, so every screen has a real URL.
final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    // A password-recovery link signs the worker in with a one-time session.
    // Until they choose a new password, every navigation lands on the
    // "Set a new password" screen.
    refreshListenable: PasswordRecovery.pending,
    redirect: (_, state) =>
        PasswordRecovery.pending.value && state.uri.path != '/reset-password'
            ? '/reset-password'
            : null,
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
        builder: (_, state) => JobDetailScreen(
          jobId: state.pathParameters['id']!,
          surface: JobSurface.fromWire(state.uri.queryParameters['from']),
          rank: int.tryParse(state.uri.queryParameters['rank'] ?? ''),
        ),
      ),
      GoRoute(
        path: '/company/:id',
        builder: (_, state) =>
            CompanyScreen(companyId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/apply/:id',
        builder: (_, state) => ApplyScreen(
          jobId: state.pathParameters['id']!,
          identityId: state.uri.queryParameters['identity'],
        ),
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
      // Release 2: work identities. Full screen, outside the tab shell.
      GoRoute(
        path: '/identities',
        redirect: _requireSignIn,
        builder: (_, __) => const IdentitiesScreen(),
      ),
      GoRoute(
        path: '/identities/:id',
        redirect: _requireSignIn,
        builder: (_, state) => IdentityEditorScreen(
          identityId: state.pathParameters['id']!,
          section: state.uri.queryParameters['section'],
        ),
      ),
      // Release 3: invitations to apply (notification deeplink
      // `/invitations/<id>`), saved jobs and who viewed my profile.
      GoRoute(
        path: '/invitations',
        redirect: _requireSignIn,
        builder: (_, __) => const InvitationsScreen(),
      ),
      GoRoute(
        path: '/invitations/:id',
        redirect: _requireSignIn,
        builder: (_, state) => InvitationDetailScreen(
            invitationId: state.pathParameters['id']!),
      ),
      // Release 4: recruiters and agencies asking to represent me
      // (notification deeplinks `/representations/<id>`).
      GoRoute(
        path: '/representations',
        redirect: _requireSignIn,
        builder: (_, state) => RepresentationsScreen(
            agency: state.uri.queryParameters['agency']),
      ),
      GoRoute(
        path: '/representations/:id',
        redirect: _requireSignIn,
        builder: (_, state) =>
            RepresentationDetailScreen(consentId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/recruiters',
        redirect: _requireSignIn,
        builder: (_, __) => const RecruitersScreen(),
      ),
      GoRoute(
        path: '/saved',
        redirect: _requireSignIn,
        builder: (_, __) => const SavedJobsScreen(),
      ),
      GoRoute(
        path: '/profile-views',
        redirect: _requireSignIn,
        builder: (_, __) => const ProfileViewsScreen(),
      ),
      GoRoute(
        path: '/notifications',
        redirect: _requireSignIn,
        builder: (_, __) => const NotificationsScreen(),
      ),
      // Account settings (notification deeplink `/settings`).
      GoRoute(
        path: '/settings',
        redirect: _requireSignIn,
        builder: (_, __) => const SettingsScreen(),
      ),
      // Where password-reset emails come back to (web hash URL; mobile via
      // com.omelo.app://reset-password and the recovery auth event).
      GoRoute(
        path: '/reset-password',
        builder: (_, __) => const ResetPasswordScreen(),
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
