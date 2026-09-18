import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import 'jobs_repository.dart' show supabaseProvider;
import 'representations.dart';

export 'representations.dart';

final representationsRepositoryProvider = Provider<RepresentationsRepository>(
  (ref) => RepresentationsRepository(ref.watch(supabaseProvider)),
);

/// Recruiter and agency requests to represent me. Everything goes through the
/// omelo_* functions except `allow_recruiter_requests`, which the owner
/// updates directly on their own identity (RLS).
class RepresentationsRepository {
  RepresentationsRepository(this._db);
  final SupabaseClient _db;

  Future<List<Representation>> mine() async {
    if (_db.auth.currentUser == null) return const [];
    final res = await _db.rpc('omelo_my_representations');
    return parseRepresentations(res);
  }

  Future<void> accept(String consentId) => _db.rpc(
    'omelo_respond_to_representation',
    params: acceptRepresentationPayload(consentId),
  );

  Future<void> decline(
    String consentId,
    RepresentationDeclineReason? reason, [
    String? otherText,
  ]) => _db.rpc(
    'omelo_respond_to_representation',
    params: declineRepresentationPayload(consentId, reason, otherText),
  );

  Future<void> revoke(String consentId, [String? reason]) => _db.rpc(
    'omelo_revoke_representation',
    params: revokeRepresentationPayload(consentId, reason),
  );

  Future<bool> allowRecruiterRequests(String identityId) async {
    final row = await _db
        .from('work_identities')
        .select('allow_recruiter_requests')
        .eq('id', identityId)
        .maybeSingle();
    return row?['allow_recruiter_requests'] != false;
  }

  Future<void> setAllowRecruiterRequests(String identityId, bool allow) => _db
      .from('work_identities')
      .update({'allow_recruiter_requests': allow})
      .eq('id', identityId);
}

// -- Providers -------------------------------------------------------------------

/// My representations, waiting ones first. Empty when signed out.
final myRepresentationsProvider =
    FutureProvider.autoDispose<List<Representation>>((ref) async {
      if (!ref.watch(isSignedInProvider)) return const [];
      final list = await ref.watch(representationsRepositoryProvider).mine();
      return sortRepresentations(list, DateTime.now());
    });

/// Requests still waiting for an answer, for badges and the Home card.
/// Empty on any failure: a badge must never break a screen.
final pendingRepresentationsProvider =
    Provider.autoDispose<List<Representation>>((ref) {
      final list = ref.watch(myRepresentationsProvider).valueOrNull;
      return list == null
          ? const []
          : pendingRepresentations(list, DateTime.now());
    });

/// application id → agency name ("Submitted by Acme Staffing").
final agencyByApplicationProvider = Provider.autoDispose<Map<String, String>>((
  ref,
) {
  final list = ref.watch(myRepresentationsProvider).valueOrNull;
  return list == null ? const {} : agencyByApplication(list);
});

/// Whether recruiters and agencies may ask to represent this identity
/// (defaults to yes).
final allowRecruiterRequestsProvider = FutureProvider.autoDispose
    .family<bool, String>((ref, identityId) async {
      try {
        return await ref
            .watch(representationsRepositoryProvider)
            .allowRecruiterRequests(identityId);
      } catch (_) {
        return true;
      }
    });
