import 'dart:async';

import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:supabase_flutter/supabase_flutter.dart' show RealtimeChannel;

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/hiring.dart' show HiringCopy;
import '../../data/meet_repository.dart';
import 'meet_chat.dart';
import 'meet_devices.dart';
import 'meet_room_view.dart';

enum _Stage {
  loading,
  tooEarly,
  preJoin,
  joining,
  waiting,
  inRoom,
  unavailable,
  error,
  denied,
  completed,
  left,
}

/// `/meet/:room` — Omelo Meet, the candidate's side.
///
/// loading → too early (countdown) → pre-join (camera check) → waiting room
/// → in the interview → completed / left. The server decides every step;
/// this screen only follows and explains.
class MeetScreen extends ConsumerStatefulWidget {
  const MeetScreen({super.key, required this.roomName});
  final String roomName;

  @override
  ConsumerState<MeetScreen> createState() => _MeetScreenState();
}

class _MeetScreenState extends ConsumerState<MeetScreen>
    with WidgetsBindingObserver {
  late final MeetRepository _repo;
  final _devices = MeetDevices();

  _Stage _stage = _Stage.loading;
  MeetInterviewInfo? _info;
  DateTime? _opensAt;
  DateTime? _scheduledAt;

  String? _errorMessage;
  bool _errorRetryable = false;
  bool _leftInBackground = false;

  /// The server has us down as waiting or in the room, so tell it on exit.
  bool _registered = false;

  Timer? _ticker;
  Timer? _poll;
  Timer? _backgroundTimer;
  RealtimeChannel? _participantChannel;
  bool _checkingAdmission = false;

  lk.Room? _room;
  lk.EventsListener<lk.RoomEvent>? _roomEvents;
  bool _reconnecting = false;
  bool _leaving = false;
  MeetChat? _chat;

  String? get _interviewId => _info?.interviewId;

  @override
  void initState() {
    super.initState();
    _repo = ref.read(meetRepositoryProvider);
    WidgetsBinding.instance.addObserver(this);
    _devices.addListener(_onDevices);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _backgroundTimer?.cancel();
    _stopWaiting();
    _devices.removeListener(_onDevices);
    _devices.dispose();
    final id = _interviewId;
    final wasIn = _registered && _stage != _Stage.completed;
    _teardownRoom();
    if (wasIn && id != null) _repo.leave(id);
    super.dispose();
  }

  void _onDevices() {
    if (mounted) setState(() {});
  }

  void _go(_Stage s) {
    if (!mounted) return;
    setState(() => _stage = s);
  }

  // -- Flow -----------------------------------------------------------------

  Future<void> _start() async {
    _go(_Stage.loading);
    final r = await _repo.join(widget.roomName);
    if (!mounted) return;
    _remember(r);
    switch (r) {
      case MeetTooEarly():
        _showTooEarly(r);
      case MeetWaiting():
        _registered = true;
        _go(_Stage.preJoin);
      case MeetAdmitted():
        // Rejoining an interview already under way; still check devices first.
        // The server already has us in the room, so leaving must be reported.
        _registered = true;
        _go(_Stage.preJoin);
      case MeetUnavailable():
        _registered = true;
        _go(_Stage.unavailable);
      case MeetJoinError():
        _showError(r);
    }
  }

  void _remember(MeetJoinResult r) {
    if (r.interview != null) _info = r.interview;
  }

  void _showTooEarly(MeetTooEarly r) {
    _scheduledAt = r.scheduledAt ?? _info?.scheduledAt;
    _opensAt = r.opensAt ?? _scheduledAt?.subtract(kMeetOpensBefore);
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _stage == _Stage.tooEarly) setState(() {});
    });
    _go(_Stage.tooEarly);
  }

  void _showError(MeetJoinError r) {
    _errorMessage = r.message;
    _errorRetryable = r.retryable;
    _go(_Stage.error);
  }

  /// Pre-join done: ask to come in.
  Future<void> _requestEntry() async {
    _ticker?.cancel();
    _go(_Stage.joining);
    final r = await _repo.join(widget.roomName);
    if (!mounted) return;
    _remember(r);
    switch (r) {
      case MeetTooEarly():
        _showTooEarly(r);
      case MeetWaiting():
        _registered = true;
        _go(_Stage.waiting);
        _startWaiting();
      case MeetAdmitted():
        await _connect(r);
      case MeetUnavailable():
        _registered = true;
        _go(_Stage.unavailable);
      case MeetJoinError():
        _showError(r);
    }
  }

  void _startWaiting() {
    _stopWaiting();
    final id = _interviewId;
    if (id != null) {
      _participantChannel = _repo.watchMyParticipant(id, _onParticipant);
    }
    // Realtime can drop quietly on mobile networks; poll as a fallback.
    _poll = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_stage != _Stage.waiting) return;
      final p = id == null ? null : await _repo.myParticipant(id);
      if (p != null) {
        _onParticipant(p);
      } else {
        _checkAdmission();
      }
    });
  }

  void _stopWaiting() {
    _poll?.cancel();
    _poll = null;
    final c = _participantChannel;
    _participantChannel = null;
    if (c != null) _repo.unsubscribe(c);
  }

  void _onParticipant(MeetParticipant p) {
    if (!mounted || _stage != _Stage.waiting) return;
    if (p.isAdmitted) {
      _checkAdmission();
    } else if (p.isDenied) {
      _stopWaiting();
      _registered = false;
      _go(_Stage.denied);
    } else if (p.isRemoved) {
      _stopWaiting();
      _registered = false;
      _errorMessage = 'You cannot join this interview.';
      _errorRetryable = false;
      _go(_Stage.error);
    }
  }

  Future<void> _checkAdmission() async {
    if (_checkingAdmission) return;
    _checkingAdmission = true;
    try {
      final r = await _repo.join(widget.roomName);
      if (!mounted || _stage != _Stage.waiting) return;
      _remember(r);
      switch (r) {
        case MeetWaiting():
          break; // still waiting
        case MeetAdmitted():
          _stopWaiting();
          await _connect(r);
        case MeetUnavailable():
          _stopWaiting();
          _go(_Stage.unavailable);
        case MeetTooEarly():
          break;
        case MeetJoinError():
          // Rate limit or a network blip: keep waiting, the next poll retries.
          if (!r.retryable) {
            _stopWaiting();
            _showError(r);
          }
      }
    } finally {
      _checkingAdmission = false;
    }
  }

  Future<void> _connect(MeetAdmitted a) async {
    _stopWaiting();
    _registered = true;
    _go(_Stage.joining);

    final room = lk.Room(
      roomOptions: const lk.RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultCameraCaptureOptions: lk.CameraCaptureOptions(
          params: lk.VideoParametersPresets.h540_169,
        ),
      ),
    );
    final events = room.createListener();
    _room = room;
    _roomEvents = events;
    events
      ..on<lk.RoomReconnectingEvent>((_) => _setReconnecting(true))
      ..on<lk.RoomAttemptReconnectEvent>((_) => _setReconnecting(true))
      ..on<lk.RoomReconnectedEvent>((_) => _setReconnecting(false))
      ..on<lk.RoomDisconnectedEvent>((e) => _onDisconnected(room, e.reason));

    try {
      await room.connect(a.url, a.token);
    } catch (_) {
      _teardownRoom();
      if (!mounted) return;
      _errorMessage = 'Could not connect to the video. Check your internet '
          'and try again.';
      _errorRetryable = true;
      _go(_Stage.error);
      return;
    }
    if (!mounted || _room != room) return;

    final local = room.localParticipant;
    final preview = _devices.takePreviewTrack();
    if (_devices.cameraOn) {
      try {
        if (preview != null) {
          await local?.publishVideoTrack(preview);
        } else {
          await local?.setCameraEnabled(true);
        }
      } catch (e) {
        _snack(MeetCopy.deviceIssue(classifyDeviceError(e), camera: true));
      }
    } else {
      await preview?.stop();
    }
    if (_devices.micOn) {
      try {
        await local?.setMicrophoneEnabled(true);
      } catch (e) {
        _snack(MeetCopy.deviceIssue(classifyDeviceError(e), camera: false));
      }
    }

    final id = _interviewId;
    if (id != null) {
      _chat?.dispose();
      _chat = MeetChat(_repo, id)..start();
    }
    _reconnecting = false;
    _go(_Stage.inRoom);
  }

  void _setReconnecting(bool v) {
    if (mounted && _reconnecting != v) setState(() => _reconnecting = v);
  }

  Future<void> _onDisconnected(lk.Room room, lk.DisconnectReason? reason) async {
    if (_room != room || _leaving || !mounted) return;
    _teardownRoom();

    switch (reason) {
      case lk.DisconnectReason.roomDeleted:
        // The host ended the interview.
        _registered = false;
        _go(_Stage.completed);
        return;
      case lk.DisconnectReason.participantRemoved:
        _registered = false;
        _errorMessage = 'You were removed from this interview.';
        _errorRetryable = false;
        _go(_Stage.error);
        return;
      case lk.DisconnectReason.clientInitiated:
        return;
      default:
        break;
    }

    // Not clear why we dropped. Ask the server whether the interview is over.
    _go(_Stage.joining);
    final r = await _repo.join(widget.roomName);
    if (!mounted) return;
    _remember(r);
    if (r is MeetJoinError && r.interviewEnded) {
      _registered = false;
      _go(_Stage.completed);
      return;
    }
    _devices.resetAfterCall();
    _errorMessage = 'The connection was lost. You can join again.';
    _errorRetryable = true;
    _go(_Stage.error);
  }

  void _teardownRoom() {
    _roomEvents?.dispose();
    _roomEvents = null;
    final room = _room;
    _room = null;
    if (room != null) {
      room.disconnect().whenComplete(room.dispose);
    }
    _chat?.dispose();
    _chat = null;
    _reconnecting = false;
  }

  Future<void> _leave({bool background = false}) async {
    _leaving = true;
    final id = _interviewId;
    _stopWaiting();
    _teardownRoom();
    _devices.resetAfterCall();
    if (id != null) await _repo.leave(id);
    _registered = false;
    _leaving = false;
    _leftInBackground = background;
    _go(_Stage.left);
  }

  Future<void> _report() async {
    final id = _interviewId;
    if (id == null) return;
    final r = await showMeetReportSheet(context);
    if (r == null) return;
    try {
      await _repo.report(id, r.reason, details: r.details);
      _snack("Thank you. Omelo's safety team will look at this.");
    } catch (e) {
      _snack(meetActionError(e));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(text)));
  }

  void _backToApplication() {
    final appId = _info?.applicationId;
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(appId == null ? '/applications' : '/applications/$appId');
    }
  }

  // -- App lifecycle --------------------------------------------------------

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = _stage == _Stage.inRoom || _stage == _Stage.waiting;
    if (!active) return;
    switch (state) {
      case AppLifecycleState.resumed:
        _backgroundTimer?.cancel();
      case AppLifecycleState.paused:
        // A quick look at another app is fine; staying away is leaving.
        // Browsers pause hidden tabs too, so only phones do this.
        if (kIsWeb) return;
        _backgroundTimer?.cancel();
        _backgroundTimer = Timer(const Duration(minutes: 2), () {
          if (mounted && (_stage == _Stage.inRoom || _stage == _Stage.waiting)) {
            _leave(background: true);
          }
        });
      case AppLifecycleState.detached:
        final id = _interviewId;
        _teardownRoom();
        if (id != null) _repo.leave(id);
        _registered = false;
      default:
        break;
    }
  }

  // -- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final inCall = _stage == _Stage.inRoom || _stage == _Stage.waiting;
    return PopScope(
      canPop: !inCall,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final ok = await _confirmLeave();
        if (ok && mounted) {
          await _leave();
          if (mounted) _backToApplication();
        }
      },
      child: _buildStage(context),
    );
  }

  Future<bool> _confirmLeave() async {
    final waiting = _stage == _Stage.waiting;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(waiting ? 'Leave the waiting room?' : 'Leave the interview?'),
        content: Text(waiting
            ? 'The interviewer will not be able to let you in.'
            : 'The interviewer will see that you left.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: OmeloTheme.danger),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Widget _buildStage(BuildContext context) {
    final room = _room;
    if (_stage == _Stage.inRoom && room != null) {
      return MeetRoomView(
        room: room,
        info: _info,
        chat: _chat,
        reconnecting: _reconnecting,
        onLeave: _leave,
        onReport: _report,
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Omelo Meet'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () async {
            if (_stage == _Stage.waiting) {
              if (!await _confirmLeave()) return;
              await _leave();
            }
            if (mounted) _backToApplication();
          },
        ),
      ),
      body: SafeArea(
        child: switch (_stage) {
          _Stage.loading => const _Centered(
              icon: null,
              title: 'Opening your interview…',
            ),
          _Stage.joining => const _Centered(
              icon: null,
              title: 'Joining…',
              body: 'This can take a few seconds.',
            ),
          _Stage.tooEarly => _tooEarly(context),
          _Stage.preJoin => _preJoin(context),
          _Stage.waiting => _waiting(context),
          _Stage.inRoom => const _Centered(icon: null, title: 'Joining…'),
          _Stage.unavailable => _Centered(
              icon: Icons.videocam_off_outlined,
              title: 'Video is not ready yet',
              body: MeetCopy.notConfigured,
              info: _info,
              primary: 'Back to my application',
              onPrimary: _backToApplication,
            ),
          _Stage.error => _Centered(
              icon: Icons.info_outline,
              title: _errorMessage ?? 'Could not open this interview.',
              info: _info,
              primary: _errorRetryable ? 'Try again' : 'Back to my application',
              onPrimary: _errorRetryable ? _retry : _backToApplication,
              secondary: _errorRetryable ? 'Back to my application' : null,
              onSecondary: _backToApplication,
            ),
          _Stage.denied => _Centered(
              icon: Icons.do_not_disturb_on_outlined,
              title: 'The interviewer could not let you in',
              body: 'This can happen when plans change. The employer will '
                  'update your application, and you will be notified.',
              info: _info,
              primary: 'Back to my application',
              onPrimary: _backToApplication,
            ),
          _Stage.completed => _Centered(
              icon: Icons.check_circle,
              iconColor: OmeloTheme.verified,
              title: 'Interview completed ✓',
              body: '${MeetCopy.submitted}\n\n${MeetCopy.finalReview}\n\n'
                  '${MeetCopy.willNotify}',
              info: _info,
              primary: 'Back to my application',
              onPrimary: _backToApplication,
            ),
          _Stage.left => _Centered(
              icon: Icons.logout,
              title: 'You left the interview',
              body: _leftInBackground
                  ? 'Omelo was closed for a while, so you left the interview. '
                      'You can join again while it is still open.'
                  : 'You can join again while the interview is still open.',
              info: _info,
              primary: 'Join again',
              onPrimary: () => _go(_Stage.preJoin),
              secondary: 'Back to my application',
              onSecondary: _backToApplication,
            ),
        },
      ),
    );
  }

  void _retry() {
    if (_registered || _devices.asked) {
      _requestEntry();
    } else {
      _start();
    }
  }

  // -- Too early ------------------------------------------------------------

  Widget _tooEarly(BuildContext context) {
    final now = DateTime.now();
    final window = MeetWindow(opensAt: _opensAt, closesAt: null);
    final canJoin = window.state(now) != MeetWindowState.notYet;
    final scheme = Theme.of(context).colorScheme;

    return _Page(children: [
      _InterviewHeader(info: _info),
      const SizedBox(height: 24),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Text(
              _scheduledAt == null
                  ? 'Your interview has not started yet'
                  : meetStartsInLabel(_scheduledAt!, now),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              canJoin
                  ? 'The waiting room is open. You can go in now.'
                  : 'You can join 15 minutes before it starts. '
                      'This page will let you in when it is time.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15.5, height: 1.4),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: canJoin
            ? () {
                _ticker?.cancel();
                _go(_Stage.preJoin);
              }
            : null,
        icon: const Icon(Icons.meeting_room_outlined),
        label: Text(canJoin
            ? 'Join waiting room'
            : 'Opens in ${meetCountdown(window.untilOpen(now))}'),
      ),
      const SizedBox(height: 24),
      const _Tips(),
    ]);
  }

  // -- Pre-join -------------------------------------------------------------

  Widget _preJoin(BuildContext context) {
    final d = _devices;
    final wide = Breakpoints.of(context).index >= WindowSize.expanded.index;

    final explain = !d.asked
        ? [
            const _InfoBox(
              icon: Icons.videocam_outlined,
              text: 'Omelo needs your camera and microphone so the '
                  'interviewer can see and hear you.\n'
                  '${MeetCopy.devicesOnlyDuring}',
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: d.busy ? null : d.requestAccess,
              icon: const Icon(Icons.check),
              label: const Text('Turn on camera and microphone'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: d.busy ? null : d.skip,
              child: const Text('Continue without them'),
            ),
          ]
        : [
            _DeviceToggles(devices: d),
            ..._deviceProblems(d),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: d.busy ? null : _requestEntry,
              icon: const Icon(Icons.login),
              label: const Text('Join interview'),
            ),
            if (!d.micOn) ...[
              const SizedBox(height: 8),
              const Text(
                'Your microphone is off. The interviewer will not hear you '
                'until you turn it on. You can also use chat.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5),
              ),
            ],
          ];

    final preview = _Preview(devices: d);

    return _Page(
      maxWidth: wide ? Breakpoints.contentWidth : Breakpoints.readingWidth,
      children: [
        _InterviewHeader(info: _info),
        const SizedBox(height: 16),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: preview),
              const SizedBox(width: 24),
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Get ready',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    ...explain,
                    const SizedBox(height: 16),
                    const _NotRecorded(),
                  ],
                ),
              ),
            ],
          )
        else ...[
          preview,
          const SizedBox(height: 16),
          ...explain,
          const SizedBox(height: 16),
          const _NotRecorded(),
        ],
      ],
    );
  }

  List<Widget> _deviceProblems(MeetDevices d) {
    final ios = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final out = <Widget>[];
    if (d.cameraIssue != null) {
      out.add(const SizedBox(height: 12));
      out.add(_InfoBox(
        icon: Icons.videocam_off_outlined,
        color: OmeloTheme.warning,
        text: '${MeetCopy.deviceIssue(d.cameraIssue!, camera: true)} '
            'You can still join with your camera off.',
      ));
    }
    if (d.micIssue != null) {
      out.add(const SizedBox(height: 12));
      out.add(_InfoBox(
        icon: Icons.mic_off_outlined,
        color: OmeloTheme.warning,
        text: MeetCopy.deviceIssue(d.micIssue!, camera: false),
      ));
    }
    if (d.anyDenied) {
      out.add(const SizedBox(height: 12));
      out.add(_InfoBox(
        icon: Icons.settings_outlined,
        text: MeetCopy.enableInSettings(web: kIsWeb, ios: ios),
      ));
    }
    return out;
  }

  // -- Waiting room ---------------------------------------------------------

  Widget _waiting(BuildContext context) {
    final wide = Breakpoints.of(context).index >= WindowSize.expanded.index;
    final status = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Row(
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                'Please wait, the interviewer will let you in soon',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        const Text(
          'Keep this screen open. You will go in automatically.',
          style: TextStyle(fontSize: 15.5, height: 1.4),
        ),
        const SizedBox(height: 16),
        _DeviceToggles(devices: _devices),
        const SizedBox(height: 16),
        const _NotRecorded(),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: () async {
            if (await _confirmLeave()) {
              await _leave();
            }
          },
          child: const Text('Leave waiting room'),
        ),
      ],
    );

    return _Page(
      maxWidth: wide ? Breakpoints.contentWidth : Breakpoints.readingWidth,
      children: [
        _InterviewHeader(info: _info),
        const SizedBox(height: 16),
        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: _Preview(devices: _devices)),
              const SizedBox(width: 24),
              Expanded(flex: 2, child: status),
            ],
          )
        else ...[
          _Preview(devices: _devices),
          const SizedBox(height: 16),
          status,
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _Page extends StatelessWidget {
  const _Page({
    required this.children,
    this.maxWidth = Breakpoints.readingWidth,
  });
  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        ContentWidth(
          maxWidth: maxWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _InterviewHeader extends StatelessWidget {
  const _InterviewHeader({required this.info});
  final MeetInterviewInfo? info;

  @override
  Widget build(BuildContext context) {
    final i = info;
    if (i == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(i.roundName ?? 'Interview',
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          [
            if (i.jobTitle != null) i.jobTitle!,
            if (i.companyName != null) i.companyName!,
          ].join(' · '),
          style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: scheme.onSurfaceVariant),
        ),
        if (i.scheduledAt != null) ...[
          const SizedBox(height: 4),
          Text(
            [
              HiringCopy.dayTime(i.scheduledAt!),
              if (i.durationMinutes != null) 'About ${i.durationMinutes} minutes',
            ].join(' · '),
            style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant),
          ),
        ],
        if (i.instructions != null) ...[
          const SizedBox(height: 10),
          _InfoBox(icon: Icons.info_outline, text: i.instructions!),
        ],
      ],
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.devices});
  final MeetDevices devices;

  @override
  Widget build(BuildContext context) {
    final track = devices.previewTrack;
    return AspectRatio(
      aspectRatio: 4 / 3,
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1F2624),
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (track != null)
              lk.VideoTrackRenderer(
                track,
                fit: lk.VideoViewFit.cover,
                mirrorMode: lk.VideoViewMirrorMode.mirror,
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (devices.busy)
                      const CircularProgressIndicator(color: Colors.white)
                    else
                      const Icon(Icons.videocam_off,
                          color: Colors.white70, size: 48),
                    const SizedBox(height: 10),
                    Text(
                      devices.busy ? 'Starting camera…' : 'Camera is off',
                      style:
                          const TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            const Positioned(
              left: 10,
              bottom: 10,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Color(0x99000000),
                  borderRadius: BorderRadius.all(Radius.circular(8)),
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text('You',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DeviceToggles extends StatelessWidget {
  const _DeviceToggles({required this.devices});
  final MeetDevices devices;

  @override
  Widget build(BuildContext context) {
    final d = devices;
    Widget toggle({
      required bool on,
      required IconData onIcon,
      required IconData offIcon,
      required String onLabel,
      required String offLabel,
      required VoidCallback? onTap,
    }) {
      final button = on
          ? FilledButton.tonalIcon(
              onPressed: onTap,
              icon: Icon(onIcon),
              label: Text(onLabel),
            )
          : OutlinedButton.icon(
              onPressed: onTap,
              icon: Icon(offIcon),
              label: Text(offLabel),
            );
      return SizedBox(height: 56, child: button);
    }

    return Row(
      children: [
        Expanded(
          child: toggle(
            on: d.micOn,
            onIcon: Icons.mic,
            offIcon: Icons.mic_off,
            onLabel: 'Mic on',
            offLabel: 'Mic off',
            onTap: d.busy ? null : () => d.setMic(!d.micOn),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: toggle(
            on: d.cameraOn,
            onIcon: Icons.videocam,
            offIcon: Icons.videocam_off,
            onLabel: 'Camera on',
            offLabel: 'Camera off',
            onTap: d.busy ? null : () => d.setCamera(!d.cameraOn),
          ),
        ),
        if (lk.lkPlatformIsMobile() && d.previewTrack != null) ...[
          const SizedBox(width: 10),
          SizedBox(
            height: 56,
            width: 56,
            child: IconButton.outlined(
              tooltip: 'Switch camera',
              onPressed: d.switchCamera,
              icon: const Icon(Icons.cameraswitch),
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.icon, required this.text, this.color});
  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 15, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _NotRecorded extends StatelessWidget {
  const _NotRecorded();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.lock_outline, size: 18, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${MeetCopy.notRecorded} ${MeetCopy.neverPay}',
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _Tips extends StatelessWidget {
  const _Tips();

  @override
  Widget build(BuildContext context) {
    Widget tip(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Icon(icon, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 15.5))),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Get ready',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        tip(Icons.volume_off_outlined, 'Find a quiet place'),
        tip(Icons.wifi, 'Check your internet is working'),
        tip(Icons.battery_charging_full, 'Charge your phone'),
        tip(Icons.lock_outline, MeetCopy.notRecorded),
        tip(Icons.shield_outlined, MeetCopy.neverPay),
      ],
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({
    required this.icon,
    required this.title,
    this.iconColor,
    this.body,
    this.info,
    this.primary,
    this.onPrimary,
    this.secondary,
    this.onSecondary,
  });

  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? body;
  final MeetInterviewInfo? info;
  final String? primary;
  final VoidCallback? onPrimary;
  final String? secondary;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ContentWidth.reading(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon == null)
                const Center(child: CircularProgressIndicator())
              else
                Icon(icon, size: 64, color: iconColor ?? scheme.primary),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              if (info != null &&
                  (info!.roundName != null || info!.companyName != null)) ...[
                const SizedBox(height: 6),
                Text(
                  [
                    if (info!.roundName != null) info!.roundName!,
                    if (info!.companyName != null) info!.companyName!,
                  ].join(' · '),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 15, color: scheme.onSurfaceVariant),
                ),
              ],
              if (body != null) ...[
                const SizedBox(height: 14),
                Text(body!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 16, height: 1.45)),
              ],
              if (primary != null) ...[
                const SizedBox(height: 24),
                FilledButton(onPressed: onPrimary, child: Text(primary!)),
              ],
              if (secondary != null) ...[
                const SizedBox(height: 10),
                OutlinedButton(onPressed: onSecondary, child: Text(secondary!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
