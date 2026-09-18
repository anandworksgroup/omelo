import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import 'account.dart' show serverMessage;
import 'identity.dart';
import 'jobs_repository.dart' show supabaseProvider;
import 'work.dart' show WorkAvailability;

export 'identity.dart';

final identityRepositoryProvider = Provider<IdentityRepository>(
  (ref) => IdentityRepository(ref.watch(supabaseProvider)),
);

/// A profession or skill from the taxonomy search.
class TaxonomyHit {
  const TaxonomyHit({required this.id, required this.name, this.extra});
  final String id;
  final String name;

  /// category_id for professions, country code for places.
  final String? extra;
}

/// Everything the hub card needs for one identity.
class IdentityCardData {
  const IdentityCardData({
    required this.identity,
    required this.completeness,
    required this.skillCount,
  });
  final WorkIdentity identity;
  final Completeness completeness;
  final int skillCount;

  String? get tip => completenessTip(completeness.missing, skillCount: skillCount);
}

/// Work identities: reads go straight through RLS (owner only); status,
/// primary, create and delete go through the omelo_* functions.
class IdentityRepository {
  IdentityRepository(this._db);
  final SupabaseClient _db;

  String? get _uid => _db.auth.currentUser?.id;

  static const _identitySelect =
      'id, label, profession_id, category_id, headline, about, is_primary, '
      'status, discoverability, total_experience_months, completeness_score, '
      'updated_at, professions ( name )';

