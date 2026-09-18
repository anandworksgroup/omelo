import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../data/invitations_repository.dart';
import 'invitation_widgets.dart';

/// `/invitations` — employers who invited me to apply. Waiting ones first.
class InvitationsScreen extends ConsumerWidget {
  const InvitationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myInvitationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job invitations'),
        leading: context.canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => context.go('/profile'),
              ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myInvitationsProvider);
          try {
            await ref.read(myInvitationsProvider.future);
          } catch (_) {
            // The error state shows its own message.
          }
        },
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => _Message(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load your invitations',
            body: 'Check your internet and try again.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(myInvitationsProvider),
          ),
          data: (items) {
            if (items.isEmpty) {
              return _Message(
                icon: Icons.mail_outline,
                title: 'No invitations yet',
                body: 'Employers can invite you to apply when they find your '
                    'profile. Make an identity visible to employers so they '
                    'can find you.',
                actionLabel: 'Choose who can see me',
                onAction: () => context.push('/identities'),
              );
            }
            final gutter = Breakpoints.of(context).gutter;
            final pending = pendingInvitationCount(items);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                ContentWidth.reading(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (pending > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            pending == 1
                                ? '1 invitation is waiting for your answer.'
                                : '$pending invitations are waiting for your '
                                    'answer.',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                      for (final i in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: InvitationCard(
                            invitation: i,
                            onTap: () => context.push('/invitations/${i.id}'),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class InvitationCard extends StatelessWidget {
  const InvitationCard({
    super.key,
    required this.invitation,
    required this.onTap,
  });

  final JobInvitation invitation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final i = invitation;
    final scheme = Theme.of(context).colorScheme;
    final expiry = expiryLabel(i, DateTime.now());
    final place = [
      if (i.locationText != null) i.locationText!,
      if (i.workType != null) Fmt.workType(i.workType),
    ].join(' · ');

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CompanyAvatar(name: i.companyName, logoUrl: i.companyLogo),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanyName(i.companyName, verified: i.companyVerified),
                    const SizedBox(height: 2),
                    Text(i.jobTitle,
                        style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            height: 1.25)),
                    const SizedBox(height: 4),
                    Text(
                      Fmt.pay(
                          min: i.payMin,
                          max: i.payMax,
                          currency: i.payCurrency,
                          period: i.payPeriod),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(place,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 13.5, color: scheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        InvitationStatusPill(i.status),
                        if (expiry != null)
                          Text(expiry,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ],
                ),
              ),
              if (i.isNew)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 4),
                  child: Semantics(
                    label: 'New',
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                          color: scheme.primary, shape: BoxShape.circle),
                    ),
                  ),
                )
              else
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      children: [
        ContentWidth.reading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(icon, size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15.5, height: 1.45)),
              if (actionLabel != null) ...[
                const SizedBox(height: 24),
                FilledButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
