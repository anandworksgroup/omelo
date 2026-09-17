import 'package:flutter_test/flutter_test.dart';
import 'package:omelo_user_app/data/messaging.dart';

void main() {
  const convId = '11111111-2222-4333-8444-555555555555';
  const appId = 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee';
  const room = 'om-0123456789abcdef0123456789abcdef0123';

  ChatMessage msg(
    int id, {
    String sender = 'recruiter',
    DateTime? readAt,
    DateTime? at,
    String body = 'Hello',
  }) =>
      ChatMessage(
        id: id,
        conversationId: convId,
        senderType: sender,
        body: body,
        readAt: readAt,
        sentAt: at ?? DateTime(2026, 9, 17, 10, id),
      );

  group('unread counting', () {
    test('only unread employer messages count', () {
      final read = DateTime(2026, 9, 17, 11);
      final thread = [
        msg(1),
        msg(2, readAt: read),
        msg(3, sender: 'candidate'),
        msg(4),
      ];
      expect(Messaging.unreadFromEmployer(thread), 2);
      expect(Messaging.unreadFromEmployer(const []), 0);
    });

    test('per conversation from raw rows', () {
      final counts = Messaging.unreadByConversation([
        {'conversation_id': 'c1', 'sender_type': 'recruiter', 'read_at': null},
        {'conversation_id': 'c1', 'sender_type': 'recruiter', 'read_at': null},
        {
          'conversation_id': 'c1',
          'sender_type': 'recruiter',
          'read_at': '2026-09-17T10:00:00Z'
        },
        {'conversation_id': 'c2', 'sender_type': 'candidate', 'read_at': null},
        {'conversation_id': 'c3', 'sender_type': 'recruiter', 'read_at': null},
        {'sender_type': 'recruiter', 'read_at': null},
      ]);
      expect(counts, {'c1': 2, 'c3': 1});
    });

    test('badge label', () {
      expect(badgeLabel(0), isNull);
      expect(badgeLabel(-1), isNull);
      expect(badgeLabel(7), '7');
      expect(badgeLabel(99), '99');
      expect(badgeLabel(100), '99+');
    });
  });

  group('thread', () {
    test('Seen shows under my latest message only once it is read', () {
      final read = DateTime(2026, 9, 17, 11);
      expect(
          Messaging.seenMessageId([
            msg(1, sender: 'candidate', readAt: read),
            msg(2),
            msg(3, sender: 'candidate', readAt: read),
          ]),
          3);
      // My latest is unread → no Seen, even if an older one was read.
      expect(
          Messaging.seenMessageId([
            msg(1, sender: 'candidate', readAt: read),
            msg(2, sender: 'candidate'),
          ]),
          isNull);
      // Employer spoke last; my latest message is still the one to mark.
      expect(
          Messaging.seenMessageId([
            msg(1, sender: 'candidate', readAt: read),
            msg(2),
          ]),
          1);
      expect(Messaging.seenMessageId([msg(1)]), isNull);
    });

    test('realtime merge appends, replaces by id and keeps order', () {
      var t = [msg(1), msg(3)];
      t = Messaging.merge(t, msg(2));
      expect(t.map((m) => m.id), [1, 2, 3]);
      t = Messaging.merge(t, msg(2, readAt: DateTime(2026, 9, 17, 12)));
      expect(t.length, 3);
      expect(t[1].isRead, isTrue);
    });

    test('validation', () {
      expect(Messaging.validate('   '), 'Write a message first');
      expect(Messaging.validate('Hi'), isNull);
      expect(Messaging.validate('a' * 4000), isNull);
      expect(Messaging.validate('a' * 4001),
          'Messages can be up to 4000 characters');
    });

    test('preview', () {
      expect(Messaging.preview(null), 'No messages yet');
      expect(Messaging.preview(msg(1, body: 'Come at\n10  am')), 'Come at 10 am');
      expect(Messaging.preview(msg(1, sender: 'candidate', body: 'OK')),
          'You: OK');
    });

    test('times', () {
      final now = DateTime(2026, 9, 17, 15);
      expect(Messaging.listTime(DateTime(2026, 9, 17, 10, 5), now), '10:05 AM');
      expect(Messaging.listTime(DateTime(2026, 9, 16, 10), now), 'Yesterday');
      expect(Messaging.listTime(DateTime(2026, 9, 1, 10), now), '1 Sep');
      expect(Messaging.listTime(DateTime(2025, 9, 1, 10), now), '1 Sep 2025');
      expect(Messaging.dayLabel(DateTime(2026, 9, 17, 1), now), 'Today');
      expect(Messaging.dayLabel(DateTime(2026, 9, 14, 1), now), 'Mon 14 Sep');
    });
  });

  group('conversations', () {
    test('parse with embeds and the latest message', () {
      final c = Conversation.fromRow({
        'id': convId,
        'company_id': 'co1',
        'job_id': 'j1',
        'application_id': appId,
        'subject': 'Delivery driver',
        'person_archived': false,
        'last_message_at': '2026-09-17T10:00:00Z',
        'companies': {'display_name': 'Fresh Mart', 'logo_url': null},
        'jobs': {'title': 'Delivery driver'},
        'messages': [
          {
            'id': 9,
            'sender_type': 'recruiter',
            'body': 'Can you come tomorrow?',
            'read_at': null,
            'sent_at': '2026-09-17T10:00:00Z',
          }
        ],
      });
      expect(c.companyOrEmployer, 'Fresh Mart');
      expect(c.jobOrSubject, 'Delivery driver');
      expect(c.lastMessage?.id, 9);
      expect(c.lastMessage?.conversationId, convId);
      expect(c.applicationId, appId);
    });

    test('archived hidden by default, newest first', () {
      Conversation c(String id, int minute, {bool archived = false}) =>
          Conversation(
            id: id,
            archived: archived,
            lastMessageAt: DateTime(2026, 9, 17, 10, minute),
          );
      final all = [c('a', 1), c('b', 5, archived: true), c('c', 3)];
      expect(Messaging.visible(all, showArchived: false).map((x) => x.id),
          ['c', 'a']);
      expect(Messaging.visible(all, showArchived: true).map((x) => x.id),
          ['b', 'c', 'a']);
    });
  });

  group('notification deeplinks', () {
    test('worker routes resolve', () {
      expect(workerDeeplink('/applications/$appId'), '/applications/$appId');
      expect(workerDeeplink('/messages/$convId'), '/messages/$convId');
      expect(workerDeeplink('/meet/$room'), '/meet/$room');
      expect(workerDeeplink('https://omelo.app/messages/$convId'),
          '/messages/$convId');
      expect(workerDeeplink(' /messages/$convId/ '), '/messages/$convId');
      expect(workerDeeplink('/applications'), '/applications');
    });

    test('unknown or unsafe links are ignored', () {
      expect(workerDeeplink(null), isNull);
      expect(workerDeeplink(''), isNull);
      expect(workerDeeplink('/dashboard/messages/$convId'), isNull);
      expect(workerDeeplink('/messages/not-a-uuid'), isNull);
      expect(workerDeeplink('/meet/om-xyz'), isNull);
      expect(workerDeeplink('/applications/$appId/extra'), isNull);
      expect(workerDeeplink('messages/$convId'), isNull);
      expect(workerDeeplink('javascript:alert(1)'), isNull);
      expect(workerDeeplink('/wallet'), isNull);
    });

    test('falls back to the entity when the link is missing or unknown', () {
      AppNotification n({String? link, String? type, String? id}) =>
          AppNotification(
            id: 'n1',
            type: 'message_received',
            title: 'New message',
            createdAt: DateTime(2026, 9, 17),
            deeplink: link,
            entityType: type,
            entityId: id,
          );
      expect(n(link: '/meet/$room').target, '/meet/$room');
      expect(n(type: 'conversation', id: convId).target, '/messages/$convId');
      expect(n(link: '/dashboard/x', type: 'application', id: appId).target,
          '/applications/$appId');
      expect(n(type: 'offer', id: appId).target, isNull);
      expect(n(type: 'application', id: 'nope').target, isNull);
      expect(n().target, isNull);
    });

    test('parse and mark read', () {
      final n = AppNotification.fromRow({
        'id': 'n1',
        'type': 'interview_scheduled',
        'title': 'Interview on Mon',
        'body': null,
        'deeplink': '/applications/$appId',
        'entity_type': 'application',
        'entity_id': appId,
        'read_at': null,
        'created_at': '2026-09-17T10:00:00Z',
      });
      expect(n.isRead, isFalse);
      expect(notificationKind(n.type), NotificationKind.interview);
      final r = n.markedRead(DateTime(2026, 9, 17, 12));
      expect(r.isRead, isTrue);
      expect(r.target, '/applications/$appId');
      expect(notificationKind('message_received'), NotificationKind.message);
      expect(notificationKind('offer_received'), NotificationKind.offer);
      expect(notificationKind('application_update'),
          NotificationKind.application);
      expect(notificationKind('something_new'), NotificationKind.other);
    });
  });
}
