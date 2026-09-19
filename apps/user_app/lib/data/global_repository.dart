import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import 'global.dart';
import 'identity_repository.dart' show TaxonomyHit;
import 'jobs_repository.dart' show supabaseProvider;

export 'global.dart';

final globalRepositoryProvider = Provider<GlobalRepository>(
  (ref) => GlobalRepository(ref.watch(supabaseProvider)),
);

/// Countries, my mobility profile and work authorizations, jobs worldwide,
/// eligibility and country guides. The server owns every rule; the app sends
/// what the worker chose and shows the server's words.
class GlobalRepository {
  GlobalRepository(this._db);
  final SupabaseClient _db;

  String? get _uid => _db.auth.currentUser?.id;

  // -- Countries ---------------------------------------------------------------

  Future<List<Country>> countries() async {
    final rows = await _db
        .from('country_policies')
        .select(
          'country_code, name, default_currency, default_language, '
          'default_timezone, calling_code, world_region',
        )
        .order('name');
    return parseCountries(rows);
  }

  static String _like(String q) =>
      '%${q.trim().replaceAll(RegExp(r'[%_,()\\]'), ' ')}%';

  /// Cities by name, in [countries] when given. Extra is the country code.
  Future<List<TaxonomyHit>> searchCities(
    String q, {
    List<String> countries = const [],
  }) async {
    if (q.trim().length < 2) return const [];
    var query = _db
        .from('locations')
        .select('id, name, country_code')
        .eq('kind', 'city')
        .ilike('name', _like(q));
    if (countries.isNotEmpty) query = query.inFilter('country_code', countries);
    final rows = await query.order('name').limit(25);
    return _hits(rows);
  }

  /// Names for cities already chosen.
  Future<List<TaxonomyHit>> citiesByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final rows = await _db
        .from('locations')
        .select('id, name, country_code')
        .inFilter('id', ids);
    return _hits(rows);
  }

  static List<TaxonomyHit> _hits(dynamic rows) => (rows as List)
      .map((r) => Map<String, dynamic>.from(r as Map))
      .map((m) => TaxonomyHit(
            id: m['id'].toString(),
            name: (m['name'] ?? '').toString(),
            extra: m['country_code']?.toString().trim(),
          ))
      .toList();

  // -- Mobility ----------------------------------------------------------------

  Future<MyMobility> myMobility() async {
    if (_uid == null) return const MyMobility(profile: MobilityProfile(), saved: false);
    return MyMobility.fromJson(await _db.rpc('omelo_my_mobility'));
  }

  Future<MobilityProfile> saveMobility(MobilityProfile p) async {
    final res = await _db.rpc(
      'omelo_save_mobility',
      params: {'p': p.toPayload()},
    );
    return MobilityProfile.fromJson(res);
  }

  // -- Work authorizations (my own rows, through RLS) --------------------------

  Future<void> addAuthorization({
    required String country,
    required WorkAuthStatus status,
    DateTime? validFrom,
    DateTime? expiresOn,
    String? restrictions,
  }) async {
    final uid = _uid;
    if (uid == null) throw const AuthException('Sign in first');
    await _db.from('work_authorizations').insert(authorizationRow(
          personId: uid,
          country: country,
          status: status,
          validFrom: validFrom,
          expiresOn: expiresOn,
          restrictions: restrictions,
        ));
  }

  Future<void> updateAuthorization(
    String id, {
    required String country,
    required WorkAuthStatus status,
    DateTime? validFrom,
    DateTime? expiresOn,
    String? restrictions,
  }) =>
      _db
          .from('work_authorizations')
          .update(authorizationRow(
            country: country,
            status: status,
            validFrom: validFrom,
            expiresOn: expiresOn,
            restrictions: restrictions,
          ))
          .eq('id', id);

  Future<void> deleteAuthorization(String id) =>
      _db.from('work_authorizations').delete().eq('id', id);

  // -- Jobs worldwide ----------------------------------------------------------

  Future<GlobalJobsPage> globalJobs(
    GlobalTab tab, {
    GlobalJobFilters filters = const GlobalJobFilters(),
    int limit = 20,
    int offset = 0,
  }) async {
    final res = await _db.rpc('omelo_global_jobs', params: {
      'p_tab': tab.wire,
      'p_filters': filters.toJson(tab),
      'p_limit': limit,
      'p_offset': offset,
    });
    return GlobalJobsPage.fromJson(res);
  }

  Future<JobEligibility?> jobEligibility(String jobId, {String? identityId}) async {
    final res = await _db.rpc('omelo_job_eligibility', params: {
      'p_job': jobId,
      'p_identity': ?identityId,
    });
    return JobEligibility.fromJson(res);
  }

  Future<CountryGuide?> countryGuide(String code, {String? professionId}) async {
    final res = await _db.rpc('omelo_country_guide', params: {
      'p_country': code.toUpperCase(),
      'p_profession': ?professionId,
    });
    return CountryGuide.fromJson(res, code: code);
  }
}

/// A server refusal in its own words, with the database's own constraint
/// messages turned into plain ones.
String globalError(Object e) {
  if (e is PostgrestException) {
    switch (e.code) {
      case '23505':
        return 'You already added this country. Edit that one instead.';
      case '23514':
        return 'Check the dates: the end date must be on or after the start date.';
      case '42501':
        if (e.message.contains('verified')) {
          return 'This record is verified, so the country, status and end date '
              'cannot be changed.';
        }
    }
    if (e.message.trim().isNotEmpty) return e.message.trim();
  }
  if (e is AuthException && e.message.trim().isNotEmpty) return e.message.trim();
  return 'Could not reach Omelo. Check your internet and try again.';
}

// -- Providers -------------------------------------------------------------------

/// The country list rarely changes: loaded once per app run.
final countriesProvider = FutureProvider<List<Country>>(
  (ref) => ref.watch(globalRepositoryProvider).countries(),
);

final myMobilityProvider = FutureProvider.autoDispose<MyMobility>((ref) async {
  if (!ref.watch(isSignedInProvider)) {
    return const MyMobility(profile: MobilityProfile(), saved: false);
  }
  return ref.watch(globalRepositoryProvider).myMobility();
});

/// "Can I apply?" for one job. Null when signed out.
final jobEligibilityProvider = FutureProvider.autoDispose
    .family<JobEligibility?, String>((ref, jobId) async {
  if (!ref.watch(isSignedInProvider)) return null;
  return ref.watch(globalRepositoryProvider).jobEligibility(jobId);
});

final countryGuideProvider = FutureProvider.autoDispose
    .family<CountryGuide?, String>(
      (ref, code) => ref.watch(globalRepositoryProvider).countryGuide(code),
    );

