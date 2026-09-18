import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/account.dart' show serverMessage;
import '../../data/invitations.dart' show shortDate;
import '../../data/representations_repository.dart';
import 'representation_widgets.dart';

/// `/representations/:id` — one request to represent me (notification
/// deeplink for both `representation_request` and `representation_update`).
class RepresentationDetailScreen extends ConsumerStatefulWidget {
  const RepresentationDetailScreen({super.key, required this.consentId});
  final String consentId;

  @override
  ConsumerState<RepresentationDetailScreen> createState() =>
      _RepresentationDetailScreenState();
}

class _RepresentationDetailScreenState
    extends ConsumerState<RepresentationDetailScreen> {
  /// A local answer shown until the list reloads.
  RepresentationStatus? _answered;

  Representation? _find(List<Representation> list) {
    for (final r in list) {
      if (r.id == widget.consentId) return r;
    }
    return null;
  }

  Representation _withLocal(Representation r) {
    final a = _answered;
    if (a == null || r.status == a) return r;
    final now = DateTime.now();
    return r.copyWith(
      status: a,
      respondedAt: now,
      // The server allows revoking right after a yes (nothing submitted).
      canRevoke: a == RepresentationStatus.accepted,
      expiresAt: a == RepresentationStatus.accepted
          ? now.add(Duration(days: r.validDays))
          : null,
    );
  }

  void _setAnswered(RepresentationStatus s) {
    setState(() => _answered = s);
    ref.invalidate(myRepresentationsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(myRepresentationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Request to represent you'),
        leading: context.canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => context.go('/representations'),
              ),
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => RepresentationMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load this request',
          body: 'Check your internet and try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myRepresentationsProvider),
        ),
        data: (items) {
          final found = _find(items);
          if (found == null) {
            return RepresentationMessage(
              icon: Icons.handshake_outlined,
              title: 'Request not found',
              body: 'This request was not found. It may have been removed.',
              actionLabel: 'See all requests',
              onAction: () => context.go('/representations'),
            );
          }
          return _Body(
            representation: _withLocal(found),
            onRevoked: () => _setAnswered(RepresentationStatus.revoked),
          );
        },
      ),
      bottomNavigationBar: list.maybeWhen(
        data: (items) {
          final found = _find(items);
          if (found == null) return null;
          final r = _withLocal(found);
          final actions = representationActions(r, DateTime.now());
          if (!actions.isAnswerable) return null;
          return _AnswerBar(
            representation: r,
            onAccepted: () => _setAnswered(RepresentationStatus.accepted),
            onDeclined: () => _setAnswered(RepresentationStatus.declined),
          );
        },
        orElse: () => null,
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.representation, required this.onRevoked});
  final Representation representation;
  final VoidCallback onRevoked;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = representation;
    final t = r.terms;
    final now = DateTime.now();
    final status = r.statusAt(now);
    final actions = representationActions(r, now);
    final scheme = Theme.of(context).colorScheme;
    final gutter = Breakpoints.of(context).gutter;
    final pay = representationPayLabel(t.pay);
    final type = representationTypeLine(t);
    final shifts = representationShiftLine(t);
    final start = representationStartLine(t, now);
    final openings = openingsLine(t);
    final answerBy = representationAnswerBy(r, now);
    final sub = r.submission;
    final placement = placementLine(r.placement, now);

    Widget line(IconData icon, String text, {bool strong = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15.5,
                height: 1.35,
                fontWeight: strong ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );

    Widget heading(String text) => Padding(
      padding: const EdgeInsets.only(top: 26, bottom: 12),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    );

    final shareTitle = switch (status) {
      RepresentationStatus.requested => 'What will be shared',
      RepresentationStatus.accepted ||
      RepresentationStatus.active => 'What they can share',
      _ => 'What they asked to share',
    };

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 32),
      children: [
        ContentWidth.reading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // -- Who is asking -------------------------------------------
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CompanyAvatar(
                    name: t.agencyName,
                    logoUrl: t.agencyLogo,
                    size: 52,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AgencyName(
                          name: t.agencyName,
                          verified: t.agencyVerified,
                          independent: t.agencyIndependent,
                          fontSize: 16.5,
                          showWord: true,
                        ),
                        if (t.recruiterName != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Recruiter: ${t.recruiterName}',
                            style: TextStyle(
                              fontSize: 14.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                status == RepresentationStatus.requested
                    ? wantsToRepresentTitle(r)
                    : '${t.agencyName} asked to represent you',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Row(children: [RepresentationStatusPill(status)]),
              if (actions.headline != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: OmeloTheme.verified.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.handshake_outlined,
                        color: OmeloTheme.verified,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          actions.headline!,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (actions.note != null) ...[
                const SizedBox(height: 10),
                Text(
                  actions.note!,
                  style: const TextStyle(fontSize: 15, height: 1.45),
                ),
              ],

              // -- The job -------------------------------------------------
              heading('The job'),
              Text(
                t.position,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    'at ${t.clientName}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (t.clientOnOmelo)
                    const OmeloPill('On Omelo', icon: Icons.business_outlined),
                ],
              ),
              if (pay != null) ...[
                const SizedBox(height: 8),
                Text(
                  pay,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
              const SizedBox(height: 14),
              if (t.location != null) line(Icons.place_outlined, t.location!),
              if (type.isNotEmpty) line(Icons.work_outline, type),
              if (shifts.isNotEmpty) line(Icons.schedule_outlined, shifts),
              if (start != null) line(Icons.event_outlined, start),
              if (openings != null) line(Icons.groups_outlined, openings),
              if (r.identityLabel != null)
                line(
                  Icons.badge_outlined,
                  'Asked about your ${r.identityLabel} profile',
                ),
              if (t.hardRequirements.isNotEmpty) ...[
                const SizedBox(height: 6),
                const Text(
                  'They need',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                for (final req in t.hardRequirements) line(Icons.check, req),
              ],
              if (t.description != null) ...[
                const SizedBox(height: 6),
                Text(
                  t.description!,
                  style: const TextStyle(fontSize: 15, height: 1.45),
                ),
              ],

              if (r.message != null) ...[
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Their message',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        r.message!,
                        style: const TextStyle(fontSize: 15.5, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],

              // -- What is shared -----------------------------------------
              heading(shareTitle),
              ScopeChecklist(
                items: scopeChecklist(r.scope, identityLabel: r.identityLabel),
              ),
              const SizedBox(height: 4),
              if (status == RepresentationStatus.requested) ...[
                line(Icons.timelapse_outlined, durationLine(r), strong: true),
                if (answerBy != null)
                  line(Icons.event_outlined, answerBy, strong: true),
              ],

              // -- Where I was put forward --------------------------------
              if (sub != null) ...[
                heading('Where you were put forward'),
                Text(
                  sub.submittedAt == null
                      ? 'Submitted to ${t.clientName}'
                      : 'Submitted to ${t.clientName} on '
                            '${shortDate(sub.submittedAt!, now)}',
                  style: const TextStyle(fontSize: 15.5, height: 1.4),
                ),
                const SizedBox(height: 14),
                SubmissionTimeline(status: sub.status),
                if (placement != null) ...[
                  const SizedBox(height: 14),
                  line(Icons.celebration_outlined, placement, strong: true),
                ],
              ],
              if (actions.canViewApplication) ...[
                const SizedBox(height: 14),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 52)),
                  onPressed: () =>
                      context.push('/applications/${sub!.applicationId}'),
                  icon: const Icon(Icons.assignment_outlined),
                  label: const Text('Open my application'),
                ),
              ],

              // -- Take it back -------------------------------------------
              if (actions.canRevoke) ...[
                const SizedBox(height: 28),
                const Divider(),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: OmeloTheme.danger,
                  ),
                  onPressed: () => _revoke(context, ref, r),
                  icon: const Icon(Icons.undo),
                  label: const Text('Take back my yes'),
                ),
                const SizedBox(height: 8),
                Text(
                  kRevokeEffect,
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.4,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],

              const SizedBox(height: 22),
              Text(
                'Being put forward is free. No recruiter or agency on Omelo '
                'may ask you to pay for a job.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _revoke(
    BuildContext context,
    WidgetRef ref,
    Representation r,
  ) async {
    final result = await showModalBottomSheet<RevokeResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => RevokeSheet(
        agencyName: r.agencyName,
        onRevoke: () =>
            ref.read(representationsRepositoryProvider).revoke(r.id),
      ),
    );
    if (!context.mounted || result == null) return;
    switch (result) {
      case RevokeResult.revoked:
        onRevoked();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Done. The agency can no longer put you forward.'),
          ),
        );
      case RevokeResult.blocked:
        ref.invalidate(myRepresentationsProvider);
        await showRevokeBlockedDialog(context, r.submission?.applicationId);
      case RevokeResult.cancelled:
        break;
    }
  }
}

