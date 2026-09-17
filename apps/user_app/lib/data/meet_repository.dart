import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'jobs_repository.dart' show supabaseProvider;
import 'meet.dart';

export 'meet.dart';

final meetRepositoryProvider = Provider<MeetRepository>(
  (ref) => MeetRepository(ref.watch(supabaseProvider)),
);

/// The candidate's side of Omelo Meet: joining, the waiting room, chat,
/// leaving and reporting. Every decision is the server's; this only asks.
class MeetRepository {
  MeetRepository(this._db);
  final SupabaseClient _db;

  String? get currentUserId => _db.auth.currentUser?.id;

  /// Asks `meet-token` to let us in. Never throws.
  Future<MeetJoinResult> join(String roomName) async {
    if (!isValidRoomName(roomName)) {
      return const MeetJoinError(
        interview: null,
        status: 404,
        code: 'not_found',
        message: 'We could not find this interview. Check the link and try again.',
      );
    }
    try {
      final res = await _db.functions
          .invoke('meet-token', body: {'room_name': roomName});
      return MeetJoinResult.parse(res.status, res.data);
    } on FunctionException catch (e) {
      return MeetJoinResult.parse(e.status, e.details);
    } catch (_) {
      return const MeetJoinError(
        interview: null,
        status: 0,
        code: 'network',
        message: 'Could not reach Omelo. Check your internet and try again.',
      );
    }
  }

  /// My own participant row for an interview. Null if it cannot be read.
  Future<MeetParticipant?> myParticipant(String interviewId) async {
    final uid = currentUserId;
    if (uid == null) return null;
    try {
      final row = await _db
          .from('interview_participants')
          .select('interview_id, person_id, display_name, role, status')
          .eq('interview_id', interviewId)
          .eq('person_id', uid)
          .maybeSingle();
      return row == null ? null : MeetParticipant.fromRow(row);
    } catch (_) {
      return null;
    }
  }

  /// Realtime changes to my own participant row(s). The caller filters by
  /// interview; RLS only lets the filter match my rows anyway.
  RealtimeChannel watchMyParticipant(
    String interviewId,
    void Function(MeetParticipant) onChange,
  ) {
    final uid = currentUserId ?? '';
    return _db
        .channel('meet-participant-$interviewId-$uid')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'interview_participants',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'person_id',
            value: uid,
          ),
          callback: (payload) {
            final p = MeetParticipant.fromRow(payload.newRecord);
            if (p.interviewId == interviewId) onChange(p);
          },
        )
        .subscribe();
  }

  Future<void> unsubscribe(RealtimeChannel channel) async {
    try {
      await _db.removeChannel(channel);
    } catch (_) {}
  }

  // -- Chat -----------------------------------------------------------------

  Future<List<MeetMessage>> messages(String interviewId) async {
    final rows = await _db
        .from('meet_messages')
        .select('id, interview_id, sender_id, sender_name, body, sent_at')
        .eq('interview_id', interviewId)
        .order('id')
        .limit(500);
    return (rows as List)
        .map((r) => MeetMessage.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  RealtimeChannel watchMessages(
    String interviewId,
    void Function(MeetMessage) onMessage,
  ) {
    return _db
        .channel('meet-chat-$interviewId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'meet_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'interview_id',
            value: interviewId,
          ),
          callback: (payload) =>
              onMessage(MeetMessage.fromRow(payload.newRecord)),
        )
        .subscribe();
  }

  /// Sends a chat message. The server stamps the sender name and rate limits
  /// (30 a minute). Throws with a readable message on failure.
  Future<MeetMessage?> send(String interviewId, String body) async {
    final uid = currentUserId;
    final text = body.trim();
    if (uid == null || text.isEmpty) return null;
    final row = await _db
        .from('meet_messages')
        .insert({
          'interview_id': interviewId,
          'sender_id': uid,
          'body': text.length > MeetMessage.maxLength
              ? text.substring(0, MeetMessage.maxLength)
              : text,
        })
        .select('id, interview_id, sender_id, sender_name, body, sent_at')
        .maybeSingle();
    return row == null ? null : MeetMessage.fromRow(row);
  }

  // -- Leaving and safety ---------------------------------------------------

  /// Tells the server I left. Best effort: never throws.
  Future<void> leave(String interviewId) async {
    try {
      await _db.rpc('omelo_meet_leave', params: {'p_interview_id': interviewId});
    } catch (_) {}
  }

  Future<void> report(String interviewId, String reason, {String? details}) async {
    final d = details?.trim();
    await _db.rpc('omelo_report_meet_abuse', params: {
      'p_interview_id': interviewId,
      'p_reason': reason,
      'p_details': (d == null || d.isEmpty) ? null : d,
    });
  }
}

/// A sentence for a failed chat send or report.
String meetActionError(Object e) {
  if (e is PostgrestException && e.message.trim().isNotEmpty) {
    final m = e.message.toLowerCase();
    if (m.contains('row-level security') || m.contains('permission')) {
      return 'You can chat once you are in the interview.';
    }
    return e.message;
  }
  return 'That did not go through. Check your connection and try again.';
}
