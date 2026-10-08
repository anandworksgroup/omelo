import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/global.dart' show safeLink;
import '../../data/job_events.dart' show JobSurface, jobRoute;
import '../../data/network_repository.dart';
import 'network_widgets.dart';

/// What a post card can be asked to do. The card itself owns nothing: the
/// screen around it holds the list and decides what a change means.
class PostActions {
  const PostActions({
    this.onChanged,
    this.onRemoved,
    this.onOpen,
    this.onComment,
  });

  /// The server accepted a change and sent back a fresh card.
  final void Function(FeedPost post)? onChanged;

  /// Deleted, muted or blocked: take it off the list.
  final void Function(String postId)? onRemoved;

  /// Tapping the body opens the post with its comments.
  final void Function(FeedPost post)? onOpen;

  /// Tapping "Comment" opens the post with the reply box focused.
  final void Function(FeedPost post)? onComment;
}

/// One post, as it appears in the feed, on a profile and on an
/// organization's page.
class PostCard extends ConsumerStatefulWidget {
  const PostCard({
    super.key,
    required this.post,
    this.actions = const PostActions(),
    this.showWhy = true,
    this.expanded = false,
  });

  final FeedPost post;
  final PostActions actions;

  /// The "why" line only belongs in the feed; on a profile the answer is
  /// obvious.
  final bool showWhy;

  /// Post detail shows the whole body from the start.
  final bool expanded;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  late FeedPost _post = widget.post;
  late bool _showAll = widget.expanded;
  bool _busy = false;

  @override
  void didUpdateWidget(PostCard old) {
    super.didUpdateWidget(old);
    if (old.post != widget.post) _post = widget.post;
  }

  void _update(FeedPost p) {
    if (!mounted) return;
    setState(() => _post = p);
    widget.actions.onChanged?.call(p);
  }

  NetworkRepository get _repo => ref.read(networkRepositoryProvider);

  // -- Actions ---------------------------------------------------------------

  Future<void> _react(ReactionKind tapped) async {
    final was = _post.my.reaction;
    final now = toggledReaction(was, tapped);
    // Flip at once: a reaction that waits for the network feels broken.
    _update(_post.copyWith(
      my: now == null
          ? _post.my.copyWith(clearReaction: true)
          : _post.my.copyWith(reaction: now),
      engagement: _post.engagement.copyWith(
        reactions: reactionCountAfter(_post.engagement.reactions, was, now),
      ),
    ));
    try {
      await _repo.react(_post.id, now);
    } catch (e) {
      _update(widget.post.copyWith(my: _post.my.copyWith(reaction: was)));
      if (mounted) networkSnack(context, networkError(e));
    }
  }

