import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Environment configuration.
///
/// The Supabase URL and publishable key are safe to ship in a client bundle —
/// that is what they are for. Every access decision is made by RLS and the
/// consent predicate on the server (see architecture/A4 §3).
///
/// The service role key must NEVER appear in this app.
///
/// Development: the defaults below point at the dev project, so a plain
/// `flutter run` works.
///
/// Production: always pass the production project explicitly —
///
///   flutter build appbundle --release \
///     --dart-define=SUPABASE_URL=https://PROD_REF.supabase.co \
///     --dart-define=SUPABASE_KEY=sb_publishable_...
///
///   (same flags for `flutter build ipa` and `flutter build web --release`)
///
/// Android release signing reads `android/key.properties`; see
/// `android/key.properties.example`.
class Env {
  static const devSupabaseUrl = 'https://jfyqnlucoraazjkndbvm.supabase.co';

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: devSupabaseUrl,
  );

  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_dFLJlbaDMDSTiZIw8dtMeA_kENpacgv',
  );

  /// True when the build was given its own Supabase project rather than the
  /// dev default.
  static const usesDevProject = supabaseUrl == devSupabaseUrl;

  /// Basic sanity: an https Supabase URL and a publishable (never a secret or
  /// service role) key.
  static bool get isConfigured => configProblems(supabaseUrl, supabaseKey).isEmpty;

  /// What is wrong with a URL/key pair, in words for a build log. Empty when
  /// it looks right.
  static List<String> configProblems(String url, String key) {
    final problems = <String>[];
    final uri = Uri.tryParse(url.trim());
    if (url.trim().isEmpty || uri == null || !uri.hasAuthority) {
      problems.add('SUPABASE_URL is missing or not a URL');
    } else if (uri.scheme != 'https' &&
        uri.host != 'localhost' &&
        uri.host != '127.0.0.1' &&
        uri.host != '10.0.2.2') {
      problems.add('SUPABASE_URL must use https');
    }
    final k = key.trim();
    if (k.isEmpty) {
      problems.add('SUPABASE_KEY is missing');
    } else if (k.startsWith('sb_secret_') || _looksLikeServiceRoleJwt(k)) {
      problems.add('SUPABASE_KEY is a secret/service role key — never ship it');
    }
    return problems;
  }

  static bool _looksLikeServiceRoleJwt(String key) {
    final parts = key.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = String.fromCharCodes(
          base64Url.decode(base64Url.normalize(parts[1])));
      return payload.contains('"service_role"');
    } catch (_) {
      return false;
    }
  }

  /// Logs (never crashes) when a release build is misconfigured, e.g. built
  /// without the production --dart-define flags.
  static void logStartupCheck() {
    final problems = configProblems(supabaseUrl, supabaseKey);
    if (kReleaseMode && usesDevProject) {
      problems.add('release build is using the DEV Supabase project; pass '
          '--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...');
    }
    for (final p in problems) {
      debugPrint('[Omelo config] WARNING: $p');
    }
  }

  /// Launch market. Drives currency, pay period and auth method defaults
  /// until the user picks a country. See country_policies.
  static const defaultCountry = 'IN';

  /// Fallback map centre when location permission is denied: Connaught Place.
  /// A worker who declines location must still see real jobs (UC-1, UC-6).
  static const fallbackLat = 28.6315;
  static const fallbackLng = 77.2167;

  static const defaultRadiusKm = 15;
}
