/// Job-context messaging and the notification inbox — models and rules.
///
/// Pure Dart (no Flutter, no Supabase) so what the worker sees — unread
/// counts, "Seen", where a notification goes — can be unit tested.
library;

import 'package:intl/intl.dart';

import 'meet.dart' show isValidRoomName;

// ---------------------------------------------------------------------------
// Parse helpers
// ---------------------------------------------------------------------------

Map<String, dynamic>? _map(dynamic v) {
  if (v is Map) return Map<String, dynamic>.from(v);
  // PostgREST returns a list for some embeds; take the first row.
  if (v is List && v.isNotEmpty && v.first is Map) {
    return Map<String, dynamic>.from(v.first as Map);
  }
  return null;
}

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

DateTime? _date(dynamic v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

bool _bool(dynamic v) => v == true || v?.toString() == 'true';

final _uuid = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

bool isUuid(String? s) => s != null && _uuid.hasMatch(s);

// ---------------------------------------------------------------------------
// Messages
// ---------------------------------------------------------------------------

/// `messages` — one line in a job conversation.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderType,
    required this.body,
    required this.sentAt,
    this.senderPersonId,
    this.readAt,
  });

  final int id;
  final String conversationId;
  final String? senderPersonId;

  /// candidate | recruiter
  final String senderType;
  final String body;
  final DateTime? readAt;
  final DateTime sentAt;

  /// Written by the worker using this app.
  bool get isMine => senderType == 'candidate';
  bool get isRead => readAt != null;

  static const maxLength = 4000;

  factory ChatMessage.fromRow(Map<String, dynamic> m) => ChatMessage(
        id: m['id'] is num
            ? (m['id'] as num).toInt()
            : int.tryParse('${m['id']}') ?? 0,
        conversationId: (m['conversation_id'] ?? '').toString(),
        senderPersonId: _str(m['sender_person_id']),
        senderType: _str(m['sender_type']) ?? 'recruiter',
        body: (m['body'] ?? '').toString(),
        readAt: _date(m['read_at']),
        sentAt: _date(m['sent_at']) ?? DateTime.now(),
      );
}

/// `conversations` with the company and job embedded.
class Conversation {
  const Conversation({
    required this.id,
    this.companyId,
    this.jobId,
    this.applicationId,
    this.subject,
    this.companyName,
    this.companyLogoUrl,
    this.jobTitle,
    this.archived = false,
    this.lastMessageAt,
    this.lastMessage,
    this.unread = 0,
  });

  final String id;
  final String? companyId;
  final String? jobId;
  final String? applicationId;
  final String? subject;
  final String? companyName;
  final String? companyLogoUrl;
  final String? jobTitle;

  /// `person_archived` — the worker's own archive flag.
  final bool archived;
  final DateTime? lastMessageAt;
  final ChatMessage? lastMessage;

  /// Employer messages the worker has not read yet.
  final int unread;

  String get companyOrEmployer => companyName ?? 'Employer';
  String get jobOrSubject => jobTitle ?? subject ?? 'Job';

  factory Conversation.fromRow(Map<String, dynamic> m) {
    final company = _map(m['companies']);
    final job = _map(m['jobs']);
    final last = _map(m['messages']);
    return Conversation(
      id: (m['id'] ?? '').toString(),
      companyId: _str(m['company_id']),
      jobId: _str(m['job_id']),
      applicationId: _str(m['application_id']),
      subject: _str(m['subject']),
      companyName: _str(company?['display_name']),
      companyLogoUrl: _str(company?['logo_url']),
      jobTitle: _str(job?['title']),
      archived: _bool(m['person_archived']),
      lastMessageAt: _date(m['last_message_at']),
      lastMessage: last == null
          ? null
          : ChatMessage.fromRow({'conversation_id': m['id'], ...last}),
    );
  }

