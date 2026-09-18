import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omelo_user_app/core/app_state.dart';
import 'package:omelo_user_app/core/theme.dart';
import 'package:omelo_user_app/data/account_repository.dart';
import 'package:omelo_user_app/features/settings/settings_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show User;

void main() {
  final user = User(
    id: 'u1',
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-09-01T00:00:00Z',
    email: 'worker@example.com',
  );

  Future<void> pump(WidgetTester tester, Size size, TrustStatus trust) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(user),
        isSignedInProvider.overrideWithValue(true),
        trustStatusProvider.overrideWith((_) async => trust),
        mySessionsProvider.overrideWith((_) async => [
              DeviceSession(
                id: 's1',
                userAgent: 'OmeloApp/1 (Android)',
                lastActiveAt: DateTime.now(),
                isCurrent: true,
              ),
              DeviceSession(
                id: 's2',
                userAgent:
                    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0 Safari/537.36',
                lastActiveAt:
                    DateTime.now().subtract(const Duration(hours: 3)),
                ipHint: '49.36.x.x',
              ),
            ]),
      ],
      child: MaterialApp.router(
        theme: OmeloTheme.light(),
        routerConfig: GoRouter(
          initialLocation: '/settings',
          routes: [
            GoRoute(
                path: '/settings', builder: (_, __) => const SettingsScreen()),
            GoRoute(
                path: '/profile', builder: (_, __) => const SizedBox.shrink()),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('narrow phone: everything renders without overflow',
      (tester) async {
    await pump(
      tester,
      const Size(320, 3000),
      TrustStatus.fromJson({
        'email': 'worker@example.com',
        'deletion_scheduled_for': '2026-10-02T03:17:00Z',
      }),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Send me a code'), findsOneWidget);
    expect(find.text('Coming soon'), findsOneWidget);
    expect(find.text('Omelo app on Android'), findsOneWidget);
    expect(find.textContaining('This device'), findsOneWidget);
    expect(find.text('Chrome on Windows'), findsOneWidget);
    expect(find.text('Sign out of all other devices'), findsOneWidget);
    expect(find.text('Cancel deletion'), findsOneWidget);
    expect(find.textContaining('Your account will be deleted on'),
        findsOneWidget);
  });

  testWidgets('verified email, no deletion, desktop width', (tester) async {
    await pump(
      tester,
      const Size(1400, 3000),
      TrustStatus.fromJson({'email_verified': true}),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Your email is verified.'), findsOneWidget);
    expect(find.text('Cancel deletion'), findsNothing);
    expect(find.text('Delete my account'), findsWidgets);
  });
}
