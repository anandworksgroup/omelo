import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import 'career.dart';
import 'jobs_repository.dart' show supabaseProvider;

export 'career.dart';

final careerRepositoryProvider = Provider<CareerRepository>(
  (ref) => CareerRepository(ref.watch(supabaseProvider)),
);

/// Career goals, the path to one, the development plan, Omelo skill
/// assessments and market insights. The server scores and grades everything;
/// the app sends what the worker chose and shows the server's words.
class CareerRepository {
  CareerRepository(this._db);
  final SupabaseClient _db;

  String? get _uid => _db.auth.currentUser?.id;

  static const _goalColumns =
      'id, work_identity_id, profession_id, goal_text, target_countries, '
      'target_pay_amount, target_pay_period, target_currency, target_date, '
      'priority, status, created_at, professions ( name )';

  // -- Path and goals -----------------------------------------------------------

  Future<CareerSuggestions> suggestions({String? identityId}) async =>
      CareerSuggestions.fromJson(await _db.rpc(
        'omelo_suggest_career_goals',
        params: {'p_identity': ?identityId},
      ));

  Future<CareerPath> path({String? goalId, String? identityId}) async =>
      CareerPath.fromJson(await _db.rpc('omelo_career_path', params: {
        'p_goal': ?goalId,
        'p_identity': ?identityId,
      }));

  /// All my goals, newest first (my own rows, through RLS).
  Future<List<CareerGoal>> myGoals() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _db
        .from('career_goals')
        .select(_goalColumns)
        .eq('person_id', uid)
        .order('created_at', ascending: false);
    return parseGoals(rows);
  }

  Future<CareerGoal?> saveGoal(GoalDraft d) async => CareerGoal.fromJson(
    await _db.rpc('omelo_save_career_goal', params: {'p': d.toPayload()}),
  );

  /// Achieved, archived, or active again. The identity is always sent so the
  /// goal stays with the identity it was set for.
  Future<void> setGoalStatus(CareerGoal g, GoalStatus s) =>
      _db.rpc('omelo_save_career_goal', params: {
        'p': {
          'id': g.id,
          'work_identity_id': ?g.workIdentityId,
          'status': s.wire,
        },
      });

  // -- Plan (my own rows, through RLS) ------------------------------------------

  Future<void> addPlanItem({
    required String goalId,
    required PlanKind kind,
    required String title,
    required int position,
    String? skillId,
    String? resourceId,
    String? jobId,
  }) async {
    final uid = _uid;
    if (uid == null) throw const AuthException('Sign in first');
    await _db.from('career_plan_items').insert({
      'person_id': uid,
      'goal_id': goalId,
      'kind': kind.wire,
      'title': title.trim(),
      'position': position,
      'skill_id': ?skillId,
      'resource_id': ?resourceId,
      'job_id': ?jobId,
    });
  }

  Future<void> setPlanStatus(String itemId, PlanStatus s) => _db
      .from('career_plan_items')
      .update({'status': s.wire})
      .eq('id', itemId);

  // -- Assessments -------------------------------------------------------------

  Future<AssessmentSession?> startAssessment(
    String skillId, {
    String? identityId,
  }) async =>
      AssessmentSession.fromJson(await _db.rpc(
        'omelo_start_skill_assessment',
        params: {'p_skill': skillId, 'p_identity': ?identityId},
      ));

  Future<AssessmentResult> submitAssessment(
    String attemptId,
    List<int> answers,
  ) async =>
      AssessmentResult.fromJson(await _db.rpc(
        'omelo_submit_skill_assessment',
        params: {'p_attempt': attemptId, 'p_answers': answers},
      ));

  // -- Market ------------------------------------------------------------------

  Future<MarketInsights> marketInsights(
    String professionId, {
    String? country,
    String? currency,
  }) async =>
      MarketInsights.fromJson(await _db.rpc('omelo_market_insights', params: {
        'p_profession': professionId,
        'p_country': ?country,
        'p_currency': ?currency,
      }));
}

/// A server refusal in its own words ("You can take this assessment again
/// after …"), with database constraint codes turned into plain ones.
String careerError(Object e) {
  if (e is PostgrestException) {
    switch (e.code) {
      case '23514':
        return 'Check what you entered and try again.';
      case '42501':
        if (e.message.trim().isEmpty) return 'You cannot change this.';
    }
    if (e.message.trim().isNotEmpty) return e.message.trim();
  }
  if (e is AuthException && e.message.trim().isNotEmpty) return e.message.trim();
  return 'Could not reach Omelo. Check your internet and try again.';
}

/// True when the worker has to create a work identity before anything here
/// makes sense.
bool needsIdentity(Object e) =>
    e is PostgrestException && e.message.contains('Create a work identity');

// -- Providers -------------------------------------------------------------------

/// Which goal (null: my current active one) for which identity (null: my
/// main one).
typedef CareerKey = ({String? goal, String? identity});

final careerPathProvider = FutureProvider.autoDispose
    .family<CareerPath, CareerKey>((ref, key) {
  return ref
      .watch(careerRepositoryProvider)
      .path(goalId: key.goal, identityId: key.identity);
});

final myGoalsProvider = FutureProvider.autoDispose<List<CareerGoal>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(careerRepositoryProvider).myGoals();
});

typedef MarketKey = ({String profession, String? country});

final marketInsightsProvider = FutureProvider.autoDispose
    .family<MarketInsights, MarketKey>((ref, key) {
  return ref
      .watch(careerRepositoryProvider)
      .marketInsights(key.profession, country: key.country);
});

/// Reload everything career after a change (goal saved, test passed).
void invalidateCareer(WidgetRef ref) {
  ref.invalidate(careerPathProvider);
  ref.invalidate(myGoalsProvider);
}
