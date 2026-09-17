import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../notifications/notifications_screen.dart' show NotificationBell;
import '../../core/app_state.dart';
import '../../core/format.dart';
import '../../core/responsive.dart';
import '../../data/applications_repository.dart';
import '../../data/auth_repository.dart';
import 'hiring_widgets.dart';

final myApplicationsProvider =
    FutureProvider<List<ApplicationSummary>>((ref) async {
  ref.watch(authStateProvider);
  final repo = ref.watch(applicationsRepositoryProvider);
  return repo.mine();
});

/// U-60 / U-61 — the Application Center.
///
/// The most important screen in the app for trust (PR-4). Every card says,
/// in plain words, what happens next. Things the worker has to do come first.
class ApplicationsScreen extends ConsumerStatefulWidget {
  const ApplicationsScreen({super.key});

  @override
  ConsumerState<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _ApplicationsScreenState extends ConsumerState<ApplicationsScreen> {
  ApplicationFilter? _filter;
  bool _showClosed = false;

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(authRepositoryProvider).isSignedIn;

    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Applications'),
          actions: const [NotificationBell(), SizedBox(width: 8)],
        ),
        body: const _Empty(
          icon: Icons.assignment_outlined,
          title: 'Track every application here',
          body: 'You will see when an employer opens your application, and '
              'what happens after. No application disappears silently.',
          signIn: true,
        ),
      );
    }

    final async = ref.watch(myApplicationsProvider);

    return Scaffold(
      appBar: AppBar(
          title: const Text('Applications'),
          actions: const [NotificationBell(), SizedBox(width: 8)],
        ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Could not load your applications.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => ref.invalidate(myApplicationsProvider),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (apps) => RefreshIndicator(
          onRefresh: () => ref.refresh(myApplicationsProvider.future),
          child: apps.isEmpty
              ? const _Empty(
                  icon: Icons.assignment_outlined,
                  title: 'No applications yet',
                  body: 'Jobs near you are waiting. Most need no resume.',
                )
              : _list(context, apps),
        ),
      ),
    );
  }

  Widget _list(BuildContext context, List<ApplicationSummary> apps) {
    final now = DateTime.now();
    final gutter = Breakpoints.of(context).gutter;

    int count(ApplicationFilter f) =>
        apps.where((a) => HiringCopy.matchesFilter(a, f, now)).length;

    final children = <Widget>[
      _SummaryBar(
        counts: {for (final f in ApplicationFilter.values) f: count(f)},
        selected: _filter,
        onSelect: (f) => setState(() => _filter = _filter == f ? null : f),
      ),
      const SizedBox(height: 18),
    ];

    if (_filter != null) {
      final filtered = apps
          .where((a) => HiringCopy.matchesFilter(a, _filter!, now))
          .toList();
      children.addAll([
        SectionHeading(
          '${_filterLabel(_filter!)} (${filtered.length})',
          trailing: TextButton(
            onPressed: () => setState(() => _filter = null),
            child: const Text('Show all'),
          ),
        ),
        const SizedBox(height: 10),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text(
              'Nothing here right now.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          )
        else
          _grid(filtered, now),
      ]);
    } else {
      final s = HiringCopy.sections(apps, now);
      void section(String title, List<ApplicationSummary> list) {
        if (list.isEmpty) return;
        children.addAll([
          SectionHeading('$title (${list.length})'),
          const SizedBox(height: 10),
          _grid(list, now),
          const SizedBox(height: 24),
        ]);
      }

      section('Needs your action', s.needsAction);
      section('Active', s.active);
      section('Hired', s.hired);
      if (s.closed.isNotEmpty) {
        children.add(
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => setState(() => _showClosed = !_showClosed),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SectionHeading(
                'Closed (${s.closed.length})',
                trailing: Icon(
                    _showClosed ? Icons.expand_less : Icons.expand_more),
              ),
            ),
          ),
        );
        if (_showClosed) {
          children.addAll([const SizedBox(height: 10), _grid(s.closed, now)]);
        }
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 32),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }

  Widget _grid(List<ApplicationSummary> list, DateTime now) =>
      ResponsiveCardGrid(
        minCardWidth: 380,
        children: [for (final a in list) _ApplicationCard(app: a, now: now)],
      );

  static String _filterLabel(ApplicationFilter f) => switch (f) {
        ApplicationFilter.active => 'Active',
        ApplicationFilter.interviews => 'Interviews',
        ApplicationFilter.offers => 'Offers',
        ApplicationFilter.hired => 'Hired',
      };
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({
    required this.counts,
    required this.selected,
    required this.onSelect,
  });

  final Map<ApplicationFilter, int> counts;
  final ApplicationFilter? selected;
  final ValueChanged<ApplicationFilter> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (final f in ApplicationFilter.values) ...[
          Expanded(
            child: Semantics(
              button: true,
              selected: selected == f,
              child: Material(
                color: selected == f
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelect(f),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 64),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${counts[f] ?? 0}',
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              _ApplicationsScreenState._filterLabel(f),
                              style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (f != ApplicationFilter.values.last) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard({required this.app, required this.now});
  final ApplicationSummary app;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final step = HiringCopy.nextStep(app, now);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/applications/${app.id}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
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
                        Text(
                          app.companyName.isEmpty
                              ? 'Employer'
                              : app.companyName,
                          style: TextStyle(
                              fontSize: 14, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusChip(state: app.state),
                      if (app.matchScore != null) ...[
                        const SizedBox(height: 6),
                        Text('${app.matchScore}% match',
                            style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              NextStepLine(step: step),
              if (app.isSilent(now)) ...[
                const SizedBox(height: 8),
                Text(
                  'No news for ${app.daysSinceActivity(now)} days.'
                  '${app.medianResponseHours == null ? '' : ' ${app.companyOrEmployer} ${Fmt.responseTime(app.medianResponseHours)}.'}',
                  style:
                      TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Applied ${Fmt.posted(app.appliedAt).toLowerCase()}',
                      style: TextStyle(
                          fontSize: 12.5, color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Text('See details',
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary)),
                  Icon(Icons.chevron_right, size: 18, color: scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    this.signIn = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool signIn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ContentWidth.reading(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
        children: [
          Icon(icon, size: 52, color: scheme.onSurfaceVariant),
          const SizedBox(height: 22),
          Text(title,
              textAlign: TextAlign.center,
              style:
                  const TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(body,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14.5, height: 1.5, color: scheme.onSurfaceVariant)),
          const SizedBox(height: 30),
          if (signIn) ...[
            FilledButton(
              onPressed: () => context.push('/sign-in?next=/applications'),
              child: const Text('Sign in'),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () => context.go('/discover'),
              child: const Text('Find work'),
            ),
          ] else
            FilledButton(
              onPressed: () => context.go('/discover'),
              child: const Text('Find work'),
            ),
        ],
      ),
    );
  }
}