  Future<List<WorkIdentity>> mine() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _db
        .from('work_identities')
        .select(_identitySelect)
        .eq('person_id', uid)
        .order('created_at');
    return sortIdentities((rows as List)
        .map((r) => WorkIdentity.fromRow(Map<String, dynamic>.from(r as Map))));
  }

  /// Cards for the hub: each identity with its "what is missing" list.
  Future<List<IdentityCardData>> hub() async {
    final uid = _uid;
    if (uid == null) return const [];
    final list = await mine();
    final skillRows = await _db
        .from('person_skills')
        .select('work_identity_id')
        .eq('person_id', uid);
    final skillOwners = (skillRows as List)
        .map((r) => (r as Map)['work_identity_id']?.toString())
        .toList();

    final profiles = await Future.wait(list.map((i) async {
      try {
        return await profile(i.id);
      } catch (_) {
        return null; // The card still shows, just without a tip.
      }
    }));

    return [
      for (var n = 0; n < list.length; n++)
        IdentityCardData(
          identity: list[n],
          completeness: profiles[n]?.completeness ??
              Completeness(score: list[n].completenessScore, missing: const []),
          skillCount: skillCountFor(list[n].id, skillOwners),
        ),
    ];
  }

  Future<IdentityProfile> profile(String identityId) async {
    final res = await _db.rpc('omelo_identity_profile',
        params: {'p_identity': identityId});
    return IdentityProfile.fromJson(res);
  }

  Future<String> create({
    required String label,
    String? professionId,
    String? copyFrom,
    List<String> copy = const ['skills', 'preferences', 'locations'],
  }) async {
    final res = await _db.rpc('omelo_create_work_identity', params: {
      'p_label': label.trim(),
      'p_profession_id': professionId,
      'p_copy_from': copyFrom,
      'p_copy': copy,
    });
    return res.toString();
  }

  Future<void> setPrimary(String identityId) =>
      _db.rpc('omelo_set_primary_identity', params: {'p_identity': identityId});

  Future<void> archive(String identityId, {bool archive = true}) =>
      _db.rpc('omelo_archive_work_identity',
          params: {'p_identity': identityId, 'p_archive': archive});

  Future<void> delete(String identityId) =>
      _db.rpc('omelo_delete_work_identity', params: {'p_identity': identityId});

  /// Basics. Changing the profession also moves the category, so the
  /// profile questions follow the new job type.
  Future<void> updateBasics(
    String identityId, {
    required String label,
    String? professionId,
    String? categoryId,
    String? headline,
    String? about,
    int? totalExperienceMonths,
  }) async {
    String? clean(String? s) => (s == null || s.trim().isEmpty) ? null : s.trim();
    await _db.from('work_identities').update({
      'label': label.trim(),
      'profession_id': professionId,
      if (professionId != null) 'category_id': categoryId,
      'headline': clean(headline),
      'about': clean(about),
      'total_experience_months': totalExperienceMonths,
    }).eq('id', identityId);
  }

  Future<void> setVisibility(String identityId, IdentityVisibility v) =>
      _db
          .from('work_identities')
          .update({'discoverability': v.wire}).eq('id', identityId);

  /// Saves adaptive answers `{slug: value | null}`.
  Future<SaveProfileResult> saveProfile(
      String identityId, Map<String, Object?> values) async {
    final res = await _db.rpc('omelo_save_identity_profile',
        params: {'p_identity': identityId, 'p_values': values});
    return SaveProfileResult.fromJson(res);
  }

  Future<IdentityEvidence> evidence(String identityId) async {
    final res = await _db.rpc('omelo_identity_evidence',
        params: {'p_identity': identityId});
    return IdentityEvidence.fromJson(res);
  }

  // -- Taxonomy search --------------------------------------------------------

  static String _like(String q) =>
      '%${q.trim().replaceAll(RegExp(r'[%_,()\\]'), ' ')}%';

  Future<List<TaxonomyHit>> searchProfessions(String q) async {
    var query = _db
        .from('professions')
        .select('id, name, category_id')
        .eq('status', 'active');
    if (q.trim().isNotEmpty) query = query.ilike('name', _like(q));
    final rows = await query.order('name').limit(30);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .map((m) => TaxonomyHit(
            id: m['id'].toString(),
            name: (m['name'] ?? '').toString(),
            extra: m['category_id']?.toString()))
        .toList();
  }

  Future<List<TaxonomyHit>> searchSkills(String q) async {
    var query = _db.from('skills').select('id, name').eq('status', 'active');
    if (q.trim().isNotEmpty) query = query.ilike('name', _like(q));
    final rows = await query.order('name').limit(30);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .map((m) =>
            TaxonomyHit(id: m['id'].toString(), name: (m['name'] ?? '').toString()))
        .toList();
  }

  Future<List<TaxonomyHit>> searchPlaces(String q) async {
    if (q.trim().length < 2) return const [];
    final rows = await _db
        .from('locations')
        .select('id, name, kind, country_code')
        .inFilter('kind', ['city', 'district', 'area', 'region'])
        .ilike('name', _like(q))
        .order('name')
        .limit(20);
    return (rows as List)
        .map((r) => Map<String, dynamic>.from(r as Map))
        .map((m) => TaxonomyHit(
            id: m['id'].toString(),
            name: (m['name'] ?? '').toString(),
            extra: m['country_code']?.toString().trim()))
        .toList();
  }

  // -- Skills -------------------------------------------------------------------

  Future<List<PersonSkill>> skills(String identityId) async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _db
        .from('person_skills')
        .select('id, skill_id, work_identity_id, proficiency, months_used, '
            'is_verified, evidence_type, skills ( name )')
        .eq('person_id', uid)
        .or('work_identity_id.is.null,work_identity_id.eq.$identityId')
        .order('created_at');
    return (rows as List)
        .map((r) => PersonSkill.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> addSkill(String identityId, String skillId,
      {String? proficiency, int? monthsUsed}) async {
    await _db.from('person_skills').insert({
      'person_id': _uid,
      'work_identity_id': identityId,
      'skill_id': skillId,
      'proficiency': proficiency,
      'months_used': monthsUsed,
      'evidence_type': 'self_declared',
    });
  }

  Future<void> updateSkill(String rowId,
      {String? proficiency, int? monthsUsed}) async {
    await _db.from('person_skills').update({
      'proficiency': proficiency,
      'months_used': monthsUsed,
    }).eq('id', rowId);
  }

  Future<void> removeSkill(String rowId) =>
      _db.from('person_skills').delete().eq('id', rowId);

  // -- Experience ---------------------------------------------------------------

  Future<List<Experience>> experiences(String identityId) async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _db
        .from('experiences')
        .select('id, work_identity_id, employer_name, title, started_on, '
            'ended_on, is_current, description, is_verified')
        .eq('person_id', uid)
        .or('work_identity_id.is.null,work_identity_id.eq.$identityId')
        .order('started_on', ascending: false, nullsFirst: false);
    return (rows as List)
        .map((r) => Experience.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> saveExperience(
    String identityId, {
    String? id,
    String? professionId,
    required String employerName,
    required String title,
    DateTime? startedOn,
    DateTime? endedOn,
    bool isCurrent = false,
    String? description,
  }) async {
    final row = {
      'employer_name': employerName.trim(),
      'title': title.trim(),
      'started_on': startedOn == null ? null : isoDate(startedOn),
      'ended_on': isCurrent || endedOn == null ? null : isoDate(endedOn),
      'is_current': isCurrent,
      'description':
          (description?.trim().isEmpty ?? true) ? null : description!.trim(),
    };
    if (id == null) {
      await _db.from('experiences').insert({
        ...row,
        'person_id': _uid,
        'work_identity_id': identityId,
        if (professionId != null) 'profession_id': professionId,
      });
    } else {
      await _db.from('experiences').update(row).eq('id', id);
    }
  }

  Future<void> deleteExperience(String id) =>
      _db.from('experiences').delete().eq('id', id);

  // -- Preferences and places ---------------------------------------------------

  Future<WorkPreferences> preferences(String identityId) async {
    final row = await _db
        .from('person_work_preferences')
        .select('availability, work_types, shift_types, expected_pay_amount, '
            'expected_pay_period, pay_currency')
        .eq('work_identity_id', identityId)
        .maybeSingle();
    return WorkPreferences.fromRow(row);
  }

  Future<void> savePreferences(String identityId, WorkPreferences p) async {
    await _db.from('person_work_preferences').upsert({
      'person_id': _uid,
      'work_identity_id': identityId,
      'availability': p.availability,
      'work_types': p.workTypes,
      'shift_types': p.shiftTypes,
      'expected_pay_amount': p.expectedPayAmount,
      'expected_pay_period':
          p.expectedPayAmount == null ? null : (p.expectedPayPeriod ?? 'month'),
      if (p.payCurrency != null) 'pay_currency': p.payCurrency,
    }, onConflict: 'work_identity_id');
  }

  /// Release 5: when this identity is free to work (feeds schedule fit in
  /// matching). Same row as [preferences]; only these columns are written.
  Future<WorkAvailability> availability(String identityId) async {
    final row = await _db
        .from('person_work_preferences')
        .select('available_from, available_until, preferred_days, '
            'preferred_start_time, preferred_end_time, max_weekly_hours, '
            'max_travel_km')
        .eq('work_identity_id', identityId)
        .maybeSingle();
    return WorkAvailability.fromRow(row);
  }

  Future<void> saveAvailability(String identityId, WorkAvailability a) async {
    await _db.from('person_work_preferences').upsert({
      'person_id': _uid,
      'work_identity_id': identityId,
      ...a.toRow(),
    }, onConflict: 'work_identity_id');
  }

  Future<List<LocationPreference>> places(String identityId) async {
    final rows = await _db
        .from('person_location_preferences')
        .select('id, kind, location_id, radius_km, locations ( name )')
        .eq('work_identity_id', identityId)
        .order('priority');
    return (rows as List)
        .map((r) =>
            LocationPreference.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<void> addPlace(String identityId, TaxonomyHit place,
      {int radiusKm = 10}) async {
    await _db.from('person_location_preferences').insert({
      'person_id': _uid,
      'work_identity_id': identityId,
      'kind': 'city',
      'location_id': place.id,
      if (place.extra != null && place.extra!.isNotEmpty)
        'country_code': place.extra,
      'radius_km': radiusKm,
    });
  }

  Future<void> removePlace(String id) =>
      _db.from('person_location_preferences').delete().eq('id', id);
}

class SaveProfileResult {
  const SaveProfileResult({
    required this.saved,
    required this.errors,
    required this.completeness,
  });
  final int saved;
  final Map<String, String> errors;
  final Completeness completeness;

  factory SaveProfileResult.fromJson(dynamic v) {
    final m = v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
    final errs = m['errors'] is Map
        ? Map<String, dynamic>.from(m['errors'] as Map)
        : const <String, dynamic>{};
    return SaveProfileResult(
      saved: (m['saved'] as num?)?.toInt() ?? 0,
      errors: errs.map((k, v) => MapEntry(k, v.toString())),
      completeness: Completeness.fromJson(m['completeness']),
    );
  }
}

/// A readable sentence for any failed identity action.
String identityError(Object e) => serverMessage(e,
    fallback: 'That did not go through. Check your connection and try again.');

// -- Providers -------------------------------------------------------------------

final myIdentitiesProvider =
    FutureProvider.autoDispose<List<WorkIdentity>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(identityRepositoryProvider).mine();
});

final identityHubProvider =
    FutureProvider.autoDispose<List<IdentityCardData>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(identityRepositoryProvider).hub();
});

