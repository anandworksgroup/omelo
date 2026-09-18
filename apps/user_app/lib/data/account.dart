import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

/// Account and trust models (Release 1). Pure Dart so they can be tested
/// without a Supabase connection.

Map<String, dynamic> _asMap(dynamic v) {
  // RPCs returning jsonb sometimes come back wrapped in a one-element list.
  if (v is List && v.isNotEmpty) v = v.first;
  if (v is Map) return Map<String, dynamic>.from(v);
  return const {};
}

DateTime? _date(dynamic v) =>
    v is String && v.isNotEmpty ? DateTime.tryParse(v)?.toLocal() : null;

bool _bool(dynamic v) => v == true || v == 'true';

/// `omelo_my_trust_status()`.
class TrustStatus {
  const TrustStatus({
    this.email,
    this.emailVerified = false,
    this.phone,
    this.phoneVerified = false,
    this.identityVerified = false,
    this.verifiedEmployments = 0,
    this.phoneOtpAvailable = false,
    this.emailRequiredToAcceptOffer = false,
    this.deletionScheduledFor,
  });

  final String? email;
  final bool emailVerified;
  final String? phone;
  final bool phoneVerified;
  final bool identityVerified;
  final int verifiedEmployments;
  final bool phoneOtpAvailable;
  final bool emailRequiredToAcceptOffer;
  final DateTime? deletionScheduledFor;

  factory TrustStatus.fromJson(dynamic json) {
    final m = _asMap(json);
    final employments = m['verified_employments'];
    String? text(dynamic v) =>
        v is String && v.trim().isNotEmpty ? v.trim() : null;
    return TrustStatus(
      email: text(m['email']),
      emailVerified: _bool(m['email_verified']),
      phone: text(m['phone']),
      phoneVerified: _bool(m['phone_verified']),
      identityVerified: _bool(m['identity_verified']),
      verifiedEmployments: employments is num
          ? employments.toInt()
          : int.tryParse('${employments ?? ''}') ?? 0,
      phoneOtpAvailable: _bool(m['phone_otp_available']),
      emailRequiredToAcceptOffer: _bool(m['email_required_to_accept_offer']),
      deletionScheduledFor: _date(m['deletion_scheduled_for']),
    );
  }

  bool get deletionScheduled => deletionScheduledFor != null;

  /// The offer card should send the worker to verify before accepting.
  bool get mustVerifyEmailToAcceptOffer =>
      emailRequiredToAcceptOffer && !emailVerified;
}

/// Result of asking for a verification code.
class CodeRequest {
  const CodeRequest({this.sentTo, this.expiresAt, this.alreadyVerified = false});
  final String? sentTo;
  final DateTime? expiresAt;
  final bool alreadyVerified;

  factory CodeRequest.fromJson(dynamic json) {
    final m = _asMap(json);
    return CodeRequest(
      sentTo: m['sent_to'] as String?,
      expiresAt: _date(m['expires_at']),
      alreadyVerified: _bool(m['already_verified']),
    );
  }
}

/// One row of `omelo_my_sessions()`.
class DeviceSession {
  const DeviceSession({
    required this.id,
    this.createdAt,
    this.lastActiveAt,
    this.userAgent,
    this.ipHint,
    this.isCurrent = false,
  });

  final String id;
  final DateTime? createdAt;
  final DateTime? lastActiveAt;
  final String? userAgent;
  final String? ipHint;
  final bool isCurrent;

  factory DeviceSession.fromRow(Map<String, dynamic> m) => DeviceSession(
        id: '${m['id']}',
        createdAt: _date(m['created_at']),
        lastActiveAt: _date(m['last_active_at']),
        userAgent: m['user_agent'] as String?,
        ipHint: m['ip_hint'] as String?,
        isCurrent: _bool(m['is_current']),
      );

  String get label => deviceLabel(userAgent);
  bool get isPhone => deviceIsPhone(userAgent);
}

/// The User-Agent the mobile app sends, so "Devices signed in" can say
/// "Omelo app on Android" instead of "Dart".
String omeloAppUserAgent(String platform) => 'OmeloApp/1 ($platform)';