  Future<void> _pickReaction() async {
    final picked = await showModalBottomSheet<ReactionKind>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final k in ReactionKind.values)
              ListTile(
                leading: Icon(reactionIcon(k), color: reactionColor(context, k)),
                title: Text(k.label),
                trailing: _post.my.reaction == k
                    ? const Icon(Icons.check)
                    : null,
                onTap: () => Navigator.of(context).pop(k),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked != null) await _react(picked);
  }

  Future<void> _toggleSave() async {
    final want = !_post.my.saved;
    _update(_post.copyWith(
      my: _post.my.copyWith(saved: want),
      engagement: _post.engagement.copyWith(
        reactions: _post.engagement.reactions,
        saves: want
            ? _post.engagement.saves + 1
            : (_post.engagement.saves > 0 ? _post.engagement.saves - 1 : 0),
      ),
    ));
    try {
      await _repo.savePost(_post.id, want);
      if (mounted) {
        networkSnack(context, want ? 'Saved to your feed.' : 'Removed from saved.');
      }
    } catch (e) {
      _update(widget.post);
      if (mounted) networkSnack(context, networkError(e));
    }
  }

  Future<void> _share() async {
    final result = await showSharePostSheet(context, _post);
    if (result == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await _repo.sharePost(
        _post.id,
        body: result.body,
        visibility: result.visibility,
      );
      if (!mounted) return;
      _update(_post.copyWith(
        engagement:
            _post.engagement.copyWith(shares: _post.engagement.shares + 1),
      ));
      networkSnack(context, 'Shared.');
    } catch (e) {
      if (mounted) networkSnack(context, networkError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final yes = await confirmNetworkAction(
      context,
      title: 'Delete this post?',
      body: 'It disappears from every feed. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!yes || !mounted) return;
    try {
      await _repo.deletePost(_post.id);
      if (!mounted) return;
      widget.actions.onRemoved?.call(_post.id);
      networkSnack(context, 'Post deleted.');
    } catch (e) {
      if (mounted) networkSnack(context, networkError(e));
    }
  }

  Future<void> _edit() async {
    final updated = await context.push<FeedPost>('/feed/${_post.id}/edit',
        extra: _post);
    if (updated != null) _update(updated);
  }

  Future<void> _mute(PostAuthor author) async {
    try {
      await _repo.mute(
        author.isOrganization ? MuteTarget.company : MuteTarget.person,
        author.id,
      );
      if (!mounted) return;
      widget.actions.onRemoved?.call(_post.id);
      networkSnack(context, 'You will not see ${author.name} in your feed.');
    } catch (e) {
      if (mounted) networkSnack(context, networkError(e));
    }
  }

  Future<void> _report() async {
    final answer = await askReport(context, what: 'post');
    if (answer == null || !mounted) return;
    try {
      await _repo.report(
        subject: ReportSubject.post,
        subjectId: _post.id,
        reason: answer.reason,
        details: answer.details,
      );
      if (mounted) networkSnack(context, 'Reported. Omelo will look at it.');
    } catch (e) {
      if (mounted) networkSnack(context, networkError(e));
    }
  }

  Future<void> _block(PostAuthor author) async {
    if (!await confirmBlock(context, author) || !mounted) return;
    try {
      await _repo.block(
        author.isOrganization ? BlockTarget.company : BlockTarget.person,
        author.id,
      );
      if (!mounted) return;
      widget.actions.onRemoved?.call(_post.id);
      networkSnack(context, '${author.name} is blocked.');
    } catch (e) {
      if (mounted) networkSnack(context, networkError(e));
    }
  }

  // -- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(networkClockProvider)();
    final author = _post.author;
    final why = _post.why;

    return Card(
      key: ValueKey('post-${_post.id}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showWhy && why != null) ...[
              Row(
                children: [
                  Icon(Icons.auto_awesome,
                      size: 13, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      why,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            if (author != null)
              AuthorRow(
                author: author,
                secondary: _secondaryLine(author, now),
                onTap: () => context.push(author.route),
                trailing: _overflow(author),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text('Someone who is no longer on Omelo',
                        style: TextStyle(
                            fontSize: 14.5, color: scheme.onSurfaceVariant)),
                  ),
                  _overflow(null),
                ],
              ),
            if (_post.hasBody) ...[
              const SizedBox(height: 10),
              _Body(
                text: _post.body!,
                showAll: _showAll,
                onShowAll: () => setState(() => _showAll = true),
              ),
            ],
            if (_post.media.isNotEmpty) ...[
              const SizedBox(height: 10),
              PostMediaView(media: _post.media),
            ],
            if (_post.job != null) ...[
              const SizedBox(height: 10),
              PostJobCard(job: _post.job!),
            ],
            if (_post.quoted != null) ...[
              const SizedBox(height: 10),
              QuotedPostCard(quoted: _post.quoted!),
            ],
            const SizedBox(height: 8),
            _counts(scheme),
            Divider(height: 14, color: scheme.outlineVariant),
            _actionBar(),
          ],
        ),
      ),
    );
  }

  String _secondaryLine(PostAuthor author, DateTime now) {
    final bits = <String>[
      if (!author.isOrganization && author.headline != null) author.headline!,
      if (author.isOrganization && author.organizationType != null)
        organizationTypeWords(author.organizationType),
      postTime(_post.createdAt, now),
      if (_post.isEdited) 'edited',
      visibilityWord(_post.visibility),
    ];
    return bits.where((b) => b.isNotEmpty).join(' · ');
  }

  Widget _counts(ColorScheme scheme) {
    final e = _post.engagement;
    final bits = [
      ?countWords(e.reactions, 'reaction', 'reactions'),
      ?countWords(e.comments, 'comment', 'comments'),
      ?countWords(e.shares, 'share', 'shares'),
    ];
    if (bits.isEmpty) return const SizedBox(height: 2);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        bits.join(' · '),
        style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _actionBar() {
    final mine = _post.my.reaction;
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: reactionIcon(mine ?? ReactionKind.like),
            label: mine?.chosenLabel ?? 'Like',
            active: mine != null,
            activeColor: mine == null ? null : reactionColor(context, mine),
            onPressed: _busy ? null : () => _react(mine ?? ReactionKind.like),
            onLongPress: _pickReaction,
            tooltip: 'React — hold for more reactions',
          ),
        ),
        Expanded(
          child: _ActionButton(
            icon: Icons.mode_comment_outlined,
            label: 'Comment',
            onPressed: _busy
                ? null
                : () => (widget.actions.onComment ?? widget.actions.onOpen)
                    ?.call(_post),
          ),
        ),
        Expanded(
          child: _ActionButton(
            icon: Icons.repeat,
            label: 'Share',
            // Only a public post may be shared on; the server refuses the
            // rest, so the button says so before the tap.
            onPressed: _busy || _post.visibility != PostVisibility.public
                ? null
                : _share,
            tooltip: _post.visibility == PostVisibility.public
                ? 'Share this post'
                : 'Only a public post can be shared',
          ),
        ),
        Expanded(
          child: _ActionButton(
            icon: _post.my.saved ? Icons.bookmark : Icons.bookmark_border,
            label: _post.my.saved ? 'Saved' : 'Save',
            active: _post.my.saved,
            onPressed: _busy ? null : _toggleSave,
          ),
        ),
      ],
    );
  }

  Widget _overflow(PostAuthor? author) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      icon: const Icon(Icons.more_horiz),
      onSelected: (v) {
        switch (v) {
          case 'save':
            _toggleSave();
          case 'open':
            widget.actions.onOpen?.call(_post);
          case 'edit':
            _edit();
          case 'delete':
            _delete();
          case 'mute':
            if (author != null) _mute(author);
          case 'report':
            _report();
          case 'block':
            if (author != null) _block(author);
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'save',
          child: _menuRow(
            _post.my.saved ? Icons.bookmark : Icons.bookmark_border,
            _post.my.saved ? 'Remove from saved' : 'Save this post',
          ),
        ),
        if (!widget.expanded && widget.actions.onOpen != null)
          PopupMenuItem(
            value: 'open',
            child: _menuRow(Icons.open_in_new, 'Open the post'),
          ),
        if (_post.canEdit)
          PopupMenuItem(
            value: 'edit',
            child: _menuRow(Icons.edit_outlined, 'Edit'),
          ),
        if (_post.my.mine)
          PopupMenuItem(
            value: 'delete',
            child: _menuRow(Icons.delete_outline, 'Delete', danger: true),
          ),
        if (!_post.my.mine && author != null) ...[
          PopupMenuItem(
            value: 'mute',
            child: _menuRow(
              Icons.visibility_off_outlined,
              author.isOrganization
                  ? 'Mute this organization'
                  : 'Mute this person',
            ),
          ),
          PopupMenuItem(
            value: 'report',
            child: _menuRow(Icons.flag_outlined, 'Report this post'),
          ),
          PopupMenuItem(
            value: 'block',
            child: _menuRow(Icons.block, 'Block ${author.name}', danger: true),
          ),
        ],
      ],
    );
  }

  Widget _menuRow(IconData icon, String label, {bool danger = false}) {
    final color = danger ? OmeloTheme.danger : null;
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14.5, color: color)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

