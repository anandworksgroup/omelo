import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';
import '../../data/account_repository.dart';

/// "14 Oct 2026"
String deletionDay(DateTime d) => DateFormat('d MMM yyyy').format(d);

/// Sends a 6-digit code and checks it. Used on the Settings screen and, for
/// email, before accepting an offer when the server requires it.
class VerificationFlow extends ConsumerStatefulWidget {
  const VerificationFlow({
    super.key,
    required this.channel,
    this.destination,
    this.verified = false,
    this.onVerified,
  });

  /// 'email' or 'phone'.
  final String channel;

  /// The email address, or the phone number to prefill.
  final String? destination;
  final bool verified;
  final VoidCallback? onVerified;

  @override
  ConsumerState<VerificationFlow> createState() => _VerificationFlowState();
}

enum _Stage { idle, sent, verified }

class _VerificationFlowState extends ConsumerState<VerificationFlow> {
  static const _cooldown = Duration(seconds: 60);

  late _Stage _stage = widget.verified ? _Stage.verified : _Stage.idle;
  final _code = TextEditingController();
  late final _phone = TextEditingController(
      text: widget.channel == 'phone' ? widget.destination ?? '' : '');
  bool _busy = false;
  String? _error;
  String? _sentTo;
  DateTime? _canResendAt;
  Timer? _tick;

  bool get _isEmail => widget.channel == 'email';

  @override
  void didUpdateWidget(covariant VerificationFlow old) {
    super.didUpdateWidget(old);
    if (widget.verified && _stage != _Stage.verified) {
      _stage = _Stage.verified;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _code.dispose();
    _phone.dispose();
    super.dispose();
  }

  int get _secondsLeft {
    final at = _canResendAt;
    if (at == null) return 0;
    final s = at.difference(DateTime.now()).inSeconds;
    return s < 0 ? 0 : s + 1;
  }

  void _startCooldown() {
    _canResendAt = DateTime.now().add(_cooldown);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return t.cancel();
      if (_secondsLeft == 0) t.cancel();
      setState(() {});
    });
  }

  Future<void> _send() async {
    if (!_isEmail && _phone.text.trim().isEmpty) {
      setState(() => _error = 'Enter your phone number first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final repo = ref.read(accountRepositoryProvider);
    try {
      final r = _isEmail
          ? await repo.requestEmailCode()
          : await repo.requestPhoneCode(_phone.text);
      if (!mounted) return;
      if (r.alreadyVerified) {
        _done();
        return;
      }
      _code.clear();
      setState(() {
        _stage = _Stage.sent;
        _sentTo = r.sentTo;
      });
      _startCooldown();
    } catch (e) {
      if (mounted) setState(() => _error = serverMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter all 6 numbers from the code.');
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(accountRepositoryProvider).confirmCode(widget.channel, code);
      if (!mounted) return;
      _done();
    } catch (e) {
      if (mounted) setState(() => _error = serverMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _done() {
    setState(() {
      _stage = _Stage.verified;
      _error = null;
    });
    _tick?.cancel();
    ref.invalidate(trustStatusProvider);
    widget.onVerified?.call();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final digits = (data?.text ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    final code = digits.length > 6 ? digits.substring(0, 6) : digits;
    _code.value = TextEditingValue(
      text: code,
      selection: TextSelection.collapsed(offset: code.length),
    );
    if (code.length == 6) unawaited(_confirm());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final what = _isEmail ? 'email' : 'phone number';

    final error = _error == null
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(_error!,
                style: TextStyle(color: scheme.error, fontSize: 14.5)),
          );

    switch (_stage) {
      case _Stage.verified:
        return Row(
          children: [
            const Icon(Icons.verified, color: OmeloTheme.verified),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Your $what is verified.',
                  style: const TextStyle(
                      fontSize: 15.5, fontWeight: FontWeight.w600)),
            ),
          ],
        );

      case _Stage.idle:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isEmail)
              Text(
                'We will send a 6-digit code to '
                '${widget.destination ?? 'your email'}.',
                style: const TextStyle(fontSize: 15, height: 1.4),
              )
            else
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                autofillHints: const [AutofillHints.telephoneNumber],
                decoration: const InputDecoration(
                  labelText: 'Phone number',
                  hintText: '+91 98765 43210',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _send,
              child: _busy ? const _Spinner() : const Text('Send me a code'),
            ),
            error,
          ],
        );

      case _Stage.sent:
        final wait = _secondsLeft;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Enter the 6-digit code we sent to '
              '${_sentTo ?? (_isEmail ? 'your email' : 'your phone')}. '
              'It works for 15 minutes.',
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 12),
            AutofillGroup(
              child: TextField(
                controller: _code,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(6),
                ],
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 10),
                decoration: InputDecoration(
                  labelText: '6-digit code',
                  counterText: '',
                  suffixIcon: IconButton(
                    tooltip: 'Paste code',
                    icon: const Icon(Icons.content_paste),
                    onPressed: _busy ? null : _paste,
                  ),
                ),
                onChanged: (v) {
                  if (_error != null) setState(() => _error = null);
                  if (v.length == 6) _confirm();
                },
                onSubmitted: (_) => _confirm(),
              ),
            ),
            error,
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _confirm,
              child: _busy ? const _Spinner() : const Text('Confirm'),
            ),
            const SizedBox(height: 4),
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
              onPressed: _busy || wait > 0 ? null : _send,
              child: Text(wait > 0
                  ? 'Send a new code in ${wait}s'
                  : 'Send a new code'),
            ),
          ],
        );
    }
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();
  @override
  Widget build(BuildContext context) => const SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(strokeWidth: 2.5),
      );
}

/// Bottom sheet with the email verification flow. Returns true once the
/// email is verified.
Future<bool> showEmailVerificationSheet(
    BuildContext context, String? email) async {
  var verified = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, 24 + MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Verify your email',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              'The employer needs a checked email address before you can '
              'accept this offer.',
              style: TextStyle(
                  fontSize: 14.5,
                  height: 1.4,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            VerificationFlow(
              channel: 'email',
              destination: email,
              onVerified: () {
                verified = true;
                Future.delayed(const Duration(milliseconds: 900), () {
                  if (ctx.mounted) Navigator.of(ctx).pop();
                });
              },
            ),
          ],
        ),
      ),
    ),
  );
  return verified;
}

/// "Your account will be deleted on …" with a way out. Shown at the top of
/// Home and Settings while a deletion is scheduled.
class DeletionBanner extends ConsumerStatefulWidget {
  const DeletionBanner({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<DeletionBanner> createState() => _DeletionBannerState();
}

class _DeletionBannerState extends ConsumerState<DeletionBanner> {
  bool _busy = false;

  Future<void> _cancel() async {
    setState(() => _busy = true);
    try {
      await ref.read(accountRepositoryProvider).cancelDeletion();
      ref.invalidate(trustStatusProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Good. Your account will not be deleted.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(serverMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final when = ref.watch(trustStatusProvider).value?.deletionScheduledFor;
    if (when == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: widget.padding,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.errorContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    color: scheme.onErrorContainer),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Your account will be deleted on ${deletionDay(when)}.',
                    style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: scheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _cancel,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.onErrorContainer,
                foregroundColor: scheme.errorContainer,
              ),
              child: _busy ? const _Spinner() : const Text('Cancel deletion'),
            ),
          ],
        ),
      ),
    );
  }
}
