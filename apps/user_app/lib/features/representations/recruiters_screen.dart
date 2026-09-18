import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/invitations.dart' show viewedWhen;
import '../../data/representations_repository.dart';
import 'representation_widgets.dart';

/// `/recruiters` — the recruiters and agencies I have dealt with, grouped
/// from their requests. Tap one to see its requests.
class RecruitersScreen extends ConsumerWidget {
  const RecruitersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myRepresentationsProvider);
    final gutter = Breakpoints.of(context).gutter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recruiters & agencies'),
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
          ref.invalidate(myRepresentationsProvider);
          try {
            await ref.read(myRepresentationsProvider.future);
          } catch (_) {
            // The error state shows its own message.
          }
        },
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => RepresentationMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load recruiters',
            body: 'Check your internet and try again.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(myRepresentationsProvider),
          ),
          data: (items) {
            final now = DateTime.now();
            final agencies = groupByAgency(items, now);
            final pending = pendingRepresentations(items, now).length;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                ContentWidth.reading(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const RecruiterPromiseCard(),
                      const SizedBox(height: 16),
                      if (items.isNotEmpty)
                        Card(
                          child: ListTile(
                            minTileHeight: 60,
                            leading: const Icon(Icons.handshake_outlined),
                            title: const Text(
                              'All requests',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              pending == 0
                                  ? 'Nothing waiting for you'
                                  : pending == 1
                                  ? '1 waiting for your answer'
                                  : '$pending waiting for your answer',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (pending > 0)
                                  Badge(
                                    label: Text('$pending'),
                                    largeSize: 22,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                    ),
                                  ),
                                const Icon(Icons.chevron_right),
                              ],
                            ),
                            onTap: () => context.push(representationsRoute()),
                          ),
                        ),
                      if (agencies.isEmpty) ...[
                        const SizedBox(height: 24),
                        const Text(
                          'No recruiters yet',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Agencies can ask to represent you only when one of '
                          'your work identities is set to "Employers and '
                          'agencies" (or "Anyone with the link") and lets '
                          'recruiters ask.',
                          style: TextStyle(fontSize: 15, height: 1.45),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => context.push('/identities'),
                          child: const Text('Choose who can see me'),
                        ),
                      ] else ...[
                        const SizedBox(height: 24),
                        const Text(
                          'Agencies you know',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final a in agencies)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _AgencyCard(
                              agency: a,
                              now: now,
                              onTap: () => context.push(
                                representationsRoute(agency: a.key),
                              ),
                            ),
                          ),
                      ],
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

class _AgencyCard extends StatelessWidget {
  const _AgencyCard({
    required this.agency,
    required this.now,
    required this.onTap,
  });

  final AgencySummary agency;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final a = agency;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CompanyAvatar(name: a.name, logoUrl: a.logoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AgencyName(
                      name: a.name,
                      verified: a.verified,
                      independent: a.independent,
                      fontSize: 16,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      agencyCountsLine(a),
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Last activity: ${viewedWhen(a.lastActivityAt, now)}',
                      style: TextStyle(
                        fontSize: 13.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (a.pendingCount > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Badge(
                    label: Text(
                      '${a.pendingCount}',
                      semanticsLabel: '${a.pendingCount} waiting',
                    ),
                    largeSize: 22,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                  ),
                ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
