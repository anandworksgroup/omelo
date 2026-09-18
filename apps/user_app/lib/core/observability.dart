import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Crash and error reporting.
///
/// Off unless the build is given a Sentry DSN:
///
///   flutter build web --release --dart-define=SENTRY_DSN=https://KEY@oXXX.ingest.sentry.io/PROJECT
///
/// Without it every report is a `debugPrint` and nothing leaves the device.
/// With it, a minimal Sentry envelope is POSTed over HTTPS — no SDK, no
/// breadcrumbs, no user, no device fingerprint. Report text is scrubbed of
/// emails, phone numbers, tokens and keys, and capped in length, so message
/// bodies and credentials never reach the error tracker.
class Observability {
  static const dsn = String.fromEnvironment('SENTRY_DSN');
  static const release =
      String.fromEnvironment('APP_VERSION', defaultValue: 'omelo_user_app@0.1.0+1');

  /// At most this many reports per app run, so an error in a build method
  /// cannot flood the tracker (or the worker's data plan).
  static const maxReportsPerRun = 20;

  static int _sent = 0;

  /// Tests inject a fake client.
  @visibleForTesting
  static http.Client? client;

  @visibleForTesting
  static void resetForTest() => _sent = 0;

  /// Hooks Flutter framework errors and uncaught platform errors. Call once,
  /// inside the zone that runs the app.
  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (previous != null) {
        previous(details);
      } else {
        FlutterError.presentError(details);
      }
      unawaited(reportError(details.exception,
          details.stack ?? StackTrace.current,
          context: 'flutter'));
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      unawaited(reportError(error, stack, context: 'platform'));
      return true;
    };
  }
}

/// A parsed Sentry DSN: `https://PUBLIC_KEY@HOST/PROJECT_ID`.
class SentryDsn {
  const SentryDsn({
    required this.publicKey,
    required this.origin,
    required this.projectId,
  });

  final String publicKey;
  final String origin;
  final String projectId;

  static SentryDsn? tryParse(String dsn) {
    final uri = Uri.tryParse(dsn.trim());
    if (uri == null || !uri.hasAuthority || uri.userInfo.isEmpty) return null;
    if (uri.scheme != 'https' && uri.scheme != 'http') return null;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.isEmpty) return null;
    final key = uri.userInfo.split(':').first;
    if (key.isEmpty) return null;
    final prefix = segments.length > 1
        ? '/${segments.sublist(0, segments.length - 1).join('/')}'
        : '';
    return SentryDsn(
      publicKey: key,
      origin: '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}$prefix',
      projectId: segments.last,
    );
  }

  /// Auth goes in the query string, so a browser sends a simple request with
  /// no CORS preflight.
  Uri get envelopeUri => Uri.parse('$origin/api/$projectId/envelope/').replace(
        queryParameters: {
          'sentry_key': publicKey,
          'sentry_version': '7',
          'sentry_client': 'omelo-dart/1.0',
        },
      );
}

/// Report an error. Returns true only when a report was actually sent.
///
/// [context] is a short developer label such as 'flutter', 'zone' or
/// 'apply' — never user input.
Future<bool> reportError(
  Object error,
  StackTrace stack, {
  String? context,
  String dsn = Observability.dsn,
}) async {
  final parsed = SentryDsn.tryParse(dsn);
  if (parsed == null) {
    debugPrint('[Omelo error${context == null ? '' : ' · $context'}] '
        '${scrubReportText('$error')}');
    return false;
  }
  if (Observability._sent >= Observability.maxReportsPerRun) return false;
  Observability._sent++;

  try {
    final body = buildSentryEnvelope(
      error,
      stack,
      dsn: dsn,
      context: context,
      release: Observability.release,
      environment: kReleaseMode ? 'production' : 'development',
    );
    final client = Observability.client ?? http.Client();
    try {
      final res = await client
          .post(parsed.envelopeUri,
              headers: {'Content-Type': 'text/plain;charset=UTF-8'},
              body: body)
          .timeout(const Duration(seconds: 8));
      return res.statusCode >= 200 && res.statusCode < 300;
    } finally {
      if (Observability.client == null) client.close();
    }
  } catch (e) {
    // Reporting must never become its own crash.
    debugPrint('[Omelo error] could not send report: ${e.runtimeType}');
    return false;
  }
}

