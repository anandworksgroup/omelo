import 'package:flutter_test/flutter_test.dart';
import 'package:omelo_user_app/data/hiring.dart';

void main() {
  const room = 'om-0123456789abcdef0123456789abcdef0123';
  final interviewJson = {
    'interview_id': 'i1',
    'application_id': 'a1',
    'job_title': 'Delivery driver',
    'company_name': 'Fresh Mart',
    'candidate_name': 'Ravi',
    'round': 2,
    'round_name': 'Technical Interview',
    'meeting_mode': 'omelo_meet',
    'scheduled_at': '2026-09-17T10:30:00Z',
    'duration_minutes': 30,
    'timezone': 'Asia/Kolkata',
    'location_text': null,
    'instructions': 'Keep your licence ready',
    'room_name': room,
  };

  group('room names', () {
    test('only om- plus 36 hex is a room', () {
      expect(isValidRoomName(room), isTrue);
      expect(isValidRoomName('om-xyz'), isFalse);
      expect(isValidRoomName('https://zoom.us/j/1'), isFalse);
      expect(isValidRoomName(room.toUpperCase()), isFalse);
    });
  });

  group('meet-token response parsing', () {
    test('too_early carries opens_at, scheduled_at and the interview', () {
      final r = MeetJoinResult.parse(200, {
        'state': 'too_early',
        'role': 'candidate',
        'opens_at': '2026-09-17T10:15:00Z',
        'scheduled_at': '2026-09-17T10:30:00Z',
        'interview': interviewJson,
      });
      expect(r, isA<MeetTooEarly>());
      final t = r as MeetTooEarly;
      expect(t.opensAt, DateTime.utc(2026, 9, 17, 10, 15).toLocal());
      expect(t.scheduledAt, DateTime.utc(2026, 9, 17, 10, 30).toLocal());
      expect(t.interview?.applicationId, 'a1');
      expect(t.interview?.round, 2);
      expect(t.interview?.title, 'Omelo Meet · Technical Interview · Fresh Mart');
    });

    test('waiting', () {
      final r = MeetJoinResult.parse(
          200, {'state': 'waiting', 'interview': interviewJson});
      expect(r, isA<MeetWaiting>());
      expect(r.interview?.interviewId, 'i1');
    });

    test('admitted carries url and token', () {
      final r = MeetJoinResult.parse(200, {
        'state': 'admitted',
        'url': 'wss://omelo.livekit.cloud',
        'token': 'jwt',
        'expires_at': '2026-09-17T10:40:00Z',
        'role': 'candidate',
        'identity': 'u1',
        'display_name': 'Ravi',
        'closes_at': '2026-09-17T12:00:00Z',
        'interview': interviewJson,
      });
      expect(r, isA<MeetAdmitted>());
      final a = r as MeetAdmitted;
      expect(a.url, 'wss://omelo.livekit.cloud');
      expect(a.token, 'jwt');
      expect(a.identity, 'u1');
      expect(a.displayName, 'Ravi');
      expect(a.closesAt, DateTime.utc(2026, 9, 17, 12).toLocal());
    });

    test('admitted without a token is an error, not a crash', () {
      final r = MeetJoinResult.parse(200, {'state': 'admitted'});
      expect(r, isA<MeetJoinError>());
    });

    test('503 meet_not_configured is unavailable, with the interview', () {
      final r = MeetJoinResult.parse(503, {
        'state': 'unavailable',
        'code': 'meet_not_configured',
        'error': 'Omelo Meet video is not switched on for this environment yet.',
        'role': 'candidate',
        'interview': interviewJson,
      });
      expect(r, isA<MeetUnavailable>());
      final u = r as MeetUnavailable;
      expect(u.notConfigured, isTrue);
      expect(u.interview?.applicationId, 'a1');
    });

    test('503 with an empty body is still unavailable', () {
      expect(MeetJoinResult.parse(503, null), isA<MeetUnavailable>());
    });

    test('403 / 409 / 429 show the server message', () {
      final ended = MeetJoinResult.parse(
          409, {'error': 'This interview has ended', 'code': '22023'});
      expect(ended, isA<MeetJoinError>());
      expect((ended as MeetJoinError).message, 'This interview has ended');
      expect(ended.interviewEnded, isTrue);
      expect(ended.retryable, isFalse);

      final forbidden = MeetJoinResult.parse(
          403, {'error': 'You cannot join this interview', 'code': '42501'});
      expect((forbidden as MeetJoinError).message,
          'You cannot join this interview');
      expect(forbidden.interviewEnded, isFalse);

      final limited = MeetJoinResult.parse(429,
          {'error': 'Too many attempts. Wait a moment and try again.', 'code': '54000'});
      expect((limited as MeetJoinError).retryable, isTrue);
    });

    test('error without a body gets a plain default', () {
      final r = MeetJoinResult.parse(403, 'Forbidden') as MeetJoinError;
      expect(r.message, 'You cannot join this interview.');
    });

    test('unknown 200 state is an error', () {
      expect(MeetJoinResult.parse(200, {'state': 'party'}), isA<MeetJoinError>());
    });
  });

  group('join window and countdown', () {
    final start = DateTime(2026, 9, 17, 10, 30);
    final window = MeetWindow.forInterview(scheduledAt: start, durationMinutes: 30);

    test('falls back to 15 min before / 60 min after the end', () {
      expect(window.opensAt, DateTime(2026, 9, 17, 10, 15));
      expect(window.closesAt, DateTime(2026, 9, 17, 12, 0));
    });

    test('room times win over the fallback', () {
      final w = MeetWindow.forInterview(
        room: InterviewRoom(
          interviewId: 'i1',
          roomName: room,
          status: 'scheduled',
          opensAt: DateTime(2026, 9, 17, 10, 0),
          closesAt: DateTime(2026, 9, 17, 11, 0),
        ),
        scheduledAt: start,
        durationMinutes: 30,
      );
      expect(w.opensAt, DateTime(2026, 9, 17, 10, 0));
      expect(w.closesAt, DateTime(2026, 9, 17, 11, 0));
    });

    test('not yet → open at opens_at → closed at closes_at', () {
      expect(window.state(DateTime(2026, 9, 17, 10, 14, 59)),
          MeetWindowState.notYet);
      expect(window.state(DateTime(2026, 9, 17, 10, 15)), MeetWindowState.open);
      expect(window.state(DateTime(2026, 9, 17, 11, 59)), MeetWindowState.open);
      expect(window.state(DateTime(2026, 9, 17, 12, 0)), MeetWindowState.closed);
    });

    test('an ended or cancelled room is closed even inside the window', () {
      final t = DateTime(2026, 9, 17, 10, 40);
      expect(window.state(t, roomStatus: 'ended'), MeetWindowState.closed);
      expect(window.state(t, roomStatus: 'cancelled'), MeetWindowState.closed);
      expect(window.state(t, roomStatus: 'live'), MeetWindowState.open);
    });

    test('time until the button turns on', () {
      expect(window.untilOpen(DateTime(2026, 9, 17, 10, 0)),
          const Duration(minutes: 15));
      expect(window.untilOpen(DateTime(2026, 9, 17, 10, 20)), Duration.zero);
    });

    test('countdown is HH:MM:SS and never negative', () {
      expect(meetCountdown(const Duration(minutes: 18, seconds: 42)), '00:18:42');
      expect(meetCountdown(const Duration(hours: 26, seconds: 5)), '26:00:05');
      expect(meetCountdown(const Duration(seconds: -3)), '00:00:00');
      expect(meetCountdown(const Duration(milliseconds: 400)), '00:00:01');
    });

    test('starts-in label', () {
      expect(
          meetStartsInLabel(start, DateTime(2026, 9, 17, 10, 11, 18)),
          'Interview starts in 00:18:42');
      expect(meetStartsInLabel(start, DateTime(2026, 9, 14, 10, 30)),
          'Interview starts in 3 days');
      expect(meetStartsInLabel(start, DateTime(2026, 9, 17, 10, 31)),
          'Interview has started');
    });
  });

  group('pre-join: opening the link never calls meet-token', () {
    InterviewRoom r({String status = 'scheduled'}) => InterviewRoom(
          interviewId: 'i1',
          roomName: room,
          status: status,
          opensAt: DateTime(2026, 9, 17, 10, 15),
          closesAt: DateTime(2026, 9, 17, 12, 0),
        );

    test('entry is decided from the room row alone', () {
      expect(meetEntryFor(null, DateTime(2026, 9, 17, 10)), MeetEntry.notFound);
      expect(meetEntryFor(r(), DateTime(2026, 9, 17, 10)), MeetEntry.countdown);
      expect(meetEntryFor(r(), DateTime(2026, 9, 17, 10, 15)), MeetEntry.check);
      expect(meetEntryFor(r(status: 'live'), DateTime(2026, 9, 17, 11)),
          MeetEntry.check);
      expect(meetEntryFor(r(), DateTime(2026, 9, 17, 12)), MeetEntry.closed);
      expect(meetEntryFor(r(status: 'cancelled'), DateTime(2026, 9, 17, 10)),
          MeetEntry.closed);
      expect(meetEntryFor(r(status: 'ended'), DateTime(2026, 9, 17, 10, 30)),
          MeetEntry.closed);
    });

    test('join needs the device check AND an open window', () {
      final w = MeetWindow(
        opensAt: DateTime(2026, 9, 17, 10, 15),
        closesAt: DateTime(2026, 9, 17, 12, 0),
      );
      final open = DateTime(2026, 9, 17, 10, 20);
      expect(
          meetMayRequestEntry(devicesChecked: false, window: w, now: open),
          isFalse);
      expect(meetMayRequestEntry(devicesChecked: true, window: w, now: open),
          isTrue);
      expect(
          meetMayRequestEntry(
              devicesChecked: true,
              window: w,
              now: DateTime(2026, 9, 17, 10, 14)),
          isFalse);
      expect(
          meetMayRequestEntry(
              devicesChecked: true,
              window: w,
              now: DateTime(2026, 9, 17, 12, 1)),
          isFalse);
      expect(
          meetMayRequestEntry(
              devicesChecked: true,
              window: w,
              now: open,
              roomStatus: 'cancelled'),
          isFalse);
    });

    test('too_early from the server (clock skew) holds Join back', () {
      final now = DateTime(2026, 9, 17, 10, 16);
      // Server opens_at still ahead on this device: wait for it.
      final serverOpens = DateTime(2026, 9, 17, 10, 17);
      expect(meetRetryAfterTooEarly(now: now, serverOpensAt: serverOpens),
          serverOpens);
      // Server opens_at already past here: this clock is ahead; back off.
      expect(
          meetRetryAfterTooEarly(
              now: now, serverOpensAt: DateTime(2026, 9, 17, 10, 15)),
          now.add(const Duration(seconds: 20)));
      expect(meetRetryAfterTooEarly(now: now), now.add(const Duration(seconds: 20)));

      final w = MeetWindow(
        opensAt: DateTime(2026, 9, 17, 10, 15),
        closesAt: DateTime(2026, 9, 17, 12, 0),
      ).notBefore(serverOpens);
      expect(w.opensAt, serverOpens);
      expect(w.closesAt, DateTime(2026, 9, 17, 12, 0));
      expect(meetMayRequestEntry(devicesChecked: true, window: w, now: now),
          isFalse);
      expect(
          meetMayRequestEntry(
              devicesChecked: true, window: w, now: serverOpens),
          isTrue);
      // notBefore never moves the window earlier.
      final later = MeetWindow(opensAt: DateTime(2026, 9, 17, 11), closesAt: null)
          .notBefore(DateTime(2026, 9, 17, 10));
      expect(later.opensAt, DateTime(2026, 9, 17, 11));
    });

    test('closed messages', () {
      expect(meetClosedMessage('cancelled'), 'This interview was cancelled.');
      expect(meetClosedMessage('ended'), 'This interview has ended.');
      expect(meetClosedMessage('expired'), 'This interview is closed.');
      expect(meetClosedMessage(null), 'This interview is closed.');
    });

    test('header info from a direct interviews read', () {
      final info = MeetInterviewInfo.fromInterviewRow({
        'id': 'i1',
        'application_id': 'a1',
        'round': 2,
        'round_name': 'Technical Interview',
        'meeting_mode': 'omelo_meet',
        'scheduled_at': '2026-09-17T10:30:00Z',
        'duration_minutes': 30,
        'instructions': 'Keep your licence ready',
        'applications': {
          'jobs': {'title': 'Delivery driver'},
          'companies': {'display_name': 'Fresh Mart'},
        },
      }, roomName: room);
      expect(info.interviewId, 'i1');
      expect(info.applicationId, 'a1');
      expect(info.jobTitle, 'Delivery driver');
      expect(info.companyName, 'Fresh Mart');
      expect(info.scheduledAt, DateTime.utc(2026, 9, 17, 10, 30).toLocal());
      expect(info.roomName, room);
      expect(info.title, 'Omelo Meet · Technical Interview · Fresh Mart');
      // Embeds that could not be read leave the header partial, not broken.
      final bare = MeetInterviewInfo.fromInterviewRow({'id': 'i1'});
      expect(bare.companyName, isNull);
      expect(bare.title, 'Omelo Meet · Interview');
    });
  });

  group('device errors', () {
    test('sorted into what the person can do', () {
      expect(classifyDeviceError('NotAllowedError: Permission denied'),
          DeviceIssue.denied);
      expect(classifyDeviceError(Exception('NotFoundError: Requested device not found')),
          DeviceIssue.notFound);
      expect(classifyDeviceError('NotReadableError: Could not start video source'),
          DeviceIssue.inUse);
      expect(classifyDeviceError('boom'), DeviceIssue.failed);
    });
  });

  group('parsing rows', () {
    test('participant admitted / denied', () {
      final p = MeetParticipant.fromRow({
        'interview_id': 'i1',
        'person_id': 'u1',
        'role': 'candidate',
        'status': 'admitted',
      });
      expect(p.isAdmitted, isTrue);
      expect(
          MeetParticipant.fromRow({'status': 'denied'}).isDenied, isTrue);
    });

    test('interview with an embedded room', () {
      final i = Interview.fromRow({
        'id': 'i1',
        'application_id': 'a1',
        'type': 'video',
        'status': 'scheduled',
        'round': 1,
        'round_name': 'Technical Interview',
        'meeting_mode': 'omelo_meet',
        'scheduled_at': '2026-09-17T10:30:00Z',
        'interview_rooms': {
          'interview_id': 'i1',
          'room_name': room,
          'status': 'scheduled',
          'opens_at': '2026-09-17T10:15:00Z',
          'closes_at': '2026-09-17T12:00:00Z',
        },
      });
      expect(i.isOmeloMeet, isTrue);
      expect(i.room?.roomName, room);
      expect(i.title, 'Technical Interview');
    });

    test('meeting mode copy', () {
      expect(MeetCopy.meetingMode('omelo_meet'), 'Omelo Meet video');
      expect(MeetCopy.meetingMode('phone'), 'Phone call');
      expect(MeetCopy.meetingMode('in_person', locationText: '12 MG Road'),
          'In person — 12 MG Road');
    });
  });
}
