import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import 'network_repository.dart' show PickedMedia, kPostMediaMimeTypes;

/// Choosing photos and video off the device.
///
/// Kept behind a function so the composer can be driven in a widget test
/// without a real gallery, and so the one place that knows about
/// `image_picker` is this file.
typedef MediaChooser = Future<List<PickedMedia>> Function({required bool video});

final mediaChooserProvider =
    Provider<MediaChooser>((_) => chooseMediaFromDevice);

/// Photos (several at a time) or one video from the device's gallery.
///
/// Returns an empty list when the worker backed out, which is not an error.
/// A file Omelo's bucket would refuse is dropped here rather than failing
/// halfway through an upload.
Future<List<PickedMedia>> chooseMediaFromDevice({required bool video}) async {
  final picker = ImagePicker();
  final files = <XFile>[];
  if (video) {
    final one = await picker.pickVideo(source: ImageSource.gallery);
    if (one != null) files.add(one);
  } else {
    files.addAll(await picker.pickMultiImage());
  }

  final out = <PickedMedia>[];
  for (final f in files) {
    final bytes = await f.readAsBytes();
    final mime = _mimeOf(f, video: video);
    if (!kPostMediaMimeTypes.contains(mime)) continue;
    final size = video ? null : await _imageSize(bytes);
    out.add(PickedMedia(
      bytes: bytes,
      mimeType: mime,
      isVideo: video,
      name: f.name,
      width: size?.$1,
      height: size?.$2,
    ));
  }
  return out;
}

/// The platform gives a MIME type on the web and sometimes nothing on
/// Android, where the file name is all there is.
String _mimeOf(XFile f, {required bool video}) {
  final declared = f.mimeType?.trim().toLowerCase();
  if (declared != null && declared.isNotEmpty) return declared;
  final name = f.name.toLowerCase();
  final dot = name.lastIndexOf('.');
  final ext = dot < 0 ? '' : name.substring(dot + 1);
  return switch (ext) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'gif' => 'image/gif',
    'mp4' || 'm4v' => 'video/mp4',
    'webm' => 'video/webm',
    _ => video ? 'video/mp4' : 'image/jpeg',
  };
}

/// Real pixel size, so the feed can reserve the right space before the
/// photo loads instead of jumping. Null when the bytes will not decode.
Future<(int, int)?> _imageSize(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final w = frame.image.width, h = frame.image.height;
    frame.image.dispose();
    codec.dispose();
    return (w, h);
  } catch (_) {
    return null;
  }
}
