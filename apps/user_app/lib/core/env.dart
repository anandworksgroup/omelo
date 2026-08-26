/// Environment configuration.
///
/// The Supabase URL and publishable key are safe to ship in a client bundle —
/// that is what they are for. Every access decision is made by RLS and the
/// consent predicate on the server (see architecture/A4 §3).
///
/// The service role key must NEVER appear in this app.
///
/// Override at build time:
///   flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_KEY=...
class Env {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://jfyqnlucoraazjkndbvm.supabase.co',
  );

  static const supabaseKey = String.fromEnvironment(
    'SUPABASE_KEY',
    defaultValue: 'sb_publishable_dFLJlbaDMDSTiZIw8dtMeA_kENpacgv',
  );

  /// Launch market. Drives currency, pay period and auth method defaults
  /// until the user picks a country. See country_policies.
  static const defaultCountry = 'IN';

  /// Fallback map centre when location permission is denied: Connaught Place.
  /// A worker who declines location must still see real jobs (UC-1, UC-6).
  static const fallbackLat = 28.6315;
  static const fallbackLng = 77.2167;

  static const defaultRadiusKm = 15;
}
