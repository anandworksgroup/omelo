import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/meet.dart';
import 'meet_chat.dart';

/// The interview itself: video tiles, controls, chat.
class MeetRoomView extends StatefulWidget {
  const MeetRoomView({
    super.key,
    required this.room,
    required this.info,
    required this.chat,
    required this.reconnecting,
    required this.onLeave,
    required this.onReport,
  });

  final lk.Room room;
  final MeetInterviewInfo? info;
  final MeetChat? chat;
  final bool reconnecting;
  final Future<void> Function() onLeave;
  final VoidCallback onReport;

  @override
  State<MeetRoomView> createState() => _MeetRoomViewState();
}

class _MeetRoomViewState extends State<MeetRoomView> {
  bool _sidePanelOpen = false;
  bool _micBusy = false;
  bool _camBusy = false;
  lk.CameraPosition _position = lk.CameraPosition.front;

  lk.Room get _room => widget.room;

  @override
  void initState() {
    super.initState();
    _room.addListener(_changed);
    widget.chat?.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant MeetRoomView old) {
    super.didUpdateWidget(old);
    if (old.room != widget.room) {
      old.room.removeListener(_changed);
      widget.room.addListener(_changed);
    }
    if (old.chat != widget.chat) {
      old.chat?.removeListener(_changed);
      widget.chat?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _room.removeListener(_changed);
    widget.chat?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  // -- Controls -------------------------------------------------------------

  void _snack(String text) => ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(text)));

  String _deviceHelp(Object e, {required bool camera}) {
    final issue = classifyDeviceError(e);
    final base = MeetCopy.deviceIssue(issue, camera: camera);
    if (issue != DeviceIssue.denied) return base;
    return '$base ${MeetCopy.enableInSettings(web: kIsWeb, ios: defaultTargetPlatform == TargetPlatform.iOS)}';
  }

  Future<void> _toggleMic() async {
    final local = _room.localParticipant;
    if (local == null || _micBusy) return;
    setState(() => _micBusy = true);
    try {
      await local.setMicrophoneEnabled(!local.isMicrophoneEnabled());
    } catch (e) {
      _snack(_deviceHelp(e, camera: false));
    } finally {
      if (mounted) setState(() => _micBusy = false);
    }
  }

  Future<void> _toggleCamera() async {
    final local = _room.localParticipant;
    if (local == null || _camBusy) return;
    setState(() => _camBusy = true);
    try {
      await local.setCameraEnabled(!local.isCameraEnabled());
    } catch (e) {
      _snack(_deviceHelp(e, camera: true));
    } finally {
      if (mounted) setState(() => _camBusy = false);
    }
  }

  Future<void> _switchCamera() async {
    final track = _localCameraTrack();
    if (track == null) {
      _snack('Turn your camera on first.');
      return;
    }
    final next = _position == lk.CameraPosition.front
        ? lk.CameraPosition.back
        : lk.CameraPosition.front;
    try {
      await track.setCameraPosition(next);
      _position = next;
    } catch (_) {
      _snack('Could not switch camera.');
    }
  }

  lk.LocalVideoTrack? _localCameraTrack() {
    for (final p in _room.localParticipant?.videoTrackPublications ?? const []) {
      if (p.source == lk.TrackSource.camera && p.track != null) return p.track;
    }
    return null;
  }

