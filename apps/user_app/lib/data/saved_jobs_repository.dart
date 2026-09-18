import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import 'job.dart';
import 'jobs_repository.dart' show supabaseProvider;

final savedJobsRepositoryProvider = Provider<SavedJobsRepository>(
  (ref) => SavedJobsRepository(ref.watch(supabaseProvider)),
);

/// `saved_jobs` — the worker's bookmarks. Owner-only through RLS.
class SavedJobsRepository {
  SavedJobsRepository(this._db);
  final SupabaseClient _db;

  String? get _uid => _db.auth.currentUser?.id;

  Future<Set<String>> ids() async {
    final uid = _uid;
    if (uid == null) return {};
    final rows =
        await _db.from('saved_jobs').select('job_id').eq('person_id', uid);
    return {for (final r in rows as List) (r as Map)['job_id'].toString()};
  }

  Future<void> save(String jobId) async {
    await _db.from('saved_jobs').upsert(
      {'person_id': _uid, 'job_id': jobId},
      onConflict: 'person_id,job_id',
      ignoreDuplicates: true,
    );
  }

  Future<void> unsave(String jobId) async {
    await _db
        .from('saved_jobs')
        .delete()
        .eq('person_id', _uid ?? '')
        .eq('job_id', jobId);
  }

  /// Saved jobs, newest first. Jobs that were closed since are left out.
  Future<List<Job>> list() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _db
        .from('saved_jobs')
        .select('''
          created_at,
          jobs!inner ( id, title, status, location_text, pay_min, pay_max,
                       pay_period, pay_currency, pay_negotiable, work_type,
                       workplace_type, shift_types, accepts_no_experience,
                       min_experience_months, is_immediate_start,
                       quick_apply_enabled, openings, published_at,
                       companies!inner ( id, slug, display_name, is_verified,
                                         median_response_hours ) )
        ''')
        .eq('person_id', uid)
        .order('created_at', ascending: false);
    return [
      for (final r in rows as List)
        if ((r as Map)['jobs'] is Map &&
            (r['jobs'] as Map)['status'] == 'published')
          jobFromTableRow(Map<String, dynamic>.from(r['jobs'] as Map)),
    ];
  }
}

/// A `jobs` row with `companies ( ... )` embedded, as a [Job] card.
Job jobFromTableRow(Map<String, dynamic> row) {
  final company = row['companies'] is Map
      ? Map<String, dynamic>.from(row['companies'] as Map)
      : const <String, dynamic>{};
  num? n(dynamic v) =>
      v == null ? null : (v is num ? v : num.tryParse(v.toString()));
  return Job(
    id: row['id'].toString(),
    title: (row['title'] ?? '').toString(),
    companyId: company['id']?.toString(),
    companyName: (company['display_name'] ?? '').toString(),
    companySlug: company['slug']?.toString(),
    companyVerified: company['is_verified'] == true,
    companyResponseHours: n(company['median_response_hours'])?.toInt(),
    distanceKm: null,
    locationText: row['location_text'] as String?,
    payMin: n(row['pay_min']),
    payMax: n(row['pay_max']),
    payPeriod: row['pay_period'] as String?,
    payCurrency: (row['pay_currency'] as String?)?.trim(),
    payNegotiable: row['pay_negotiable'] == true,
    payMonthlyMin: null,
    workType: row['work_type'] as String?,
    workplace: row['workplace_type'] as String?,
    shiftTypes: Job.parseStrList(row['shift_types']),
    acceptsNoExperience: row['accepts_no_experience'] == true,
    minExperienceMonths: n(row['min_experience_months'])?.toInt(),
    isImmediateStart: row['is_immediate_start'] == true,
    quickApplyEnabled: row['quick_apply_enabled'] != false,
    openings: n(row['openings'])?.toInt(),
    categorySlug: null,
    professionName: null,
    benefits: const [],
    publishedAt: row['published_at'] == null
        ? null
        : DateTime.tryParse(row['published_at'].toString())?.toLocal(),
  );
}

/// Ids of the jobs I saved, toggled optimistically so the bookmark reacts
/// at once. Empty when signed out.
final savedJobIdsProvider =
    AsyncNotifierProvider<SavedJobIdsController, Set<String>>(
        SavedJobIdsController.new);

class SavedJobIdsController extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() async {
    if (!ref.watch(isSignedInProvider)) return {};
    try {
      return await ref.watch(savedJobsRepositoryProvider).ids();
    } catch (_) {
      return {};
    }
  }

  /// Saves or un-saves. Returns the new saved state; throws on failure after
  /// putting the old state back.
  Future<bool> toggle(String jobId) async {
    final before = state.value ?? <String>{};
    final saving = !before.contains(jobId);
    state = AsyncData(
        saving ? {...before, jobId} : ({...before}..remove(jobId)));
    try {
      final repo = ref.read(savedJobsRepositoryProvider);
      if (saving) {
        await repo.save(jobId);
      } else {
        await repo.unsave(jobId);
      }
      ref.invalidate(savedJobsProvider);
      return saving;
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }
}

final savedJobsProvider = FutureProvider.autoDispose<List<Job>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(savedJobsRepositoryProvider).list();
});
