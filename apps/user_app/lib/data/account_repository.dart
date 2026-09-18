import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import '../core/auth_links.dart';
import 'account.dart';
import 'jobs_repository.dart' show supabaseProvider;

export 'account.dart';

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(ref.watch(supabaseProvider)),
);

/// Verification, deletion schedule and offer rules for the signed-in worker.
/// Null when signed out.
final trustStatusProvider = FutureProvider<TrustStatus?>((ref) async {
  final signedIn = ref.watch(isSignedInProvider);
  if (!signedIn) return null;
  return ref.watch(accountRepositoryProvider).trustStatus();
});

/// Devices signed in to this account, most recently active first.
final mySessionsProvider =
    FutureProvider.autoDispose<List<DeviceSession>>((ref) async {
  final signedIn = ref.watch(isSignedInProvider);
  if (!signedIn) return const [];
  return ref.watch(accountRepositoryProvider).sessions();
});

/// All account and trust calls. Every one of them goes through an RPC that
/// checks `auth.uid()` on the server; nothing here is privileged.
class AccountRepository {
  AccountRepository(this._db);
  final SupabaseClient _db;

  Future<TrustStatus> trustStatus() async =>
      TrustStatus.fromJson(await _db.rpc('omelo_my_trust_status'));

  Future<CodeRequest> requestEmailCode() async =>
      CodeRequest.fromJson(await _db.rpc('omelo_request_email_verification'));

  Future<CodeRequest> requestPhoneCode(String phone) async =>
      CodeRequest.fromJson(await _db.rpc('omelo_request_phone_verification',
          params: {'p_phone': phone.trim()}));

  /// Throws with a readable message when the code is wrong or expired.
  Future<void> confirmCode(String channel, String code) async {
    await _db.rpc('omelo_confirm_verification',
        params: {'p_channel': channel, 'p_code': code.trim()});
  }

  Future<List<DeviceSession>> sessions() async {
    final rows = await _db.rpc('omelo_my_sessions');
    return (rows as List)
        .map((r) => DeviceSession.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<bool> revokeSession(String id) async =>
      (await _db.rpc('omelo_revoke_session', params: {'p_session_id': id})) ==
      true;

  Future<int> revokeOtherSessions() async {
    final n = await _db.rpc('omelo_revoke_other_sessions');
    return n is num ? n.toInt() : 0;
  }

  Future<DateTime?> requestDeletion({String? reason}) async {
    final r = reason?.trim();
    final res = await _db.rpc('omelo_request_account_deletion',
        params: {'p_reason': (r == null || r.isEmpty) ? null : r});
    final when = res is Map ? res['scheduled_for'] : null;
    return when is String ? DateTime.tryParse(when)?.toLocal() : null;
  }

  Future<bool> cancelDeletion() async =>
      (await _db.rpc('omelo_cancel_account_deletion')) == true;

  Future<void> changePassword(String password) async {
    await _db.auth.updateUser(UserAttributes(password: password));
  }

  /// Sends a reset link. Callers must show the same neutral message whether
  /// or not an account uses this email.
  Future<void> sendPasswordReset(String email) async {
    await _db.auth.resetPasswordForEmail(
      email.trim(),
      redirectTo: AuthLinks.passwordResetRedirect(),
    );
  }
}
