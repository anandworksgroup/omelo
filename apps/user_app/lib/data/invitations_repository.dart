import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import 'invitations.dart';
import 'jobs_repository.dart' show supabaseProvider;

export 'invitations.dart';

final invitationsRepositoryProvider = Provider<InvitationsRepository>(
  (ref) => InvitationsRepository(ref.watch(supabaseProvider)),
);

/// Invitations to apply and profile views. Everything goes through the
/// omelo_* functions except `allow_invitations`, which the owner updates
/// directly on their own identity (RLS).
class InvitationsRepository {
  InvitationsRepository(this._db);
  final SupabaseClient _db;

  Future<List<JobInvitation>> mine() async {
    if (_db.auth.currentUser == null) return const [];
    final res = await _db.rpc('omelo_my_invitations');
    return parseInvitations(res);
  }

  Future<void> markViewed(String invitationId) => _db.rpc(
      'omelo_mark_invitation_viewed',
      params: {'p_invitation': invitationId});

  /// "Not interested", with an optional short reason.
  Future<void> decline(String invitationId, DeclineReason? reason,
          [String? otherText]) =>
      _db.rpc('omelo_respond_to_invitation',
          params: declinePayload(invitationId, reason, otherText));

  Future<List<ProfileView>> profileViews({int days = 30}) async {
    if (_db.auth.currentUser == null) return const [];
    final res =
        await _db.rpc('omelo_my_profile_views', params: {'p_days': days});
    return parseProfileViews(res);
  }

  Future<bool> allowInvitations(String identityId) async {
    final row = await _db
        .from('work_identities')
        .select('allow_invitations')
        .eq('id', identityId)
        .maybeSingle();
    return row?['allow_invitations'] != false;
  }

  Future<void> setAllowInvitations(String identityId, bool allow) => _db
      .from('work_identities')
      .update({'allow_invitations': allow}).eq('id', identityId);
}

// -- Providers -------------------------------------------------------------------

/// My invitations, pending first. Empty when signed out.
final myInvitationsProvider =
    FutureProvider.autoDispose<List<JobInvitation>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(invitationsRepositoryProvider).mine();
});

/// Invitations still waiting for an answer, for badges and the Home card.
/// Zero on any failure: a badge must never break a screen.
final pendingInvitationsProvider = Provider.autoDispose<int>((ref) {
  final list = ref.watch(myInvitationsProvider).valueOrNull;
  return list == null ? 0 : pendingInvitationCount(list);
});

final profileViewsProvider =
    FutureProvider.autoDispose<List<ProfileView>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(invitationsRepositoryProvider).profileViews(days: 30);
});

/// Whether employers may invite this identity (defaults to yes).
final allowInvitationsProvider =
    FutureProvider.autoDispose.family<bool, String>((ref, identityId) async {
  try {
    return await ref
        .watch(invitationsRepositoryProvider)
        .allowInvitations(identityId);
  } catch (_) {
    return true;
  }
});
