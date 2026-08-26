import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/location.dart';
import '../../data/job.dart';
import '../../data/jobs_repository.dart';

final filtersProvider = StateProvider<JobFilters>((_) => const JobFilters());

final categoriesProvider = FutureProvider<List<JobCategory>>(
  (ref) => ref.watch(jobsRepositoryProvider).categories(),
);

class DiscoverState {
  const DiscoverState({
    this.jobs = const [],
    this.loading = false,
    this.loadingMore = false,
    this.endReached = false,
    this.error,
    this.widenedTo,
  });

  final List<Job> jobs;
  final bool loading;
  final bool loadingMore;
  final bool endReached;
  final String? error;

  /// Set when we automatically widened the radius because the requested
  /// one returned nothing (UC-6: never show an empty screen with no
  /// explanation and no way forward).
  final int? widenedTo;

  DiscoverState copyWith({
    List<Job>? jobs,
    bool? loading,
    bool? loadingMore,
    bool? endReached,
    String? error,
    int? widenedTo,
    bool clearError = false,
    bool clearWidened = false,
  }) =>
      DiscoverState(
        jobs: jobs ?? this.jobs,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        endReached: endReached ?? this.endReached,
        error: clearError ? null : (error ?? this.error),
        widenedTo: clearWidened ? null : (widenedTo ?? this.widenedTo),
      );
}

final discoverProvider =
    NotifierProvider<DiscoverController, DiscoverState>(DiscoverController.new);

class DiscoverController extends Notifier<DiscoverState> {
  static const _pageSize = 20;

  @override
  DiscoverState build() {
    // Re-run whenever filters or the search origin change.
    ref.watch(filtersProvider);
    ref.watch(originProvider);
    Future.microtask(load);
    return const DiscoverState(loading: true);
  }

  Future<void> load() async {
    final origin = ref.read(originProvider).value;
    if (origin == null) return;

    state = state.copyWith(loading: true, clearError: true, clearWidened: true);
    final repo = ref.read(jobsRepositoryProvider);
    final filters = ref.read(filtersProvider);

    try {
      var jobs = await repo.nearby(
        lat: origin.lat,
        lng: origin.lng,
        filters: filters,
        limit: _pageSize,
      );

      // Auto-widen rather than showing "no jobs found". A worker in an outer
      // suburb should not conclude the platform is empty.
      int? widened;
      if (jobs.isEmpty && filters.search == null) {
        for (final r in [filters.radiusKm * 2, 50, 100]) {
          if (r <= filters.radiusKm) continue;
          jobs = await repo.nearby(
            lat: origin.lat,
            lng: origin.lng,
            filters: filters.copyWith(radiusKm: r),
            limit: _pageSize,
          );
          if (jobs.isNotEmpty) {
            widened = r;
            break;
          }
        }
      }

      state = DiscoverState(
        jobs: jobs,
        loading: false,
        endReached: jobs.length < _pageSize,
        widenedTo: widened,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: _friendly(e));
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || state.endReached || state.loading) return;
    final origin = ref.read(originProvider).value;
    if (origin == null) return;

    state = state.copyWith(loadingMore: true);
    try {
      final filters = ref.read(filtersProvider);
      final more = await ref.read(jobsRepositoryProvider).nearby(
            lat: origin.lat,
            lng: origin.lng,
            filters: state.widenedTo != null
                ? filters.copyWith(radiusKm: state.widenedTo)
                : filters,
            limit: _pageSize,
            offset: state.jobs.length,
          );
      state = state.copyWith(
        jobs: [...state.jobs, ...more],
        loadingMore: false,
        endReached: more.length < _pageSize,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: _friendly(e));
    }
  }

  /// Plain-language errors. "PostgrestException" means nothing to a worker.
  String _friendly(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('socket') ||
        s.contains('network') ||
        s.contains('failed host lookup')) {
      return 'No internet connection. Check your network and try again.';
    }
    return 'Could not load jobs right now. Please try again.';
  }
}