  Future<void> _openChat(bool wide) async {
    final chat = widget.chat;
    if (chat == null) return;
    if (wide) {
      final open = !_sidePanelOpen;
      setState(() => _sidePanelOpen = open);
      chat.setOpen(open);
      return;
    }
    chat.setOpen(true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: SizedBox(
          height: MediaQuery.sizeOf(ctx).height * 0.7,
          child: MeetChatPanel(chat: chat),
        ),
      ),
    );
    chat.setOpen(false);
  }

  Future<void> _confirmLeave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave the interview?'),
        content: const Text(
            'The interviewer will see that you left. You can join again '
            'while the interview is still open.'),
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
    if (ok == true) await widget.onLeave();
  }

  // -- Build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= Breakpoints.expanded;
    final chat = widget.chat;
    final local = _room.localParticipant;

    return Scaffold(
      backgroundColor: const Color(0xFF101312),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(info: widget.info),
            if (widget.reconnecting)
              const _Banner(
                icon: Icons.wifi_off,
                text: 'Reconnecting… Please check your internet.',
                color: OmeloTheme.warning,
              ),
            if (!_room.canPlaybackAudio)
              _Banner(
                icon: Icons.volume_up,
                text: 'Tap here to hear the interviewer',
                color: OmeloTheme.seed,
                onTap: () => _room.startAudio(),
              ),
            Expanded(
              child: Row(
                children: [
                  Expanded(child: _videoArea(size)),
                  if (wide && _sidePanelOpen && chat != null)
                    SizedBox(
                      width: 360,
                      child: MeetChatPanel(
                        chat: chat,
                        onClose: () {
                          setState(() => _sidePanelOpen = false);
                          chat.setOpen(false);
                        },
                      ),
                    ),
                ],
              ),
            ),
            _BottomBar(
              children: [
                _ControlButton(
                  icon: local?.isMicrophoneEnabled() == true
                      ? Icons.mic
                      : Icons.mic_off,
                  label: local?.isMicrophoneEnabled() == true
                      ? 'Mute'
                      : 'Unmute',
                  highlighted: local?.isMicrophoneEnabled() != true,
                  onTap: _micBusy ? null : _toggleMic,
                ),
                _ControlButton(
                  icon: local?.isCameraEnabled() == true
                      ? Icons.videocam
                      : Icons.videocam_off,
                  label: local?.isCameraEnabled() == true
                      ? 'Camera off'
                      : 'Camera on',
                  highlighted: local?.isCameraEnabled() != true,
                  onTap: _camBusy ? null : _toggleCamera,
                ),
                if (lk.lkPlatformIsMobile())
                  _ControlButton(
                    icon: Icons.cameraswitch,
                    label: 'Switch',
                    onTap: local?.isCameraEnabled() == true
                        ? _switchCamera
                        : null,
                  ),
                if (chat != null)
                  _ControlButton(
                    icon: Icons.chat_bubble_outline,
                    label: 'Chat',
                    badge: chat.unread,
                    onTap: () => _openChat(wide),
                  ),
                _MoreButton(onReport: widget.onReport),
                _ControlButton(
                  icon: Icons.call_end,
                  label: 'Leave',
                  color: OmeloTheme.danger,
                  onTap: _confirmLeave,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _videoArea(Size size) {
    final local = _room.localParticipant;
    final remotes = _room.remoteParticipants.values.toList()
      ..sort((a, b) => _roleOrder(a).compareTo(_roleOrder(b)));
    final phonePortrait =
        size.width < Breakpoints.medium && size.height > size.width;

    Widget selfTile({bool small = false}) => local == null
        ? const SizedBox.shrink()
        : _ParticipantTile(participant: local, isLocal: true, small: small);

    if (remotes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            selfTile(),
            const Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: _Notice(
                  'You are in. Waiting for the interviewer to turn on their '
                  'video…',
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (remotes.length == 1 && phonePortrait) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Stack(
          fit: StackFit.expand,
          children: [
            _ParticipantTile(participant: remotes.first, isLocal: false),
            Positioned(
              right: 12,
              top: 12,
              width: 112,
              height: 150,
              child: selfTile(small: true),
            ),
          ],
        ),
      );
    }

    final tiles = <Widget>[
      for (final r in remotes) _ParticipantTile(participant: r, isLocal: false),
      if (local != null) selfTile(),
    ];
    return LayoutBuilder(builder: (context, c) {
      final n = tiles.length;
      final int cols;
      if (n <= 2) {
        cols = phonePortrait ? 1 : 2;
      } else if (n <= 4) {
        cols = 2;
      } else {
        cols = c.maxWidth >= Breakpoints.expanded ? 3 : 2;
      }
      final rows = (n / cols).ceil();
      const gap = 8.0;
      final w = (c.maxWidth - gap * (cols + 1)) / cols;
      final h = (c.maxHeight - gap * (rows + 1)) / rows;
      return Padding(
        padding: const EdgeInsets.all(gap),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          alignment: WrapAlignment.center,
          runAlignment: WrapAlignment.center,
          children: [
            for (final t in tiles)
              SizedBox(width: w.clamp(80, 4000), height: h.clamp(80, 4000), child: t),
          ],
        ),
      );
    });
  }

  static int _roleOrder(lk.Participant p) => switch (participantRole(p)) {
        'host' => 0,
        'interviewer' => 1,
        'observer' => 2,
        _ => 3,
      };
}

/// The role LiveKit carries in participant metadata (`{"role": "host"}`).
String? participantRole(lk.Participant p) {
  final md = p.metadata;
  if (md == null || md.isEmpty) return null;
  try {
    final v = jsonDecode(md);
    return v is Map ? v['role']?.toString() : null;
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

class _TopBar extends StatelessWidget {
  const _TopBar({required this.info});
  final MeetInterviewInfo? info;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          const Icon(Icons.videocam, color: Colors.white70, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info?.title ?? 'Omelo Meet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                const Text(
                  MeetCopy.notRecorded,
                  style: TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.text,
    required this.color,
    this.onTap,
  });
  final IconData icon;
  final String text;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              if (onTap == null)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 15)),
      );
}

class _ParticipantTile extends StatelessWidget {
  const _ParticipantTile({
    required this.participant,
    required this.isLocal,
    this.small = false,
  });

  final lk.Participant participant;
  final bool isLocal;
  final bool small;