/// "Public" · "Followers only" · "Connections only" — the word next to the
/// time, so the author can see who they wrote to.
String visibilityWord(PostVisibility v) => switch (v) {
      PostVisibility.public => 'Public',
      PostVisibility.followers => 'Followers',
      PostVisibility.connections => 'Connections',
    };

String organizationTypeWords(String? t) => switch (t) {
      'employer' => 'Employer',
      'staffing_agency' => 'Staffing agency',
      'recruitment_agency' => 'Recruitment agency',
      'training_provider' => 'Training provider',
      null => '',
      _ => t.replaceAll('_', ' '),
    };

IconData reactionIcon(ReactionKind k) => switch (k) {
      ReactionKind.like => Icons.thumb_up_alt_outlined,
      ReactionKind.celebrate => Icons.celebration_outlined,
      ReactionKind.support => Icons.volunteer_activism_outlined,
      ReactionKind.insightful => Icons.lightbulb_outline,
      ReactionKind.curious => Icons.help_outline,
    };

Color reactionColor(BuildContext context, ReactionKind k) {
  final scheme = Theme.of(context).colorScheme;
  return switch (k) {
    ReactionKind.like => scheme.primary,
    ReactionKind.celebrate => OmeloTheme.accent,
    ReactionKind.support => OmeloTheme.verified,
    ReactionKind.insightful => OmeloTheme.warning,
    ReactionKind.curious => scheme.tertiary,
  };
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.onLongPress,
    this.active = false,
    this.activeColor,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool active;
  final Color? activeColor;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active
        ? (activeColor ?? scheme.primary)
        : scheme.onSurfaceVariant;
    final button = InkWell(
      onTap: onPressed,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(10),
      child: ConstrainedBox(
        // 44dp minimum target, UC-9.
        constraints: const BoxConstraints(minHeight: 44),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: onPressed == null
                ? scheme.outline
                : color),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: onPressed == null ? scheme.outline : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// The words, trimmed to [kPostBodyLines] lines until "See more" is tapped.
class _Body extends StatelessWidget {
  const _Body({
    required this.text,
    required this.showAll,
    required this.onShowAll,
  });

  final String text;
  final bool showAll;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 15, height: 1.45);
    if (showAll) {
      return SelectionArea(child: Text(text, style: style));
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: kPostBodyLines,
          textDirection: Directionality.of(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              maxLines: overflows ? kPostBodyLines : null,
              overflow: overflows ? TextOverflow.ellipsis : TextOverflow.clip,
              style: style,
            ),
            if (overflows)
              TextButton(
                onPressed: onShowAll,
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 36),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  alignment: Alignment.centerLeft,
                ),
                child: const Text('See more'),
              ),
          ],
        );
      },
    );
  }
}