  Conversation copyWith({int? unread, bool? archived}) => Conversation(
        id: id,
        companyId: companyId,
        jobId: jobId,
        applicationId: applicationId,
        subject: subject,
        companyName: companyName,
        companyLogoUrl: companyLogoUrl,
        jobTitle: jobTitle,
        archived: archived ?? this.archived,
        lastMessageAt: lastMessageAt,
        lastMessage: lastMessage,
        unread: unread ?? this.unread,
      );

  /// When to sort by: the last message, else when it was opened.
  DateTime get sortTime =>
      lastMessage?.sentAt ?? lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}

class Messaging {
  /// Employer messages not yet read by the worker.
  static int unreadFromEmployer(Iterable<ChatMessage> messages) =>
      messages.where((m) => !m.isMine && !m.isRead).length;

  /// Rows of `{conversation_id, sender_type, read_at}` → unread per
  /// conversation. Rows the worker wrote, or already read, do not count.
  static Map<String, int> unreadByConversation(
      Iterable<Map<String, dynamic>> rows) {
    final out = <String, int>{};
    for (final r in rows) {
      final id = _str(r['conversation_id']);
      if (id == null) continue;
      if (_str(r['sender_type']) != 'recruiter') continue;
      if (r['read_at'] != null) continue;
      out[id] = (out[id] ?? 0) + 1;
    }
    return out;
  }

  /// Newest first; archived hidden unless asked for.
  static List<Conversation> visible(
    Iterable<Conversation> all, {
    required bool showArchived,
  }) {
    final list = all.where((c) => showArchived || !c.archived).toList()
      ..sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return list;
  }

  /// Merges a realtime row into the thread: replaces by id (read_at updates)
  /// or appends, and keeps the thread in time order.
  static List<ChatMessage> merge(List<ChatMessage> current, ChatMessage m) {
    final out = [...current];
    final i = out.indexWhere((x) => x.id == m.id);
    if (i >= 0) {
      out[i] = m;
    } else {
      out.add(m);
    }
    out.sort((a, b) {
      final t = a.sentAt.compareTo(b.sentAt);
      return t != 0 ? t : a.id.compareTo(b.id);
    });
    return out;
  }

  /// Id of the message that should show "Seen": the worker's latest message,
  /// once the employer has read it. Null otherwise.
  static int? seenMessageId(List<ChatMessage> thread) {
    for (var i = thread.length - 1; i >= 0; i--) {
      final m = thread[i];
      if (m.isMine) return m.isRead ? m.id : null;
    }
    return null;
  }

  /// Null when the message can be sent; otherwise a short reason.
  static String? validate(String body) {
    final t = body.trim();
    if (t.isEmpty) return 'Write a message first';
    if (t.length > ChatMessage.maxLength) {
      return 'Messages can be up to ${ChatMessage.maxLength} characters';
    }
    return null;
  }

  /// One-line preview for the list.
  static String preview(ChatMessage? m) {
    if (m == null) return 'No messages yet';
    final text = m.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return m.isMine ? 'You: $text' : text;
  }

  /// List time: "10:42 AM" today, "Yesterday", "Mon" this week, "12 Sep".
  static String listTime(DateTime at, DateTime now) {
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return DateFormat('h:mm a').format(at);
    if (days == 1) return 'Yesterday';
    if (days < 7) return DateFormat('EEE').format(at);
    if (at.year == now.year) return DateFormat('d MMM').format(at);
    return DateFormat('d MMM yyyy').format(at);
  }

  /// Bubble time: "10:42 AM".
  static String bubbleTime(DateTime at) => DateFormat('h:mm a').format(at);

