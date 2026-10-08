import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/responsive.dart';
import '../../data/network_repository.dart';
import '../representations/representation_widgets.dart'
    show RepresentationMessage;
import 'network_widgets.dart';

/// `/network?tab=` — connections, invitations, requests I sent, followers
/// and who I follow, plus people Omelo thinks I may know.
///
/// Every action here goes straight to the server and the list is read back,
/// because the server decides what a request becomes: asking again after a
/// decline reopens the same connection the other way round.
class NetworkScreen extends ConsumerStatefulWidget {
  const NetworkScreen({super.key, this.initialView});
  final NetworkView? initialView;

  @override
  ConsumerState<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends ConsumerState<NetworkScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  int _shown = 0;

  NetworkView get _view => NetworkView.values[_tabs.index];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: NetworkView.values.length,
      vsync: this,
      initialIndex: (widget.initialView ?? NetworkView.connections).index,
    );
    _shown = _tabs.index;
    _tabs.addListener(() {
      if (_tabs.index == _shown) return;
      setState(() => _shown = _tabs.index);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    ref.invalidate(myNetworkProvider(_view));
    ref.invalidate(connectionSuggestionsProvider);
    await ref.read(myNetworkProvider(_view).future);
  }

  Future<void> _respond(NetworkEntry e, bool accept) async {
    final id = e.connectionId;
    if (id == null) return;
    try {
      await ref.read(networkRepositoryProvider).respondConnection(id, accept);
      if (!mounted) return;
      ref.invalidate(myNetworkProvider);
      ref.invalidate(connectionSuggestionsProvider);
      networkSnack(
        context,
        accept
            ? 'You are connected with ${e.person.name}.'
            : 'Request declined.',
      );
    } catch (err) {
      if (mounted) networkSnack(context, networkError(err));
    }
  }

  Future<void> _remove(NetworkEntry e, {required bool withdraw}) async {
    final yes = await confirmNetworkAction(
      context,
      title: withdraw
          ? 'Withdraw this request?'
          : 'Remove ${e.person.name}?',
      body: withdraw
          ? '${e.person.name} will no longer see your request.'
          : 'You will no longer be connected. You can ask again later.',
      confirmLabel: withdraw ? 'Withdraw' : 'Remove',
    );
    if (!yes || !mounted) return;
    try {
      await ref.read(networkRepositoryProvider).removeConnection(e.person.id);
      if (!mounted) return;
      ref.invalidate(myNetworkProvider);
      networkSnack(context, withdraw ? 'Request withdrawn.' : 'Removed.');
    } catch (err) {
      if (mounted) networkSnack(context, networkError(err));
    }
  }

  /// The button has already told the server; the list just has to catch up.
  void _unfollowed(NetworkEntry e) {
    if (!mounted) return;
    ref.invalidate(myNetworkProvider(NetworkView.following));
    networkSnack(context, 'You no longer follow ${e.person.name}.');
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(isSignedInProvider);
    final gutter = Breakpoints.of(context).gutter;

    listenForNetworkNotices(ref, () {
      if (mounted) ref.invalidate(myNetworkProvider);
    });

    if (!signedIn) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('My network'),
          leading: networkBackButton(context, '/home'),
        ),
        body: RepresentationMessage(
          icon: Icons.people_outline,
          title: 'The people you work with',
          body: 'Connect with people you have worked with and follow the '
              'organizations you want to work for. Sign in to start.',
          actionLabel: 'Sign in or create an account',
          onAction: () => context.push('/sign-in?next=/network'),
        ),
      );
    }

    final entries = ref.watch(myNetworkProvider(_view));

    return Scaffold(
      appBar: AppBar(
        title: const Text('My network'),
        leading: networkBackButton(context, '/home'),
        actions: [
          IconButton(
            tooltip: 'Omelo feed',
            icon: const Icon(Icons.forum_outlined),
            onPressed: () => context.push('/feed'),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            for (final v in NetworkView.values)
              Tab(
                child: _TabLabel(
                  view: v,
                  count: v == NetworkView.invitations
                      ? ref.watch(pendingInvitationsCountProvider)
                      : 0,
                ),
              ),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: entries.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, __) => RepresentationMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load your network',
            body: networkError(e),
            actionLabel: 'Try again',
            onAction: _refresh,
          ),
          data: (list) => _body(context, gutter, list),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, double gutter, List<NetworkEntry> list) {
    final view = _view;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(gutter, 12, gutter, 32),
      children: [
        if (view == NetworkView.connections ||
            view == NetworkView.invitations) ...[
          const SuggestionsStrip(),
          const SizedBox(height: 18),
        ],
        if (list.isEmpty)
          NetworkEmpty(
            icon: Icons.people_outline,
            title: view.emptyTitle,
            body: view.emptyBody,
          )
        else ...[
          ContentWidth(
            child: Text(
              '${list.length} ${view.label.toLowerCase()}',
              style: TextStyle(
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ContentWidth(
            child: ResponsiveCardGrid(
              children: [
                for (final e in list)
                  NetworkPersonCard(
                    key: ValueKey('${view.wire}-${e.person.id}'),
                    entry: e,
                    view: view,
                    onAccept: () => _respond(e, true),
                    onDecline: () => _respond(e, false),
                    onWithdraw: () => _remove(e, withdraw: true),
                    onRemove: () => _remove(e, withdraw: false),
                    onUnfollow: () => _unfollowed(e),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.view, required this.count});
  final NetworkView view;
  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return Text(view.label);
    return Badge(
      label: Text('$count'),
      offset: const Offset(10, -6),
      child: Text(view.label),
    );
  }
}

/// "People you may know" — each with the server's own reason for suggesting
/// them, so the suggestion explains itself.
class SuggestionsStrip extends ConsumerWidget {
  const SuggestionsStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(connectionSuggestionsProvider).valueOrNull;
    if (people == null || people.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ContentWidth(
          child: Row(
            children: [
              const Text('People you may know',
                  style:
                      TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              const Spacer(),
              IconButton(
                tooltip: 'Refresh suggestions',
                iconSize: 20,
                onPressed: () =>
                    ref.invalidate(connectionSuggestionsProvider),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 218,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: people.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final e = people[i];
              return SizedBox(
                width: 180,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        InkWell(
                          onTap: () => context.push(e.person.route),
                          child: NetworkAvatar(author: e.person, radius: 30),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          e.person.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Expanded(
                          child: Text(
                            e.reason ?? e.person.headline ?? '',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 12,
                                height: 1.3,
                                color: scheme.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 6),
                        SizedBox(
                          width: double.infinity,
                          child: ConnectButton(
                            person: e.person,
                            compact: true,
                            onRequested: () => ref
                                .invalidate(connectionSuggestionsProvider),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One row in a network list. What the buttons do depends on which list it
/// is: an invitation is accepted or declined, a sent request is withdrawn, a
/// connection is removed, a follow is dropped.
class NetworkPersonCard extends ConsumerWidget {
  const NetworkPersonCard({
    super.key,
    required this.entry,
    required this.view,
    this.onAccept,
    this.onDecline,
    this.onWithdraw,
    this.onRemove,
    this.onUnfollow,
  });

  final NetworkEntry entry;
  final NetworkView view;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onWithdraw;
  final VoidCallback? onRemove;
  final VoidCallback? onUnfollow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final p = entry.person;
    final now = ref.watch(networkClockProvider)();

    final when = switch (view) {
      NetworkView.invitations || NetworkView.sent =>
        entry.requestedAt == null ? null : postTime(entry.requestedAt!, now),
      NetworkView.connections =>
        entry.connectedAt == null ? null : 'Connected ${postTime(entry.connectedAt!, now)}',
      _ => null,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AuthorRow(
              author: p,
              onTap: () => context.push(p.route),
              secondary: [
                if (p.headline != null) p.headline!,
                if (entry.reason != null) entry.reason!,
                ?when,
              ].join(' · '),
            ),
            if (entry.message != null) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(entry.message!,
                    style: const TextStyle(fontSize: 13.5, height: 1.4)),
              ),
            ],
            const SizedBox(height: 10),
            _buttons(context),
          ],
        ),
      ),
    );
  }

  Widget _buttons(BuildContext context) {
    final p = entry.person;
    switch (view) {
      case NetworkView.invitations:
        return Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: onAccept,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Accept'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: onDecline,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('Decline'),
              ),
            ),
          ],
        );
      case NetworkView.sent:
        return Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: onWithdraw,
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
            child: const Text('Withdraw'),
          ),
        );
      case NetworkView.connections:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FollowButton(author: p, compact: true),
            OutlinedButton(
              onPressed: onRemove,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              child: const Text('Remove'),
            ),
          ],
        );
      case NetworkView.followers:
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (!p.isOrganization) ConnectButton(person: p, compact: true),
            FollowButton(author: p, compact: true),
          ],
        );
      case NetworkView.following:
        return Wrap(
          children: [
            FollowButton(
              author: p,
              following: true,
              compact: true,
              onChanged: (following) {
                if (!following) onUnfollow?.call();
              },
            ),
          ],
        );
    }
  }
}
