import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart' as lk;

import '../../data/meet.dart';

/// Camera and microphone before the call: permission, preview and the
/// on/off choices the person makes on the pre-join and waiting screens.
///
/// Opening the camera or microphone is what triggers the system permission
/// prompt (Android runtime permission, iOS prompt, browser prompt), so this
/// is only done after the screen has explained why.
class MeetDevices extends ChangeNotifier {
  bool cameraOn = true;
  bool micOn = true;

  /// True once the person has been asked (or chose to skip).
  bool asked = false;
  bool busy = false;

  DeviceIssue? cameraIssue;
  DeviceIssue? micIssue;

  lk.LocalVideoTrack? previewTrack;
  lk.CameraPosition _position = lk.CameraPosition.front;

  bool _disposed = false;

  bool get anyDenied =>
      cameraIssue == DeviceIssue.denied || micIssue == DeviceIssue.denied;

  /// Explained, now ask the system for both.
  Future<void> requestAccess() async {
    asked = true;
    _set(() => busy = true);
    await _openMicOnce();
    if (cameraOn) await _startPreview();
    _set(() => busy = false);
  }

  /// "Continue without camera and microphone".
  void skip() {
    asked = true;
    cameraOn = false;
    micOn = false;
    _set(() {});
  }

  Future<void> setCamera(bool on) async {
    cameraOn = on;
    asked = true;
    if (on) {
      _set(() => busy = true);
      await _startPreview();
      _set(() => busy = false);
    } else {
      await _stopPreview();
      _set(() {});
    }
  }

  Future<void> setMic(bool on) async {
    micOn = on;
    asked = true;
    if (on && micIssue != null) {
      _set(() => busy = true);
      await _openMicOnce();
      _set(() => busy = false);
    } else {
      _set(() {});
    }
  }

  Future<void> switchCamera() async {
    final t = previewTrack;
    if (t == null) return;
    _position = _position == lk.CameraPosition.front
        ? lk.CameraPosition.back
        : lk.CameraPosition.front;
    try {
      await t.setCameraPosition(_position);
    } catch (_) {}
    _set(() {});
  }

  /// Hands the preview track to the room, which then owns it.
  lk.LocalVideoTrack? takePreviewTrack() {
    final t = previewTrack;
    previewTrack = null;
    return t;
  }

  /// After leaving a call the devices must be opened again for a rejoin.
  void resetAfterCall() {
    previewTrack = null;
    asked = false;
    _set(() {});
  }

  Future<void> _openMicOnce() async {
    lk.LocalAudioTrack? track;
    try {
      // Only to get permission and prove the microphone works. The room opens
      // its own when the call starts.
      track = await lk.LocalAudioTrack.create();
      micIssue = null;
    } catch (e) {
      micIssue = classifyDeviceError(e);
      micOn = false;
    } finally {
      try {
        await track?.stop();
        await track?.dispose();
      } catch (_) {}
    }
  }

  Future<void> _startPreview() async {
    if (previewTrack != null) return;
    try {
      final t = await lk.LocalVideoTrack.createCameraTrack(
        lk.CameraCaptureOptions(
          cameraPosition: _position,
          params: lk.VideoParametersPresets.h540_169,
        ),
      );
      if (_disposed) {
        await t.stop();
        await t.dispose();
        return;
      }
      previewTrack = t;
      cameraIssue = null;
    } catch (e) {
      cameraIssue = classifyDeviceError(e);
      cameraOn = false;
    }
  }

  Future<void> _stopPreview() async {
    final t = previewTrack;
    previewTrack = null;
    if (t == null) return;
    try {
      await t.stop();
      await t.dispose();
    } catch (_) {}
  }

  void _set(VoidCallback fn) {
    fn();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stopPreview();
    super.dispose();
  }
}
