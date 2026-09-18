import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:omelo_user_app/core/observability.dart';

void main() {
  setUp(Observability.resetForTest);
  tearDown(() => Observability.client = null);

  test('no DSN in this build', () {
    expect(Observability.dsn, isEmpty);
  });

  test('reportError is a no-op without a DSN', () async {
    var calls = 0;
    Observability.client = MockClient((_) async {
      calls++;
      return http.Response('', 200);
    });
    final sent = await reportError(StateError('boom'), StackTrace.current,
        context: 'test');
    expect(sent, isFalse);
    expect(calls, 0);
  });

  test('an invalid DSN is also a no-op', () async {
    var calls = 0;
    Observability.client = MockClient((_) async {
      calls++;
      return http.Response('', 200);
    });
    expect(
        await reportError(StateError('x'), StackTrace.current,
            dsn: 'not a dsn'),
        isFalse);
    expect(calls, 0);
  });

  test('DSN parsing', () {
    final d = SentryDsn.tryParse('https://abc123@o42.ingest.sentry.io/7')!;
    expect(d.publicKey, 'abc123');
    expect(d.projectId, '7');
    final uri = d.envelopeUri;
    expect(uri.host, 'o42.ingest.sentry.io');
    expect(uri.path, '/api/7/envelope/');
    expect(uri.queryParameters['sentry_key'], 'abc123');
    expect(SentryDsn.tryParse(''), isNull);
    expect(SentryDsn.tryParse('https://o42.ingest.sentry.io/7'), isNull);
  });

  test('with a DSN it posts one scrubbed envelope', () async {
    late http.Request captured;
    Observability.client = MockClient((req) async {
      captured = req;
      return http.Response('{}', 200);
    });
    final sent = await reportError(
      Exception('failed for worker@example.com with token '
          'eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.c2lnbmF0dXJl code 123456 '
          'phone +919876543210'),
      StackTrace.current,
      context: 'apply',
      dsn: 'https://abc123@o42.ingest.sentry.io/7',
    );
    expect(sent, isTrue);
    expect(captured.url.path, '/api/7/envelope/');

    final lines = captured.body.split('\n');
    expect(lines, hasLength(3));
    final event = jsonDecode(lines[2]) as Map<String, dynamic>;
    final value =
        (event['exception']['values'] as List).first['value'] as String;
    expect(value, isNot(contains('worker@example.com')));
    expect(value, isNot(contains('eyJ')));
    expect(value, isNot(contains('123456')));
    expect(value, isNot(contains('9876543210')));
    expect(event['tags']['context'], 'apply');
    expect(event.containsKey('user'), isFalse);
    expect(captured.body, isNot(contains('worker@example.com')));
  });

  test('reports are capped per run', () async {
    var calls = 0;
    Observability.client = MockClient((_) async {
      calls++;
      return http.Response('', 200);
    });
    for (var i = 0; i < Observability.maxReportsPerRun + 5; i++) {
      await reportError(StateError('x'), StackTrace.current,
          dsn: 'https://abc@o1.ingest.sentry.io/1');
    }
    expect(calls, Observability.maxReportsPerRun);
  });

  test('a failing tracker never throws', () async {
    Observability.client = MockClient((_) async => throw Exception('offline'));
    expect(
        await reportError(StateError('x'), StackTrace.current,
            dsn: 'https://abc@o1.ingest.sentry.io/1'),
        isFalse);
  });

  test('scrubbing', () {
    expect(scrubReportText('mail a.b@c.io now'), 'mail [email] now');
    expect(scrubReportText('Bearer abc.def'), 'Bearer [token]');
    expect(scrubReportText('key sb_publishable_abcDEF123'), 'key [key]');
    expect(scrubReportText('?password=hunter22&x=1'),
        '?password=[redacted]&x=1');
    expect(scrubReportText('x' * 900).length, lessThanOrEqualTo(501));
  });
}
