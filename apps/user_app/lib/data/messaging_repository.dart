import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'jobs_repository.dart' show supabaseProvider;
import 'messaging.dart';

export 'messaging.dart';

final messagingRepositoryProvider = Provider<MessagingRepository>(
  (ref) => MessagingRepository(ref.watch(supabaseProvider)),
);

final notificationsRepositoryProvider = Provider<NotificationsRepository>(
  (ref) => NotificationsRepository(ref.watch(supabaseProvider)),
);

int _channelSeq = 0;
String _channelName(String base) => '$base-${++_channelSeq}';

Future<void> _removeChannel(SupabaseClient db, RealtimeChannel c) async {
  try {
    await db.removeChannel(c);
  } catch (_) {}
}

/// The worker's side of job conversations. Writes only go through the
/// `omelo_*` functions; the database blocks direct inserts.
class MessagingRepository {
  MessagingRepository(this._db);
  final SupabaseClient _db;

  String? get currentUserId => _db.auth.currentUser?.id;

  static const _conversationSelect =
      'id, company_id, job_id, application_id, subject, person_archived, '
      'last_message_at, companies ( display_name, logo_url ), jobs ( title )';

  static const _messageSelect =
      'id, conversation_id, sender_person_id, sender_type, body, read_at, sent_at';

  /// All my conversations with the latest message and my unread count.
  Future<List<Conversation>> conversations() async {
    final uid = currentUserId;
    if (uid == null) return const [];
    final rows = await _db
        .from('conversations')
        .select('$_conversationSelect, messages ( $_messageSelect )')
        .eq('person_id', uid)
        .order('sent_at', referencedTable: 'messages', ascending: false)
        .limit(1, referencedTable: 'messages')
        .order('last_message_at', ascending: false, nullsFirst: false)
        .limit(200);
    final list = (rows as List)
        .map((r) => Conversation.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
    if (list.isEmpty) return list;

    final unreadRows = await _db
        .from('messages')
        .select('conversation_id, sender_type, read_at')
        .inFilter('conversation_id', [for (final c in list) c.id])
        .eq('sender_type', 'recruiter')
        .isFilter('read_at', null)
        .limit(5000);
    final unread = Messaging.unreadByConversation((unreadRows as List)
        .map((e) => Map<String, dynamic>.from(e as Map)));
    return [for (final c in list) c.copyWith(unread: unread[c.id] ?? 0)];
  }

  /// One conversation, or null when it does not exist or is not mine.
  Future<Conversation?> conversation(String id) async {
    if (!isUuid(id)) return null;
    final row = await _db
        .from('conversations')
        .select(_conversationSelect)
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Conversation.fromRow(row);
  }

  /// The latest 500 messages, oldest first.
  Future<List<ChatMessage>> messages(String conversationId) async {
    final rows = await _db
        .from('messages')
        .select(_messageSelect)
        .eq('conversation_id', conversationId)
        .order('sent_at', ascending: false)
        .order('id', ascending: false)
        .limit(500);
    return (rows as List)
        .map((r) => ChatMessage.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList()
        .reversed
        .toList();
  }

  /// Employer messages I have not read, across all my conversations.
  Future<int> unreadCount() async {
    final uid = currentUserId;
    if (uid == null) return 0;
    final res = await _db
        .from('messages')
        .select('id, conversations!inner ( person_id )')
        .eq('conversations.person_id', uid)
        .eq('sender_type', 'recruiter')
        .isFilter('read_at', null)
        .limit(1)
        .count(CountOption.exact);
    return res.count;
  }

  /// Get or open the conversation for my application. Returns its id.
  Future<String> start(String applicationId) async {
    final id = await _db.rpc('omelo_start_conversation',
        params: {'p_application_id': applicationId});
    return id.toString();
  }

  Future<void> send(String conversationId, String body) async {
    await _db.rpc('omelo_send_message', params: {
      'p_conversation_id': conversationId,
      'p_body': body.trim(),
    });
  }

  /// Marks the employer's messages read and clears this conversation's
  /// notifications. Best effort.
  Future<int> markRead(String conversationId) async {
    try {
      final n = await _db.rpc('omelo_mark_conversation_read',
          params: {'p_conversation_id': conversationId});
      return n is num ? n.toInt() : 0;
    } catch (_) {
      return 0;
    }
  }

  /// Only `person_archived` may change on my side.
  Future<void> setArchived(String conversationId, bool archived) async {
    await _db
        .from('conversations')
        .update({'person_archived': archived}).eq('id', conversationId);
  }

  /// Any message or conversation change I can see (RLS scopes the feed).
  RealtimeChannel watchAll(void Function() onChange) {
    return _db
        .channel(_channelName('messages-mine'))
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          callback: (_) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'person_id',
            value: currentUserId ?? '',
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  /// New and updated messages in one conversation.
  RealtimeChannel watchThread(
    String conversationId,
    void Function(ChatMessage) onMessage, {
    void Function()? onTrouble,
  }) {
    return _db
        .channel(_channelName('thread-$conversationId'))
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: conversationId,
          ),
          callback: (p) {
            if (p.newRecord.isEmpty) return;
            onMessage(ChatMessage.fromRow(p.newRecord));
          },
        )
        .subscribe((status, _) {
      if (status == RealtimeSubscribeStatus.channelError ||
          status == RealtimeSubscribeStatus.timedOut) {
        onTrouble?.call();
      }
    });
  }

  Future<void> unsubscribe(RealtimeChannel c) => _removeChannel(_db, c);
}

/// The worker's notification inbox. Rows are created by the server only.
class NotificationsRepository {
  NotificationsRepository(this._db);
  final SupabaseClient _db;

  String? get currentUserId => _db.auth.currentUser?.id;

  Future<List<AppNotification>> list({int limit = 100}) async {
    final uid = currentUserId;
    if (uid == null) return const [];
    final rows = await _db
        .from('notifications')
        .select('id, type, title, body, deeplink, entity_type, entity_id, '
            'read_at, created_at')
        .eq('person_id', uid)
        .order('created_at', ascending: false)
        .limit(limit);
    return (rows as List)
        .map((r) => AppNotification.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  Future<int> unreadCount() async {
    final uid = currentUserId;
    if (uid == null) return 0;
    final res = await _db
        .from('notifications')
        .select('id')
        .eq('person_id', uid)
        .isFilter('read_at', null)
        .limit(1)
        .count(CountOption.exact);
    return res.count;
  }

  Future<void> markRead(String id) async {
    await _db
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', id)
        .isFilter('read_at', null);
  }

  Future<void> markAllRead() async {
    final uid = currentUserId;
    if (uid == null) return;
    await _db
        .from('notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('person_id', uid)
        .isFilter('read_at', null);
  }

  Future<void> delete(String id) async {
    await _db.from('notifications').delete().eq('id', id);
  }

  RealtimeChannel watch(void Function() onChange) {
    final uid = currentUserId ?? '';
    return _db
        .channel(_channelName('notifications-$uid'))
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'person_id',
            value: uid,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
  }

  Future<void> unsubscribe(RealtimeChannel c) => _removeChannel(_db, c);
}

/// A failed send, start or archive, in plain words.
String messagingError(Object e) {
  if (e is PostgrestException && e.message.trim().isNotEmpty) {
    return e.message;
  }
  return 'That did not go through. Check your connection and try again.';
}
