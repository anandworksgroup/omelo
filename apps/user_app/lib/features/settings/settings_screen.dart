import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/account_repository.dart';
import '../../data/auth_repository.dart';
import '../applications/applications_screen.dart' show myApplicationsProvider;
import 'account_widgets.dart';

/// `/settings` — verify contact details, see signed-in devices, change the
/// password, delete the account, sign out. Also the target of the
/// "Account deletion scheduled" notification.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final trust = ref.watch(trustStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: context.canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => context.go('/profile'),
              ),
      ),
      body: user == null
          ? const Center(child: Text('Sign in to see your settings.'))
          : RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(mySessionsProvider);
                ref.invalidate(trustStatusProvider);
                await ref.read(trustStatusProvider.future);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(Breakpoints.of(context).gutter,
                    8, Breakpoints.of(context).gutter, 40),
                children: [
                  ContentWidth.reading(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const DeletionBanner(
                            padding: EdgeInsets.only(bottom: 20)),
                        const _Heading('Check your details'),
                        _Section(
                          icon: Icons.mail_outline,
                          title: 'Email',
                          child: trust.when(
                            loading: () => const _Loading(),
                            error: (_, __) => _Retry(
                              onRetry: () =>
                                  ref.invalidate(trustStatusProvider),
                            ),
                            data: (t) => VerificationFlow(
                              channel: 'email',
                              destination: t?.email ?? user.email,
                              verified: t?.emailVerified ?? false,
                            ),
                          ),
                        ),
                        _Section(
                          icon: Icons.phone_outlined,
                          title: 'Phone',
                          child: trust.when(
                            loading: () => const _Loading(),
                            error: (_, __) => const SizedBox.shrink(),
                            data: (t) => t?.phoneOtpAvailable == true
                                ? VerificationFlow(
                                    channel: 'phone',
                                    destination: t?.phone,
                                    verified: t?.phoneVerified ?? false,
                                  )
                                : const _ComingSoon(),
                          ),
                        ),
                        const SizedBox(height: 20),
                        const _Heading('Devices signed in'),
                        const _DevicesSection(),
                        const SizedBox(height: 20),
                        const _Heading('Password'),
                        const _ChangePasswordSection(),
                        const SizedBox(height: 20),
                        const _Heading('Delete my account'),
                        _DeleteSection(
                            scheduled: trust.value?.deletionScheduled ?? false),
                        const SizedBox(height: 28),
                        OutlinedButton.icon(
                          onPressed: () async {
                            await ref.read(authRepositoryProvider).signOut();
                            ref.invalidate(myApplicationsProvider);
                            if (context.mounted) context.go('/discover');
                          },
                          icon: const Icon(Icons.logout),
                          label: const Text('Sign out'),
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

// ---------------------------------------------------------------------------

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
      );
}

class _Section extends StatelessWidget {
  const _Section({required this.child, this.icon, this.title});
  final Widget child;
  final IconData? icon;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (title != null) ...[
                Row(
                  children: [
                    if (icon != null) ...[
                      Icon(icon, size: 22),
                      const SizedBox(width: 10),
                    ],
                    Text(title!,
                        style: const TextStyle(
                            fontSize: 16.5, fontWeight: FontWeight.w700)),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
}

class _Retry extends StatelessWidget {
  const _Retry({required this.onRetry});
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Could not load this. Check your connection.',
              style: TextStyle(fontSize: 15)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      );
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon();
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Text('Checking your phone number is coming soon.',
              style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant)),
        ),
        const SizedBox(width: 8),
        const OmeloPill('Coming soon'),
      ],
    );
  }
}

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(text)));

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
  required String yes,
  String no = 'Cancel',
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(body, style: const TextStyle(fontSize: 15.5, height: 1.4)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(no),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(yes),
        ),
      ],
    ),
  );
  return ok == true;
}

// -- Devices ----------------------------------------------------------------

class _DevicesSection extends ConsumerStatefulWidget {
  const _DevicesSection();

  @override
  ConsumerState<_DevicesSection> createState() => _DevicesSectionState();
}

class _DevicesSectionState extends ConsumerState<_DevicesSection> {
  String? _busyId;
  bool _busyAll = false;

  Future<void> _signOutOne(DeviceSession s) async {
    final ok = await _confirm(context,
        title: 'Sign out ${s.label}?',
        body: 'That device will be signed out within the hour. '
            'You can sign in there again at any time.',
        yes: 'Sign out');
    if (!ok || !mounted) return;
    setState(() => _busyId = s.id);
    try {
      await ref.read(accountRepositoryProvider).revokeSession(s.id);
      if (mounted) _snack(context, '${s.label} signed out.');
    } catch (e) {
      if (mounted) _snack(context, serverMessage(e));
    } finally {
      if (mounted) setState(() => _busyId = null);
      ref.invalidate(mySessionsProvider);
    }
  }

