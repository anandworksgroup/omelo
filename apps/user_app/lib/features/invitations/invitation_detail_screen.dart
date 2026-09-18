import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../data/invitations_repository.dart';
import '../../data/job_events.dart';
import 'invitation_widgets.dart';

/// `/invitations/:id` — one invitation to apply (notification deeplink).
class InvitationDetailScreen extends ConsumerStatefulWidget {
  const InvitationDetailScreen({super.key, required this.invitationId});
  final String invitationId;

  @override
  ConsumerState<InvitationDetailScreen> createState() =>
      _InvitationDetailScreenState();
}

class _InvitationDetailScreenState
    extends ConsumerState<InvitationDetailScreen> {
  bool _opened = false;

  /// Local answer after "Not interested", before the list reloads.
  InvitationStatus? _answered;

  JobInvitation? _find(List<JobInvitation> list) {
    for (final i in list) {
      if (i.id == widget.invitationId) return i;
    }
    return null;
  }

  /// Once per screen: tell the employer it was seen, and record that the
  /// job was shown from an invitation.
  void _onOpen(JobInvitation i) {
    if (_opened) return;
    _opened = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      trackJobEvent(
        ref,
        i.jobId,
        JobEventType.impression,
        JobSurface.invitation,
      );
      if (i.viewedAt == null) {
        try {
          await ref.read(invitationsRepositoryProvider).markViewed(i.id);
        } catch (_) {
          // Not worth bothering the worker about.
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(myInvitationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invitation'),
        leading: context.canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => context.go('/invitations'),
              ),
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _Problem(
          text:
              'Could not load this invitation.\nCheck your internet and '
              'try again.',
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(myInvitationsProvider),
        ),
        data: (items) {
          final found = _find(items);
          if (found == null) {
            return _Problem(
              text: 'This invitation was not found. It may have been removed.',
              actionLabel: 'See all invitations',
              onAction: () => context.go('/invitations'),
            );
          }
          _onOpen(found);
          final i = _answered == null
              ? found
              : found.copyWith(status: _answered);
          return _Body(invitation: i);
        },
      ),
      bottomNavigationBar: list.maybeWhen(
        data: (items) {
          final found = _find(items);
          if (found == null) return null;
          final i = _answered == null
              ? found
              : found.copyWith(status: _answered);
          final actions = invitationActions(i);
          if (!actions.hasAnyAction) return null;
          return _ActionBar(
            invitation: i,
            actions: actions,
            onDeclined: () =>
                setState(() => _answered = InvitationStatus.declined),
          );
        },
        orElse: () => null,
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.invitation});
  final JobInvitation invitation;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = invitation;
    final scheme = Theme.of(context).colorScheme;
    final actions = invitationActions(i);
    final expiry = expiryLabel(i, DateTime.now());

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

    final type = [
      if (i.workType != null) Fmt.workType(i.workType),
      if (i.workplaceType != null) Fmt.workplace(i.workplaceType),
    ].where((s) => s.isNotEmpty).join(' · ');

    return ListView(
      padding: EdgeInsets.fromLTRB(
        Breakpoints.of(context).gutter,
        12,
        Breakpoints.of(context).gutter,
        32,
      ),
      children: [
        ContentWidth.reading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  CompanyAvatar(
                    name: i.companyName,
                    logoUrl: i.companyLogo,
                    size: 52,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CompanyName(
                          i.companyName,
                          verified: i.companyVerified,
                          fontSize: 16.5,
                          showWord: true,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'invited you to apply',
                          style: TextStyle(
                            fontSize: 14.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                i.jobTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                Fmt.pay(
                  min: i.payMin,
                  max: i.payMax,
                  currency: i.payCurrency,
                  period: i.payPeriod,
                ),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              if (i.locationText != null)
                line(Icons.place_outlined, i.locationText!),
              if (type.isNotEmpty) line(Icons.work_outline, type),
              line(Icons.badge_outlined, invitedAsLine(i), strong: true),
              if (expiry != null)
                line(Icons.event_outlined, expiry, strong: true),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                  ),
                  onPressed: () {
                    trackJobEvent(
                      ref,
                      i.jobId,
                      JobEventType.click,
                      JobSurface.invitation,
                    );
                    context.push(jobRoute(i.jobId, JobSurface.invitation));
                  },
                  icon: const Icon(Icons.open_in_new, size: 20),
                  label: const Text('See the full job'),
                ),
              ),
              if (i.message != null) ...[
                const SizedBox(height: 14),
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
                        i.message!,
                        style: const TextStyle(fontSize: 15.5, height: 1.45),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(children: [InvitationStatusPill(i.status)]),
              if (actions.note != null) ...[
                const SizedBox(height: 10),
                Text(
                  actions.note!,
                  style: const TextStyle(fontSize: 15, height: 1.45),
                ),
              ],
              if (i.isPending) ...[
                const SizedBox(height: 18),
                Text(
                  'Applying is free. Omelo will never ask you to pay to apply '
                  'or to start a job.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionBar extends ConsumerWidget {
  const _ActionBar({
    required this.invitation,
    required this.actions,
    required this.onDeclined,
  });

  final JobInvitation invitation;
  final InvitationActions actions;
  final VoidCallback onDeclined;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final i = invitation;

    Future<void> apply() async {
      trackJobEvent(ref, i.jobId, JobEventType.click, JobSurface.invitation);
      await context.push(invitationApplyRoute(i));
      // Applying marks the invitation applied on the server.
      ref.invalidate(myInvitationsProvider);
    }

    Future<void> decline() async {
      final done = await showDeclineSheet(context, ref, i);
      if (done == true) {
        onDeclined();
        ref.invalidate(myInvitationsProvider);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Done. The employer will see your answer.'),
            ),
          );
        }
      }
    }

    final children = <Widget>[
      if (actions.canApply)
        FilledButton.icon(
          onPressed: apply,
          icon: const Icon(Icons.send_outlined),
          label: const Text('Apply now'),
        ),
      if (actions.canViewApplication)
        FilledButton(
          onPressed: () => context.push('/applications/${i.applicationId}'),
          child: const Text('View application'),
        ),
      if (actions.canDecline)
        OutlinedButton(onPressed: decline, child: const Text('Not interested')),
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
                  // Side by side when there is room, stacked on a narrow phone.
                  if (c.maxWidth >= 420 && children.length > 1) {
                    return Row(
                      children: [
                        for (var n = 0; n < children.length; n++) ...[
                          Expanded(flex: n == 0 ? 3 : 2, child: children[n]),
                          if (n != children.length - 1)
                            const SizedBox(width: 12),
                        ],
                      ],
                    );
                  }
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var n = 0; n < children.length; n++) ...[
                        children[n],
                        if (n != children.length - 1)
                          const SizedBox(height: 10),
                      ],
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

/// "Not interested": optional reason, then decline. Returns true when sent.
Future<bool?> showDeclineSheet(
  BuildContext context,
  WidgetRef ref,
  JobInvitation i,
) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => DeclineSheet(
      companyName: i.companyName,
      onSend: (reason, other) =>
          ref.read(invitationsRepositoryProvider).decline(i.id, reason, other),
    ),
  );
}

class DeclineSheet extends StatefulWidget {
  const DeclineSheet({
    super.key,
    required this.companyName,
    required this.onSend,
  });

  final String companyName;
  final Future<void> Function(DeclineReason? reason, String? other) onSend;

  @override
  State<DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<DeclineSheet> {
  DeclineReason? _reason;
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
        _reason == DeclineReason.other ? _other.text : null,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'That did not go through. Check your connection and try '
              'again.';
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
                  'Not interested?',
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tell ${widget.companyName} why, if you like. This is '
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
                    for (final r in DeclineReason.values)
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
                if (_reason == DeclineReason.other) ...[
                  const SizedBox(height: 14),
                  TextField(
                    controller: _other,
                    enabled: !_busy,
                    maxLength: kDeclineReasonMax,
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
                  child: Text(_busy ? 'Sending…' : 'Send: not interested'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(0, 48)),
                  onPressed: _busy ? null : () => Navigator.pop(context, false),
                  child: const Text('Keep the invitation'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.mail_outline, size: 48),
            const SizedBox(height: 16),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, height: 1.4),
            ),
            const SizedBox(height: 24),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
