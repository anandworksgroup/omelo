import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';
import 'jobs_repository.dart' show supabaseProvider;

final applicationsRepositoryProvider = Provider<ApplicationsRepository>(
  (ref) => ApplicationsRepository(
    ref.watch(supabaseProvider),
    ref.watch(authRepositoryProvider),
  ),
);

/// Candidate-visible application states, in pipeline order.
/// Mirrors the `application_state` enum. The employer cannot invent one.
const kApplicationStages = <String, String>{
  'applied': 'Applied',
  'viewed': 'Employer viewed',
  'shortlisted': 'Shortlisted',
  'screening': 'Screening',
  'assessment': 'Assessment',
  'interview': 'Interview',
  'offer': 'Offer',
  'hired': 'Hired',
};

const kTerminalStates = {
  'rejected',
  'withdrawn',
  'expired',
  'declined_by_candidate',
};

class ApplicationSummary {
  ApplicationSummary({
    required this.id,
    required this.jobId,
    required this.jobTitle,
    required this.companyName,
    required this.state,
    required this.appliedAt,
    required this.lastActivityAt,
    required this.firstViewedAt,
    required this.rejectionReason,
    required this.medianResponseHours,
  });

  final String id;
  final String jobId;
  final String jobTitle;
  final String companyName;
  final String state;
  final DateTime appliedAt;
  final DateTime lastActivityAt;
  final DateTime? firstViewedAt;
  final String? rejectionReason;
  final int? medianResponseHours;

  bool get isTerminal => kTerminalStates.contains(state);

  int get daysSinceActivity =>
      DateTime.now().difference(lastActivityAt).inDays;

  /// PR-4: silence is a displayed state, not an absence of one.
  bool get isSilent => !isTerminal && daysSinceActivity >= 5;
}

class ApplyOutcome {
  const ApplyOutcome({this.error, this.applicationId});
  final String? error;
  final String? applicationId;
  bool get ok => error == null;
}

class ApplicationsRepository {
  ApplicationsRepository(this._db, this._auth);
  final SupabaseClient _db;
  final AuthRepository _auth;

  Future<List<ApplicationSummary>> mine() async {
    final uid = _auth.currentUser?.id;
    if (uid == null) return [];

    final rows = await _db
        .from('applications')
        .select('''
          id, state, applied_at, last_activity_at, first_viewed_at,
          rejection_reason, job_id,
          jobs ( title ),
          companies ( display_name, median_response_hours )
        ''')
        .eq('person_id', uid)
        .order('applied_at', ascending: false);

    return (rows as List).map((r) {
      final m = Map<String, dynamic>.from(r as Map);
      final job = m['jobs'] == null
          ? null
          : Map<String, dynamic>.from(m['jobs'] as Map);
      final co = m['companies'] == null
          ? null
          : Map<String, dynamic>.from(m['companies'] as Map);
      return ApplicationSummary(
        id: m['id'] as String,
        jobId: m['job_id'] as String,
        jobTitle: (job?['title'] ?? 'Job') as String,
        companyName: (co?['display_name'] ?? '') as String,
        state: (m['state'] ?? 'applied') as String,
        appliedAt: DateTime.parse(m['applied_at'].toString()).toLocal(),
        lastActivityAt:
            DateTime.parse(m['last_activity_at'].toString()).toLocal(),
        firstViewedAt: m['first_viewed_at'] == null
            ? null
            : DateTime.parse(m['first_viewed_at'].toString()).toLocal(),
        rejectionReason: m['rejection_reason'] as String?,
        medianResponseHours: (co?['median_response_hours'] as num?)?.toInt(),
      );
    }).toList();
  }

  Future<bool> hasApplied(String jobId) async {
    final uid = _auth.currentUser?.id;
    if (uid == null) return false;
    final row = await _db
        .from('applications')
        .select('id')
        .eq('person_id', uid)
        .eq('job_id', jobId)
        .maybeSingle();
    return row != null;
  }

  /// Quick apply.
  ///
  /// Builds the immutable identity snapshot the employer will see. The
  /// snapshot is a copy, not a reference — editing the profile later must not
  /// silently change an application already under review (docs/02).
  Future<ApplyOutcome> apply({
    required String jobId,
    required String companyId,
    Map<String, dynamic>? answers,
    String? coverNote,
  }) async {
    final uid = _auth.currentUser?.id;
    if (uid == null) {
      return const ApplyOutcome(error: 'Sign in to apply.');
    }

    final identityId = await _auth.primaryWorkIdentityId();
    if (identityId == null) {
      return const ApplyOutcome(
        error: 'Your work profile is not ready yet. Try again in a moment.',
      );
    }

    try {
      final person = await _db
          .from('persons')
          .select('display_name, phone, email, location_text, country_code')
          .eq('id', uid)
          .maybeSingle();

      final identity = await _db
          .from('work_identities')
          .select(
              'label, headline, about, total_experience_months, professions ( name )')
          .eq('id', identityId)
          .maybeSingle();

      final skills = await _db
          .from('person_skills')
          .select('proficiency, skills ( name )')
          .eq('person_id', uid)
          .limit(25);

      final snapshot = <String, dynamic>{
        'captured_at': DateTime.now().toUtc().toIso8601String(),
        'person': person ?? {},
        'work_identity': identity ?? {},
        'skills': (skills as List)
            .map((s) {
              final m = Map<String, dynamic>.from(s as Map);
              final sk = m['skills'];
              return sk == null
                  ? null
                  : Map<String, dynamic>.from(sk as Map)['name'];
            })
            .whereType<String>()
            .toList(),
      };

      final inserted = await _db
          .from('applications')
          .insert({
            'job_id': jobId,
            'person_id': uid,
            'company_id': companyId,
            'work_identity_id': identityId,
            'identity_snapshot': snapshot,
            'answers': answers == null ? [] : [answers],
            'cover_note': coverNote,
            'applied_via': 'omelo',
          })
          .select('id')
          .single();

      return ApplyOutcome(applicationId: inserted['id'] as String);
    } on PostgrestException catch (e) {
      if (e.code == '23505') {
        return const ApplyOutcome(
            error: 'You have already applied to this job.');
      }
      return ApplyOutcome(error: e.message);
    } catch (_) {
      return const ApplyOutcome(
        error: 'Could not send your application. Check your connection.',
      );
    }
  }

  Future<void> withdraw(String applicationId, {String? reason}) async {
    await _db
        .from('applications')
        .update({'state': 'withdrawn', 'withdrawal_reason': reason})
        .eq('id', applicationId);
  }
}
