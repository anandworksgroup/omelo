import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'jobs_repository.dart' show supabaseProvider;

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

class AuthResult {
  const AuthResult({this.error, this.needsConfirmation = false});
  final String? error;
  final bool needsConfirmation;
  bool get ok => error == null && !needsConfirmation;
}

class AuthRepository {
  AuthRepository(this._db);
  final SupabaseClient _db;

  User? get currentUser => _db.auth.currentUser;
  bool get isSignedIn => currentUser != null;

  /// Email + password.
  ///
  /// The spec calls for phone-first auth in India (country_policies
  /// .phone_auth_preferred), but the Supabase project currently has the phone
  /// provider disabled — it needs an SMS provider configured. This is the
  /// working path until then; swapping to OTP is a change in this file only.
  Future<AuthResult> signIn(String email, String password) async {
    try {
      await _db.auth.signInWithPassword(email: email.trim(), password: password);
      return const AuthResult();
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('invalid')) {
        return const AuthResult(
          error: 'That email and password do not match an account.',
        );
      }
      if (m.contains('confirm')) {
        return const AuthResult(
          error: 'This account has not been confirmed yet. Check your email.',
        );
      }
      return AuthResult(error: e.message);
    } catch (_) {
      return const AuthResult(
        error: 'Could not sign in. Check your connection and try again.',
      );
    }
  }

  Future<AuthResult> signUp(String email, String password, String name) async {
    try {
      final res = await _db.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'full_name': name.trim()},
      );
      if (res.session == null) return const AuthResult(needsConfirmation: true);
      return const AuthResult();
    } on AuthException catch (e) {
      final m = e.message.toLowerCase();
      if (m.contains('rate limit')) {
        return const AuthResult(
          error:
              'Too many sign-up emails from this project right now. Try again in a few minutes.',
        );
      }
      return AuthResult(error: e.message);
    } catch (_) {
      return const AuthResult(error: 'Could not create your account.');
    }
  }

  Future<void> signOut() => _db.auth.signOut();

  /// The primary work identity, created automatically at signup by
  /// omelo_handle_new_user(). Applications are anchored to it.
  Future<String?> primaryWorkIdentityId() async {
    final uid = currentUser?.id;
    if (uid == null) return null;
    final row = await _db
        .from('work_identities')
        .select('id')
        .eq('person_id', uid)
        .eq('is_primary', true)
        .maybeSingle();
    return row?['id'] as String?;
  }
}
