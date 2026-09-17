/// Omelo Meet — models, response parsing and join-window logic.
///
/// Pure Dart (no Flutter, no Supabase, no LiveKit) so every rule that decides
/// what the candidate sees can be unit tested. See
/// architecture/A6-omelo-meet.md.
library;

// ---------------------------------------------------------------------------
// Parse helpers
// ---------------------------------------------------------------------------

Map<String, dynamic>? _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

num? _num(dynamic v) =>
    v == null ? null : (v is num ? v : num.tryParse(v.toString()));

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

bool _bool(dynamic v) => v == true || v?.toString() == 'true';

/// Room names are `om-` + 36 hex characters. Anything else is not a room,
/// so there is no point asking the server.
final kRoomNamePattern = RegExp(r'^om-[0-9a-f]{36}$');
bool isValidRoomName(String name) => kRoomNamePattern.hasMatch(name);

/// The room opens this long before the scheduled start.
const kMeetOpensBefore = Duration(minutes: 15);

/// The room closes this long after the scheduled end.
const kMeetClosesAfterEnd = Duration(minutes: 60);

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// `interview_rooms` — one per Omelo Meet interview.
class InterviewRoom {
  const InterviewRoom({
    required this.interviewId,
    required this.roomName,
    required this.status,
    this.opensAt,
    this.closesAt,
    this.waitingRoom = true,
    this.recordingEnabled = false,
  });

  final String interviewId;
  final String roomName;

  /// scheduled | live | ended | expired | cancelled
  final String status;
  final DateTime? opensAt;
  final DateTime? closesAt;
  final bool waitingRoom;

  /// Always false in v1 — the database makes recording impossible.
  final bool recordingEnabled;

  bool get isFinished =>
      status == 'ended' || status == 'expired' || status == 'cancelled';

  factory InterviewRoom.fromRow(Map<String, dynamic> m) => InterviewRoom(
        interviewId: (m['interview_id'] ?? '').toString(),
        roomName: _str(m['room_name']) ?? '',
        status: _str(m['status']) ?? 'scheduled',
        opensAt: _date(m['opens_at']),
        closesAt: _date(m['closes_at']),
        waitingRoom: m['waiting_room'] == null ? true : _bool(m['waiting_room']),
        recordingEnabled: _bool(m['recording_enabled']),
      );
}

/// `job_interview_rounds` — the employer's planned process for the job.
class PlannedRound {
  const PlannedRound({
    required this.position,
    required this.name,
    this.kind = 'general',
    this.meetingMode = 'omelo_meet',
    this.durationMinutes,
  });

  final int position;
  final String name;
  final String kind;
  final String meetingMode;
  final int? durationMinutes;

  factory PlannedRound.fromRow(Map<String, dynamic> m) => PlannedRound(
        position: _num(m['position'])?.toInt() ?? 1,
        name: _str(m['name']) ?? 'Interview',
        kind: _str(m['kind']) ?? 'general',
        meetingMode: _str(m['meeting_mode']) ?? 'omelo_meet',
        durationMinutes: _num(m['duration_minutes'])?.toInt(),
      );
}

/// `interview_participants`
class MeetParticipant {
  const MeetParticipant({
    required this.interviewId,
    required this.personId,
    required this.role,
    required this.status,
    this.displayName,
  });

  final String interviewId;
  final String personId;
  final String? displayName;

  /// candidate | host | interviewer | observer
  final String role;

  /// invited | waiting | admitted | in_room | left | removed | denied
  final String status;

  bool get isAdmitted => status == 'admitted' || status == 'in_room';
  bool get isDenied => status == 'denied';
  bool get isRemoved => status == 'removed';

  factory MeetParticipant.fromRow(Map<String, dynamic> m) => MeetParticipant(
        interviewId: (m['interview_id'] ?? '').toString(),
        personId: (m['person_id'] ?? '').toString(),
        displayName: _str(m['display_name']),
        role: _str(m['role']) ?? 'candidate',
        status: _str(m['status']) ?? 'invited',
      );
}

/// `meet_messages` — in-room chat.
class MeetMessage {
  const MeetMessage({
    required this.id,
    required this.interviewId,
    required this.senderId,
    required this.body,
    required this.sentAt,
    this.senderName,
  });

  final int id;
  final String interviewId;
  final String senderId;
  final String? senderName;
  final String body;
  final DateTime sentAt;

  static const maxLength = 2000;

