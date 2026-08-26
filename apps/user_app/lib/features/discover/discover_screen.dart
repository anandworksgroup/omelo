import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/location.dart';
import '../../data/jobs_repository.dart';
import 'discover_controller.dart';
import 'filters_sheet.dart';
import 'job_card.dart';

class DiscoverScreen extends ConsumerStatefulWidget {
  const DiscoverScreen({super.key});

  @override
  ConsumerState<DiscoverScreen> createState() => _DiscoverScreenState();
}

class _DiscoverScreenState extends ConsumerState<DiscoverScreen> {
  final _scroll = ScrollController();
  final _searchCtl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels >
          _scroll.position.maxScrollExtent - 600) {
        ref.read(discoverProvider.notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _searchCtl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(discoverProvider);
    final filters = ref.watch(filtersProvider);
    final origin = ref.watch(originProvider).value;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _SearchBar(
              controller: _searchCtl,
              onSubmit: (q) => ref.read(filtersProvider.notifier).state =
                  q.trim().isEmpty
                      ? filters.copyWith(clearSearch: true)
                      : filters.copyWith(search: q.trim()),
              onFilters: () => showFiltersSheet(context, ref),
              activeFilters: filters.activeCount,
            ),
            _OriginBar(origin: origin),
            _QuickChips(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => ref.read(discoverProvider.notifier).load(),
                child: _buildBody(state, scheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(DiscoverState state, ColorScheme scheme) {
    if (state.loading && state.jobs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.jobs.isEmpty) {
      return _Message(
        icon: Icons.wifi_off_rounded,
        title: state.error!,
        actionLabel: 'Try again',
        onAction: () => ref.read(discoverProvider.notifier).load(),
      );
    }

    if (state.jobs.isEmpty) {
      // UC-6: an empty result names the constraint and offers a way forward.
      final f = ref.read(filtersProvider);
      return _Message(
        icon: Icons.search_off_rounded,
        title: f.search != null
            ? 'No jobs match "${f.search}" near you'
            : 'No jobs match these filters near you',
        subtitle: f.activeCount > 0
            ? 'You have ${f.activeCount} filter${f.activeCount == 1 ? '' : 's'} on. '
                'Removing them will show more work.'
            : 'Try widening the distance.',
        actionLabel: f.activeCount > 0 ? 'Clear filters' : 'Search 50 km',
        onAction: () {
          ref.read(filtersProvider.notifier).state = f.activeCount > 0
              ? const JobFilters()
              : f.copyWith(radiusKm: 50);
          _searchCtl.clear();
        },
      );
    }

    return ListView.separated(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: state.jobs.length + 2,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, i) {
        if (i == 0) {
          return _ResultHeader(
            count: state.jobs.length,
            endReached: state.endReached,
            widenedTo: state.widenedTo,
          );
        }
        if (i == state.jobs.length + 1) {
          if (state.loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (state.endReached && state.jobs.length > 4) {
            return Padding(
              padding: const EdgeInsets.only(top: 24),
              child: Center(
                child: Text(
                  "That's every job matching this search.",
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ),
            );
          }
          return const SizedBox.shrink();
        }

        final job = state.jobs[i - 1];
        return JobCard(
          job: job,
          onTap: () => context.push('/job/${job.id}'),
        );
      },
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onSubmit,
    required this.onFilters,
    required this.activeFilters,
  });

  final TextEditingController controller;
  final ValueChanged<String> onSubmit;
  final VoidCallback onFilters;
  final int activeFilters;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmit,
              decoration: InputDecoration(
                hintText: 'Search jobs, companies',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          controller.clear();
                          onSubmit('');
                        },
                      ),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Badge(
            isLabelVisible: activeFilters > 0,
            label: Text('$activeFilters'),
            child: IconButton.filledTonal(
              onPressed: onFilters,
              icon: const Icon(Icons.tune),
              tooltip: 'Filters',
              style: IconButton.styleFrom(
                minimumSize: const Size(52, 52),
                backgroundColor: scheme.surfaceContainerHighest,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// States plainly where results are measured from. If the app is guessing,
/// it says so — an empty list is only explainable if the origin is visible.
class _OriginBar extends ConsumerWidget {
  const _OriginBar({required this.origin});
  final Origin? origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (origin == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final precise = origin!.isPrecise;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      child: Row(
        children: [
          Icon(precise ? Icons.my_location : Icons.location_searching,
              size: 15, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              precise
                  ? 'Showing jobs near your location'
                  : 'Showing jobs near ${origin!.label ?? "your area"}',
              style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
            ),
          ),
          if (!precise)
            TextButton(
              onPressed: () async {
                final ok = await ref
                    .read(originProvider.notifier)
                    .useDeviceLocation();
                if (!ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Location is off. You can still search by area.'),
                    ),
                  );
                }
              },
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
              child: const Text('Use my location'),
            ),
        ],
      ),
    );
  }
}

/// The chips that make this a universal employment app rather than a
/// white-collar board: no experience, immediate start, part-time.
class _QuickChips extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final f = ref.watch(filtersProvider);
    final notifier = ref.read(filtersProvider.notifier);

    Widget chip(String label, bool selected, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: FilterChip(
            label: Text(label),
            selected: selected,
            onSelected: (_) => onTap(),
            showCheckmark: false,
          ),
        );

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          chip('No experience needed', f.noExperienceOnly,
              () => notifier.state = f.copyWith(noExperienceOnly: !f.noExperienceOnly)),
          chip(
              'Part-time',
              (f.workTypes ?? const []).contains('part_time'),
              () => notifier.state = f.copyWith(
                  workTypes: (f.workTypes ?? const []).contains('part_time')
                      ? const []
                      : ['part_time'])),
          chip(
              'Full-time',
              (f.workTypes ?? const []).contains('full_time'),
              () => notifier.state = f.copyWith(
                  workTypes: (f.workTypes ?? const []).contains('full_time')
                      ? const []
                      : ['full_time'])),
          chip(
              'Night shift',
              (f.shiftTypes ?? const []).contains('night'),
              () => notifier.state = f.copyWith(
                  shiftTypes: (f.shiftTypes ?? const []).contains('night')
                      ? const []
                      : ['night'])),
          chip(
              'Daily wage',
              (f.workTypes ?? const []).contains('daily_wage'),
              () => notifier.state = f.copyWith(
                  workTypes: (f.workTypes ?? const []).contains('daily_wage')
                      ? const []
                      : ['daily_wage'])),
        ],
      ),
    );
  }
}

class _ResultHeader extends ConsumerWidget {
  const _ResultHeader({
    required this.count,
    required this.endReached,
    required this.widenedTo,
  });

  final int count;
  final bool endReached;
  final int? widenedTo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final f = ref.watch(filtersProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            endReached
                ? '$count job${count == 1 ? '' : 's'} within ${widenedTo ?? f.radiusKm} km'
                : '$count+ jobs within ${widenedTo ?? f.radiusKm} km',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          ),
          if (widenedTo != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Nothing within ${f.radiusKm} km, so we widened the '
                      'search to $widenedTo km.',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(32, 80, 32, 32),
      children: [
        Icon(icon, size: 56, color: scheme.onSurfaceVariant),
        const SizedBox(height: 20),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 10),
          Text(
            subtitle!,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant),
          ),
        ],
        if (actionLabel != null) ...[
          const SizedBox(height: 28),
          FilledButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      ],
    );
  }
}
