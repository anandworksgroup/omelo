import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import '../../core/responsive.dart';
import '../../data/account_repository.dart';
import '../../data/auth_repository.dart';

/// Worker sign-in.
///
/// The spec calls for phone-first auth in India. The Supabase project has the
/// phone provider disabled (it needs an SMS provider), so this is email +
/// password for now. The note at the bottom says so honestly rather than
/// pretending this is the intended experience.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key, this.redirectTo});
  final String? redirectTo;

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _name = TextEditingController();

  bool _isSignUp = false;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    final repo = ref.read(authRepositoryProvider);
    final res = _isSignUp
        ? await repo.signUp(_email.text, _password.text, _name.text)
        : await repo.signIn(_email.text, _password.text);

    if (!mounted) return;

    if (res.error != null) {
      setState(() {
        _busy = false;
        _error = res.error;
      });
      return;
    }

    setState(() => _busy = false);
    if (widget.redirectTo != null) {
      context.go(widget.redirectTo!);
    } else {
      context.go('/home');
    }
  }

  /// Sends a reset link. The answer is the same whether or not an account
  /// uses the email, so this cannot be used to find out who has one.
  Future<void> _forgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (_) => _ForgotPasswordDialog(initialEmail: _email.text.trim()),
    );
    if (email == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    String? error;
    try {
      await ref.read(accountRepositoryProvider).sendPasswordReset(email);
    } on AuthException catch (e) {
      // Rate limits apply to everyone, so saying so reveals nothing.
      if (e.statusCode == '429' || e.message.toLowerCase().contains('seconds')) {
        error = 'Please wait a minute before asking for another link.';
      }
      // Any other auth error gets the same neutral answer as success.
    } catch (_) {
      error = 'Could not send the link. Check your connection and try again.';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = error;
      _notice = error == null
          ? 'If an account uses $email, we have sent it a link to set a new '
              'password. Check your inbox and spam folder. Open the link on '
              'this phone or computer.'
          : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? 'Create account' : 'Sign in')),
      body: ContentWidth.reading(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Text(
            _isSignUp ? 'Join Omelo' : 'Welcome back',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            _isSignUp
                ? 'You need an account to apply. Takes under a minute — no email to confirm.'
                : 'Sign in to apply and track your applications.',
            style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 28),

          if (_isSignUp) ...[
            TextField(
              controller: _name,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Your name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 14),
          ],

          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.mail_outline),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _password,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline),
              helperText: _isSignUp ? 'At least 8 characters' : null,
            ),
          ),

          if (!_isSignUp)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _busy ? null : _forgotPassword,
                child: const Text('Forgot password?'),
              ),
            ),

          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: TextStyle(color: scheme.error, fontSize: 14)),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(_notice!, style: const TextStyle(fontSize: 14)),
            ),
          ],

          const SizedBox(height: 24),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(_isSignUp ? 'Create account' : 'Sign in'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                      _isSignUp = !_isSignUp;
                      _error = null;
                      _notice = null;
                    }),
            child: Text(_isSignUp
                ? 'I already have an account'
                : "I don't have an account"),
          ),

          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'No email confirmation needed — your account works straight '
                    'away. Signing in with a phone number is not switched on for '
                    'this project yet; it needs an SMS provider.',
                    style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  const _ForgotPasswordDialog({required this.initialEmail});
  final String initialEmail;

  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  late final _email = TextEditingController(text: widget.initialEmail);
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  void _send() {
    final email = _email.text.trim();
    if (!looksLikeEmail(email)) {
      setState(() => _error = 'Enter the email you signed up with.');
      return;
    }
    Navigator.pop(context, email);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Forgot your password?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'We will email you a link to set a new password.',
            style: TextStyle(fontSize: 15, height: 1.4),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              labelText: 'Email',
              prefixIcon: const Icon(Icons.mail_outline),
              errorText: _error,
            ),
            onSubmitted: (_) => _send(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _send, child: const Text('Send link')),
      ],
    );
  }
}
