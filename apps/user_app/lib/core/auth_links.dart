import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Links that come back into the app from auth emails.
///
/// Password reset:
///   * Web uses the hash URL strategy, so the link lands on
///     `<origin><path>#/reset-password` (Supabase puts `?code=` before the
///     hash; supabase_flutter exchanges it on start-up).
///   * Android/iOS use the custom scheme `com.omelo.app://reset-password`,
///     registered in AndroidManifest.xml and Info.plist. supabase_flutter
///     receives the link through app_links.
///
/// Both URLs must be listed in Supabase → Auth → URL configuration →
/// Redirect URLs, or Supabase falls back to the Site URL.
class AuthLinks {
  static const mobileScheme = 'com.omelo.app';
  static const mobileResetRedirect = '$mobileScheme://reset-password';

  static String passwordResetRedirect() =>
      passwordResetRedirectFor(web: kIsWeb, base: kIsWeb ? Uri.base : null);

  @visibleForTesting
  static String passwordResetRedirectFor({required bool web, Uri? base}) {
    if (!web || base == null) return mobileResetRedirect;
    return '${base.origin}${base.path}#/reset-password';
  }
}

/// True between a password-recovery link opening the app and the worker
/// choosing a new password. The router sends every navigation to
/// `/reset-password` while it is set.
class PasswordRecovery {
  static final pending = ValueNotifier<bool>(false);
  static StreamSubscription<AuthState>? _sub;

  /// Call once, right after `Supabase.initialize`. The auth stream replays its
  /// last event, so a recovery link handled during initialisation is seen.
  static void listen(GoTrueClient auth) {
    _sub ??= auth.onAuthStateChange.listen((s) {
      if (s.event == AuthChangeEvent.passwordRecovery) pending.value = true;
      if (s.event == AuthChangeEvent.signedOut) pending.value = false;
    }, onError: (_) {});
  }

  static void done() => pending.value = false;
}