/// A friendly name for a device from its user agent:
/// "Chrome on Android", "Safari on iPhone", "Omelo app on iPhone".
String deviceLabel(String? userAgent) {
  final ua = (userAgent ?? '').trim();
  if (ua.isEmpty) return 'Unknown device';
  final l = ua.toLowerCase();

  final os = l.contains('iphone')
      ? 'iPhone'
      : l.contains('ipad')
          ? 'iPad'
          : l.contains('android')
              ? 'Android'
              : l.contains('cros')
                  ? 'Chromebook'
                  : l.contains('windows')
                      ? 'Windows'
                      : (l.contains('macintosh') || l.contains('mac os'))
                          ? 'Mac'
                          : (l.contains('ios') || l.contains('darwin'))
                              ? 'iPhone'
                              : l.contains('linux')
                                  ? 'Linux'
                                  : null;

  // Our own app first: it names itself, or it is the plain Dart client.
  if (l.startsWith('omeloapp') || l.startsWith('dart/')) {
    return os == null ? 'Omelo app' : 'Omelo app on $os';
  }

  final browser = l.contains('edg/') || l.contains('edga/') || l.contains('edgios/')
      ? 'Edge'
      : (l.contains('opr/') || l.contains('opera'))
          ? 'Opera'
          : l.contains('samsungbrowser')
              ? 'Samsung Internet'
              : (l.contains('firefox/') || l.contains('fxios/'))
                  ? 'Firefox'
                  : (l.contains('chrome/') || l.contains('crios/'))
                      ? 'Chrome'
                      : l.contains('safari/')
                          ? 'Safari'
                          : null;

  if (browser != null && os != null) return '$browser on $os';
  if (browser != null) return browser;
  if (os != null) return os;
  return 'Unknown device';
}

bool deviceIsPhone(String? userAgent) {
  final l = (userAgent ?? '').toLowerCase();
  return l.contains('android') ||
      l.contains('iphone') ||
      l.contains('mobile') ||
      l.startsWith('dart/') ||
      l.startsWith('omeloapp');
}

// -- Messages ---------------------------------------------------------------

const _connectionProblem =
    'That did not go through. Check your connection and try again.';

/// The server's own words when it gave any (they are written for people),
/// otherwise a plain fallback. Never a stack trace or error code.
String serverMessage(Object e, {String fallback = _connectionProblem}) {
  if (e is PostgrestException && e.message.trim().isNotEmpty) {
    return e.message.trim();
  }
  if (e is AuthException && e.message.trim().isNotEmpty) {
    return e.message.trim();
  }
  return fallback;
}

/// Applying failed. Rate limits (30/hour, 100/day) come back from the server
/// as a readable sentence — show it, not a generic failure.
String applyErrorMessage(Object e) {
  if (e is PostgrestException && e.code == '23505') {
    return 'You have already applied to this job.';
  }
  return serverMessage(e,
      fallback: 'Could not send your application. Check your connection.');
}

/// Accepting an offer failed because the email must be verified first.
bool isVerifyEmailToAcceptError(Object e) {
  final m = e is PostgrestException
      ? e.message
      : e is AuthException
          ? e.message
          : '$e';
  return m.toLowerCase().contains('verify your email');
}

/// Password rules shared by sign-up, change password and reset.
String? passwordProblem(String password, String confirm) {
  if (password.length < 8) return 'Use at least 8 characters.';
  if (password != confirm) return 'The two passwords do not match.';
  return null;
}

/// Changing or resetting a password failed.
String passwordChangeError(Object e) {
  if (e is AuthException) {
    final m = e.message.toLowerCase();
    if (m.contains('different from the old')) {
      return 'Choose a password you have not used here before.';
    }
    if (m.contains('weak') || m.contains('at least')) {
      return 'That password is too easy to guess. Try a longer one.';
    }
    if (m.contains('reauthent') || m.contains('session')) {
      return 'For your safety, sign in again and then change your password.';
    }
  }
  return serverMessage(e);
}

/// Only an email that looks like one is worth sending a reset link to.
bool looksLikeEmail(String s) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(s.trim());

/// "just now" · "5 minutes ago" · "3 hours ago" · "2 days ago"
String lastActive(DateTime? at, {DateTime? now}) {
  if (at == null) return 'Not known';
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 2) return 'Active now';
  if (d.inMinutes < 60) return 'Active ${d.inMinutes} minutes ago';
  if (d.inHours < 2) return 'Active 1 hour ago';
  if (d.inHours < 24) return 'Active ${d.inHours} hours ago';
  if (d.inDays < 2) return 'Active yesterday';
  return 'Active ${d.inDays} days ago';
}
