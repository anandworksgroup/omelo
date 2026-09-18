import 'package:flutter_test/flutter_test.dart';
import 'package:omelo_user_app/core/auth_links.dart';
import 'package:omelo_user_app/data/account.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show AuthException, PostgrestException;

void main() {
  group('deviceLabel', () {
    const cases = {
      'Mozilla/5.0 (Linux; Android 13; SM-A135F) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36':
          'Chrome on Android',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1':
          'Safari on iPhone',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/124.0 Mobile/15E148 Safari/604.1':
          'Chrome on iPhone',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36 Edg/124.0.0.0':
          'Edge on Windows',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36':
          'Chrome on Mac',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 14.4; rv:125.0) Gecko/20100101 Firefox/125.0':
          'Firefox on Mac',
      'Mozilla/5.0 (Linux; Android 12; SM-M325F) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/24.0 Chrome/117.0.0.0 Mobile Safari/537.36':
          'Samsung Internet on Android',
      'OmeloApp/1 (Android)': 'Omelo app on Android',
      'OmeloApp/1 (iPhone)': 'Omelo app on iPhone',
      'Dart/3.8 (dart:io)': 'Omelo app',
      'curl/8.4.0': 'Unknown device',
      '': 'Unknown device',
    };
    cases.forEach((ua, label) {
      test(label.isEmpty ? '(empty)' : '$label <- ${ua.split(' ').first}', () {
        expect(deviceLabel(ua), label);
      });
    });

    test('null user agent', () => expect(deviceLabel(null), 'Unknown device'));

    test('the app\'s own user agent round-trips', () {
      expect(deviceLabel(omeloAppUserAgent('Android')), 'Omelo app on Android');
      expect(deviceLabel(omeloAppUserAgent('iPhone')), 'Omelo app on iPhone');
    });

    test('phones get a phone icon', () {
      expect(deviceIsPhone('OmeloApp/1 (Android)'), isTrue);
      expect(deviceIsPhone(
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/124.0 Safari/537.36'),
          isFalse);
    });
  });

  group('TrustStatus', () {
    test('parses the RPC payload', () {
      final t = TrustStatus.fromJson({
        'email': 'worker@example.com',
        'email_verified': false,
        'phone': null,
        'phone_verified': false,
        'identity_verified': true,
        'verified_employments': 2,
        'phone_otp_available': false,
        'email_required_to_accept_offer': true,
        'deletion_scheduled_for': '2026-10-02T03:17:00+00:00',
      });
      expect(t.email, 'worker@example.com');
      expect(t.emailVerified, isFalse);
      expect(t.phone, isNull);
      expect(t.identityVerified, isTrue);
      expect(t.verifiedEmployments, 2);
      expect(t.phoneOtpAvailable, isFalse);
      expect(t.mustVerifyEmailToAcceptOffer, isTrue);
      expect(t.deletionScheduled, isTrue);
      expect(t.deletionScheduledFor!.toUtc(),
          DateTime.utc(2026, 10, 2, 3, 17));
    });

    test('accepts a one-element list and missing fields', () {
      final t = TrustStatus.fromJson([
        {'email_verified': true, 'email_required_to_accept_offer': true}
      ]);
      expect(t.emailVerified, isTrue);
      expect(t.mustVerifyEmailToAcceptOffer, isFalse);
      expect(t.deletionScheduled, isFalse);
      expect(t.verifiedEmployments, 0);
    });

    test('garbage in, safe defaults out', () {
      final t = TrustStatus.fromJson(null);
      expect(t.emailVerified, isFalse);
      expect(t.mustVerifyEmailToAcceptOffer, isFalse);
      expect(t.deletionScheduledFor, isNull);
    });

    test('offer needs verification only when the flag is on', () {
      expect(
          TrustStatus.fromJson({'email_required_to_accept_offer': false})
              .mustVerifyEmailToAcceptOffer,
          isFalse);
    });
  });

  group('CodeRequest and DeviceSession', () {
    test('code request', () {
      final r = CodeRequest.fromJson(
          {'sent_to': 'w***@e***.com', 'expires_at': '2026-09-18T10:15:00Z'});
      expect(r.sentTo, 'w***@e***.com');
      expect(r.alreadyVerified, isFalse);
      expect(CodeRequest.fromJson({'already_verified': true}).alreadyVerified,
          isTrue);
    });

    test('session row', () {
      final s = DeviceSession.fromRow({
        'id': 'a1',
        'created_at': '2026-09-17T10:00:00Z',
        'last_active_at': '2026-09-18T09:00:00Z',
        'user_agent': 'OmeloApp/1 (Android)',
        'ip_hint': '49.36.x.x',
        'is_current': true,
      });
      expect(s.label, 'Omelo app on Android');
      expect(s.isCurrent, isTrue);
      expect(s.isPhone, isTrue);
    });

    test('last active wording', () {
      final now = DateTime(2026, 9, 18, 12);
      expect(lastActive(now.subtract(const Duration(seconds: 30)), now: now),
          'Active now');
      expect(lastActive(now.subtract(const Duration(minutes: 5)), now: now),
          'Active 5 minutes ago');
      expect(lastActive(now.subtract(const Duration(hours: 3)), now: now),
          'Active 3 hours ago');
      expect(lastActive(now.subtract(const Duration(days: 4)), now: now),
          'Active 4 days ago');
      expect(lastActive(null), 'Not known');
    });
  });

  group('messages', () {
    const rateLimit =
        'You have applied to a lot of jobs today. Please wait a while before applying again.';

    test('apply rate limit shows the server sentence', () {
      expect(
          applyErrorMessage(
              const PostgrestException(message: rateLimit, code: '54000')),
          rateLimit);
    });

    test('duplicate application', () {
      expect(
          applyErrorMessage(const PostgrestException(
              message: 'duplicate key value violates unique constraint',
              code: '23505')),
          'You have already applied to this job.');
    });

    test('network failure falls back to plain words', () {
      expect(applyErrorMessage(Exception('SocketException: failed host lookup')),
          contains('Check your connection'));
    });

    test('offer needs a verified email', () {
      const e = PostgrestException(
          message: 'Verify your email address before accepting an offer',
          code: '22023');
      expect(isVerifyEmailToAcceptError(e), isTrue);
      expect(
          isVerifyEmailToAcceptError(
              const PostgrestException(message: 'This offer has expired')),
          isFalse);
    });

    test('verification errors are shown as the server wrote them', () {
      expect(
          serverMessage(const PostgrestException(
              message: 'That code is not right. Check it and try again.',
              code: '22023')),
          'That code is not right. Check it and try again.');
    });

    test('password rules', () {
      expect(passwordProblem('short', 'short'), isNotNull);
      expect(passwordProblem('longenough1', 'longenough2'),
          'The two passwords do not match.');
      expect(passwordProblem('longenough1', 'longenough1'), isNull);
      expect(
          passwordChangeError(const AuthException(
              'New password should be different from the old password.')),
          'Choose a password you have not used here before.');
    });

    test('email shape check', () {
      expect(looksLikeEmail('a@b.co'), isTrue);
      expect(looksLikeEmail(' worker@example.com '), isTrue);
      expect(looksLikeEmail('not-an-email'), isFalse);
    });
  });

  group('password reset redirect', () {
    test('web keeps the hash route', () {
      expect(
          AuthLinks.passwordResetRedirectFor(
              web: true, base: Uri.parse('https://app.omelo.in/#/sign-in')),
          'https://app.omelo.in/#/reset-password');
      expect(
          AuthLinks.passwordResetRedirectFor(
              web: true, base: Uri.parse('http://localhost:5000/app/')),
          'http://localhost:5000/app/#/reset-password');
    });

    test('mobile uses the app scheme', () {
      expect(AuthLinks.passwordResetRedirectFor(web: false),
          'com.omelo.app://reset-password');
    });
  });
}
