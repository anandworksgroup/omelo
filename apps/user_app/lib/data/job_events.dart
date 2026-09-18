/// Release 3 — funnel tracking.
///
/// Records what a signed-in worker saw and did with each job (impression,
/// view, click, save) and where (the surface), so Omelo can measure which
/// lists lead to applications. The server (`omelo_track_job_events`)
/// de-duplicates, ignores signed-out users and attributes applications on its
/// own; nothing is ever read back.
///
/// Rules:
/// * Fire and forget. Tracking never blocks the UI and never throws into it.
/// * Only while signed in. Anything queued while signed out is dropped.
/// * Batched: sent every [JobEvents.flushEvery], as soon as
///   [JobEvents.batchSize] events are waiting, when the app goes to the
///   background, and just before sign-out.
/// * An impression is recorded once per session per job and surface.
///
/// [JobEvents] itself is pure Dart (sender, clock and timer are injected) so
/// the batching rules are unit tested. The Riverpod wiring is at the bottom.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import 'jobs_repository.dart' show supabaseProvider;

/// Where the worker met the job. Mirrors `match_events.surface`.
enum JobSurface {
  recommended,
  nearby,
  search,
  jobPage('job_page'),
  invitation,
  notification,
  email,
  saved,
  other;

  const JobSurface([this._wire]);
  final String? _wire;

  /// Value sent to the server.
  String get wire => _wire ?? name;

  /// Parses a `?from=` value; anything unknown is [other].
  static JobSurface fromWire(String? v) {
    for (final s in values) {
      if (s.wire == v) return s;
    }
    return other;
  }
}

/// What happened. Mirrors the client-writable `match_events.event` values.
enum JobEventType { impression, view, click, save }

class JobEvent {
  const JobEvent({
    required this.jobId,
    required this.type,
    required this.surface,
    this.rank,
  });

  final String jobId;
  final JobEventType type;
  final JobSurface surface;

  /// 1-based position in the list, when shown in one.
  final int? rank;

  String get key => '${type.name}|$jobId|${surface.wire}';

  Map<String, Object?> toJson() => {
        'job_id': jobId,
        'event': type.name,
        'surface': surface.wire,
        if (rank != null && rank! > 0) 'rank': rank,
      };
}

typedef JobEventSender = Future<void> Function(
    List<Map<String, Object?>> events);
typedef TimerFactory = Timer Function(Duration after, void Function() run);

class JobEvents {
  JobEvents({
    required JobEventSender send,
    required bool Function() isSignedIn,
    DateTime Function()? now,
    TimerFactory? startTimer,
    this.flushEvery = const Duration(seconds: 5),
    this.batchSize = 20,
    this.repeatWindow = const Duration(seconds: 2),
  })  : _send = send,
        _isSignedIn = isSignedIn,
        _now = now ?? DateTime.now,
        _startTimer = startTimer ?? Timer.new;

  final JobEventSender _send;
  final bool Function() _isSignedIn;
  final DateTime Function() _now;
  final TimerFactory _startTimer;

  /// Longest an event waits before it is sent.
  final Duration flushEvery;

  /// Send as soon as this many events are waiting.
  final int batchSize;

  /// The same view / click / save within this window is a double tap.
  final Duration repeatWindow;

  /// Most events one call may carry (server limit).
  static const maxPerCall = 100;

  /// Most events kept waiting; the oldest are dropped past this.
  static const maxQueued = 500;

  final List<JobEvent> _queue = [];
  final Set<String> _impressionsThisSession = {};
  final Map<String, DateTime> _lastSeen = {};
  final Map<String, int> _failures = {};
  Timer? _timer;
  Future<void>? _inFlight;
  bool _disposed = false;

  /// Events waiting to be sent (for tests and debugging).
  List<JobEvent> get pending => List.unmodifiable(_queue);

  void impression(String jobId, JobSurface surface, {int? rank}) =>
      track(JobEvent(
          jobId: jobId,
          type: JobEventType.impression,
          surface: surface,
          rank: rank));

  void view(String jobId, JobSurface surface, {int? rank}) => track(JobEvent(
      jobId: jobId, type: JobEventType.view, surface: surface, rank: rank));

  void click(String jobId, JobSurface surface, {int? rank}) => track(JobEvent(
      jobId: jobId, type: JobEventType.click, surface: surface, rank: rank));

  void save(String jobId, JobSurface surface, {int? rank}) => track(JobEvent(
      jobId: jobId, type: JobEventType.save, surface: surface, rank: rank));