/// Photos in a grid, video with a play control. One item fills the width;
/// more share it.
class PostMediaView extends ConsumerWidget {
  const PostMediaView({super.key, required this.media, this.compact = false});

  final List<PostMedia> media;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (media.isEmpty) return const SizedBox.shrink();
    final url = ref.watch(mediaUrlProvider);

    if (media.length == 1) {
      final m = media.first;
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: AspectRatio(
          aspectRatio: m.aspectRatio.clamp(0.6, 2.2),
          child: _Tile(media: m, url: url(m.path), all: media, index: 0),
        ),
      );
    }

    final columns = media.length == 2 ? 2 : (compact ? 2 : 3);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: media.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemBuilder: (context, i) => ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: _Tile(
          media: media[i],
          url: url(media[i].path),
          all: media,
          index: i,
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.media,
    required this.url,
    required this.all,
    required this.index,
  });

  final PostMedia media;
  final String url;
  final List<PostMedia> all;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final body = media.isVideo
        ? Container(
            color: scheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.play_circle_fill,
                    size: 52, color: scheme.onSurfaceVariant),
                if (media.durationLabel != null) ...[
                  const SizedBox(height: 6),
                  Text(media.durationLabel!,
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
          )
        : Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : Container(
                    color: scheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
            errorBuilder: (_, __, ___) => Container(
              color: scheme.surfaceContainerHighest,
              alignment: Alignment.center,
              child: Icon(Icons.broken_image_outlined,
                  color: scheme.onSurfaceVariant),
            ),
          );

    return Semantics(
      label: media.semanticLabel,
      button: true,
      child: InkWell(
        onTap: () => media.isVideo
            ? _playVideo(context, url)
            : _openViewer(context, all, index),
        child: body,
      ),
    );
  }

  /// Omelo does not bundle a video player, so a video opens in the device's
  /// own player. Saying so beats a play button that does nothing.
  Future<void> _playVideo(BuildContext context, String url) async {
    final link = safeLink(url);
    if (link == null) {
      networkSnack(context, 'That video is not available.');
      return;
    }
    final ok = await launchUrl(link, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      networkSnack(context, 'Could not open the video.');
    }
  }

  void _openViewer(BuildContext context, List<PostMedia> all, int index) {
    Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => MediaViewerScreen(media: all, initialIndex: index),
    ));
  }
}

