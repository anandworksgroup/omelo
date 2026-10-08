import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/network_repository.dart';
import '../representations/representation_widgets.dart'
    show RepresentationMessage;
import 'network_widgets.dart';
import 'post_card.dart';

/// `/feed/:id` — one post and its comments.
///
/// Threads are one level deep, the way the database enforces: a comment can
/// have replies, a reply cannot. Anyone may delete their own comment; the
/// author of the post may delete any comment on it.
class PostDetailScreen extends ConsumerStatefulWidget {
  const PostDetailScreen({super.key, required this.postId, this.autoReply = false});

  final String postId;

  /// True when the worker tapped "Comment" rather than the post itself.
  final bool autoReply;

  @override
  ConsumerState<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends ConsumerState<PostDetailScreen> {
  final _reply = TextEditingController();
  final _replyFocus = FocusNode();

  FeedPost? _post;
  List<PostCommentItem> _comments = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  /// The comment being replied to, if any. Null means a new top-level
  /// comment.
  PostCommentItem? _replyingTo;

  @override
  void initState() {
    super.initState();
    _reply.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _load();
      if (mounted && widget.autoReply) _replyFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _reply.dispose();
    _replyFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final repo = ref.read(networkRepositoryProvider);
    try {
      final post = await repo.postDetail(widget.postId);
      if (!mounted) return;
      if (post == null) {
        setState(() {
          _loading = false;
          _error = 'This post is not available. It may have been deleted, or '
              'you may not be able to see it.';
        });
        return;
      }
      final comments = await repo.comments(widget.postId, limit: 100);
      if (!mounted) return;
      setState(() {
        _post = post;
        _comments = comments;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = networkError(e);
      });
    }
  }

  Future<void> _send() async {
    final problem = validateComment(_reply.text);
    if (problem != null) {
      networkSnack(context, problem);
      return;
    }
    setState(() => _sending = true);
    try {
      await ref.read(networkRepositoryProvider).comment(
            widget.postId,
            _reply.text,
            parentId: _replyingTo?.id,
          );
      if (!mounted) return;
      _reply.clear();
      setState(() {
        _replyingTo = null;
        _sending = false;
      });
      await _load();
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      networkSnack(context, networkError(e));
    }
  }

  Future<void> _deleteComment(String id) async {
    final yes = await confirmNetworkAction(
      context,
      title: 'Delete this comment?',
      body: 'It disappears from the post. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!yes || !mounted) return;
    try {
      await ref.read(networkRepositoryProvider).deleteComment(id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) networkSnack(context, networkError(e));
    }
  }

  Future<void> _reportComment(String id) async {
    final answer = await askReport(context, what: 'comment');
    if (answer == null || !mounted) return;
    try {
      await ref.read(networkRepositoryProvider).report(
            subject: ReportSubject.comment,
            subjectId: id,
            reason: answer.reason,
            details: answer.details,
          );
      if (mounted) networkSnack(context, 'Reported. Omelo will look at it.');
    } catch (e) {
      if (mounted) networkSnack(context, networkError(e));
    }
  }

  void _startReply(PostCommentItem c) {
    setState(() => _replyingTo = c);
    _replyFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final gutter = Breakpoints.of(context).gutter;
    final signedIn = ref.watch(isSignedInProvider);
    final post = _post;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        leading: networkBackButton(context, '/feed'),
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? RepresentationMessage(
                          icon: Icons.cloud_off_outlined,
                          title: 'Could not open this post',
                          body: _error!,
                          actionLabel: 'Try again',
                          onAction: _load,
                        )
                      : _list(context, gutter, post!),
            ),
          ),
          if (!_loading && _error == null && post != null)
            _composer(context, signedIn),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, double gutter, FeedPost post) {
    final scheme = Theme.of(context).colorScheme;
    final iOwnThePost = post.my.mine;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(gutter, 10, gutter, 20),
      children: [
        ContentWidth.reading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PostCard(
                post: post,
                showWhy: false,
                expanded: true,
                actions: PostActions(
                  onChanged: (p) => setState(() => _post = p),
                  onRemoved: (_) {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/feed');
                    }
                  },
                ),
              ),
              const SizedBox(height: 18),
              Text(
                _comments.isEmpty
                    ? 'No comments yet'
                    : '${_comments.length} '
                        'comment${_comments.length == 1 ? '' : 's'}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              if (_comments.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'Be the first to say something.',
                    style: TextStyle(
                        fontSize: 14, color: scheme.onSurfaceVariant),
                  ),
                ),
              for (final c in _comments)
                CommentTile(
                  key: ValueKey('comment-${c.id}'),
                  comment: c,
                  iOwnThePost: iOwnThePost,
                  onReply: () => _startReply(c),
                  onDelete: () => _deleteComment(c.id),
                  onDeleteReply: _deleteComment,
                  onReport: () => _reportComment(c.id),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _composer(BuildContext context, bool signedIn) {
    final scheme = Theme.of(context).colorScheme;

    if (!signedIn) {
      return Material(
        color: scheme.surfaceContainerHighest,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Sign in to join the conversation.',
                    style: TextStyle(
                        fontSize: 14, color: scheme.onSurfaceVariant),
                  ),
                ),
                FilledButton(
                  onPressed: () => context
                      .push('/sign-in?next=/feed/${widget.postId}'),
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final replyingTo = _replyingTo;
    final left = charactersLeft(_reply.text, kCommentBodyMax);
    final tooLong = left < 0;

    return Material(
      color: scheme.surface,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: ContentWidth.reading(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (replyingTo != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Replying to '
                          '${replyingTo.author?.name ?? 'this comment'}',
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurfaceVariant),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel the reply',
                        iconSize: 18,
                        onPressed: () => setState(() => _replyingTo = null),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _reply,
                        focusNode: _replyFocus,
                        minLines: 1,
                        maxLines: 5,
                        enabled: !_sending,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: replyingTo == null
                              ? 'Add a comment'
                              : 'Write your reply',
                          counterText: '',
                          errorText: tooLong
                              ? '${-left} characters too many'
                              : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: 'Send',
                      onPressed: _sending || tooLong || _reply.text.trim().isEmpty
                          ? null
                          : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      style: IconButton.styleFrom(
                          minimumSize: const Size(48, 48)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One comment, with its replies underneath.
class CommentTile extends ConsumerStatefulWidget {
  const CommentTile({
    super.key,
    required this.comment,
    required this.iOwnThePost,
    required this.onReply,
    required this.onDelete,
    required this.onDeleteReply,
    required this.onReport,
  });

  final PostCommentItem comment;

  /// The post's author may delete any comment on it.
  final bool iOwnThePost;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final void Function(String replyId) onDeleteReply;
  final VoidCallback onReport;

  @override
  ConsumerState<CommentTile> createState() => _CommentTileState();
}

class _CommentTileState extends ConsumerState<CommentTile> {
  late ReactionKind? _mine = widget.comment.myReaction;
  late int _reactions = widget.comment.reactions;

  @override
  void didUpdateWidget(CommentTile old) {
    super.didUpdateWidget(old);
    if (old.comment != widget.comment) {
      _mine = widget.comment.myReaction;
      _reactions = widget.comment.reactions;
    }
  }

  /// Comment reactions are a plain row through RLS; there is no RPC for
  /// them, so the count here is what the app knows until the next reload.
  Future<void> _toggle() async {
    final was = _mine;
    final now = toggledReaction(was, ReactionKind.like);
    setState(() {
      _mine = now;
      _reactions = reactionCountAfter(_reactions, was, now);
    });
    try {
      await ref
          .read(networkRepositoryProvider)
          .reactToComment(widget.comment.id, now);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _mine = was;
        _reactions = widget.comment.reactions;
      });
      networkSnack(context, networkError(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.comment;
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(networkClockProvider)();
    final canDelete =
        canDeleteComment(mine: c.mine, iOwnThePost: widget.iOwnThePost);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CommentBody(
            author: c.author,
            body: c.body,
            time: postTime(c.createdAt, now),
            edited: c.editedAt != null,
            radius: 18,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 48, top: 2),
            // A Wrap, not a Row: three buttons do not fit side by side on a
            // 320px phone, and a comment thread is already indented.
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _toggle,
                  icon: Icon(
                    _mine == null
                        ? Icons.thumb_up_alt_outlined
                        : Icons.thumb_up_alt,
                    size: 16,
                  ),
                  label: Text(_reactions > 0 ? 'Like · $_reactions' : 'Like'),
                  style: _barStyle(),
                ),
                TextButton(
                  onPressed: widget.onReply,
                  style: _barStyle(),
                  child: const Text('Reply'),
                ),
                if (canDelete)
                  TextButton(
                    onPressed: widget.onDelete,
                    style: _barStyle(color: OmeloTheme.danger),
                    child: const Text('Delete'),
                  )
                else
                  TextButton(
                    onPressed: widget.onReport,
                    style: _barStyle(),
                    child: const Text('Report'),
                  ),
              ],
            ),
          ),
          for (final r in c.thread)
            Padding(
              padding: const EdgeInsets.only(left: 36, top: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CommentBody(
                    author: r.author,
                    body: r.body,
                    time: postTime(r.createdAt, now),
                    edited: false,
                    radius: 14,
                  ),
                  if (r.mine || widget.iOwnThePost)
                    Padding(
                      padding: const EdgeInsets.only(left: 40),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () => widget.onDeleteReply(r.id),
                          style: _barStyle(color: OmeloTheme.danger),
                          child: const Text('Delete'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // The server counts replies that were later deleted, so the two
          // can differ; saying so beats a silent gap.
          if (c.replyCount > c.thread.length)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 6),
              child: Text(
                '${c.replyCount - c.thread.length} more '
                'repl${c.replyCount - c.thread.length == 1 ? 'y was' : 'ies were'} '
                'deleted',
                style:
                    TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }

  ButtonStyle _barStyle({Color? color}) => TextButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      );
}

class _CommentBody extends StatelessWidget {
  const _CommentBody({
    required this.author,
    required this.body,
    required this.time,
    required this.edited,
    required this.radius,
  });

  final PostAuthor? author;
  final String body;
  final String time;
  final bool edited;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (author != null)
          NetworkAvatar(author: author!, radius: radius)
        else
          CircleAvatar(
            radius: radius,
            backgroundColor: scheme.surfaceContainerHighest,
            child: Icon(Icons.person_outline,
                size: radius, color: scheme.onSurfaceVariant),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        author?.name ?? 'Someone who is no longer on Omelo',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                    if (author?.verified == true) ...[
                      const SizedBox(width: 5),
                      const Icon(Icons.verified,
                          size: 14,
                          color: OmeloTheme.verified,
                          semanticLabel: 'Verified'),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      edited ? '$time · edited' : time,
                      style: TextStyle(
                          fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(fontSize: 14.5, height: 1.4)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
