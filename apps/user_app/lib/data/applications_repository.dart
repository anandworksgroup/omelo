import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'account.dart' show applyErrorMessage;
import 'auth_repository.dart';
import 'hiring.dart';
import 'jobs_repository.dart' show supabaseProvider;

export 'hiring.dart';

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

  static const _summarySelect = '''
          id, job_id, company_id, work_identity_id, state, match_score,
          applied_at, first_viewed_at, last_activity_at, closed_at,
          rejection_reason, withdrawal_reason,
          jobs ( title, pay_min, pay_max, pay_period, pay_currency, location_text ),
          companies ( display_name, slug, logo_url, median_response_hours )
        ''';

  static const _interviewSelect =
      'id, application_id, type, status, round, scheduled_at, duration_minutes, '
      'timezone, meeting_url, location_text, instructions, '
      'candidate_confirmed_at, cancel_reason, round_name, round_kind, '
      'meeting_mode, completed_at';

  static const _roomSelect =
      'interview_id, room_name, status, opens_at, closes_at, waiting_room, '
      'recording_enabled';

  static const _offerSelect =
      'id, application_id, status, title, pay_amount, pay_period, pay_currency, '
      'start_date, expires_at, conditions, benefits, sent_at, responded_at';

  /// My applications, newest first, with their interviews and offers so the
  /// list can say what happens next without a round trip per card.
  Future<List<ApplicationSummary>> mine() async {
    final uid = _auth.currentUser?.id;
    if (uid == null) return [];

    final rows = await _db
        .from('applications')
        .select(_summarySelect)
        .eq('person_id', uid)
        .order('applied_at', ascending: false);

    final apps = (rows as List)
        .map((r) =>
            ApplicationSummary.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
    if (apps.isEmpty) return apps;

    final ids = apps.map((a) => a.id).toList();
    // Interviews and offers sharpen the "Next:" line. If either read fails the
    // list still loads and falls back to state-only wording.
    final interviews = await _safeList(() => _db
        .from('interviews')
        .select(_interviewSelect)
        .inFilter('application_id', ids)
        .order('scheduled_at'));
    final offers = await _safeList(() => _db
        .from('offers')
        .select(_offerSelect)
        .inFilter('application_id', ids)
        .order('sent_at', ascending: false));

    return apps
        .map((a) => a.copyWith(
              interviews: interviews
                  .where((m) => m['application_id']?.toString() == a.id)
                  .map(Interview.fromRow)
                  .toList(),
              offers: offers
                  .where((m) => m['application_id']?.toString() == a.id)
                  .map(Offer.fromRow)
                  .toList(),
            ))
        .toList();
  }

  /// One application with everything the worker can see about it.
  /// Returns null when it does not exist or is not theirs (RLS).
  Future<ApplicationDetail?> detail(String applicationId) async {
    final row = await _db
        .from('applications')
        .select(_summarySelect)
        .eq('id', applicationId)
        .maybeSingle();
    if (row == null) return null;

    final results = await Future.wait([
      _db
          .from('interviews')
          .select(_interviewSelect)
          .eq('application_id', applicationId)
          .order('scheduled_at'),
      _db
          .from('offers')
          .select(_offerSelect)
          .eq('application_id', applicationId)
          .order('sent_at', ascending: false),
      // The timeline is helpful, not essential; never block the actions on it.
      _safeList(() => _db
          .from('application_events')
          .select('event_type, actor_type, from_state, to_state, reason, '
              'metadata, occurred_at')
          .eq('application_id', applicationId)
          .order('occurred_at')),
    ]);

    List<Map<String, dynamic>> maps(dynamic v) => (v as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    final interviews = maps(results[0]).map(Interview.fromRow).toList();
    final base = ApplicationSummary.fromRow(Map<String, dynamic>.from(row));

    // Rooms and the planned process add to the page; if either read fails
    // the interviews still show, just without a Join button or ○ steps.
    final extras = await Future.wait([
      interviews.any((i) => i.isOmeloMeet)
          ? _safeList(() => _db
              .from('interview_rooms')
              .select(_roomSelect)
              .inFilter('interview_id', [for (final i in interviews) i.id]))
          : Future.value(const <Map<String, dynamic>>[]),
      base.jobId.isEmpty
          ? Future.value(const <Map<String, dynamic>>[])
          : _safeList(() => _db
              .from('job_interview_rounds')
              .select('position, name, kind, meeting_mode, duration_minutes')
              .eq('job_id', base.jobId)
              .order('position')),
    ]);
    final rooms = {
      for (final r in extras[0].map(InterviewRoom.fromRow)) r.interviewId: r,
    };

    final app = base.copyWith(
      interviews: [for (final i in interviews) i.withRoom(rooms[i.id])],
      offers: maps(results[1]).map(Offer.fromRow).toList(),
    );
    return ApplicationDetail(
      application: app,
      events: maps(results[2]).map(ApplicationEvent.fromRow).toList(),
      plannedRounds: extras[1].map(PlannedRound.fromRow).toList(),
    );
  }

  Future<List<Map<String, dynamic>>> _safeList(
      Future<dynamic> Function() query) async {
    try {
      final rows = await query();
      return (rows as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    } catch (_) {
      return const [];
    }
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
    } catch (e) {
      // Includes the server's rate limit ("You have applied to a lot of jobs
      // today…"), which is shown word for word.
      return ApplyOutcome(error: applyErrorMessage(e));
    }
  }

  // -- Hiring loop actions --------------------------------------------------
  //
  // State changes only happen through these RPCs; the database rejects direct
  // updates. Failures throw PostgrestException with a readable message — show
  // it with [HiringActionError.message].

  /// Withdraw. The server also cancels interviews and declines open offers.
  Future<void> withdraw(String applicationId, {String? reason}) async {
    await _db.rpc('omelo_withdraw_application', params: {
      'p_application_id': applicationId,
      'p_reason': _clean(reason),
    });
  }

  Future<void> confirmInterview(String interviewId) async {
    await _db.rpc('omelo_confirm_interview',
        params: {'p_interview_id': interviewId});
  }

  /// "I can't attend". The server requires a reason of 3+ characters.
  Future<void> cancelInterview(String interviewId, String reason) async {
    await _db.rpc('omelo_cancel_interview', params: {
      'p_interview_id': interviewId,
      'p_reason': reason.trim(),
    });
  }

  /// Marks the offer as seen by the worker. Safe to call repeatedly.
  Future<void> viewOffer(String offerId) async {
    await _db.rpc('omelo_view_offer', params: {'p_offer_id': offerId});
  }

  Future<OfferResponse> respondToOffer(
    String offerId, {
    required bool accept,
    String? reason,
  }) async {
    final res = await _db.rpc('omelo_respond_to_offer', params: {
      'p_offer_id': offerId,
      'p_accept': accept,
      'p_reason': _clean(reason),
    });
    return OfferResponse.fromJson(res);
  }

  /// Why this job fits me. Throws when signed out or the job is not published.
  Future<MatchResult> myMatch(String jobId, {String? workIdentityId}) async {
    final res = await _db.rpc('omelo_my_match', params: {
      'p_job_id': jobId,
      if (workIdentityId != null) 'p_work_identity_id': workIdentityId,
    });
    return MatchResult.fromJson(res);
  }

  /// Best-first recommendations near a point.
  Future<List<RecommendedJob>> recommendJobs({
    required double lat,
    required double lng,
    int radiusKm = 25,
    int limit = 20,
    String? workIdentityId,
  }) async {
    final rows = await _db.rpc('omelo_recommend_jobs', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_radius_km': radiusKm,
      'p_limit': limit,
      if (workIdentityId != null) 'p_work_identity_id': workIdentityId,
    });
    return (rows as List)
        .map((r) => RecommendedJob.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  static String? _clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }
}

/// Turns any failure from a hiring action into a sentence for the worker.
class HiringActionError {
  static String message(Object e) {
    if (e is PostgrestException && e.message.trim().isNotEmpty) {
      return e.message;
    }
    return 'That did not go through. Check your connection and try again.';
  }
}
