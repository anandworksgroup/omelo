import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../data/job.dart';
import '../../data/job_events.dart';
import '../../data/saved_jobs_repository.dart';
import 'job_card.dart';

/// A [JobCard] in a list that records the funnel: an impression once it is
/// really on screen, a click when tapped, a save when bookmarked. Tapping
/// opens the job page with the surface and rank, so the page records its
/// view against the right list.
class TrackedJobCard extends ConsumerWidget {
  const TrackedJobCard({
    super.key,
    required this.job,
    required this.surface,
    required this.rank,
  });

  final Job job;
  final JobSurface surface;

  /// 1-based position in the list.
  final int rank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn = ref.watch(isSignedInProvider);
    final saved = signedIn &&
        (ref.watch(savedJobIdsProvider).value?.contains(job.id) ?? false);

    return TrackImpression(
      onSeen: () => trackJobEvent(
          ref, job.id, JobEventType.impression, surface,
          rank: rank),
      child: JobCard(
        job: job,
        saved: saved,
        onTap: () {
          trackJobEvent(ref, job.id, JobEventType.click, surface, rank: rank);
          context.push(jobRoute(job.id, surface, rank: rank));
        },
        onSave: signedIn
            ? () => toggleSavedJob(context, ref, job.id, surface, rank: rank)
            : null,
      ),
    );
  }
}

/// Saves or un-saves a job, records the save, and says what happened.
Future<void> toggleSavedJob(
  BuildContext context,
  WidgetRef ref,
  String jobId,
  JobSurface surface, {
  int? rank,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  void say(String text) {
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  try {
    final nowSaved =
        await ref.read(savedJobIdsProvider.notifier).toggle(jobId);
    if (nowSaved) {
      trackJobEvent(ref, jobId, JobEventType.save, surface, rank: rank);
    }
    say(nowSaved ? 'Saved. Find it in Profile > Saved jobs.' : 'Removed from saved jobs.');
  } catch (_) {
    say('Could not save it. Check your connection and try again.');
  }
}

/// Calls [onSeen] once, the first time at least half of [child] (or 120 px
/// of it, for a tall card) is inside the window. Rebuilds and scrolling
/// back do not call it again; the tracker also de-duplicates per session.
class TrackImpression extends StatefulWidget {
  const TrackImpression({super.key, required this.onSeen, required this.child});
  final VoidCallback onSeen;
  final Widget child;

  @override
  State<TrackImpression> createState() => _TrackImpressionState();
}

class _TrackImpressionState extends State<TrackImpression> {
  ScrollPosition? _position;
  bool _seen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final p = Scrollable.maybeOf(context)?.position;
    if (p != _position) {
      _position?.removeListener(_check);
      _position = p;
      _position?.addListener(_check);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  @override
  void dispose() {
    _position?.removeListener(_check);
    super.dispose();
  }

  void _check() {
    if (_seen || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final size = box.size;
    if (size.height <= 0) return;
    final top = box.localToGlobal(Offset.zero).dy;
    final window = MediaQuery.sizeOf(context).height;
    final visible =
        (top + size.height).clamp(0.0, window) - top.clamp(0.0, window);
    final needed = size.height / 2 < 120 ? size.height / 2 : 120.0;
    if (visible >= needed) {
      _seen = true;
      _position?.removeListener(_check);
      widget.onSeen();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