final identityProfileProvider = FutureProvider.autoDispose
    .family<IdentityProfile, String>(
        (ref, id) => ref.watch(identityRepositoryProvider).profile(id));

final identitySkillsProvider = FutureProvider.autoDispose
    .family<List<PersonSkill>, String>(
        (ref, id) => ref.watch(identityRepositoryProvider).skills(id));

final identityExperiencesProvider = FutureProvider.autoDispose
    .family<List<Experience>, String>(
        (ref, id) => ref.watch(identityRepositoryProvider).experiences(id));

final identityPreferencesProvider = FutureProvider.autoDispose
    .family<WorkPreferences, String>(
        (ref, id) => ref.watch(identityRepositoryProvider).preferences(id));

final identityAvailabilityProvider = FutureProvider.autoDispose
    .family<WorkAvailability, String>(
        (ref, id) => ref.watch(identityRepositoryProvider).availability(id));

final identityPlacesProvider = FutureProvider.autoDispose
    .family<List<LocationPreference>, String>(
        (ref, id) => ref.watch(identityRepositoryProvider).places(id));

final identityEvidenceProvider = FutureProvider.autoDispose
    .family<IdentityEvidence, String>(
        (ref, id) => ref.watch(identityRepositoryProvider).evidence(id));

/// The main identity when it is below [kNudgeBelowScore], for the gentle
/// "Complete your ... profile" card. Null otherwise, or on any failure.
final mainIdentityNudgeProvider =
    FutureProvider.autoDispose<WorkIdentity?>((ref) async {
  if (!ref.watch(isSignedInProvider)) return null;
  try {
    final list = await ref.watch(identityRepositoryProvider).mine();
    final main = list.where((i) => i.isPrimary).firstOrNull;
    if (main == null || main.completenessScore >= kNudgeBelowScore) return null;
    return main;
  } catch (_) {
    return null;
  }
});

/// Refresh everything that shows identity data after a change.
void invalidateIdentities(WidgetRef ref, [String? identityId]) {
  ref.invalidate(myIdentitiesProvider);
  ref.invalidate(identityHubProvider);
  ref.invalidate(mainIdentityNudgeProvider);
  if (identityId != null) {
    ref.invalidate(identityProfileProvider(identityId));
    ref.invalidate(identityEvidenceProvider(identityId));
  }
}
