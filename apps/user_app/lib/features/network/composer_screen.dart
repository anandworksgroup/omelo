import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/media_picker.dart';
import '../../data/network_repository.dart';
import 'network_widgets.dart';
import 'post_card.dart' show PostJobCard, VisibilityPicker;

/// `/feed/compose` and `/feed/:id/edit` — writing a post, and editing one.
///
/// Editing only changes the words and who may read them: the server keeps a
/// post's media, its job and its author for good, and the screen says so
/// rather than offering a control that would be ignored.
class ComposerScreen extends ConsumerStatefulWidget {
  const ComposerScreen({super.key, this.editing});

  /// The post being edited, when there is one.
  final FeedPost? editing;

  @override
  ConsumerState<ComposerScreen> createState() => _ComposerScreenState();
}

class _ComposerScreenState extends ConsumerState<ComposerScreen> {
  final _body = TextEditingController();
  final _focus = FocusNode();

  late PostVisibility _visibility =
      widget.editing?.visibility ?? PostVisibility.public;

  final _media = <PickedMedia>[];
  PostJob? _job;

  bool _sending = false;

  /// How many files have finished, out of how many: an honest progress bar
  /// for an upload the server gives no byte counts for.
  int _uploaded = 0;
  int _uploading = 0;

  String? _error;

  bool get _isEdit => widget.editing != null;

  @override
  void initState() {
    super.initState();
    final post = widget.editing;
    if (post != null) {
      _body.text = post.body ?? '';
      _job = post.job;
    }
    _body.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _body.dispose();
    _focus.dispose();
    super.dispose();
  }

  // -- Attachments -----------------------------------------------------------

  bool get _hasVideo => _media.any((m) => m.isVideo);

  Future<void> _pick({required bool video}) async {
    if (_media.length >= kPostMediaMax) {
      networkSnack(context, 'A post takes at most $kPostMediaMax items.');
      return;
    }
    try {
      final picked =
          await ref.read(mediaChooserProvider)(video: video);
      if (!mounted || picked.isEmpty) return;
      setState(() {
        for (final m in picked) {
          if (_media.length >= kPostMediaMax) break;
          // One video per post: mixing a video with photos has no sensible
          // layout, and the server orders them by position either way.
          if (m.isVideo && _media.isNotEmpty) continue;
          if (!m.isVideo && _hasVideo) continue;
          _media.add(m);
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) networkSnack(context, networkError(e));
    }
  }

  Future<void> _describe(int index) async {
    final controller = TextEditingController(text: _media[index].altText ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Describe this for people who cannot see it'),
        content: TextField(
          controller: controller,
          maxLength: 300,
          maxLines: 3,
          minLines: 2,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Two electricians wiring a panel on site.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (text == null || !mounted) return;
    setState(() => _media[index] = _media[index].withAltText(text));
  }

  Future<void> _pickJob() async {
    final job = await showJobPicker(context, ref);
    if (job == null || !mounted) return;
    setState(() {
      _job = job;
      _error = null;
    });
  }

  // -- Sending ---------------------------------------------------------------

  Future<void> _send() async {
    final problem = validatePostBody(
      _body.text,
      hasMedia: _media.isNotEmpty || (widget.editing?.media.isNotEmpty ?? false),
      hasJob: _job != null,
      hasSharedPost: widget.editing?.quoted != null,
    );
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
      _uploaded = 0;
      _uploading = _isEdit ? 0 : _media.length;
    });

    final repo = ref.read(networkRepositoryProvider);
    try {
      if (_isEdit) {
        final updated = await repo.updatePost(
          widget.editing!.id,
          PostDraft(body: _body.text, visibility: _visibility),
        );
        if (!mounted) return;
        context.pop(updated);
        return;
      }

      final uploaded = <UploadedMedia>[];
      for (var i = 0; i < _media.length; i++) {
        uploaded.add(await repo.uploadMedia(_media[i], index: i));
        if (!mounted) return;
        setState(() => _uploaded = i + 1);
      }

      final post = await repo.createPost(PostDraft(
        body: _body.text,
        visibility: _visibility,
        jobId: _job?.id,
        media: uploaded,
      ));
      if (!mounted) return;
      context.pop(post);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = networkError(e);
      });
    }
  }

