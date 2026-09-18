import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/work_repository.dart';
import 'work_widgets.dart';

/// `/work` — My work. Today's shifts with the big Check in / Check out
/// button, extra shifts offered to me, what is coming in the next two
/// weeks, and the way to assignments, timesheets, earnings and time off.
class WorkScreen extends ConsumerWidget {
  const WorkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForWorkNotices(ref);
    final shiftsAsync = ref.watch(myWorkProvider);
    final assignments = ref.watch(myAssignmentsProvider).valueOrNull ?? const [];
    final now = workNow(ref);

    Future<void> refresh() async {
      invalidateWork(ref);
      try {
        await ref.read(myWorkProvider.future);
      } catch (_) {
        // The error state shows its own message.
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My work'),
        leading: workBackButton(context, '/home'),
      ),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: shiftsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => RepresentationMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load your work',
            body: workError(e),
            actionLabel: 'Try again',
            onAction: () => invalidateWork(ref),
          ),
          data: (shifts) {
            final o = workOverview(shifts, now);
            final offers = assignments
                .where((a) => a.isOfferOpenAt(now))
                .toList();
            if (o.isEmpty && assignments.isEmpty) {
              return RepresentationMessage(
                icon: Icons.work_outline,
                title: 'No work here yet',
                body:
                    'When an employer or agency offers you work, it shows up '
                    'here: your shifts, check-in, timesheets and pay.',
                actionLabel: 'Find work',
                onAction: () => context.go('/discover'),
              );
            }
            final gutter = Breakpoints.of(context).gutter;
            final next = o.upcoming.where((s) => !s.isCancelled);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                ContentWidth.reading(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final a in offers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _OfferBanner(assignment: a),
                        ),
                      const _Heading('Today'),
                      if (o.today.isEmpty)
                        _Quiet(
                          next.isEmpty
                              ? 'No work today.'
                              : 'No work today. Next: '
                                    '${shiftDayLabel(next.first.startsAt, next.first.timezone, now)}, '
                                    '${shiftTimeRange(next.first.startsAt, next.first.endsAt, next.first.timezone)}.',
                        ),
                      for (final s in o.today)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TodayShiftCard(shift: s, now: now),
                        ),
                      if (o.offers.isNotEmpty) ...[
                        const _Heading('Extra shifts offered'),
                        for (final s in o.offers)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: ShiftOfferCard(shift: s, now: now),
                          ),
                      ],
                      const _Heading('Coming up'),
                      if (o.upcoming.isEmpty)
                        const _Quiet('No shifts in the next two weeks yet.'),
                      for (final s in o.upcoming)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ShiftTile(shift: s, now: now),
                        ),
                      const SizedBox(height: 16),
                      WorkLinks(pendingOffers: offers.length),
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

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
    ),
  );
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 15.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// "Acme Staffing offered you work" at the top of My work.
class _OfferBanner extends StatelessWidget {
  const _OfferBanner({required this.assignment});
  final Assignment assignment;

  @override
  Widget build(BuildContext context) {
    final a = assignment;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer.withValues(alpha: 0.7),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push(assignmentRoute(a.id)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(
                  Icons.mark_email_unread_outlined,
                  size: 30,
                  color: scheme.onTertiaryContainer,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${a.employerName} offered you work',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${a.title} · ${payLine(a.pay)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
