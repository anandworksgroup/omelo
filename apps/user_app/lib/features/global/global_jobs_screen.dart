import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/location.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/global_repository.dart';
import '../../data/job_events.dart' show JobSurface, jobRoute;
import '../representations/representation_widgets.dart'
    show RepresentationMessage;
import '../work/work_widgets.dart' show workBackButton;
import 'global_widgets.dart';

/// `/jobs/global?tab=&country=` — work near me, remote, with help to move,
/// with visa sponsorship, in other countries, and abroad where I want to go.
class GlobalJobsScreen extends ConsumerStatefulWidget {
  const GlobalJobsScreen({super.key, this.initialTab, this.initialCountry});
  final GlobalTab? initialTab;
  final String? initialCountry;

  @override
  ConsumerState<GlobalJobsScreen> createState() => _GlobalJobsScreenState();
}

class _GlobalJobsScreenState extends ConsumerState<GlobalJobsScreen>
    with SingleTickerProviderStateMixin {
  static const _page = 20;

  late final TabController _tabs;
  final _search = TextEditingController();
  String? _country;
  String? _query;

  List<GlobalJob> _jobs = const [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _seq = 0;
  int _shownTab = 0;

  GlobalTab get _tab => GlobalTab.values[_tabs.index];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: GlobalTab.values.length,
      vsync: this,
      initialIndex: (widget.initialTab ?? GlobalTab.international).index,
    );
    _shownTab = _tabs.index;
    _tabs.addListener(() {
      // Fires on tap (at the start of the animation) and on swipe.
      if (_tabs.index == _shownTab) return;
      _shownTab = _tabs.index;
      _load();
    });
    _country = widget.initialCountry?.toUpperCase();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _search.dispose();
    super.dispose();
  }

  GlobalJobFilters _filters() {
    final origin = ref.read(originProvider).valueOrNull;
    final useOrigin = origin != null && origin.source != OriginSource.fallback;
    return GlobalJobFilters(
      country: _country,
      query: _query,
      lat: useOrigin ? origin.lat : null,
      lng: useOrigin ? origin.lng : null,
    );
  }

  Future<void> _load({bool more = false}) async {
    if (!mounted) return;
    final seq = ++_seq;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        _loading = true;
        _error = null;
      }
    });
    try {
      final page = await ref.read(globalRepositoryProvider).globalJobs(
            _tab,
            filters: _filters(),
            limit: _page,
            offset: more ? _jobs.length : 0,
          );
      if (!mounted || seq != _seq) return;
      setState(() {
        _jobs = more ? [..._jobs, ...page.results] : page.results;
        _total = page.total;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (more) {
          showGlobalSnack(context, globalError(e));
        } else {
          _error = globalError(e);
        }
      });
    }
  }

  Future<void> _pickCountry(List<Country> countries) async {
    final picked = await pickCountry(context, countries,
        title: 'Jobs in which country?');
    if (picked == null) return;
    setState(() => _country = picked.code);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final countries = ref.watch(countriesProvider).valueOrNull ?? const <Country>[];
    final gutter = Breakpoints.of(context).gutter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jobs worldwide'),
        leading: workBackButton(context, '/discover'),
        actions: [
          IconButton(
            onPressed: () => context.push('/mobility'),
            icon: const Icon(Icons.flight_takeoff),
            tooltip: 'Global mobility',
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in GlobalTab.values) Tab(text: t.label)],
        ),
      ),
      body: Column(
        children: [
          ContentWidth(
            padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Job title or employer',
                      prefixIcon: const Icon(Icons.search),
                      isDense: true,
                      suffixIcon: _query == null
                          ? null
                          : IconButton(
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = null);
                                _load();
                              },
                              icon: const Icon(Icons.close),
                              tooltip: 'Clear search',
                            ),
                    ),
                    onSubmitted: (q) {
                      final t = q.trim();
                      setState(() => _query = t.isEmpty ? null : t);
                      _load();
                    },
                  ),
                ),
                if (_country == null)
                  ActionChip(
                    avatar: const Icon(Icons.public, size: 18),
                    label: const Text('All countries'),
                    onPressed: () => _pickCountry(countries),
                  )
                else ...[
                  InputChip(
                    avatar: const Icon(Icons.flag_outlined, size: 18),
                    label: Text(countryName(_country, countries)),
                    onPressed: () => _pickCountry(countries),
                    onDeleted: () {
                      setState(() => _country = null);
                      _load();
                    },
                    deleteButtonTooltipMessage: 'Show all countries',
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.menu_book_outlined, size: 18),
                    label: const Text('Country guide'),
                    onPressed: () => context.push('/countries/$_country'),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _body(context, gutter),
            ),
          ),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, double gutter) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return RepresentationMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load jobs',
        body: _error!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }
    if (_jobs.isEmpty) {
      return RepresentationMessage(
        icon: Icons.travel_explore,
        title: 'No jobs here yet',
        body: _tab.emptyText,
        actionLabel: _tab == GlobalTab.workAbroad ? 'Set where I would move' : null,
        onAction: _tab == GlobalTab.workAbroad
            ? () => context.push('/mobility')
            : null,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '$_total job${_total == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
              ResponsiveCardGrid(
                children: [
                  for (var i = 0; i < _jobs.length; i++)
                    GlobalJobCard(
                      key: ValueKey('global-${_jobs[i].id}'),
                      job: _jobs[i],
                      onTap: () => context.push(
                          jobRoute(_jobs[i].id, JobSurface.search, rank: i + 1)),
                    ),
                ],
              ),
              if (_jobs.length < _total) ...[
                const SizedBox(height: 16),
                Center(
                  child: OutlinedButton(
                    onPressed: _loadingMore ? null : () => _load(more: true),
                    child: Text(_loadingMore ? 'Loading…' : 'Show more'),
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

class GlobalJobCard extends StatelessWidget {
  const GlobalJobCard({super.key, required this.job, required this.onTap});
  final GlobalJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final j = job;
    final scheme = Theme.of(context).colorScheme;
    final sponsor = sponsorshipLabel(j.sponsorship);
    final remote = remoteLine(j);
    final pay = j.pay;

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(j.title,
                  style: const TextStyle(
                      fontSize: 17, fontWeight: FontWeight.w700, height: 1.25)),
              Row(
                children: [
                  Flexible(
                    child: Text(j.companyName,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14.5, color: scheme.onSurfaceVariant)),
                  ),
                  if (j.companyVerified) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified,
                        size: 15, color: OmeloTheme.verified,
                        semanticLabel: 'Verified employer'),
                  ],
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.place_outlined,
                      size: 16, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      [
                        if (j.distanceKm != null) Fmt.distance(j.distanceKm),
                        if (j.placeLine.isNotEmpty) j.placeLine,
                      ].join(' · '),
                      style: const TextStyle(fontSize: 13.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                [
                  ?remote,
                  if (remote == null && j.workplace != null)
                    Fmt.workplace(j.workplace),
                  if (j.workType != null) Fmt.workType(j.workType),
                ].join(' · '),
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 10),
              Text(
                pay == null ? 'Pay not shown' : payLineOf(pay),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              if (pay != null)
                ApproxPayLine(
                  text: approxPayLineOf(pay),
                  source: conversionSource(pay.normalized),
                ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  if (j.eligibility != null) EligibilityChip(j.eligibility!),
                  if (sponsor != null)
                    OmeloPill(sponsor,
                        icon: Icons.badge_outlined,
                        color: scheme.primary,
                        background: scheme.primaryContainer.withValues(alpha: 0.5)),
                  for (final s in supportLabels(j))
                    OmeloPill(s, icon: Icons.check),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