  // -- Build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final left = charactersLeft(_body.text, kPostBodyMax);
    final tooLong = left < 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Edit post' : 'New post'),
        leading: networkBackButton(context, '/feed'),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: FilledButton(
              onPressed: _sending || tooLong ? null : _send,
              style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
              child: Text(_isEdit ? 'Save' : 'Post'),
            ),
          ),
        ],
      ),
      body: ContentWidth.reading(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
              Breakpoints.of(context).gutter, 12,
              Breakpoints.of(context).gutter, 32),
          children: [
            if (_error != null) ...[
              _Banner(text: _error!),
              const SizedBox(height: 14),
            ],
            TextField(
              controller: _body,
              focusNode: _focus,
              autofocus: !_isEdit,
              enabled: !_sending,
              minLines: 6,
              maxLines: 20,
              textCapitalization: TextCapitalization.sentences,
              keyboardType: TextInputType.multiline,
              decoration: const InputDecoration(
                hintText: 'What do you want your network to know?',
                counterText: '',
              ),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                '$left',
                semanticsLabel: tooLong
                    ? '${-left} characters too many'
                    : '$left characters left',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: tooLong ? FontWeight.w800 : FontWeight.w600,
                  color: tooLong ? OmeloTheme.danger : scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 10),
            VisibilityPicker(
              value: _visibility,
              onChanged: _sending
                  ? (_) {}
                  : (v) => setState(() => _visibility = v),
            ),

            if (_isEdit) ...[
              const SizedBox(height: 18),
              Text(
                'Photos, video and an attached job stay as they were. To '
                'change them, delete this post and write a new one.',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              if (widget.editing!.media.isNotEmpty) ...[
                const SizedBox(height: 12),
                PostMediaViewReadOnly(media: widget.editing!.media),
              ],
            ] else ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ActionChip(
                    avatar: const Icon(Icons.image_outlined, size: 18),
                    label: const Text('Add photos'),
                    onPressed:
                        _sending || _hasVideo ? null : () => _pick(video: false),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.videocam_outlined, size: 18),
                    label: const Text('Add a video'),
                    onPressed: _sending || _media.isNotEmpty
                        ? null
                        : () => _pick(video: true),
                  ),
                  ActionChip(
                    avatar: const Icon(Icons.work_outline, size: 18),
                    label: Text(_job == null ? 'Attach a job' : 'Change the job'),
                    onPressed: _sending ? null : _pickJob,
                  ),
                ],
              ),
            ],

            if (_media.isNotEmpty) ...[
              const SizedBox(height: 14),
              _Attachments(
                media: _media,
                busy: _sending,
                onDescribe: _describe,
                onRemove: (i) => setState(() => _media.removeAt(i)),
              ),
            ],

            if (_job != null) ...[
              const SizedBox(height: 14),
              PostJobCard(job: _job!),
              if (!_isEdit)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _sending ? null : () => setState(() => _job = null),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Remove the job'),
                  ),
                ),
            ],

            if (_sending && _uploading > 0) ...[
              const SizedBox(height: 20),
              _UploadProgress(done: _uploaded, total: _uploading),
            ] else if (_sending) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 14, height: 1.4, color: scheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}

class _UploadProgress extends StatelessWidget {
  const _UploadProgress({required this.done, required this.total});
  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = done >= total
        ? 'Posting…'
        : 'Uploading ${done + 1} of $total…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label,
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: total == 0 ? null : done / total,
          semanticsLabel: 'Upload progress',
        ),
      ],
    );
  }
}

/// Thumbnails of what will be uploaded, each with a way to describe it or
/// take it off again.
class _Attachments extends StatelessWidget {
  const _Attachments({
    required this.media,
    required this.busy,
    required this.onDescribe,
    required this.onRemove,
  });

  final List<PickedMedia> media;
  final bool busy;
  final void Function(int index) onDescribe;
  final void Function(int index) onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < media.length; i++)
          SizedBox(
            width: 104,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        height: 96,
                        width: 104,
                        child: media[i].isVideo
                            ? Container(
                                color: scheme.surfaceContainerHighest,
                                alignment: Alignment.center,
                                child: Icon(Icons.play_circle_fill,
                                    size: 36, color: scheme.onSurfaceVariant),
                              )
                            : Image.memory(media[i].bytes, fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 2,
                      right: 2,
                      child: IconButton(
                        tooltip: 'Remove',
                        iconSize: 18,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.black54,
                          foregroundColor: Colors.white,
                          minimumSize: const Size(32, 32),
                        ),
                        onPressed: busy ? null : () => onRemove(i),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: busy ? null : () => onDescribe(i),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: EdgeInsets.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    media[i].altText == null ? 'Describe' : 'Described',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The media already on a post being edited: shown so the author can see
/// what stays, not something they can change.
class PostMediaViewReadOnly extends ConsumerWidget {
  const PostMediaViewReadOnly({super.key, required this.media});
  final List<PostMedia> media;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final url = ref.watch(mediaUrlProvider);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final m in media)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 96,
              height: 96,
              child: m.isVideo
                  ? Container(
                      color: scheme.surfaceContainerHighest,
                      alignment: Alignment.center,
                      child: Icon(Icons.play_circle_fill,
                          size: 32, color: scheme.onSurfaceVariant),
                    )
                  : Image.network(
                      url(m.path),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: scheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: Icon(Icons.broken_image_outlined,
                            color: scheme.onSurfaceVariant),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}

/// Pick a published job to attach. Searching by title keeps the list
/// manageable on a market with thousands of open jobs.
Future<PostJob?> showJobPicker(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<PostJob>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _JobPicker(ref: ref),
  );
}

class _JobPicker extends StatefulWidget {
  const _JobPicker({required this.ref});
  final WidgetRef ref;

  @override
  State<_JobPicker> createState() => _JobPickerState();
}

class _JobPickerState extends State<_JobPicker> {
  final _search = TextEditingController();
  List<PostJob> _jobs = const [];
  bool _loading = true;
  String? _error;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jobs = await widget.ref
          .read(networkRepositoryProvider)
          .jobsToShare(query: _search.text);
      if (!mounted || seq != _seq) return;
      setState(() {
        _jobs = jobs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _loading = false;
        _error = networkError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.7,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Attach a job',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                hintText: 'Job title',
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.arrow_forward),
                  onPressed: _load,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Text(_error!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 14.5)))
                      : _jobs.isEmpty
                          ? Center(
                              child: Text(
                                'No open jobs matched that.',
                                style: TextStyle(
                                    fontSize: 14.5,
                                    color: scheme.onSurfaceVariant),
                              ),
                            )
                          : ListView.separated(
                              itemCount: _jobs.length,
                              separatorBuilder: (_, __) => const Divider(),
                              itemBuilder: (context, i) {
                                final j = _jobs[i];
                                return ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  minTileHeight: 64,
                                  title: Text(j.title,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700)),
                                  subtitle: Text(
                                    [
                                      if (j.company != null) j.company!,
                                      if (j.placeLine.isNotEmpty) j.placeLine,
                                      j.payLine,
                                    ].join(' · '),
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  onTap: () => Navigator.of(context).pop(j),
                                );
                              },
                            ),
            ),
          ],
        ),
      ),
    );
  }
}
