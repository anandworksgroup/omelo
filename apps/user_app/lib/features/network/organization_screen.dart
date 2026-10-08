import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/responsive.dart';
import '../../data/network_repository.dart';
import '../representations/representation_widgets.dart'
    show RepresentationMessage;
import 'network_widgets.dart';
import 'post_card.dart';

/// `/organizations/:id` — an organization's page on the network: who they
/// are, how many people follow them, and what they have posted publicly.
///
/// The jobs they have open live on `/company/:id`, which this links to
/// rather than duplicating.
class OrganizationScreen extends ConsumerStatefulWidget {
  const OrganizationScreen({super.key, required this.companyId});
  final String companyId;

  @override
  ConsumerState<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends ConsumerState<OrganizationScreen> {
  /// Edits made on a card here stay until the next reload.
  final _changed = <String, FeedPost>{};
  final _removed = <String>{};

  Future<void> _refresh() async {
    setState(() {
      _changed.clear();
      _removed.clear();
    });
    ref.invalidate(organizationFeedProvider(widget.companyId));
    await ref.read(organizationFeedProvider(widget.companyId).future);
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(organizationFeedProvider(widget.companyId));
    final gutter = Breakpoints.of(context).gutter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Organization'),
        leading: networkBackButton(context, '/feed'),
        actions: [
          IconButton(
            tooltip: 'Jobs at this organization',
            icon: const Icon(Icons.work_outline),
            onPressed: () => context.push('/company/${widget.companyId}'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: feed.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, __) => RepresentationMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not open this organization',
            body: networkError(e),
            actionLabel: 'Try again',
            onAction: _refresh,
          ),
          data: (org) {
            if (org?.organization == null) {
              return const RepresentationMessage(
                icon: Icons.business_outlined,
                title: 'Organization not found',
                body: 'It may have been removed from Omelo.',
              );
            }
            return _body(context, gutter, org!);
          },
        ),
      ),
    );
  }

  Widget _body(BuildContext context, double gutter, OrganizationFeed org) {
    final author = org.organization!;
    final posts = org.posts
        .where((p) => !_removed.contains(p.id))
        .map((p) => _changed[p.id] ?? p)
        .toList();

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(gutter, 14, gutter, 32),
      children: [
        ContentWidth.reading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OrganizationHeader(organization: org),
              const SizedBox(height: 22),
              Text(
                posts.isEmpty ? 'Posts' : 'Posts (${posts.length})',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (posts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    '${author.name} has not posted anything you can see yet.',
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.45,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                for (final p in posts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PostCard(
                      key: ValueKey('org-${p.id}'),
                      post: p,
                      showWhy: false,
                      actions: PostActions(
                        onChanged: (fresh) =>
                            setState(() => _changed[fresh.id] = fresh),
                        onRemoved: (id) => setState(() => _removed.add(id)),
                        onOpen: (post) => context.push('/feed/${post.id}'),
                        onComment: (post) =>
                            context.push('/feed/${post.id}?reply=1'),
                      ),
                    ),
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Logo, name, verified tick, follower count and the Follow button.
class OrganizationHeader extends ConsumerWidget {
  const OrganizationHeader({super.key, required this.organization});
  final OrganizationFeed organization;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final signedIn = ref.watch(isSignedInProvider);
    final author = organization.organization!;
    final type = organizationTypeWords(author.organizationType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NetworkAvatar(author: author, radius: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          author.name,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.2),
                        ),
                      ),
                      if (author.verified) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified,
                            size: 19,
                            color: Color(0xFF12805C),
                            semanticLabel: 'Verified organization'),
                      ],
                    ],
                  ),
                  if (type.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(type,
                        style: TextStyle(
                            fontSize: 13.5, color: scheme.onSurfaceVariant)),
                  ],
                  const SizedBox(height: 4),
                  Text(organization.followerLine,
                      style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (signedIn)
              FollowButton(
                author: author,
                following: organization.following,
              )
            else
              FilledButton(
                onPressed: () => context
                    .push('/sign-in?next=/organizations/${author.id}'),
                child: const Text('Sign in to follow'),
              ),
            OutlinedButton.icon(
              onPressed: () => context.push('/company/${author.id}'),
              icon: const Icon(Icons.work_outline, size: 18),
              label: const Text('Open jobs'),
            ),
          ],
        ),
      ],
    );
  }
}
