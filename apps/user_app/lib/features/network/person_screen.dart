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

/// `/people/:id` — another person's page on the network.
///
/// Omelo never exposes a person's record to another worker: the only thing
/// the server hands out is the author card that travels with a post or a
/// network list. So this screen takes the card it was given when the name
/// was tapped, and falls back to the one on the person's own first post
/// when it was opened cold from a notification.
class PersonScreen extends ConsumerStatefulWidget {
  const PersonScreen({super.key, required this.personId, this.author});

  final String personId;

  /// The card the previous screen already had, when there was one.
  final PostAuthor? author;

  @override
  ConsumerState<PersonScreen> createState() => _PersonScreenState();
}

class _PersonScreenState extends ConsumerState<PersonScreen> {
  final _changed = <String, FeedPost>{};
  final _removed = <String>{};

  Future<void> _refresh() async {
    setState(() {
      _changed.clear();
      _removed.clear();
    });
    ref.invalidate(personPostsProvider(widget.personId));
    await ref.read(personPostsProvider(widget.personId).future);
  }

  Future<void> _report(PostAuthor person) async {
    final answer = await askReport(context, what: 'person');
    if (answer == null || !mounted) return;
    try {
      await ref.read(networkRepositoryProvider).report(
            subject: ReportSubject.person,
            subjectId: person.id,
            reason: answer.reason,
            details: answer.details,
          );
      if (mounted) networkSnack(context, 'Reported. Omelo will look at it.');
    } catch (e) {
      if (mounted) networkSnack(context, networkError(e));
    }
  }

  Future<void> _block(PostAuthor person) async {
    if (!await confirmBlock(context, person) || !mounted) return;
    try {
      await ref
          .read(networkRepositoryProvider)
          .block(BlockTarget.person, person.id);
      if (!mounted) return;
      networkSnack(context, '${person.name} is blocked.');
      if (context.canPop()) {
        context.pop();
      } else {
        context.go('/feed');
      }
    } catch (e) {
      if (mounted) networkSnack(context, networkError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final posts = ref.watch(personPostsProvider(widget.personId));
    final gutter = Breakpoints.of(context).gutter;
    final me = ref.watch(currentUserProvider);
    final isMe = me != null && me.id == widget.personId;

    // Whatever card we have: the one handed over, else the one on their own
    // first post.
    final author = widget.author ??
        posts.valueOrNull
            ?.map((p) => p.author)
            .whereType<PostAuthor>()
            .where((a) => a.id == widget.personId && !a.isOrganization)
            .firstOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(author?.name ?? 'Person'),
        leading: networkBackButton(context, '/feed'),
        actions: [
          if (author != null && !isMe)
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (v) =>
                  v == 'report' ? _report(author) : _block(author),
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'report', child: Text('Report this person')),
                PopupMenuItem(value: 'block', child: Text('Block')),
              ],
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: posts.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, __) => RepresentationMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not open this profile',
            body: networkError(e),
            actionLabel: 'Try again',
            onAction: _refresh,
          ),
          data: (list) => _body(context, gutter, author, list, isMe: isMe),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    double gutter,
    PostAuthor? author,
    List<FeedPost> all, {
    required bool isMe,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final posts = all
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
              if (author != null)
                PersonHeader(person: author, isMe: isMe)
              else
                Text(
                  'This person has not shared anything you can see.',
                  style: TextStyle(
                      fontSize: 15, color: scheme.onSurfaceVariant),
                ),
              const SizedBox(height: 22),
              Text(
                isMe ? 'My posts' : 'Posts',
                style:
                    const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              if (posts.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    isMe
                        ? 'You have not posted anything yet.'
                        : 'Nothing here that you can see. Posts for '
                            'connections only stay with their connections.',
                    style: TextStyle(
                        fontSize: 14.5,
                        height: 1.45,
                        color: scheme.onSurfaceVariant),
                  ),
                )
              else
                for (final p in posts)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: PostCard(
                      key: ValueKey('person-${p.id}'),
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

/// Photo, name, headline, and what you can do about this person.
class PersonHeader extends ConsumerWidget {
  const PersonHeader({super.key, required this.person, this.isMe = false});

  final PostAuthor person;
  final bool isMe;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final signedIn = ref.watch(isSignedInProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NetworkAvatar(author: person, radius: 34),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          person.name,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              height: 1.2),
                        ),
                      ),
                      if (person.verified) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.verified,
                            size: 19,
                            color: Color(0xFF12805C),
                            semanticLabel: 'Verified'),
                      ],
                    ],
                  ),
                  if (person.headline != null) ...[
                    const SizedBox(height: 4),
                    Text(person.headline!,
                        style: const TextStyle(fontSize: 14.5, height: 1.35)),
                  ],
                ],
              ),
            ),
          ],
        ),
        if (!isMe && !signedIn) ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: () =>
                  context.push('/sign-in?next=/people/${person.id}'),
              child: const Text('Sign in to connect'),
            ),
          ),
        ] else if (!isMe) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ConnectButton(person: person),
              FollowButton(author: person),
              Tooltip(
                message: 'Omelo messages belong to a job you applied to',
                child: OutlinedButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.chat_bubble_outline, size: 18),
                  label: const Text('Message'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Messages on Omelo belong to a job: you and an employer talk about '
            'an application. Messaging another worker directly is not built '
            'yet.',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
        ] else ...[
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: () => context.push('/feed/compose'),
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Write a post'),
            ),
          ),
        ],
      ],
    );
  }
}
