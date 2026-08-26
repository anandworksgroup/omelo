import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/applications_repository.dart';
import '../../data/auth_repository.dart';

final myApplicationsProvider =
    FutureProvider<List<ApplicationSummary>>((ref) async {
  final repo = ref.watch(applicationsRepositoryProvider);
  return repo.mine();
});

/// U-60 / U-61 — the hiring timeline.
///
/// The most important screen in the app for trust (PR-4). Silence is a
/// displayed state with elapsed time, never an absence of one.
class ApplicationsScreen extends ConsumerWidget {
  const ApplicationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(authRepositoryProvider).isSignedIn;
    final scheme = Theme.of(context).colorScheme;

    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Applications')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
          children: [
            Icon(Icons.assignment_outlined,
                size: 52, color: scheme.onSurfaceVariant),
            const SizedBox(height: 22),
            const Text(
              'Track every application here',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            Text(
              'You will see when an employer opens your application, and what '
              'happens after. No application disappears silently.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14.5,
                  height: 1.5,
                  color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 30),
            FilledButton(
              onPressed: () => context.push('/sign-in?next=/applications'),
              child: const Text('Sign in'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => context.go('/discover'),
              child: const Text('Find work'),
            ),
          ],
        ),
      );
    }

    final async = ref.watch(myApplicationsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Applications')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Could not load your applications.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => ref.invalidate(myApplicationsProvider),
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
        data: (apps) {
          if (apps.isEmpty) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
              children: [
                Icon(Icons.assignment_outlined,
                    size: 52, color: scheme.onSurfaceVariant),
                const SizedBox(height: 22),
                const Text('No applications yet',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Text(
                  'Jobs near you are waiting. Most need no resume.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14.5, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 30),
                FilledButton(
                  onPressed: () => context.go('/discover'),
                  child: const Text('Find work'),
                ),
              ],
            );
          }

          final active = apps.where((a) => !a.isTerminal).toList();
          final archived = apps.where((a) => a.isTerminal).toList();

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(myApplicationsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                if (active.isNotEmpty) ...[
                  Text('Active (${active.length})',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  for (final a in active)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ApplicationCard(app: a),
                    ),
                ],
                if (archived.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('Closed (${archived.length})',
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  for (final a in archived)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _ApplicationCard(app: a),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ApplicationCard extends ConsumerWidget {
  const _ApplicationCard({required this.app});
  final ApplicationSummary app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final stages = kApplicationStages.keys.toList();
    final currentIndex = stages.indexOf(app.state);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(app.jobTitle,
                          style: const TextStyle(
                              fontSize: 16.5, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(app.companyName,
                          style: TextStyle(
                              fontSize: 14, color: scheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                _StateChip(state: app.state),
              ],
            ),
            const SizedBox(height: 14),

            if (app.state == 'rejected') ...[
              Text(
                '${app.companyName} is not moving forward.',
                style: const TextStyle(
                    fontSize: 14.5, fontWeight: FontWeight.w600),
              ),
              if ((app.rejectionReason ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Reason: ${app.rejectionReason}',
                    style: TextStyle(
                        fontSize: 13.5, color: scheme.onSurfaceVariant)),
              ] else ...[
                const SizedBox(height: 6),
                Text('They did not give a reason.',
                    style: TextStyle(
                        fontSize: 13.5, color: scheme.onSurfaceVariant)),
              ],
              const SizedBox(height: 12),
              Text(
                'This is one job, not a verdict.',
                style: TextStyle(
                    fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => context.go('/discover'),
                child: const Text('Find similar work'),
              ),
            ] else if (app.isTerminal) ...[
              Text(
                app.state == 'withdrawn'
                    ? 'You withdrew this application.'
                    : app.state == 'expired'
                        ? 'This application expired with no response.'
                        : 'Closed.',
                style: TextStyle(
                    fontSize: 14, color: scheme.onSurfaceVariant),
              ),
            ] else ...[
              // Timeline
              for (var i = 0; i < stages.length; i++)
                if (i <= (currentIndex < 0 ? 0 : currentIndex) || i == currentIndex + 1)
                  _TimelineRow(
                    label: kApplicationStages[stages[i]]!,
                    done: i <= currentIndex,
                    current: i == currentIndex,
                    timestamp: i == 0
                        ? app.appliedAt
                        : (stages[i] == 'viewed' ? app.firstViewedAt : null),
                  ),

              if (app.isSilent) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'No activity for ${app.daysSinceActivity} days.',
                        style: const TextStyle(
                            fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      if (app.medianResponseHours != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${app.companyName} ${Fmt.responseTime(app.medianResponseHours)}.',
                          style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        'We will tell you if this closes without an answer.',
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            const SizedBox(height: 12),
            Divider(color: scheme.outlineVariant, height: 1),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Applied ${Fmt.posted(app.appliedAt).toLowerCase()}',
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant)),
                const Spacer(),
                TextButton(
                  onPressed: () => context.push('/job/${app.jobId}'),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 34),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('View job'),
                ),
                if (!app.isTerminal)
                  TextButton(
                    onPressed: () => _withdraw(context, ref),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      foregroundColor: scheme.onSurfaceVariant,
                    ),
                    child: const Text('Withdraw'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Withdraw application?'),
        content: Text(
            'You are telling ${app.companyName} you are no longer interested '
            'in ${app.jobTitle}. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Withdraw'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(applicationsRepositoryProvider).withdraw(app.id);
    ref.invalidate(myApplicationsProvider);
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.label,
    required this.done,
    required this.current,
    this.timestamp,
  });

  final String label;
  final bool done;
  final bool current;
  final DateTime? timestamp;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(
            done
                ? Icons.check_circle
                : current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
            size: 17,
            color: done
                ? OmeloTheme.verified
                : current
                    ? scheme.primary
                    : scheme.outlineVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: done || current ? FontWeight.w600 : FontWeight.w400,
                color: done || current ? null : scheme.onSurfaceVariant,
              ),
            ),
          ),
          if (timestamp != null)
            Text(
              Fmt.posted(timestamp).toLowerCase(),
              style:
                  TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip({required this.state});
  final String state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, color) = switch (state) {
      'hired' => ('Hired', OmeloTheme.verified),
      'offer' => ('Offer', OmeloTheme.verified),
      'rejected' => ('Not selected', scheme.onSurfaceVariant),
      'withdrawn' => ('Withdrawn', scheme.onSurfaceVariant),
      'expired' => ('Expired', scheme.onSurfaceVariant),
      'declined_by_candidate' => ('You declined', scheme.onSurfaceVariant),
      _ => (kApplicationStages[state] ?? state, scheme.primary),
    };
    return OmeloPill(label, color: color);
  }
}