/// Full-screen photos, swiped left and right.
class MediaViewerScreen extends ConsumerStatefulWidget {
  const MediaViewerScreen({
    super.key,
    required this.media,
    this.initialIndex = 0,
  });

  final List<PostMedia> media;
  final int initialIndex;

  @override
  ConsumerState<MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends ConsumerState<MediaViewerScreen> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final url = ref.watch(mediaUrlProvider);
    final current = widget.media[_index];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.media.length == 1
            ? 'Photo'
            : '${_index + 1} of ${widget.media.length}'),
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pages,
              itemCount: widget.media.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Semantics(
                    label: widget.media[i].semanticLabel,
                    image: true,
                    child: Image.network(
                      url(widget.media[i].path),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          size: 48,
                          color: Colors.white54),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (current.altText != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Text(
                current.altText!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13.5),
              ),
            ),
        ],
      ),
    );
  }
}

/// The job attached to a post. Pay stays in the job's own currency.
class PostJobCard extends StatelessWidget {
  const PostJobCard({super.key, required this.job});
  final PostJob job;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final place = job.placeLine;
    final shape = [
      if (job.workplaceType != null) Fmt.workplace(job.workplaceType),
      if (job.workType != null) Fmt.workType(job.workType),
    ].where((s) => s.isNotEmpty).join(' · ');

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () =>
            context.push(jobRoute(job.id, JobSurface.recommended)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.work_outline, size: 22, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(job.title,
                        style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            height: 1.25)),
                    if (job.company != null) ...[
                      const SizedBox(height: 2),
                      Text(job.company!,
                          style: TextStyle(
                              fontSize: 13.5, color: scheme.onSurfaceVariant)),
                    ],
                    if (place.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(place,
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant)),
                    ],
                    if (shape.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(shape,
                          style: TextStyle(
                              fontSize: 13, color: scheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 6),
                    Text(job.payLine,
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w800)),
                    if (!job.isOpen) ...[
                      const SizedBox(height: 6),
                      const OmeloPill('No longer taking applications',
                          icon: Icons.lock_clock),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

/// The original post inside a share.
class QuotedPostCard extends ConsumerWidget {
  const QuotedPostCard({super.key, required this.quoted});
  final QuotedPost quoted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(networkClockProvider)();
    final author = quoted.author;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.push('/feed/${quoted.id}'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (author != null)
                  AuthorRow(
                    author: author,
                    radius: 16,
                    dense: true,
                    secondary: [
                      if (!author.isOrganization && author.headline != null)
                        author.headline!,
                      if (quoted.createdAt != null)
                        postTime(quoted.createdAt!, now),
                    ].join(' · '),
                  )
                else
                  Text('A post that is no longer available',
                      style: TextStyle(
                          fontSize: 13.5, color: scheme.onSurfaceVariant)),
                if ((quoted.body ?? '').trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    quoted.body!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, height: 1.4),
                  ),
                ],
                if (quoted.media.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  PostMediaView(media: quoted.media, compact: true),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a share will say and who will see it.
typedef ShareChoice = ({String body, PostVisibility visibility});

Future<ShareChoice?> showSharePostSheet(
  BuildContext context,
  FeedPost post,
) {
  final controller = TextEditingController();
  var visibility = PostVisibility.public;

  return showModalBottomSheet<ShareChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Share this post',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 4,
              minLines: 2,
              maxLength: kPostBodyMax,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'Say something about it (optional)',
              ),
            ),
            const SizedBox(height: 4),
            VisibilityPicker(
              value: visibility,
              onChanged: (v) => setState(() => visibility = v),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                (body: controller.text.trim(), visibility: visibility),
              ),
              child: const Text('Share'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    ),
  );
}

/// Public / Followers / Connections, each with the plain sentence that says
/// who can read it.
class VisibilityPicker extends StatelessWidget {
  const VisibilityPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final PostVisibility value;
  final ValueChanged<PostVisibility> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final v in PostVisibility.values)
                ChoiceChip(
                  label: Text(v.label),
                  selected: value == v,
                  onSelected: (_) => onChanged(v),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value.description,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