  /// Day divider in a thread: "Today", "Yesterday", "Mon 14 Sep".
  static String dayLabel(DateTime at, DateTime now) {
    final day = DateTime(at.year, at.month, at.day);
    final today = DateTime(now.year, now.month, now.day);
    final days = today.difference(day).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (at.year == now.year) return DateFormat('EEE d MMM').format(at);
    return DateFormat('d MMM yyyy').format(at);
  }
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

/// `notifications` — one row in the worker's inbox.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.createdAt,
    this.body,
    this.deeplink,
    this.entityType,
    this.entityId,
    this.readAt,
  });

  final String id;
  final String type;
  final String title;
  final String? body;
  final String? deeplink;
  final String? entityType;
  final String? entityId;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  factory AppNotification.fromRow(Map<String, dynamic> m) => AppNotification(
        id: (m['id'] ?? '').toString(),
        type: _str(m['type']) ?? 'general',
        title: _str(m['title']) ?? 'Update',
        body: _str(m['body']),
        deeplink: _str(m['deeplink']),
        entityType: _str(m['entity_type']),
        entityId: _str(m['entity_id']),
        readAt: _date(m['read_at']),
        createdAt: _date(m['created_at']) ?? DateTime.now(),
      );

  AppNotification markedRead(DateTime at) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        deeplink: deeplink,
        entityType: entityType,
        entityId: entityId,
        readAt: readAt ?? at,
        createdAt: createdAt,
      );

  /// Where tapping this goes in the worker app, or null to stay put.
  String? get target =>
      workerDeeplink(deeplink) ?? _fromEntity(entityType, entityId, deeplink);

  static String? _fromEntity(String? type, String? id, String? link) {
    if (!isUuid(id)) return null;
    return switch (type) {
      'application' => '/applications/$id',
      'conversation' => '/messages/$id',
      'candidate_invitation' => '/invitations/$id',
      // Recruiters get consent notices that link to their dashboard; only a
      // notice without a link of its own falls back to the worker screen.
      'candidate_consent' when link == null || link.trim().isEmpty =>
        '/representations/$id',
      _ => null,
    };
  }
}

/// Turns a notification deeplink into a route this app has, or null.
///
/// Accepts `/applications/<uuid>`, `/messages/<uuid>`, `/invitations/<uuid>`,
/// `/representations/<uuid>`,
/// `/job/<uuid>` (opened as surface `notification`), `/meet/<room>` and the
/// list screens, as a path or a full https link to the same path. Anything
/// else — employer dashboard links, typos, other sites — is ignored so a bad
/// row can never send the worker somewhere broken.
String? workerDeeplink(String? link) {
  final raw = link?.trim();
  if (raw == null || raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  if (uri.hasScheme && uri.scheme != 'https' && uri.scheme != 'http') {
    return null;
  }
  if (!uri.hasScheme && !raw.startsWith('/')) return null;

  final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
  if (s.length == 1) {
    return switch (s[0]) {
      'applications' => '/applications',
      'messages' => '/messages',
      'notifications' => '/notifications',
      'invitations' => '/invitations',
      'representations' => '/representations',
      'recruiters' => '/recruiters',
      _ => null,
    };
  }
  if (s.length != 2) return null;
  final id = s[1];
  return switch (s[0]) {
    'applications' when isUuid(id) => '/applications/$id',
    'messages' when isUuid(id) => '/messages/$id',
    'invitations' when isUuid(id) => '/invitations/$id',
    'representations' when isUuid(id) => '/representations/$id',
    'job' || 'jobs' when isUuid(id) => '/job/$id?from=notification',
    'meet' when isValidRoomName(id) => '/meet/$id',
    _ => null,
  };
}

/// Groups notification types for icons.
enum NotificationKind {
  interview,
  application,
  offer,
  message,
  invitation,
  representation,
  other
}

NotificationKind notificationKind(String type) => switch (type) {
      'interview_scheduled' ||
      'interview_reminder' ||
      'interview_updated' ||
      'interview_cancelled' =>
        NotificationKind.interview,
      'application_update' || 'application_viewed' => NotificationKind.application,
      'offer_received' || 'offer_update' => NotificationKind.offer,
      'message_received' => NotificationKind.message,
      'job_invitation' => NotificationKind.invitation,
      'representation_request' ||
      'representation_update' =>
        NotificationKind.representation,
      _ => NotificationKind.other,
    };

/// Badge text: "3", or "99+" past 99. Null hides the badge.
String? badgeLabel(int count) {
  if (count <= 0) return null;
  return count > 99 ? '99+' : '$count';
}
