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
  ///
  /// This registers the candidate in the waiting room and notifies the
  /// interviewers — call it only when the candidate taps Join.
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

  /// Reads the room and what the interview is, WITHOUT calling meet-token —
  /// so opening the link never puts the candidate in the waiting room.
  /// `room` is null when there is no such room (or it is not mine).
  /// Throws on network failure.
  Future<({InterviewRoom? room, MeetInterviewInfo? info})> lookup(
      String roomName) async {
    if (!isValidRoomName(roomName)) return (room: null, info: null);
    final row = await _db
        .from('interview_rooms')
        .select('interview_id, room_name, status, opens_at, closes_at, '
            'waiting_room, recording_enabled')
        .eq('room_name', roomName)
        .maybeSingle();
    if (row == null) return (room: null, info: null);
    final room = InterviewRoom.fromRow(row);

    // The header is nice to have; the room alone is enough to continue.
    MeetInterviewInfo? info;
    try {
      final i = await _db
          .from('interviews')
          .select('id, application_id, round, round_name, meeting_mode, '
              'scheduled_at, duration_minutes, timezone, location_text, '
              'instructions, '
              'applications ( jobs ( title ), companies ( display_name ) )')
          .eq('id', room.interviewId)
          .maybeSingle();
      if (i != null) {
        info = MeetInterviewInfo.fromInterviewRow(i, roomName: roomName);
      }
    } catch (_) {}
    return (room: room, info: info);
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