/// The envelope body: header line, item header line, event JSON.
@visibleForTesting
String buildSentryEnvelope(
  Object error,
  StackTrace stack, {
  required String dsn,
  String? context,
  String release = Observability.release,
  String environment = 'development',
  DateTime? now,
}) {
  final at = (now ?? DateTime.now()).toUtc().toIso8601String();
  final id = _eventId();
  final event = <String, dynamic>{
    'event_id': id,
    'timestamp': at,
    'platform': 'dart',
    'level': 'error',
    'logger': 'omelo',
    'release': release,
    'environment': environment,
    'tags': {
      if (context != null) 'context': scrubReportText(context, max: 60),
      'web': kIsWeb.toString(),
      'os': defaultTargetPlatform.name,
    },
    'exception': {
      'values': [
        {
          'type': error.runtimeType.toString(),
          'value': scrubReportText('$error'),
          'stacktrace': {'frames': stackFrames(stack)},
        },
      ],
    },
  };
  final payload = jsonEncode(event);
  return [
    jsonEncode({'event_id': id, 'sent_at': at, 'dsn': dsn}),
    jsonEncode({
      'type': 'event',
      'content_type': 'application/json',
      'length': utf8.encode(payload).length,
    }),
    payload,
  ].join('\n');
}

/// Frames for Sentry, oldest call first. Only file, function and line —
/// never argument values (Dart stack traces do not carry them anyway).
@visibleForTesting
List<Map<String, dynamic>> stackFrames(StackTrace stack, {int max = 40}) {
  final vm = RegExp(r'^#\d+\s+(.+?) \((.+?)(?::(\d+))?(?::(\d+))?\)$');
  final frames = <Map<String, dynamic>>[];
  for (final raw in stack.toString().split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = vm.firstMatch(line);
    if (m != null) {
      final file = m.group(2)!;
      frames.add({
        'function': m.group(1),
        'filename': file,
        'abs_path': file,
        if (m.group(3) != null) 'lineno': int.tryParse(m.group(3)!),
        'in_app': file.contains('omelo_user_app'),
      });
    } else {
      frames.add({'function': scrubReportText(line, max: 200)});
    }
    if (frames.length >= max) break;
  }
  return frames.reversed.toList();
}

/// Removes anything personal or secret from free text before it is reported.
String scrubReportText(String s, {int max = 500}) {
  var out = s
      // JWTs / access and refresh tokens
      .replaceAll(
          RegExp(r'eyJ[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]+\.[A-Za-z0-9_\-]*'),
          '[token]')
      .replaceAll(RegExp(r'bearer\s+\S+', caseSensitive: false), 'Bearer [token]')
      .replaceAll(RegExp(r'sb_(publishable|secret)_[A-Za-z0-9_\-]+'), '[key]')
      .replaceAllMapped(
          RegExp(r'(password|token|code|apikey|api_key|secret)=([^&\s]+)',
              caseSensitive: false),
          (m) => '${m.group(1)}=[redacted]')
      // emails
      .replaceAll(RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}'),
          '[email]')
      // phone numbers and other long digit runs (OTP codes, ids)
      .replaceAll(RegExp(r'\+?\d[\d \-]{7,}\d'), '[number]')
      .replaceAll(RegExp(r'\b\d{6}\b'), '[number]')
      // long opaque strings
      .replaceAll(RegExp(r'[A-Za-z0-9_\-]{40,}'), '[redacted]');
  if (out.length > max) out = '${out.substring(0, max)}…';
  return out;
}

String _eventId() {
  final r = Random();
  return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
}