  factory MeetMessage.fromRow(Map<String, dynamic> m) => MeetMessage(
        id: _num(m['id'])?.toInt() ?? 0,
        interviewId: (m['interview_id'] ?? '').toString(),
        senderId: (m['sender_id'] ?? '').toString(),
        senderName: _str(m['sender_name']),
        body: (m['body'] ?? '').toString(),
        sentAt: _date(m['sent_at']) ?? DateTime.now(),
      );
}

/// The `interview` payload every meet-token response carries.
class MeetInterviewInfo {
  const MeetInterviewInfo({
    this.interviewId,
    this.applicationId,
    this.jobTitle,
    this.companyName,
    this.candidateName,
    this.round,
    this.roundName,
    this.meetingMode,
    this.scheduledAt,
    this.durationMinutes,
    this.timezone,
    this.locationText,
    this.instructions,
    this.roomName,
  });

  final String? interviewId;
  final String? applicationId;
  final String? jobTitle;
  final String? companyName;
  final String? candidateName;
  final int? round;
  final String? roundName;
  final String? meetingMode;
  final DateTime? scheduledAt;
  final int? durationMinutes;
  final String? timezone;
  final String? locationText;
  final String? instructions;
  final String? roomName;

  static MeetInterviewInfo? fromJson(dynamic v) {
    final m = _map(v);
    if (m == null) return null;
    return MeetInterviewInfo(
      interviewId: _str(m['interview_id']),
      applicationId: _str(m['application_id']),
      jobTitle: _str(m['job_title']),
      companyName: _str(m['company_name']),
      candidateName: _str(m['candidate_name']),
      round: _num(m['round'])?.toInt(),
      roundName: _str(m['round_name']),
      meetingMode: _str(m['meeting_mode']),
      scheduledAt: _date(m['scheduled_at']),
      durationMinutes: _num(m['duration_minutes'])?.toInt(),
      timezone: _str(m['timezone']),
      locationText: _str(m['location_text']),
      instructions: _str(m['instructions']),
      roomName: _str(m['room_name']),
    );
  }

  /// "Omelo Meet · Technical Interview · Fresh Mart"
  String get title => [
        'Omelo Meet',
        roundName ?? 'Interview',
        if (companyName != null) companyName!,
      ].join(' · ');
}

// ---------------------------------------------------------------------------
// meet-token responses
// ---------------------------------------------------------------------------

/// What happened when the candidate asked to join a room.
sealed class MeetJoinResult {
  const MeetJoinResult(this.interview);
  final MeetInterviewInfo? interview;

  /// Maps an HTTP status and JSON body from the `meet-token` Edge Function.
  ///
  /// Non-2xx responses reach the app as a `FunctionException` with the
  /// status and the decoded body in `details`; pass those straight in.
  static MeetJoinResult parse(int status, dynamic body) {
    final m = _map(body) ?? const <String, dynamic>{};
    final interview = MeetInterviewInfo.fromJson(m['interview']);
    final state = _str(m['state']);
    final code = _str(m['code']);

    if (status == 503 || state == 'unavailable') {
      return MeetUnavailable(
        interview: interview,
        code: code ?? 'unavailable',
        serverMessage: _str(m['error']),
      );
    }

    if (status >= 200 && status < 300) {
      switch (state) {
        case 'too_early':
          return MeetTooEarly(
            interview: interview,
            opensAt: _date(m['opens_at']),
            scheduledAt: _date(m['scheduled_at']) ?? interview?.scheduledAt,
          );
        case 'waiting':
          return MeetWaiting(interview: interview);
        case 'admitted':
          final url = _str(m['url']);
          final token = _str(m['token']);
          if (url == null || token == null) {
            return MeetJoinError(
              interview: interview,
              status: status,
              code: 'bad_response',
              message: 'Something went wrong joining the interview. '
                  'Please try again.',
            );
          }
          return MeetAdmitted(
            interview: interview,
            url: url,
            token: token,
            expiresAt: _date(m['expires_at']),
            role: _str(m['role']) ?? 'candidate',
            identity: _str(m['identity']) ?? '',
            displayName: _str(m['display_name']) ?? 'You',
            closesAt: _date(m['closes_at']),
          );
      }
      return MeetJoinError(
        interview: interview,
        status: status,
        code: 'bad_response',
        message: 'Something went wrong joining the interview. Please try again.',
      );
    }

    return MeetJoinError(
      interview: interview,
      status: status,
      code: code,
      message: _str(m['error']) ?? _defaultErrorMessage(status),
    );
  }

