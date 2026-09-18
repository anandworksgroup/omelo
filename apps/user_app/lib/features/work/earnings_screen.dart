import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/responsive.dart';
import '../../data/work_repository.dart';
import 'work_widgets.dart';

/// `/work/earnings` — what I earned per pay period, how it adds up, and
/// where the payment is, in each record's own currency. Totals per month.
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForWorkNotices(ref);
    final async = ref.watch(myEarningsProvider);
    final now = workNow(ref);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        leading: workBackButton(context, '/work'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myEarningsProvider);
          try {
            await ref.read(myEarningsProvider.future);
          } catch (_) {}
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => RepresentationMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load your earnings',
            body: workError(e),
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(myEarningsProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return const RepresentationMessage(
                icon: Icons.payments_outlined,
                title: 'No earnings yet',
                body:
                    'When your supervisor approves a timesheet, your pay for '
                    'those days shows up here.',
              );
            }
            final months = monthlyTotals(list);
            final gutter = Breakpoints.of(context).gutter;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                ContentWidth.reading(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final month in _monthKeys(months)) ...[
                        _MonthHeader(
                          month: month,
                          totals: months
                              .where((m) => m.month == month)
                              .toList(),
                        ),
                        for (final e in list.where(
                          (e) =>
                              e.periodEnd.year == month.year &&
                              e.periodEnd.month == month.month,
                        ))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: EarningCard(earning: e, now: now),
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

  static List<DateTime> _monthKeys(List<MonthTotal> months) {
    final out = <DateTime>[];
    for (final m in months) {
      if (!out.contains(m.month)) out.add(m.month);
    }
    return out;
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month, required this.totals});
  final DateTime month;
  final List<MonthTotal> totals;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              monthLabel(month),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              // Different currencies are listed, never added up.
              totals.map((t) => money(t.gross, t.currency)).join(' + '),
              textAlign: TextAlign.end,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

class EarningCard extends StatelessWidget {
  const EarningCard({super.key, required this.earning, required this.now});
  final Earning earning;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final e = earning;
    final scheme = Theme.of(context).colorScheme;
    final rows = earningBreakdown(e);
    final who = [?e.title, ?e.employer].join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  periodLine(e.periodStart, e.periodEnd, now),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (who.isNotEmpty)
                  Text(
                    who,
                    style: TextStyle(
                      fontSize: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  money(e.gross, e.currency),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    WorkPill(
                      earningStatusLabel(e.status),
                      tone: earningTone(e.status),
                    ),
                    Text(
                      paymentLine(e, now),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          ExpansionTile(
            minTileHeight: 52,
            title: const Text(
              'How it adds up',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              r.label,
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                          Text(
                            signedMoney(r.amount, e.currency),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      for (final why in r.reasons)
                        Padding(
                          padding: const EdgeInsets.only(top: 2, left: 10),
                          child: Text(
                            why,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              const Divider(),
              const SizedBox(height: 6),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Total',
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    money(e.gross, e.currency),
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              if (e.lines.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  'Details',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                for (final l in e.lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            [
                              l.description,
                              ?earningLineMath(l, e.currency),
                            ].join(' · '),
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l.kind == 'deduction'
                              ? signedMoney(-l.amount.abs(), e.currency)
                              : signedMoney(l.amount, e.currency),
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