  Future<void> _signOutOthers() async {
    final ok = await _confirm(context,
        title: 'Sign out of all other devices?',
        body: 'Every other phone or computer will be signed out within the '
            'hour. This device stays signed in.',
        yes: 'Sign out others');
    if (!ok || !mounted) return;
    setState(() => _busyAll = true);
    try {
      final n = await ref.read(accountRepositoryProvider).revokeOtherSessions();
      if (mounted) {
        _snack(
            context,
            n == 0
                ? 'No other devices were signed in.'
                : n == 1
                    ? '1 other device signed out.'
                    : '$n other devices signed out.');
      }
    } catch (e) {
      if (mounted) _snack(context, serverMessage(e));
    } finally {
      if (mounted) setState(() => _busyAll = false);
      ref.invalidate(mySessionsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessions = ref.watch(mySessionsProvider);
    final scheme = Theme.of(context).colorScheme;

    return _Section(
      child: sessions.when(
        loading: () => const _Loading(),
        error: (_, __) =>
            _Retry(onRetry: () => ref.invalidate(mySessionsProvider)),
        data: (list) {
          if (list.isEmpty) {
            return const Text('No devices found.',
                style: TextStyle(fontSize: 15));
          }
          final others = list.where((s) => !s.isCurrent).length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0) const Divider(height: 20),
                _DeviceRow(
                  session: list[i],
                  busy: _busyId == list[i].id,
                  onSignOut: list[i].isCurrent || _busyAll
                      ? null
                      : () => _signOutOne(list[i]),
                ),
              ],
              if (others > 0) ...[
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: _busyAll ? null : _signOutOthers,
                  style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error),
                  child: _busyAll
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Sign out of all other devices'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.session, required this.busy, this.onSignOut});
  final DeviceSession session;
  final bool busy;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = session;
    return Row(
      children: [
        Icon(s.isPhone ? Icons.smartphone : Icons.computer,
            size: 28, color: scheme.onSurfaceVariant),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.label,
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text(
                [
                  s.isCurrent ? 'This device' : lastActive(s.lastActiveAt),
                  if (s.ipHint != null) s.ipHint!,
                ].join(' · '),
                style: TextStyle(
                    fontSize: 13.5,
                    color: s.isCurrent
                        ? OmeloTheme.verified
                        : scheme.onSurfaceVariant,
                    fontWeight:
                        s.isCurrent ? FontWeight.w700 : FontWeight.normal),
              ),
            ],
          ),
        ),
        if (!s.isCurrent)
          busy
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5)),
                )
              : TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: onSignOut,
                  child: const Text('Sign out'),
                ),
      ],
    );
  }
}

// -- Password ---------------------------------------------------------------

class _ChangePasswordSection extends ConsumerStatefulWidget {
  const _ChangePasswordSection();

  @override
  ConsumerState<_ChangePasswordSection> createState() =>
      _ChangePasswordSectionState();
}

class _ChangePasswordSectionState
    extends ConsumerState<_ChangePasswordSection> {
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
      _password.clear();
      _confirm.clear();
      FocusScope.of(context).unfocus();
      _snack(context, 'Password changed.');
    } catch (e) {
      if (mounted) setState(() => _error = passwordChangeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return _Section(
      child: AutofillGroup(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _password,
              obscureText: !_show,
              autofillHints: const [AutofillHints.newPassword],
              decoration: InputDecoration(
                labelText: 'New password',
                helperText: 'At least 8 characters',
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  tooltip: _show ? 'Hide password' : 'Show password',
                  icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _show = !_show),
                ),
              ),
            ),
            const SizedBox(height: 12),
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
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(color: scheme.error, fontSize: 14.5)),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Change password'),
            ),
          ],
        ),
      ),
    );
  }
}

// -- Delete -----------------------------------------------------------------

class _DeleteSection extends ConsumerStatefulWidget {
  const _DeleteSection({required this.scheduled});
  final bool scheduled;

  @override
  ConsumerState<_DeleteSection> createState() => _DeleteSectionState();
}

class _DeleteSectionState extends ConsumerState<_DeleteSection> {
  final _reason = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    final ok = await _confirm(context,
        title: 'Delete your account?',
        body: 'Your account will be deleted in 14 days. Until then you can '
            'cancel from Settings or the Home screen.',
        yes: 'Delete my account',
        no: 'Keep my account',
        destructive: true);
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final when = await ref
          .read(accountRepositoryProvider)
          .requestDeletion(reason: _reason.text);
      _reason.clear();
      ref.invalidate(trustStatusProvider);
      if (mounted) {
        _snack(
            context,
            when == null
                ? 'Your account will be deleted in 14 days.'
                : 'Your account will be deleted on ${deletionDay(when)}.');
      }
    } catch (e) {
      if (mounted) _snack(context, serverMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const points = [
      'Your account, work profile, applications and messages are deleted.',
      'Employers can no longer see your details.',
      'You have 14 days to change your mind. Sign in and tap "Cancel deletion".',
      'After 14 days it cannot be undone.',
    ];

    return _Section(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final p in points)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 7, right: 10),
                    child: Icon(Icons.circle,
                        size: 7, color: scheme.onSurfaceVariant),
                  ),
                  Expanded(
                    child: Text(p,
                        style: const TextStyle(fontSize: 15, height: 1.4)),
                  ),
                ],
              ),
            ),
          if (widget.scheduled)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Your account is already set to be deleted. Use '
                '"Cancel deletion" at the top of this page to keep it.',
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.error),
              ),
            )
          else ...[
            const SizedBox(height: 6),
            TextField(
              controller: _reason,
              maxLength: 500,
              maxLines: 2,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Why are you leaving? (optional)',
              ),
            ),
            const SizedBox(height: 6),
            FilledButton(
              onPressed: _busy ? null : _delete,
              style: FilledButton.styleFrom(
                  backgroundColor: scheme.error,
                  foregroundColor: scheme.onError),
              child: _busy
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Delete my account'),
            ),
          ],
        ],
      ),
    );
  }
}