  static String _defaultErrorMessage(int status) => switch (status) {
        401 => 'Please sign in to join your interview.',
        403 => 'You cannot join this interview.',
        404 => 'We could not find this interview.',
        409 => 'This interview is not open.',
        429 => 'Too many attempts. Wait a moment and try again.',
        _ => 'Could not join the interview. Check your connection and try again.',
      };
}

class MeetTooEarly extends MeetJoinResult {
  const MeetTooEarly({
    required MeetInterviewInfo? interview,
    this.opensAt,
    this.scheduledAt,
  }) : super(interview);

  final DateTime? opensAt;
  final DateTime? scheduledAt;
}

class MeetWaiting extends MeetJoinResult {
  const MeetWaiting({required MeetInterviewInfo? interview}) : super(interview);
}

class MeetAdmitted extends MeetJoinResult {
  const MeetAdmitted({
    required MeetInterviewInfo? interview,
    required this.url,
    required this.token,
    required this.role,
    required this.identity,
    required this.displayName,
    this.expiresAt,
    this.closesAt,
  }) : super(interview);

  final String url;
  final String token;
  final DateTime? expiresAt;
  final String role;
  final String identity;
  final String displayName;
  final DateTime? closesAt;
}

/// The video server is not configured in this environment yet (503).
class MeetUnavailable extends MeetJoinResult {
  const MeetUnavailable({
    required MeetInterviewInfo? interview,
    required this.code,
    this.serverMessage,
  }) : super(interview);

  final String code;
  final String? serverMessage;

  bool get notConfigured => code == 'meet_not_configured';
}

class MeetJoinError extends MeetJoinResult {
  const MeetJoinError({
    required MeetInterviewInfo? interview,
    required this.status,
    required this.message,
    this.code,
  }) : super(interview);

  /// HTTP status, or 0 when the request never reached the server.
  final int status;
  final String? code;

  /// Already in plain words — shown to the candidate as is.
  final String message;

  /// Worth offering "Try again": network trouble or rate limiting.
  bool get retryable => status == 0 || status == 429 || status >= 500;

  /// The interview is over; nothing to rejoin.
  bool get interviewEnded =>
      status == 409 && message.toLowerCase().contains('ended');
}

// ---------------------------------------------------------------------------
// Join window and countdown
// ---------------------------------------------------------------------------

enum MeetWindowState { notYet, open, closed }

class MeetWindow {
  const MeetWindow({required this.opensAt, required this.closesAt});

  final DateTime? opensAt;
  final DateTime? closesAt;

  /// From the room when we have it, otherwise the same rule the database
  /// uses: open 15 min before start, close 60 min after the scheduled end.
  factory MeetWindow.forInterview({
    InterviewRoom? room,
    DateTime? scheduledAt,
    int? durationMinutes,
  }) {
    final opens = room?.opensAt ?? scheduledAt?.subtract(kMeetOpensBefore);
    final closes = room?.closesAt ??
        scheduledAt
            ?.add(Duration(minutes: durationMinutes ?? 30))
            .add(kMeetClosesAfterEnd);
    return MeetWindow(opensAt: opens, closesAt: closes);
  }

  MeetWindowState state(DateTime now, {String? roomStatus}) {
    if (roomStatus == 'ended' ||
        roomStatus == 'expired' ||
        roomStatus == 'cancelled') {
      return MeetWindowState.closed;
    }
    if (closesAt != null && !now.isBefore(closesAt!)) {
      return MeetWindowState.closed;
    }
    if (opensAt != null && now.isBefore(opensAt!)) {
      return MeetWindowState.notYet;
    }
    return MeetWindowState.open;
  }

  /// Time until the Join button turns on; zero once it is on.
  Duration untilOpen(DateTime now) {
    if (opensAt == null) return Duration.zero;
    final d = opensAt!.difference(now);
    return d.isNegative ? Duration.zero : d;
  }
}

/// "00:18:42". Hours keep counting past 24 ("26:05:00"); never negative.
String meetCountdown(Duration d) {
  if (d.isNegative) d = Duration.zero;
  // Round up so the display never shows 00:00:00 while time remains.
  final total = (d.inMilliseconds / 1000).ceil();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(h)}:${two(m)}:${two(s)}';
}

