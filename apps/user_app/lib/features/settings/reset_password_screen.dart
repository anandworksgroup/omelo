import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/auth_links.dart';
import '../../core/responsive.dart';
import '../../data/account_repository.dart';

/// `/reset-password` — "Set a new password", reached from the reset email.
///
/// supabase_flutter exchanges the link for a short recovery session and emits
/// `passwordRecovery`; the router then sends the worker here. Without that
/// session the link was expired or already used.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _show = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final problem = passwordProblem(_password.text, _confirm.text);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountRepositoryProvider).changePassword(_password.text);
      if (!mounted) return;
      PasswordRecovery.done();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Your new password is saved. You are signed in.')));
      context.go('/home');
    } catch (e) {
      if (mounted) setState(() => _error = passwordChangeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _leave() {
    PasswordRecovery.done();
    context.go(ref.read(isSignedInProvider) ? '/home' : '/sign-in');
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(isSignedInProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Set a new password'),
        automaticallyImplyLeading: false,
      ),
      body: ContentWidth.reading(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          children: !signedIn
              ? [
                  const SizedBox(height: 24),
                  Icon(Icons.link_off, size: 48, color: scheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  const Text(
                    'This link has expired or was already used.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Go to Sign in and tap "Forgot password?" to get a new '
                    'link. Open it on this same phone or computer.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 15, height: 1.45,
                        color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _leave,
                    child: const Text('Go to Sign in'),
                  ),
                ]
              : [
                  const Text(
                    'Choose a new password',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Use at least 8 characters. You will use it to sign in '
                    'from now on.',
                    style: TextStyle(
                        fontSize: 15, color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 24),
                  AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _password,
                          obscureText: !_show,
                          autofocus: true,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: InputDecoration(
                            labelText: 'New password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip:
                                  _show ? 'Hide password' : 'Show password',
                              icon: Icon(_show
                                  ? Icons.visibility_off
                                  : Icons.visibility),
                              onPressed: () => setState(() => _show = !_show),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _confirm,
                          obscureText: !_show,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: const InputDecoration(
                            labelText: 'Type it again',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          onSubmitted: (_) => _save(),
                        ),
                      ],
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(_error!,
                        style: TextStyle(color: scheme.error, fontSize: 14.5)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('Save new password'),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                    onPressed: _busy ? null : _leave,
                    child: const Text('Not now'),
                  ),
                ],
        ),
      ),
    );
  }
}
