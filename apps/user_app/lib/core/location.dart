import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'env.dart';

/// Where the worker is searching from.
///
/// UC-6: declining location permission must never dead-end. We fall back to
/// the last known position, then to a city-centre default, and always tell
/// the user which one is in use so an empty result set is explainable.
class Origin {
  const Origin({
    required this.lat,
    required this.lng,
    required this.source,
    this.label,
  });

  final double lat;
  final double lng;
  final OriginSource source;
  final String? label;

  bool get isPrecise => source == OriginSource.device;
}

enum OriginSource { device, saved, fallback }

final originProvider =
    AsyncNotifierProvider<OriginNotifier, Origin>(OriginNotifier.new);

class OriginNotifier extends AsyncNotifier<Origin> {
  static const _kLat = 'origin_lat';
  static const _kLng = 'origin_lng';
  static const _kLabel = 'origin_label';

  @override
  Future<Origin> build() async {
    final prefs = await SharedPreferences.getInstance();
    final savedLat = prefs.getDouble(_kLat);
    final savedLng = prefs.getDouble(_kLng);

    if (savedLat != null && savedLng != null) {
      return Origin(
        lat: savedLat,
        lng: savedLng,
        source: OriginSource.saved,
        label: prefs.getString(_kLabel),
      );
    }
    return const Origin(
      lat: Env.fallbackLat,
      lng: Env.fallbackLng,
      source: OriginSource.fallback,
      label: 'Delhi NCR',
    );
  }

  /// Requests device location. Returns false if the user declined, so the
  /// caller can explain rather than silently showing the wrong area.
  Future<bool> useDeviceLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 12),
        ),
      );

      await _persist(pos.latitude, pos.longitude, null);
      state = AsyncData(Origin(
        lat: pos.latitude,
        lng: pos.longitude,
        source: OriginSource.device,
      ));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Manual area selection — the path for a worker who will not or cannot
  /// share device location.
  Future<void> setManual(double lat, double lng, String label) async {
    await _persist(lat, lng, label);
    state = AsyncData(
      Origin(lat: lat, lng: lng, source: OriginSource.saved, label: label),
    );
  }

  Future<void> _persist(double lat, double lng, String? label) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kLat, lat);
    await prefs.setDouble(_kLng, lng);
    if (label != null) {
      await prefs.setString(_kLabel, label);
    } else {
      await prefs.remove(_kLabel);
    }
  }
}