  lk.VideoTrack? _videoTrack() {
    for (final pub in participant.videoTrackPublications) {
      if (pub.source != lk.TrackSource.camera &&
          pub.source != lk.TrackSource.screenShareVideo &&
          pub.source != lk.TrackSource.unknown) {
        continue;
      }
      final track = pub.track;
      if (track is lk.VideoTrack && !pub.muted) return track;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: participant,
      builder: (context, _) {
        final track = _videoTrack();
        final name = isLocal
            ? 'You'
            : (participant.name.isNotEmpty ? participant.name : 'Interviewer');
        final role = isLocal ? null : MeetCopy.role(participantRole(participant));
        final speaking = participant.isSpeaking;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: const Color(0xFF1F2624),
            borderRadius: BorderRadius.circular(small ? 12 : 16),
            border: Border.all(
              color: speaking ? OmeloTheme.accent : Colors.white24,
              width: speaking ? 3 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (track != null)
                lk.VideoTrackRenderer(
                  track,
                  key: ValueKey(track.sid ?? track.mediaStreamTrack.id),
                  fit: lk.VideoViewFit.cover,
                )
              else
                Center(
                  child: CircleAvatar(
                    radius: small ? 22 : 40,
                    backgroundColor: OmeloTheme.seed,
                    child: Text(
                      _initials(name),
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: small ? 16 : 28,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              Positioned(
                left: 6,
                bottom: 6,
                right: 6,
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (participant.isMuted) ...[
                          const Icon(Icons.mic_off,
                              color: Colors.white, size: 15),
                          const SizedBox(width: 4),
                        ],
                        Flexible(
                          child: Text(
                            [name, if (role != null && role.isNotEmpty && !small) role]
                                .join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: small ? 12 : 14,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF181D1B),
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [for (final c in children) Expanded(child: c)],
          ),
        ),
      ),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
    this.color,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool highlighted;
  final Color? color;
  final int badge;

  @override
  Widget build(BuildContext context) {
    final bg = color ??
        (highlighted ? Colors.white : Colors.white.withValues(alpha: 0.14));
    final fg = color != null
        ? Colors.white
        : (highlighted ? Colors.black87 : Colors.white);
    return Semantics(
      button: true,
      label: badge > 0 ? '$label, $badge new' : label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Badge(
            isLabelVisible: badge > 0,
            label: Text(badge > 9 ? '9+' : '$badge'),
            child: Material(
              color: onTap == null ? bg.withValues(alpha: 0.4) : bg,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: onTap,
                child: SizedBox(
                  width: 54,
                  height: 54,
                  child: Icon(icon, color: fg, size: 26),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _MoreButton extends StatelessWidget {
  const _MoreButton({required this.onReport});
  final VoidCallback onReport;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          tooltip: 'More',
          onSelected: (v) {
            if (v == 'report') onReport();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'report',
              child: ListTile(
                leading: Icon(Icons.flag_outlined),
                title: Text('Report a problem'),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
          child: Material(
            color: Colors.white.withValues(alpha: 0.14),
            shape: const CircleBorder(),
            child: const SizedBox(
              width: 54,
              height: 54,
              child: Icon(Icons.more_vert, color: Colors.white, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 4),
        const Text('More',
            style: TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}

/// "Report a problem" — returns the reason code and optional details.
Future<({String reason, String? details})?> showMeetReportSheet(
    BuildContext context) {
  return showModalBottomSheet<({String reason, String? details})>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (_) => const _ReportSheet(),
  );
}

class _ReportSheet extends StatefulWidget {
  const _ReportSheet();

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _details = TextEditingController();

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ContentWidth.reading(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Report a problem',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: OmeloTheme.warning.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '${MeetCopy.neverPay} If anyone asks you for money, report '
                  'it here. You can leave the interview at any time.',
                  style: TextStyle(fontSize: 14.5, height: 1.4),
                ),
              ),
              const SizedBox(height: 12),
              const Text('What happened?',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              _ReasonList(
                value: _reason,
                onChanged: (v) => setState(() => _reason = v),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _details,
                minLines: 1,
                maxLines: 4,
                maxLength: 1000,
                decoration: const InputDecoration(
                    hintText: 'Tell us more (optional)'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _reason == null
                    ? null
                    : () => Navigator.pop(
                          context,
                          (reason: _reason!, details: _details.text.trim()),
                        ),
                child: const Text('Send report'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Go back'),
              ),
              Text(
                'Only Omelo\'s safety team sees this report.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A list of big tappable reason rows (avoids the Radio API churn between
/// Flutter versions).
class _ReasonList extends StatelessWidget {
  const _ReasonList({required this.value, required this.onChanged});
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final e in MeetCopy.reportReasons.entries)
          InkWell(
            onTap: () => onChanged(e.key),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
              child: Row(
                children: [
                  Icon(
                    value == e.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: value == e.key ? scheme.primary : scheme.outline,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(e.value, style: const TextStyle(fontSize: 15.5)),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
