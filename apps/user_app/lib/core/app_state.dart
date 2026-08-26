import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'env.dart';

/// Onboarding + preference state that survives a restart.
///
/// UC-3: signup to first application in under 10 minutes. Anything the user
/// already told us must never be asked twice.
class AppPrefs {
  const AppPrefs({
    required this.locale,
    required this.country,
    required this.onboarded,
  });

  final String locale;
  final String country;
  final bool onboarded;

  AppPrefs copyWith({String? locale, String? country, bool? onboarded}) =>
      AppPrefs(
        locale: locale ?? this.locale,
        country: country ?? this.country,
        onboarded: onboarded ?? this.onboarded,
      );
}

final appPrefsProvider =
    AsyncNotifierProvider<AppPrefsNotifier, AppPrefs>(AppPrefsNotifier.new);

class AppPrefsNotifier extends AsyncNotifier<AppPrefs> {
  static const _kLocale = 'locale';
  static const _kCountry = 'country';
  static const _kOnboarded = 'onboarded';

  @override
  Future<AppPrefs> build() async {
    final p = await SharedPreferences.getInstance();
    return AppPrefs(
      locale: p.getString(_kLocale) ?? 'en',
      country: p.getString(_kCountry) ?? Env.defaultCountry,
      onboarded: p.getBool(_kOnboarded) ?? false,
    );
  }

  Future<void> setLocale(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kLocale, v);
    state = AsyncData((state.value ?? await build()).copyWith(locale: v));
  }

  Future<void> setCountry(String v) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCountry, v);
    state = AsyncData((state.value ?? await build()).copyWith(country: v));
  }

  Future<void> completeOnboarding() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kOnboarded, true);
    state = AsyncData((state.value ?? await build()).copyWith(onboarded: true));
  }
}

/// Current auth session. Null means browsing signed out, which is a fully
/// supported state — not a degraded one (UC-1).
final authStateProvider = StreamProvider<AuthState?>((ref) async* {
  yield null;
  yield* Supabase.instance.client.auth.onAuthStateChange;
});

final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return Supabase.instance.client.auth.currentUser;
});

final isSignedInProvider = Provider<bool>(
  (ref) => ref.watch(currentUserProvider) != null,
);

/// Country policy for the active country — currency, pay period, auth method.
/// Drives defaults so the app never assumes a US- or Europe-shaped market.
final countryPolicyProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, code) async {
  final rows = await Supabase.instance.client
      .from('country_policies')
      .select()
      .eq('country_code', code)
      .maybeSingle();
  return rows;
});

/// Supported countries for the picker.
final supportedCountriesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('country_policies')
      .select('country_code, name, default_currency, phone_auth_preferred, supported')
      .order('name');
  return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});

/// Languages available in the picker, from the seeded taxonomy.
final languagesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final rows = await Supabase.instance.client
      .from('languages')
      .select('code, name, native_name, rtl')
      .order('name');
  return (rows as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
});