  /// Queues one event. Returns whether it was accepted.
  bool track(JobEvent e) {
    try {
      if (_disposed || e.jobId.isEmpty || !_isSignedIn()) return false;
      if (e.type == JobEventType.impression) {
        if (!_impressionsThisSession.add(e.key)) return false;
      } else {
        final at = _now();
        final last = _lastSeen[e.key];
        if (last != null && at.difference(last) < repeatWindow) return false;
        _lastSeen[e.key] = at;
      }
      _queue.add(e);
      if (_queue.length > maxQueued) {
        _queue.removeRange(0, _queue.length - maxQueued);
      }
      if (_queue.length >= batchSize) {
        unawaited(flush());
      } else {
        _timer ??= _startTimer(flushEvery, () {
          _timer = null;
          unawaited(flush());
        });
      }
      return true;
    } catch (_) {
      return false; // Tracking must never break the screen that called it.
    }
  }

  /// Sends everything waiting. Never throws.
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    // One send at a time; a second call waits for it, then sends the rest.
    while (_inFlight != null) {
      await _inFlight;
    }
    if (_queue.isEmpty) return;
    if (!_isSignedIn()) {
      _queue.clear();
      return;
    }
    final done = Completer<void>();
    _inFlight = done.future;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(maxPerCall).toList();
        _queue.removeRange(0, batch.length);
        try {
          await _send([for (final e in batch) e.toJson()]);
          for (final e in batch) {
            _failures.remove(e.key);
          }
        } catch (_) {
          // Put the batch back once; drop it after a second failure so a
          // broken endpoint cannot grow the queue forever.
          final retry = [
            for (final e in batch)
              if ((_failures[e.key] = (_failures[e.key] ?? 0) + 1) < 2) e,
          ];
          _queue.insertAll(0, retry);
          if (_queue.isNotEmpty && !_disposed) {
            _timer ??= _startTimer(flushEvery, () {
              _timer = null;
              unawaited(flush());
            });
          }
          break;
        }
      }
    } finally {
      _inFlight = null;
      done.complete();
    }
  }

  /// Forget everything: the queue and this session's impressions. Called when
  /// the signed-in person changes, so nothing is sent as the wrong person.
  void reset() {
    _timer?.cancel();
    _timer = null;
    _queue.clear();
    _impressionsThisSession.clear();
    _lastSeen.clear();
    _failures.clear();
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

// ---------------------------------------------------------------------------
// App wiring
// ---------------------------------------------------------------------------

final jobEventsProvider = Provider<JobEvents>((ref) {
  SupabaseClient db() => ref.read(supabaseProvider);
  final events = JobEvents(
    send: (batch) => db().rpc('omelo_track_job_events',
        params: {'p_events': batch}),
    isSignedIn: () {
      try {
        return db().auth.currentUser != null;
      } catch (_) {
        return false;
      }
    },
  );

  // A different person (or nobody) is signed in: start over.
  ref.listen<User?>(currentUserProvider, (before, now) {
    if (before?.id != now?.id) events.reset();
  });

  // Send what is waiting when the app is hidden or paused; the OS may kill
  // it after that.
  final lifecycle = AppLifecycleListener(
    onHide: () => unawaited(events.flush()),
    onPause: () => unawaited(events.flush()),
    onDetach: () => unawaited(events.flush()),
  );

  ref.onDispose(() {
    lifecycle.dispose();
    unawaited(events.flush());
    events.dispose();
  });
  return events;
});

/// Records one event without ever throwing into the caller.
void trackJobEvent(
  WidgetRef ref,
  String jobId,
  JobEventType type,
  JobSurface surface, {
  int? rank,
}) {
  try {
    ref.read(jobEventsProvider).track(
        JobEvent(jobId: jobId, type: type, surface: surface, rank: rank));
  } catch (_) {
    // No Supabase (tests) or not ready yet: tracking is optional.
  }
}

/// Sends anything waiting. Call just before sign-out, while the session is
/// still valid.
Future<void> flushJobEvents(WidgetRef ref) async {
  try {
    await ref.read(jobEventsProvider).flush();
  } catch (_) {}
}

/// The route to a job's page, carrying where it was opened from so the page
/// can record its view against the right surface.
String jobRoute(String jobId, JobSurface surface, {int? rank}) {
  final q = <String, String>{
    'from': surface.wire,
    if (rank != null && rank > 0) 'rank': '$rank',
  };
  return Uri(path: '/job/$jobId', queryParameters: q).toString();
}