/// The line above the Join button.
///
/// "Interview starts in 00:18:42" within a day, "Interview starts in 3 days"
/// further out, "Interview has started" once it is under way.
String meetStartsInLabel(DateTime scheduledAt, DateTime now) {
  final d = scheduledAt.difference(now);
  if (d <= Duration.zero) return 'Interview has started';
  if (d >= const Duration(hours: 24)) {
    final days = (d.inHours / 24).round();
    return 'Interview starts in $days day${days == 1 ? '' : 's'}';
  }
  return 'Interview starts in ${meetCountdown(d)}';
}

// ---------------------------------------------------------------------------
// Camera and microphone problems
// ---------------------------------------------------------------------------

enum DeviceIssue {
  /// The person (or the OS / browser) said no.
  denied,

  /// No camera or microphone on this device.
  notFound,

  /// Another app is using it.
  inUse,

  /// Anything else.
  failed,
}

/// Camera/microphone errors come back as platform strings that differ between
/// Android, iOS and each browser. Sort them into what the person can do.
DeviceIssue classifyDeviceError(Object error) {
  final s = error.toString().toLowerCase();
  if (s.contains('notallowed') ||
      s.contains('permission') ||
      s.contains('denied') ||
      s.contains('securityerror') ||
      s.contains('not authorized') ||
      s.contains('unauthorized')) {
    return DeviceIssue.denied;
  }
  if (s.contains('notfound') ||
      s.contains('not found') ||
      s.contains('no camera') ||
      s.contains('no microphone') ||
      s.contains('overconstrained')) {
    return DeviceIssue.notFound;
  }
  if (s.contains('notreadable') ||
      s.contains('in use') ||
      s.contains('could not start') ||
      s.contains('trackstarterror') ||
      s.contains('busy')) {
    return DeviceIssue.inUse;
  }
  return DeviceIssue.failed;
}

// ---------------------------------------------------------------------------
// Copy
// ---------------------------------------------------------------------------

class MeetCopy {
  static String meetingMode(String? mode, {String? locationText}) =>
      switch (mode) {
        'omelo_meet' => 'Omelo Meet video',
        'phone' => 'Phone call',
        'in_person' =>
          locationText == null ? 'In person' : 'In person — $locationText',
        _ => 'Interview',
      };

  static String role(String? role) => switch (role) {
        'host' => 'Interviewer',
        'interviewer' => 'Interviewer',
        'observer' => 'From the company',
        'candidate' => 'Candidate',
        _ => '',
      };

  /// Abuse report reasons, in the order shown, with plain labels.
  static const reportReasons = <String, String>{
    'scam_or_fee_request': 'They asked me for money',
    'harassment': 'Rude, threatening or bullying',
    'discrimination': 'Treated unfairly (religion, caste, gender, age…)',
    'inappropriate_content': 'Showed or said something inappropriate',
    'impersonation': 'Pretending to be someone else',
    'other': 'Something else',
  };

  static const notRecorded = 'This interview is not recorded.';
  static const devicesOnlyDuring =
      'Your camera and microphone are only used during the interview.';
  static const neverPay = 'Omelo will never ask you to pay for an interview.';
  static const submitted =
      'Your interview has been submitted to the employer.';
  static const finalReview = 'Current status: Final review';
  static const willNotify =
      'You will be notified when the employer updates your application.';
  static String deviceIssue(DeviceIssue issue, {required bool camera}) {
    final thing = camera ? 'camera' : 'microphone';
    return switch (issue) {
      DeviceIssue.denied => 'Omelo is not allowed to use your $thing.',
      DeviceIssue.notFound => 'We could not find a $thing on this device.',
      DeviceIssue.inUse =>
        'Your $thing is being used by another app. Close it and try again.',
      DeviceIssue.failed => 'Your $thing did not start. Try again.',
    };
  }

  /// How to switch a blocked permission back on, per platform.
  static String enableInSettings({required bool web, required bool ios}) {
    if (web) {
      return 'To allow it: click the lock or camera icon next to the web '
          'address at the top of the browser, choose Allow for camera and '
          'microphone, then reload the page.';
    }
    if (ios) {
      return 'To allow it: open the Settings app, scroll down and tap Omelo, '
          'then turn on Camera and Microphone.';
    }
    return 'To allow it: open your phone Settings, tap Apps, tap Omelo, tap '
        'Permissions, then allow Camera and Microphone.';
  }

  static const notConfigured =
      "Video interviews aren't switched on yet in this test version. "
      'Your interviewer can see you joined.';
}
