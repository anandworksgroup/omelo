import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/responsive.dart';
import '../../data/network_repository.dart';
import '../notifications/notifications_screen.dart' show NotificationBell;
import 'feed_preferences_sheet.dart';
import 'network_widgets.dart';
import 'post_card.dart';
import '../../core/ui.dart';

/// `/feed?tab=` — Omelo's professional network.
///
/// Five tabs over one server function: "For you" is ranked and pages by
/// offset, the other four are newest-first and page by the oldest post on
/// screen. Which one is which is the server's business — the app follows
/// whichever cursor came back and stops when a page comes back short.
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key, this.initialTab});
  final FeedTab? initialTab;

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen>
    with SingleTickerProviderStateMixin {
  static const _page = 20;

  late final TabController _tabs;
  final _scroll = ScrollController();

  List<FeedPost> _posts = const [];
  FeedPreferences _preferences = const FeedPreferences();
  String? _ranking;
  DateTime? _nextBefore;
  int? _nextOffset;
  bool _end = false;

  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  int _seq = 0;
  int _shownTab = 0;

  FeedTab get _tab => FeedTab.values[_tabs.index];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: FeedTab.values.length,
      vsync: this,
      initialIndex: (widget.initialTab ?? FeedTab.forYou).index,
    );
    _shownTab = _tabs.index;
    _tabs.addListener(() {
      if (_tabs.index == _shownTab) return;
      _shownTab = _tabs.index;
      _load(clear: true);
    });
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _tabs.dispose();
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || _loading || _loadingMore || _end) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 600) _load(more: true);
  }

  /// [clear] empties the list first; a pull-to-refresh does not, so what is
  /// on screen stays there while the new page arrives.
  Future<void> _load({bool more = false, bool clear = false}) async {
    if (!mounted) return;
    if (more && _end) return;
    final seq = ++_seq;
    final tab = _tab;
    setState(() {
      if (more) {
        _loadingMore = true;
      } else {
        if (clear) _posts = const [];
        _loading = _posts.isEmpty;
        _error = null;
        _end = false;
        _nextBefore = null;
        _nextOffset = null;
      }
    });

    try {
      final page = await ref
          .read(networkRepositoryProvider)
          .feed(
            tab,
            limit: _page,
            // Each tab uses exactly one cursor: the ranked tab an offset,
            // the chronological ones the oldest timestamp on screen.
            before: more && !tab.pagesByOffset ? _nextBefore : null,
            offset: tab.pagesByOffset ? (more ? (_nextOffset ?? 0) : 0) : null,
          );
      if (!mounted || seq != _seq) return;
      setState(() {
        // A post can come back twice across pages when something new was
        // written between them; the id decides.
        final seen = more ? {for (final p in _posts) p.id} : <String>{};
        final fresh = page.posts.where((p) => seen.add(p.id)).toList();
        _posts = more ? [..._posts, ...fresh] : page.posts;
        _preferences = page.preferences;
        _ranking = page.ranking ?? _ranking;
        _nextBefore = page.nextBefore;
        _nextOffset = page.nextOffset;
        // A short page is the end. So is one that added nothing new.
        _end = page.posts.length < _page || (more && fresh.isEmpty);
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (more) {
          networkSnack(context, networkError(e));
        } else {
          _error = networkError(e);
        }
      });
    }
  }

  void _replace(FeedPost post) {
    final i = _posts.indexWhere((p) => p.id == post.id);
    if (i < 0) return;
    setState(() => _posts = [..._posts]..[i] = post);
  }

  void _remove(String postId) =>
      setState(() => _posts = _posts.where((p) => p.id != postId).toList());

  Future<void> _compose() async {
    final created = await context.push<FeedPost>('/feed/compose');
    if (created == null || !mounted) return;
    setState(() => _posts = [created, ..._posts]);
  }

  Future<void> _preferencesSheet() async {
    final saved = await showFeedPreferencesSheet(context, ref, _preferences);
    if (saved == null || !mounted) return;
    setState(() => _preferences = saved);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(isSignedInProvider);
    final gutter = Breakpoints.of(context).gutter;

    // A new reaction, comment or share means the counts on screen are stale.
    listenForNetworkNotices(ref, () {
      if (mounted && !_loading) _load();
    });

    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Omelo feed'),
          leading: networkBackButton(context, '/home'),
        ),
        body: OmeloMessage(
          icon: Icons.groups_outlined,
          title: 'Your professional network',
          body:
              'Follow the people and organizations you work with, and see '
              'what they are doing. Sign in to start.',
          actionLabel: 'Sign in or create an account',
          onAction: () => context.push('/sign-in?next=/feed'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Omelo feed'),
        leading: networkBackButton(context, '/home'),
        actions: [
          IconButton(
            tooltip: 'My network',
            icon: const Icon(Icons.people_outline),
            onPressed: () => context.push('/network'),
          ),
          IconButton(
            tooltip: 'What I see',
            icon: const Icon(Icons.tune),
            onPressed: _preferencesSheet,
          ),
          const NotificationBell(),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final t in FeedTab.values) Tab(text: t.label)],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _compose,
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Post'),
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body(context, gutter)),
    );
  }

  Widget _body(BuildContext context, double gutter) {
    if (_loading) return const OmeloSkeletonList();

    if (_error != null) {
      return OmeloMessage(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load the feed',
        body: _error!,
        actionLabel: 'Try again',
        onAction: _load,
      );
    }

    if (_posts.isEmpty) {
      return OmeloMessage(
        icon: Icons.forum_outlined,
        title: _tab.emptyTitle,
        body: _tab.emptyBody,
        actionLabel: _tab == FeedTab.saved ? null : 'Find people to follow',
        onAction: _tab == FeedTab.saved ? null : () => context.push('/network'),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    final ranking = _ranking;

    return ListView.builder(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 96),
      // One extra row for the ranking note or the "that is everything" line.
      itemCount: _posts.length + 2,
      itemBuilder: (context, i) {
        if (i == 0) {
          if (_tab != FeedTab.forYou || ranking == null) {
            return const SizedBox.shrink();
          }
          return ContentWidth.reading(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Ordered by: $ranking',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }
        if (i == _posts.length + 1) {
          if (_loadingMore) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          if (!_end) return const SizedBox(height: 40);
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Center(
              child: Text(
                'That is everything for now.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          );
        }

        final post = _posts[i - 1];
        return ContentWidth.reading(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: PostCard(
              key: ValueKey('feed-${post.id}'),
              post: post,
              actions: PostActions(
                onChanged: _replace,
                onRemoved: _remove,
                onOpen: (p) => context.push('/feed/${p.id}'),
                onComment: (p) => context.push('/feed/${p.id}?reply=1'),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A card on Home: what is new on the network, without pretending to be a
/// feed inside Home.
class FeedHomeCard extends ConsumerWidget {
  const FeedHomeCard({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isSignedInProvider)) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final waiting = ref.watch(pendingInvitationsCountProvider);

    return Padding(
      padding: padding,
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/feed'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Badge(
                    isLabelVisible: waiting > 0,
                    label: Text('$waiting'),
                    child: Icon(
                      Icons.groups_outlined,
                      size: 30,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Your professional network',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          waiting > 0
                              ? '$waiting connection '
                                    'request${waiting == 1 ? '' : 's'} waiting'
                              : 'See what the people and organizations you '
                                    'follow are doing.',
                          style: TextStyle(
                            fontSize: 13.5,
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
      ),
    );
  }
}
