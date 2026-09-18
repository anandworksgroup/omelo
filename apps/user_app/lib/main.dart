import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth_links.dart';
import 'core/env.dart';
import 'core/observability.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'data/account.dart' show omeloAppUserAgent;

void main() {
  // Everything runs inside one guarded zone so uncaught async errors are
  // reported too. Reporting is a no-op unless built with SENTRY_DSN.
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    Observability.install();
    Env.logStartupCheck();

    await Supabase.initialize(
      url: Env.supabaseUrl,
      publishableKey: Env.supabaseKey,
      // The mobile app names itself so "Devices signed in" can say
      // "Omelo app on Android". Browsers send their own user agent.
      headers: kIsWeb
          ? null
          : {'User-Agent': omeloAppUserAgent(_platformName())},
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    PasswordRecovery.listen(Supabase.instance.client.auth);

    runApp(const ProviderScope(child: OmeloApp()));
  }, (error, stack) {
    unawaited(reportError(error, stack, context: 'zone'));
  });
}

String _platformName() => switch (defaultTargetPlatform) {
      TargetPlatform.android => 'Android',
      TargetPlatform.iOS => 'iPhone',
      TargetPlatform.macOS => 'Mac',
      TargetPlatform.windows => 'Windows',
      TargetPlatform.linux => 'Linux',
      TargetPlatform.fuchsia => 'Fuchsia',
    };

class OmeloApp extends ConsumerWidget {
  const OmeloApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Omelo',
      debugShowCheckedModeBanner: false,
      theme: OmeloTheme.light(),
      darkTheme: OmeloTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('hi'),
      ],
      builder: (context, child) {
        // Cap text scaling so a large accessibility setting cannot break
        // layouts, without ignoring the user's preference entirely.
        final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 1.5);
        return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}