/// The employer is already considering the worker: explain, and offer the
/// application (where "Withdraw application" lives).
Future<void> showRevokeBlockedDialog(
  BuildContext context,
  String? applicationId,
) {
  return showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('You cannot take it back here'),
      content: const Text(
        kRevokeBlockedMessage,
        style: TextStyle(fontSize: 15.5, height: 1.45),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('Close'),
        ),
        if (applicationId != null)
          FilledButton(
            onPressed: () {
              Navigator.pop(dialog);
              context.push('/applications/$applicationId');
            },
            child: const Text('Open my application'),
          ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Accept / decline
// ---------------------------------------------------------------------------

class _AnswerBar extends ConsumerWidget {
  const _AnswerBar({
    required this.representation,
    required this.onAccepted,
    required this.onDeclined,
  });

  final Representation representation;
  final VoidCallback onAccepted;
  final VoidCallback onDeclined;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final r = representation;
    final repo = ref.read(representationsRepositoryProvider);

    Future<void> accept() async {
      final done = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) =>
            AcceptSheet(representation: r, onAccept: () => repo.accept(r.id)),
      );
      if (done == true) {
        onAccepted();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Done. ${r.agencyName} can now put you forward '
                'for this job.',
              ),
            ),
          );
        }
      }
    }

    Future<void> decline() async {
      final done = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => RepresentationDeclineSheet(
          agencyName: r.agencyName,
          onSend: (reason, other) => repo.decline(r.id, reason, other),
        ),
      );
      if (done == true) {
        onDeclined();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Done. The agency will see your answer.'),
            ),
          );
        }
      }
    }

    final children = <Widget>[
      FilledButton.icon(
        onPressed: accept,
        icon: const Icon(Icons.check),
        label: const Text('Accept'),
      ),
      OutlinedButton(onPressed: decline, child: const Text('Decline')),
    ];

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        // Not ContentWidth: its Align would fill the whole screen height
        // here, because a bottom bar gets loose height constraints.
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: Breakpoints.readingWidth,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: LayoutBuilder(
                builder: (context, c) {
                  if (c.maxWidth >= 420) {
                    return Row(
                      children: [
                        Expanded(flex: 3, child: children[0]),
                        const SizedBox(width: 12),
                        Expanded(flex: 2, child: children[1]),
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      children[0],
                      const SizedBox(height: 10),
                      children[1],
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Confirm a yes: restates who, for which job, what is shared and for how
/// long. Returns true when accepted.
class AcceptSheet extends StatefulWidget {
  const AcceptSheet({
    super.key,
    required this.representation,
    required this.onAccept,
  });

  final Representation representation;
  final Future<void> Function() onAccept;

  @override
  State<AcceptSheet> createState() => _AcceptSheetState();
}

class _AcceptSheetState extends State<AcceptSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onAccept();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = serverMessage(
            e,
            fallback:
                'That did not go through. Check your connection and '
                'try again.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.representation;
    final t = r.terms;
    final scheme = Theme.of(context).colorScheme;
    final shared = scopeChecklist(
      r.scope,
      identityLabel: r.identityLabel,
    ).where((i) => i.shared);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: ContentWidth.reading(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Say yes to ${t.agencyName}?',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '${t.agencyName} can put you forward to ${t.clientName} for '
                '${t.position}. Only this job.',
                style: const TextStyle(fontSize: 15.5, height: 1.45),
              ),
              const SizedBox(height: 14),
              const Text(
                'They will share',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final i in shared)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.check_circle,
                        size: 20,
                        color: OmeloTheme.verified,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          i.label,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.timelapse_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'For ${r.validDays} days, until '
                      '${shortDate(DateTime.now().add(Duration(days: r.validDays)), DateTime.now())}. '
                      'You can take it back until the employer starts '
                      'looking at you.',
                      style: const TextStyle(fontSize: 15, height: 1.4),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _go,
                child: Text(_busy ? 'Sending…' : 'Yes, represent me'),
              ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "No thanks": optional reason, then decline. Returns true when sent.
class RepresentationDeclineSheet extends StatefulWidget {
  const RepresentationDeclineSheet({
    super.key,
    required this.agencyName,
    required this.onSend,
  });

  final String agencyName;
  final Future<void> Function(
    RepresentationDeclineReason? reason,
    String? other,
  )
  onSend;

  @override
  State<RepresentationDeclineSheet> createState() =>
      _RepresentationDeclineSheetState();
}

class _RepresentationDeclineSheetState
    extends State<RepresentationDeclineSheet> {
  RepresentationDeclineReason? _reason;
  final _other = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSend(
        _reason,
        _reason == RepresentationDeclineReason.other ? _other.text : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = serverMessage(
            e,
            fallback:
                'That did not go through. Check your connection and '
                'try again.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: ContentWidth.reading(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Say no?',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tell ${widget.agencyName} why, if you like. This is '
                  'optional.',
                  style: TextStyle(
                    fontSize: 14.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final r in RepresentationDeclineReason.values)
                      ChoiceChip(
                        label: Text(
                          r.label,
                          style: const TextStyle(fontSize: 15),
                        ),
                        selected: _reason == r,
                        materialTapTargetSize: MaterialTapTargetSize.padded,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        onSelected: _busy
                            ? null
                            : (on) => setState(() => _reason = on ? r : null),
                      ),
                  ],
                ),
                if (_reason == RepresentationDeclineReason.other) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _other,
                    enabled: !_busy,
                    maxLength: kRepresentationReasonMax,
                    maxLines: 3,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Your reason (optional)',
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: scheme.error)),
                ],
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: _busy ? null : _send,
                  child: Text(_busy ? 'Sending…' : 'Send: no thanks'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: const Text('Keep the request'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Revoke
// ---------------------------------------------------------------------------

enum RevokeResult { revoked, blocked, cancelled }

/// Confirm taking back a yes, with what it does.
class RevokeSheet extends StatefulWidget {
  const RevokeSheet({
    super.key,
    required this.agencyName,
    required this.onRevoke,
  });

  final String agencyName;
  final Future<void> Function() onRevoke;

  @override
  State<RevokeSheet> createState() => _RevokeSheetState();
}

class _RevokeSheetState extends State<RevokeSheet> {
  bool _busy = false;
  String? _error;

  Future<void> _go() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onRevoke();
      if (mounted) Navigator.pop(context, RevokeResult.revoked);
    } catch (e) {
      if (!mounted) return;
      if (isRevokeBlockedError(e)) {
        Navigator.pop(context, RevokeResult.blocked);
        return;
      }
      setState(() {
        _busy = false;
        _error = serverMessage(
          e,
          fallback:
              'That did not go through. Check your connection and '
              'try again.',
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: ContentWidth.reading(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Take back your yes?',
                style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(
                '${widget.agencyName} will no longer represent you for this '
                'job.',
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 1.45,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                kRevokeEffect,
                style: TextStyle(fontSize: 15, height: 1.45),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 18),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: OmeloTheme.danger,
                  foregroundColor: Colors.white,
                ),
                onPressed: _busy ? null : _go,
                child: Text(_busy ? 'Sending…' : 'Yes, take it back'),
              ),
              const SizedBox(height: 8),
              TextButton(
                style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                onPressed: _busy
                    ? null
                    : () => Navigator.pop(context, RevokeResult.cancelled),
                child: const Text('Keep it'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
