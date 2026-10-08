import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:omelo_user_app/core/app_state.dart';
import 'package:omelo_user_app/core/router.dart' show networkRoutes;
import 'package:omelo_user_app/core/theme.dart';
import 'package:omelo_user_app/data/media_picker.dart' show mediaChooserProvider;
import 'package:omelo_user_app/data/messaging.dart'
    show AppNotification, NotificationKind, notificationKind, workerDeeplink;
import 'package:omelo_user_app/data/network_repository.dart';
import 'package:omelo_user_app/features/network/composer_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

final fixedNow = DateTime(2026, 10, 8, 12);

const meId = '11111111-1111-4111-8111-111111111111';
const postId = '22222222-2222-4222-8222-222222222222';
const otherPostId = '33333333-3333-4333-8333-333333333333';
const personId = '44444444-4444-4444-8444-444444444444';
const companyId = '55555555-5555-4555-8555-555555555555';
const jobId = '66666666-6666-4666-8666-666666666666';
const connectionId = '77777777-7777-4777-8777-777777777777';
const commentId = '88888888-8888-4888-8888-888888888888';
const replyId = '99999999-9999-4999-8999-999999999999';

Map<String, dynamic> personAuthor({bool verified = false}) => {
      'type': 'person',
      'id': personId,
      'name': 'Priya Nair',
      'avatar_url': null,
      'headline': 'Industrial electrician, Pune',
      'slug': 'priya-nair',
      'verified': verified,
    };

Map<String, dynamic> organizationAuthor() => {
      'type': 'organization',
      'id': companyId,
      'name': 'Sunrise Facilities',
      'avatar_url': 'logos/sunrise.png',
      'slug': 'sunrise-facilities',
      'verified': true,
      'organization_type': 'staffing_agency',
    };

/// A card with everything on it: media, a job in euros, a quoted post and my
/// own reaction.
Map<String, dynamic> fullPostJson({
  String id = postId,
  String? reaction = 'celebrate',
  bool saved = false,
  bool mine = false,
  String visibility = 'public',
}) =>
    {
      'id': id,
      'kind': 'update',
      'body': 'Finished the panel wiring on the new line today.',
      'visibility': visibility,
      'created_at': '2026-10-08T09:00:00Z',
      'edited_at': '2026-10-08T09:30:00Z',
      'author': personAuthor(verified: true),
      'media': [
        {
          'kind': 'image',
          'url': '$meId/1-0.jpg',
          'alt_text': 'A finished control panel',
          'width': 1200,
          'height': 900,
          'duration_seconds': null,
        },
        {
          'kind': 'video',
          'url': '$meId/1-1.mp4',
          'alt_text': null,
          'width': null,
          'height': null,
          'duration_seconds': 125,
        },
      ],
      'job': {
        'id': jobId,
        'title': 'Industrial electrician',
        'company': 'Werkhaus GmbH',
        'location_text': 'Hamburg',
        'country': 'DE',
        'workplace_type': 'onsite',
        'work_type': 'full_time',
        'status': 'published',
        'pay': {
          'min': 2800,
          'max': 3400,
          'period': 'month',
          'currency': 'EUR',
        },
      },
      'shared_post': {
        'id': otherPostId,
        'body': 'We are hiring across three sites.',
        'created_at': '2026-10-07T09:00:00Z',
        'author': organizationAuthor(),
        'media': [
          {'kind': 'image', 'url': '$meId/0-0.jpg'},
        ],
      },
      'engagement': {
        'reactions': 12,
        'comments': 3,
        'shares': 1,
        'saves': 4,
      },
      'my': {'reaction': reaction, 'saved': saved, 'mine': mine},
      'why': 'From a connection',
      'score': 3.482,
    };

/// A plain text post with nothing attached.
Map<String, dynamic> plainPostJson({
  String id = otherPostId,
  bool mine = false,
  String body = 'Looking for a mate on the Chakan site next week.',
}) =>
    {
      'id': id,
      'kind': 'update',
      'body': body,
      'visibility': 'public',
      'created_at': '2026-10-08T06:00:00Z',
      'author': personAuthor(),
      'media': const [],
      'job': null,
      'shared_post': null,
      'engagement': {'reactions': 3, 'comments': 0, 'shares': 0, 'saves': 0},
      'my': {'reaction': null, 'saved': false, 'mine': mine},
      'why': 'Popular on Omelo',
      'score': 0.5,
    };

/// A full page, so the feed believes there is more to fetch.
List<Map<String, dynamic>> manyPosts(int n) =>
    [for (var i = 0; i < n; i++) plainPostJson(id: 'post-$i', body: 'Post $i')];

Map<String, dynamic> feedJson(
  String tab,
  List<Map<String, dynamic>> posts, {
  int? nextOffset,
  String? nextBefore,
}) =>
    {
      'tab': tab,
      'posts': posts,
      'next_before': nextBefore,
      'next_offset': nextOffset,
      'preferences': {
        'show_jobs': true,
        'show_organizations': false,
        'show_career_content': true,
        'show_network_activity': true,
        'preferred_languages': ['en', 'mr'],
      },
      'ranking': 'connection 3 · following 2 · your profession 1',
    };

List<Map<String, dynamic>> commentsJson() => [
      {
        'id': commentId,
        'body': 'Good work. What gauge did you run?',
        'created_at': '2026-10-08T10:00:00Z',
        'edited_at': null,
        'author': organizationAuthor(),
        'reactions': 2,
        'replies': 3,
        'mine': false,
        'my_reaction': 'like',
        'thread': [
          {
            'id': replyId,
            'body': 'Four square, same as the last run.',
            'created_at': '2026-10-08T10:05:00Z',
            'author': personAuthor(),
            'reactions': 0,
            'mine': true,
          },
        ],
      },
    ];

const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Uint8List get _pngBytes => base64Decode(_png);

// ---------------------------------------------------------------------------
// A fake server
// ---------------------------------------------------------------------------

class FakeNetwork implements NetworkRepository {
  final calls = <String, Object?>{};
  final feedCalls = <({FeedTab tab, int? offset, DateTime? before})>[];

  Map<String, List<Map<String, dynamic>>> postsByTab = {
    'for_you': [fullPostJson(), plainPostJson()],
    'following': [plainPostJson()],
    'organizations': const [],
    'jobs': const [],
    'saved': const [],
  };

  Map<String, dynamic> detail = fullPostJson();
  List<Map<String, dynamic>> commentRows = commentsJson();
  Map<NetworkView, List<NetworkEntry>> network = {};
  List<NetworkEntry> suggestionList = const [];
  Object? failWith;

  @override
  String? get myId => meId;

  @override
  Future<FeedPage> feed(FeedTab tab,
      {int limit = 20, DateTime? before, int? offset}) async {
    feedCalls.add((tab: tab, offset: offset, before: before));
    if (failWith != null) throw failWith!;
    return FeedPage.fromJson(
      feedJson(
        tab.wire,
        postsByTab[tab.wire] ?? const [],
        nextOffset: tab.pagesByOffset ? 20 : null,
        nextBefore: tab.pagesByOffset ? null : '2026-10-07T06:00:00Z',
      ),
      fallbackTab: tab,
    );
  }

  @override
  Future<FeedPost?> postDetail(String id) async {
    calls['detail'] = id;
    return FeedPost.fromJson(detail);
  }

  @override
  Future<List<FeedPost>> personPosts(String personId,
          {int limit = 20, DateTime? before}) async =>
      parsePosts([plainPostJson()]);

  @override
  Future<OrganizationFeed?> organizationFeed(String companyId,
          {int limit = 20, DateTime? before}) async =>
      OrganizationFeed.fromJson({
        'organization': organizationAuthor(),
        'followers': 1204,
        'following': false,
        'posts': [plainPostJson()],
      });

  @override
  Future<FeedPost?> createPost(PostDraft d) async {
    calls['create'] = d.toPayload();
    if (failWith != null) throw failWith!;
    return FeedPost.fromJson(plainPostJson(body: d.body));
  }

  @override
  Future<FeedPost?> updatePost(String id, PostDraft d) async {
    calls['update'] = {'post': id, ...d.toEditPayload()};
    return FeedPost.fromJson(plainPostJson(body: d.body));
  }

  @override
  Future<void> deletePost(String id) async => calls['delete'] = id;

  @override
  Future<FeedPost?> sharePost(String id,
      {String? body, PostVisibility visibility = PostVisibility.public}) async {
    calls['share'] = {'post': id, 'body': body, 'visibility': visibility.wire};
    return FeedPost.fromJson(plainPostJson());
  }

  @override
  Future<void> react(String id, ReactionKind? kind) async {
    calls['react'] = '$id:${kind?.wire}';
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> savePost(String id, bool save) async =>
      calls['save'] = '$id:$save';

  @override
  Future<List<PostCommentItem>> comments(String id,
      {int limit = 30, DateTime? after}) async {
    calls['comments'] = id;
    return parseComments(commentRows);
  }

  @override
  Future<void> comment(String id, String body, {String? parentId}) async =>
      calls['comment'] = {'post': id, 'body': body, 'parent': parentId};

  @override
  Future<void> deleteComment(String id) async => calls['deleteComment'] = id;

  @override
  Future<void> reactToComment(String id, ReactionKind? kind) async =>
      calls['commentReaction'] = '$id:${kind?.wire}';

  @override
  Future<void> follow(AuthorType type, String id, bool f) async =>
      calls['follow'] = '${followTargetWire(type)}:$id:$f';

  @override
  Future<void> requestConnection(String id, {String? message}) async =>
      calls['connect'] = {'person': id, 'message': message};

  @override
  Future<void> respondConnection(String id, bool accept) async =>
      calls['respond'] = '$id:$accept';

  @override
  Future<void> removeConnection(String id) async => calls['remove'] = id;

  @override
  Future<List<NetworkEntry>> myNetwork(NetworkView view) async {
    calls['network'] = view.wire;
    return network[view] ?? const [];
  }

  @override
  Future<List<NetworkEntry>> suggestions({int limit = 10}) async =>
      suggestionList;

  @override
  Future<FeedPreferences> saveFeedPreferences(FeedPreferences p) async {
    calls['preferences'] = p.toPayload();
    return p;
  }

  @override
  Future<void> mute(MuteTarget target, String id, {bool mute = true}) async =>
      calls['mute'] = '${target.wire}:$id:$mute';

  @override
  Future<void> block(BlockTarget target, String id, {String? reason}) async =>
      calls['block'] = '${target.wire}:$id';

  @override
  Future<void> report({
    required ReportSubject subject,
    required String subjectId,
    required ReportReason reason,
    String? details,
  }) async =>
      calls['report'] = '${subject.wire}:$subjectId:${reason.wire}';

  @override
  Future<List<PostJob>> jobsToShare({String? query, int limit = 20}) async {
    calls['jobs'] = query;
    return [
      PostJob.fromRow({
        'id': jobId,
        'title': 'Industrial electrician',
        'location_text': 'Hamburg',
        'country_code': 'DE',
        'workplace_type': 'onsite',
        'work_type': 'full_time',
        'status': 'published',
        'pay_min': 2800,
        'pay_max': 3400,
        'pay_period': 'month',
        'pay_currency': 'EUR',
        'pay_disclosed': true,
        'companies': {'display_name': 'Werkhaus GmbH'},
      })!,
    ];
  }

  @override
  String mediaUrl(String path) => 'https://media.example.test/$path';

  @override
  Future<UploadedMedia> uploadMedia(PickedMedia m, {int index = 0}) async {
    final path = NetworkRepository.mediaPath(
      meId,
      index: index,
      extension: m.extension,
      now: fixedNow,
    );
    (calls['uploads'] ??= <String>[]);
    (calls['uploads'] as List).add(path);
    return UploadedMedia(
      storagePath: path,
      kind: m.isVideo ? MediaKind.video : MediaKind.image,
      mimeType: m.mimeType,
      width: m.width,
      height: m.height,
      altText: m.altText,
    );
  }
}

// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  group('post card parsing', () {
    test('every shape on one card', () {
      final p = FeedPost.fromJson(fullPostJson())!;

      expect(p.id, postId);
      expect(p.kind, 'update');
      expect(p.visibility, PostVisibility.public);
      expect(p.isEdited, isTrue);
      expect(p.why, 'From a connection');
      expect(p.score, 3.482);

      final author = p.author!;
      expect(author.type, AuthorType.person);
      expect(author.name, 'Priya Nair');
      expect(author.headline, 'Industrial electrician, Pune');
      expect(author.verified, isTrue);
      expect(author.initial, 'P');
      expect(author.route, '/people/$personId');

      expect(p.media, hasLength(2));
      expect(p.media.first.kind, MediaKind.image);
      expect(p.media.first.aspectRatio, closeTo(1200 / 900, 0.001));
      expect(p.media.first.semanticLabel, 'A finished control panel');
      expect(p.media.last.isVideo, isTrue);
      expect(p.media.last.durationLabel, '2:05');
      // No width or height: a safe 4:3 rather than a divide by zero.
      expect(p.media.last.aspectRatio, closeTo(4 / 3, 0.001));
      expect(p.media.last.semanticLabel, 'Video on this post');

      expect(p.engagement.reactions, 12);
      expect(p.engagement.comments, 3);
      expect(p.engagement.shares, 1);
      expect(p.engagement.saves, 4);

      expect(p.my.reaction, ReactionKind.celebrate);
      expect(p.my.saved, isFalse);
      expect(p.my.mine, isFalse);
      expect(p.canEdit, isFalse);
    });

    test('a job keeps its own currency and period', () {
      final job = FeedPost.fromJson(fullPostJson())!.job!;
      expect(job.title, 'Industrial electrician');
      expect(job.company, 'Werkhaus GmbH');
      expect(job.placeLine, 'Hamburg · DE');
      expect(job.isOpen, isTrue);
      // Euros, per month — never converted, never a bare number.
      expect(job.payLine, contains('€2,800'));
      expect(job.payLine, contains('€3,400'));
      expect(job.payLine, endsWith('per month'));
    });

    test('a job in rupees uses Indian grouping; a job without pay says so', () {
      final inr = PostJob.fromJson({
        'id': jobId,
        'title': 'Tandoor cook',
        'pay': {'min': 320000, 'period': 'year', 'currency': 'INR'},
      })!;
      expect(inr.payLine, contains('3,20,000'));
      expect(inr.payLine, endsWith('per year'));

      final none = PostJob.fromJson({'id': jobId, 'title': 'Helper'})!;
      expect(none.payLine, 'Pay not shown');

      // pay_disclosed = false means the employer chose not to show it.
      final hidden = PostJob.fromRow({
        'id': jobId,
        'title': 'Helper',
        'pay_min': 500,
        'pay_currency': 'INR',
        'pay_disclosed': false,
      })!;
      expect(hidden.payLine, 'Pay not shown');

      final closed = PostJob.fromJson({
        'id': jobId,
        'title': 'Helper',
        'status': 'closed',
      })!;
      expect(closed.isOpen, isFalse);
    });

    test('a quoted post carries its own author and media', () {
      final q = FeedPost.fromJson(fullPostJson())!.quoted!;
      expect(q.id, otherPostId);
      expect(q.body, 'We are hiring across three sites.');
      expect(q.author!.type, AuthorType.organization);
      expect(q.author!.isOrganization, isTrue);
      expect(q.author!.route, '/organizations/$companyId');
      expect(q.media, hasLength(1));
    });

    test('a card without an author or a time is dropped, not shown broken',
        () {
      expect(FeedPost.fromJson({'body': 'no id'}), isNull);
      expect(FeedPost.fromJson({'id': postId}), isNull);
      // An author who left Omelo: the post is still readable.
      final p = FeedPost.fromJson({
        'id': postId,
        'created_at': '2026-10-08T09:00:00Z',
        'author': null,
      })!;
      expect(p.author, isNull);
      expect(p.hasBody, isFalse);
      expect(p.engagement.reactions, 0);
      expect(p.my.reaction, isNull);
      expect(parsePosts([{'nonsense': 1}, plainPostJson()]), hasLength(1));
    });

    test('my own post can be edited; an organization post cannot', () {
      final mine = FeedPost.fromJson(plainPostJson(mine: true))!;
      expect(mine.my.mine, isTrue);
      expect(mine.canEdit, isTrue);

      final orgPost = FeedPost.fromJson({
        ...plainPostJson(mine: true),
        'author': organizationAuthor(),
      })!;
      expect(orgPost.my.mine, isTrue);
      expect(orgPost.canEdit, isFalse);
    });

    test('visibility an organization uses reads as public', () {
      expect(visibilityFromWire('organization'), PostVisibility.public);
      expect(visibilityFromWire('connections'), PostVisibility.connections);
      expect(visibilityFromWire(null), PostVisibility.public);
      expect(PostVisibility.followers.description,
          contains('follow you'));
    });
  });

  // -------------------------------------------------------------------------
  group('feed page', () {
    test('the ranked tab pages by offset, the rest by timestamp', () {
      final ranked = FeedPage.fromJson(
          feedJson('for_you', [fullPostJson()], nextOffset: 20));
      expect(ranked.tab, FeedTab.forYou);
      expect(ranked.tab.pagesByOffset, isTrue);
      expect(ranked.nextOffset, 20);
      expect(ranked.nextBefore, isNull);

      final chronological = FeedPage.fromJson(feedJson(
          'saved', [plainPostJson()],
          nextBefore: '2026-10-08T06:00:00Z'));
      expect(chronological.tab, FeedTab.saved);
      expect(chronological.tab.pagesByOffset, isFalse);
      expect(chronological.nextOffset, isNull);
      expect(chronological.nextBefore, DateTime.utc(2026, 10, 8, 6));
      expect(chronological.nextBefore!.isUtc, isTrue);
    });

    test('preferences and ranking come back with the page', () {
      final page = FeedPage.fromJson(feedJson('for_you', const []));
      expect(page.posts, isEmpty);
      expect(page.preferences.showJobs, isTrue);
      expect(page.preferences.showOrganizations, isFalse);
      expect(page.preferences.preferredLanguages, ['en', 'mr']);
      expect(page.ranking, startsWith('connection 3'));
    });

    test('a person with no feed_preferences row sees everything', () {
      final page = FeedPage.fromJson({'tab': 'for_you', 'posts': []});
      expect(page.preferences.showJobs, isTrue);
      expect(page.preferences.showOrganizations, isTrue);
      expect(page.preferences.showCareerContent, isTrue);
      expect(page.preferences.showNetworkActivity, isTrue);
      expect(page.preferences.preferredLanguages, isEmpty);
      expect(FeedPage.fromJson(null, fallbackTab: FeedTab.jobs).tab,
          FeedTab.jobs);
    });

    test('tab wires round-trip and unknown falls back to For you', () {
      for (final t in FeedTab.values) {
        expect(feedTabFromWire(t.wire), t);
      }
      expect(feedTabFromWire('nonsense'), FeedTab.forYou);
      expect(FeedTab.forYou.wire, 'for_you');
      expect(FeedTab.forYou.label, 'For you');
    });

    test('preferences payload uses the server\'s own keys', () {
      const p = FeedPreferences(
        showJobs: false,
        showOrganizations: true,
        showCareerContent: false,
        showNetworkActivity: true,
        preferredLanguages: ['hi'],
      );
      expect(p.toPayload(), {
        'show_jobs': false,
        'show_organizations': true,
        'show_career_content': false,
        'show_network_activity': true,
        'preferred_languages': ['hi'],
      });
    });
  });

  // -------------------------------------------------------------------------
  group('reactions', () {
    test('tapping the same one removes it, another replaces it', () {
      expect(toggledReaction(null, ReactionKind.like), ReactionKind.like);
      expect(toggledReaction(ReactionKind.like, ReactionKind.like), isNull);
      expect(toggledReaction(ReactionKind.like, ReactionKind.support),
          ReactionKind.support);
    });

    test('the count follows the change and never goes below zero', () {
      expect(reactionCountAfter(3, null, ReactionKind.like), 4);
      expect(reactionCountAfter(3, ReactionKind.like, null), 2);
      // Swapping one reaction for another does not change the count.
      expect(
          reactionCountAfter(3, ReactionKind.like, ReactionKind.support), 3);
      expect(reactionCountAfter(0, ReactionKind.like, null), 0);
    });

    test('wire values round-trip; an unknown one is no reaction', () {
      for (final k in ReactionKind.values) {
        expect(reactionFromWire(k.wire), k);
      }
      expect(reactionFromWire('applause'), isNull);
      expect(reactionFromWire(null), isNull);
      expect(ReactionKind.celebrate.chosenLabel, 'Celebrated');
    });
  });

  // -------------------------------------------------------------------------
  group('comments', () {
    test('one level of replies, with my own reaction', () {
      final list = parseComments(commentsJson());
      expect(list, hasLength(1));
      final c = list.single;
      expect(c.body, 'Good work. What gauge did you run?');
      expect(c.author!.isOrganization, isTrue);
      expect(c.reactions, 2);
      expect(c.myReaction, ReactionKind.like);
      expect(c.mine, isFalse);
      // Three replies were written, one survives: the screen says so.
      expect(c.replyCount, 3);
      expect(c.thread, hasLength(1));
      expect(c.thread.single.body, 'Four square, same as the last run.');
      expect(c.thread.single.mine, isTrue);
    });

    test('a comment without an id or a time is dropped', () {
      expect(parseComments([
        {'body': 'no id'},
        {'id': commentId, 'body': 'no time'},
      ]), isEmpty);
    });

    test('who may delete a comment', () {
      expect(canDeleteComment(mine: true, iOwnThePost: false), isTrue);
      expect(canDeleteComment(mine: false, iOwnThePost: true), isTrue);
      expect(canDeleteComment(mine: false, iOwnThePost: false), isFalse);
    });

    test('validation matches what the database accepts', () {
      expect(validateComment('   '), isNotNull);
      expect(validateComment('Nice work'), isNull);
      expect(validateComment('x' * kCommentBodyMax), isNull);
      expect(validateComment('x' * (kCommentBodyMax + 1)), isNotNull);
    });
  });

  // -------------------------------------------------------------------------
  group('composer validation', () {
    test('a post needs words, media, a job or something shared', () {
      expect(validatePostBody(''), isNotNull);
      expect(validatePostBody('   '), isNotNull);
      expect(validatePostBody('', hasMedia: true), isNull);
      expect(validatePostBody('', hasJob: true), isNull);
      expect(validatePostBody('', hasSharedPost: true), isNull);
      expect(validatePostBody('Hello'), isNull);
    });

    test('3000 characters, counted the way the database counts them', () {
      expect(validatePostBody('x' * kPostBodyMax), isNull);
      expect(validatePostBody('x' * (kPostBodyMax + 1)), isNotNull);
      // An emoji is one character, not two.
      expect(charactersLeft('👷', kPostBodyMax), kPostBodyMax - 1);
      expect(charactersLeft('x' * 3001, kPostBodyMax), -1);
    });

    test('the draft sends what the server asks for, and no company_id', () {
      const d = PostDraft(
        body: '  Hello  ',
        visibility: PostVisibility.connections,
        jobId: jobId,
        media: [
          UploadedMedia(
            storagePath: '$meId/1-0.jpg',
            kind: MediaKind.image,
            mimeType: 'image/jpeg',
            width: 10,
            height: 20,
            altText: 'A panel',
          ),
        ],
      );
      final p = d.toPayload();
      expect(p['body'], 'Hello');
      expect(p['visibility'], 'connections');
      expect(p['job_id'], jobId);
      expect(p.containsKey('company_id'), isFalse);
      expect(p['media'], [
        {
          'kind': 'image',
          'storage_path': '$meId/1-0.jpg',
          'mime_type': 'image/jpeg',
          'width': 10,
          'height': 20,
          'alt_text': 'A panel',
        }
      ]);

      // Editing only changes the words and who may read them.
      expect(const PostDraft(body: 'x').toEditPayload(),
          {'body': 'x', 'visibility': 'public'});
    });

    test('media goes in my own folder, which is the only place I may write',
        () {
      final path = NetworkRepository.mediaPath(meId,
          index: 2, extension: 'png', now: fixedNow);
      expect(path, startsWith('$meId/'));
      expect(path, endsWith('-2.png'));
    });
  });

  // -------------------------------------------------------------------------
  group('my network', () {
    test('each of the five views has its own shape', () {
      final connections = parseNetwork([
        {...personAuthor(), 'connected_at': '2026-09-01T10:00:00Z'},
      ], NetworkView.connections);
      expect(connections.single.person.name, 'Priya Nair');
      expect(connections.single.connectedAt, isNotNull);
      expect(connections.single.connectionId, isNull);

      final invitations = parseNetwork([
        {
          'connection_id': connectionId,
          'message': 'We worked the same site.',
          'requested_at': '2026-10-07T10:00:00Z',
          'person': personAuthor(),
        },
      ], NetworkView.invitations);
      expect(invitations.single.connectionId, connectionId);
      expect(invitations.single.message, 'We worked the same site.');
      expect(invitations.single.person.id, personId);

      final sent = parseNetwork([
        {
          'connection_id': connectionId,
          'requested_at': '2026-10-07T10:00:00Z',
          'person': personAuthor(),
        },
      ], NetworkView.sent);
      expect(sent.single.connectionId, connectionId);
      expect(sent.single.message, isNull);

      final followers =
          parseNetwork([personAuthor()], NetworkView.followers);
      expect(followers.single.person.type, AuthorType.person);

      // Following mixes people and organizations.
      final following = parseNetwork(
          [personAuthor(), organizationAuthor()], NetworkView.following);
      expect(following.map((e) => e.person.type),
          [AuthorType.person, AuthorType.organization]);
    });

    test('suggestions carry the server\'s own reason', () {
      final list = parseSuggestions([
        {...personAuthor(), 'reason': 'Worked at the same organization'},
      ]);
      expect(list.single.reason, 'Worked at the same organization');
    });

    test('view wires round-trip; an unknown one falls back to connections',
        () {
      for (final v in NetworkView.values) {
        expect(networkViewFromWire(v.wire), v);
      }
      expect(networkViewFromWire('nonsense'), NetworkView.connections);
    });

    test('follow targets map person to person and organization to company',
        () {
      expect(followTargetWire(AuthorType.person), 'person');
      expect(followTargetWire(AuthorType.organization), 'company');
    });
  });

  // -------------------------------------------------------------------------
  group('organization feed', () {
    test('header, follower count and posts', () {
      final org = OrganizationFeed.fromJson({
        'organization': organizationAuthor(),
        'followers': 1204,
        'following': true,
        'posts': [plainPostJson()],
      })!;
      expect(org.organization!.name, 'Sunrise Facilities');
      expect(org.organization!.verified, isTrue);
      expect(org.followerLine, '1,204 followers');
      expect(org.following, isTrue);
      expect(org.posts, hasLength(1));

      expect(
        OrganizationFeed.fromJson({
          'organization': organizationAuthor(),
          'followers': 1,
        })!.followerLine,
        '1 follower',
      );
      expect(
        OrganizationFeed.fromJson({
          'organization': organizationAuthor(),
          'followers': 0,
        })!.followerLine,
        'No followers yet',
      );
      // A company that is gone: nothing to show.
      expect(OrganizationFeed.fromJson({'followers': 3}), isNull);
      expect(OrganizationFeed.fromJson(null), isNull);
    });
  });

  // -------------------------------------------------------------------------
  group('words', () {
    test('post times', () {
      final now = DateTime(2026, 10, 8, 12);
      expect(postTime(now.subtract(const Duration(seconds: 20)), now),
          'Just now');
      expect(postTime(now.subtract(const Duration(minutes: 5)), now), '5m');
      expect(postTime(now.subtract(const Duration(hours: 3)), now), '3h');
      expect(postTime(now.subtract(const Duration(days: 2)), now), '2d');
      expect(postTime(now.subtract(const Duration(days: 10)), now), '1w');
      expect(postTime(DateTime(2026, 5, 2), now), '2 May');
      expect(postTime(DateTime(2025, 5, 2), now), '2 May 2025');
    });

    test('counts', () {
      expect(countWords(0, 'reaction', 'reactions'), isNull);
      expect(countWords(1, 'reaction', 'reactions'), '1 reaction');
      expect(countWords(9, 'reaction', 'reactions'), '9 reactions');
    });

    test('report reasons use the database enum', () {
      expect(ReportReason.paymentRequest.wire, 'payment_request');
      expect(ReportReason.inappropriateContent.wire, 'inappropriate_content');
      expect(ReportSubject.comment.wire, 'comment');
      expect(BlockTarget.company.wire, 'company');
      expect(MuteTarget.post.wire, 'post');
    });
  });

  // -------------------------------------------------------------------------
  group('errors', () {
    test('the server\'s own words are kept', () {
      const e = PostgrestException(
          message: 'Replies go one level deep', code: '22023');
      expect(networkError(e), 'Replies go one level deep');
      expect(
        networkError(const PostgrestException(message: '', code: '42501')),
        'You cannot do that.',
      );
      expect(networkError(Exception('x')), startsWith('Could not reach Omelo'));
      expect(
        needsSignIn(
            const PostgrestException(message: 'Sign in first', code: '42501')),
        isTrue,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('notifications', () {
    test('every new type has an icon group', () {
      expect(notificationKind('post_reaction'), NotificationKind.post);
      expect(notificationKind('post_comment'), NotificationKind.post);
      expect(notificationKind('post_share'), NotificationKind.post);
      expect(notificationKind('post_mention'), NotificationKind.post);
      expect(notificationKind('connection_request'), NotificationKind.network);
      expect(notificationKind('connection_update'), NotificationKind.network);
      expect(notificationKind('new_follower'), NotificationKind.network);
    });

    test('the server\'s own deeplinks resolve to real screens', () {
      expect(workerDeeplink('/feed/$postId'), '/feed/$postId');
      expect(workerDeeplink('/network/invitations'), '/network/invitations');
      expect(workerDeeplink('/network/followers'), '/network/followers');
      expect(workerDeeplink('/network'), '/network');
      expect(workerDeeplink('/feed'), '/feed');
      expect(workerDeeplink('/people/$personId'), '/people/$personId');
      expect(workerDeeplink('/organizations/$companyId'),
          '/organizations/$companyId');
      expect(workerDeeplink('https://omelo.app/feed/$postId'),
          '/feed/$postId');
      // Anything else is ignored rather than sending the worker nowhere.
      expect(workerDeeplink('/network/everyone'), isNull);
      expect(workerDeeplink('/feed/not-a-uuid'), isNull);
    });

    test('a notice without a link falls back to its entity', () {
      AppNotification notice(String type, String entity, String id) =>
          AppNotification.fromRow({
            'id': 'n1',
            'type': type,
            'title': 'x',
            'entity_type': entity,
            'entity_id': id,
            'created_at': '2026-10-08T09:00:00Z',
          });

      expect(notice('post_reaction', 'post', postId).target, '/feed/$postId');
      expect(notice('post_comment', 'comment', postId).target, '/feed/$postId');
      expect(notice('connection_request', 'connection', connectionId).target,
          '/network/invitations');
      expect(notice('new_follower', 'person', personId).target,
          '/people/$personId');
    });
  });

  // -------------------------------------------------------------------------
  group('screens', () {
    late FakeNetwork repo;
    setUp(() => repo = FakeNetwork());

    List<Override> overrides() => [
          isSignedInProvider.overrideWithValue(true),
          // Null keeps the notification bell and its realtime channel out of
          // the test; the screens only need "signed in".
          currentUserProvider.overrideWithValue(null),
          networkRepositoryProvider.overrideWithValue(repo),
          networkClockProvider.overrideWithValue(() => fixedNow),
          mediaUrlProvider.overrideWithValue(repo.mediaUrl),
          languagesProvider.overrideWith((_) async => const []),
          mediaChooserProvider.overrideWithValue(({required bool video}) async =>
              [
                PickedMedia(
                  bytes: _pngBytes,
                  mimeType: video ? 'video/mp4' : 'image/png',
                  isVideo: video,
                  name: video ? 'clip.mp4' : 'panel.png',
                  width: video ? null : 1,
                  height: video ? null : 1,
                ),
              ]),
        ];

    Future<void> pumpAt(
      WidgetTester tester,
      Size size,
      String location, {
      List<Override> extra = const [],
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [...overrides(), ...extra],
        child: MaterialApp.router(
          theme: OmeloTheme.light(),
          routerConfig: GoRouter(
            initialLocation: location,
            routes: [
              ...networkRoutes(),
              GoRoute(path: '/home', builder: (_, __) => const Text('home')),
              GoRoute(
                path: '/company/:id',
                builder: (_, s) =>
                    Scaffold(body: Text('company ${s.pathParameters['id']}')),
              ),
              GoRoute(
                path: '/job/:id',
                builder: (_, s) =>
                    Scaffold(body: Text('job ${s.pathParameters['id']}')),
              ),
              GoRoute(path: '/sign-in', builder: (_, __) => const Text('sign in')),
              // `/feed/:id/edit` is reached with the card in hand, which a
              // GoRouter initial location cannot carry; this stands in for
              // that hand-over.
              GoRoute(
                path: '/edit-test',
                builder: (_, __) => ComposerScreen(
                  editing: FeedPost.fromJson(fullPostJson(mine: true)),
                ),
              ),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    // -- The feed ------------------------------------------------------------

    for (final size in const [Size(360, 2400), Size(1400, 2000)]) {
      testWidgets('feed at ${size.width.toInt()}px shows a whole card',
          (tester) async {
        await pumpAt(tester, size, '/feed');
        expect(tester.takeException(), isNull);

        expect(find.text('Omelo feed'), findsOneWidget);
        // The server's own explanation of why this post is here.
        expect(find.text('From a connection'), findsOneWidget);
        // Both cards are hers.
        expect(find.text('Priya Nair'), findsNWidgets(2));
        expect(
            find.text(
                'Finished the panel wiring on the new line today.'),
            findsOneWidget);
        // The job, in euros per month.
        expect(find.textContaining('€2,800'), findsOneWidget);
        expect(find.textContaining('per month'), findsOneWidget);
        // The quoted post.
        expect(find.text('We are hiring across three sites.'), findsOneWidget);
        // Counts and actions.
        expect(find.textContaining('12 reactions'), findsOneWidget);
        expect(find.text('Celebrated'), findsOneWidget);
        expect(find.text('Comment'), findsWidgets);
        expect(find.text('Save'), findsWidgets);
      });
    }

    testWidgets('switching tabs asks the server for that tab', (tester) async {
      await pumpAt(tester, const Size(1000, 2000), '/feed');
      expect(repo.feedCalls.single.tab, FeedTab.forYou);
      // The ranked tab pages by offset.
      expect(repo.feedCalls.single.offset, 0);

      await tester.tap(find.text('Saved'));
      await tester.pumpAndSettle();
      expect(repo.feedCalls.last.tab, FeedTab.saved);
      // A chronological tab never sends an offset of its own.
      expect(repo.feedCalls.last.before, isNull);
      expect(find.text('Nothing saved yet'), findsOneWidget);

      await tester.tap(find.text('Following'));
      await tester.pumpAndSettle();
      expect(repo.feedCalls.last.tab, FeedTab.following);
      expect(find.text('Looking for a mate on the Chakan site next week.'),
          findsOneWidget);
    });

    testWidgets('scrolling the ranked tab asks for the next offset',
        (tester) async {
      repo.postsByTab['for_you'] = manyPosts(20);
      await pumpAt(tester, const Size(500, 3000), '/feed');
      expect(repo.feedCalls.single.offset, 0);

      await tester.drag(find.byType(ListView), const Offset(0, -2600));
      await tester.pumpAndSettle();
      expect(repo.feedCalls.length, greaterThan(1));
      // The server said where the next page starts; the app does not guess.
      expect(repo.feedCalls.last.tab, FeedTab.forYou);
      expect(repo.feedCalls.last.offset, 20);
      expect(repo.feedCalls.last.before, isNull);
    });

    testWidgets('scrolling a chronological tab asks for the next timestamp',
        (tester) async {
      repo.postsByTab['following'] = manyPosts(20);
      await pumpAt(tester, const Size(500, 3000), '/feed?tab=following');
      expect(repo.feedCalls.single.tab, FeedTab.following);

      await tester.drag(find.byType(ListView), const Offset(0, -2600));
      await tester.pumpAndSettle();
      expect(repo.feedCalls.last.before, DateTime.utc(2026, 10, 7, 6));
      expect(repo.feedCalls.last.offset, isNull);
    });

    testWidgets('feed preferences save what the worker chose', (tester) async {
      await pumpAt(tester, const Size(700, 2000), '/feed');
      await tester.tap(find.byIcon(Icons.tune));
      await tester.pumpAndSettle();
      expect(find.text('What I see'), findsOneWidget);

      await tester.tap(find.text('Jobs people share'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.calls['preferences'], {
        // The page came back with organizations already off.
        'show_jobs': false,
        'show_organizations': false,
        'show_career_content': true,
        'show_network_activity': true,
        'preferred_languages': ['en', 'mr'],
      });
    });

    testWidgets('a refusal is shown in the server\'s words', (tester) async {
      repo.failWith = const PostgrestException(
          message: 'Unknown feed boom', code: '22023');
      await pumpAt(tester, const Size(500, 1200), '/feed');
      expect(find.text('Could not load the feed'), findsOneWidget);
      expect(find.text('Unknown feed boom'), findsOneWidget);
    });

    testWidgets('signed out, the feed asks you to sign in', (tester) async {
      await pumpAt(tester, const Size(500, 1200), '/feed',
          extra: [isSignedInProvider.overrideWithValue(false)]);
      expect(find.text('Your professional network'), findsOneWidget);
      expect(find.text('Sign in or create an account'), findsOneWidget);
    });

    // -- Reacting ------------------------------------------------------------

    testWidgets('tapping Like reacts, tapping again takes it back',
        (tester) async {
      await pumpAt(tester, const Size(500, 3200), '/feed');
      // The plain post has no reaction of mine and three in all.
      expect(find.text('3 reactions'), findsOneWidget);

      await tester.tap(find.text('Like'));
      await tester.pumpAndSettle();
      expect(repo.calls['react'], '$otherPostId:like');
      expect(find.text('Liked'), findsOneWidget);
      expect(find.text('4 reactions'), findsOneWidget);

      await tester.tap(find.text('Liked'));
      await tester.pumpAndSettle();
      expect(repo.calls['react'], '$otherPostId:null');
      expect(find.text('3 reactions'), findsOneWidget);
    });

    testWidgets('holding Like offers the other reactions', (tester) async {
      await pumpAt(tester, const Size(500, 3200), '/feed');
      await tester.longPress(find.text('Like'));
      await tester.pumpAndSettle();
      expect(find.text('Insightful'), findsOneWidget);
      await tester.tap(find.text('Insightful'));
      await tester.pumpAndSettle();
      expect(repo.calls['react'], '$otherPostId:insightful');
    });

    testWidgets('saving a post tells the server and says so', (tester) async {
      await pumpAt(tester, const Size(500, 3200), '/feed');
      await tester.tap(find.text('Save').first);
      await tester.pumpAndSettle();
      expect(repo.calls['save'], '$postId:true');
      expect(find.text('Saved to your feed.'), findsOneWidget);
    });

    testWidgets('a post that is not public cannot be shared on',
        (tester) async {
      repo.postsByTab['for_you'] = [
        fullPostJson(visibility: 'connections'),
      ];
      await pumpAt(tester, const Size(500, 3200), '/feed');
      final share = tester.widget<InkWell>(
        find.ancestor(of: find.text('Share'), matching: find.byType(InkWell))
            .first,
      );
      expect(share.onTap, isNull);
    });

    // -- The overflow menu ---------------------------------------------------

    testWidgets('muting someone takes their post off the feed',
        (tester) async {
      repo.postsByTab['for_you'] = [plainPostJson()];
      await pumpAt(tester, const Size(500, 3200), '/feed');
      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mute this person'));
      await tester.pumpAndSettle();
      expect(repo.calls['mute'], 'person:$personId:true');
      expect(find.text('Looking for a mate on the Chakan site next week.'),
          findsNothing);
    });

    testWidgets('my own post offers Edit and Delete, not Block',
        (tester) async {
      repo.postsByTab['for_you'] = [plainPostJson(mine: true)];
      await pumpAt(tester, const Size(500, 3200), '/feed');
      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
      expect(find.text('Edit'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.textContaining('Block'), findsNothing);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(find.text('Delete this post?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repo.calls['delete'], otherPostId);
    });

    testWidgets('reporting a post sends the reason', (tester) async {
      repo.postsByTab['for_you'] = [plainPostJson()];
      await pumpAt(tester, const Size(500, 3200), '/feed');
      await tester.tap(find.byIcon(Icons.more_horiz).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Report this post'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('It asks me for money'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Report'));
      await tester.pumpAndSettle();
      expect(repo.calls['report'], 'post:$otherPostId:payment_request');
    });

    // -- Post detail and comments --------------------------------------------

    for (final size in const [Size(360, 2200), Size(1400, 1800)]) {
      testWidgets('post detail at ${size.width.toInt()}px threads the comments',
          (tester) async {
        await pumpAt(tester, size, '/feed/$postId');
        expect(tester.takeException(), isNull);
        expect(repo.calls['detail'], postId);
        expect(repo.calls['comments'], postId);

        expect(find.text('1 comment'), findsOneWidget);
        expect(find.text('Good work. What gauge did you run?'), findsOneWidget);
        // The reply sits under its comment.
        expect(find.text('Four square, same as the last run.'), findsOneWidget);
        // Two of the three replies were deleted; the screen says so.
        expect(find.textContaining('2 more replies were deleted'),
            findsOneWidget);
        // The post's "why" line belongs to the feed, not here.
        expect(find.text('From a connection'), findsNothing);
      });
    }

    testWidgets('replying sends the parent comment', (tester) async {
      await pumpAt(tester, const Size(600, 2200), '/feed/$postId');
      await tester.tap(find.text('Reply'));
      await tester.pumpAndSettle();
      expect(find.text('Replying to Sunrise Facilities'), findsOneWidget);

      await tester.enterText(
          find.byType(TextField).last, 'Four square, yes.');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(repo.calls['comment'], {
        'post': postId,
        'body': 'Four square, yes.',
        'parent': commentId,
      });
    });

    testWidgets('a top-level comment has no parent', (tester) async {
      await pumpAt(tester, const Size(600, 2200), '/feed/$postId');
      await tester.enterText(find.byType(TextField).last, 'Well done.');
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.send));
      await tester.pumpAndSettle();
      expect(repo.calls['comment'],
          {'post': postId, 'body': 'Well done.', 'parent': null});
    });

    testWidgets('I can delete my own reply; the comment offers Report',
        (tester) async {
      await pumpAt(tester, const Size(600, 2200), '/feed/$postId');
      // One Delete, for the reply that is mine.
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Report'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
      await tester.pumpAndSettle();
      expect(repo.calls['deleteComment'], replyId);
    });

    testWidgets('the post\'s author may delete any comment on it',
        (tester) async {
      repo.detail = fullPostJson(mine: true);
      await pumpAt(tester, const Size(600, 2200), '/feed/$postId');
      // Mine (the reply) and the organization's comment: two Deletes.
      expect(find.text('Delete'), findsNWidgets(2));
      expect(find.text('Report'), findsNothing);
    });

    testWidgets('a comment reaction flips at once', (tester) async {
      await pumpAt(tester, const Size(600, 2200), '/feed/$postId');
      expect(find.text('Like · 2'), findsOneWidget);
      await tester.tap(find.text('Like · 2'));
      await tester.pumpAndSettle();
      expect(repo.calls['commentReaction'], '$commentId:null');
      expect(find.text('Like · 1'), findsOneWidget);
    });

    testWidgets('a post that is gone says so', (tester) async {
      repo.detail = const {};
      await pumpAt(tester, const Size(600, 1200), '/feed/$postId');
      expect(find.text('Could not open this post'), findsOneWidget);
    });

    // -- Composer ------------------------------------------------------------

    testWidgets('the composer counts down and refuses an empty post',
        (tester) async {
      await pumpAt(tester, const Size(600, 1600), '/feed/compose');
      expect(find.text('New post'), findsOneWidget);
      expect(find.text('$kPostBodyMax'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Write something'), findsOneWidget);
      expect(repo.calls['create'], isNull);

      await tester.enterText(find.byType(TextField).first, 'Hello Omelo');
      await tester.pumpAndSettle();
      expect(find.text('${kPostBodyMax - 11}'), findsOneWidget);
    });

    testWidgets('too long disables Post and says how far over', (tester) async {
      await pumpAt(tester, const Size(600, 1600), '/feed/compose');
      await tester.enterText(
          find.byType(TextField).first, 'x' * (kPostBodyMax + 5));
      await tester.pumpAndSettle();
      expect(find.text('-5'), findsOneWidget);
      final post = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Post'));
      expect(post.onPressed, isNull);
    });

    testWidgets('visibility is sent with the post', (tester) async {
      await pumpAt(tester, const Size(600, 1600), '/feed/compose');
      expect(find.textContaining('Anyone on Omelo can see this'),
          findsOneWidget);
      await tester.tap(find.widgetWithText(ChoiceChip, 'Connections'));
      await tester.pumpAndSettle();
      expect(find.textContaining('people you are connected with'),
          findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Hello Omelo');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();
      final payload = repo.calls['create'] as Map<String, dynamic>;
      expect(payload['body'], 'Hello Omelo');
      expect(payload['visibility'], 'connections');
    });

    testWidgets('a photo is uploaded into my own folder before the post goes',
        (tester) async {
      await pumpAt(tester, const Size(600, 1800), '/feed/compose');
      await tester.tap(find.text('Add photos'));
      await tester.pumpAndSettle();
      expect(find.text('Describe'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'On site today');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();

      final uploads = repo.calls['uploads'] as List;
      expect(uploads.single, startsWith('$meId/'));
      final payload = repo.calls['create'] as Map<String, dynamic>;
      expect((payload['media'] as List).single['storage_path'],
          startsWith('$meId/'));
    });

    testWidgets('a failed post keeps the words and shows the refusal',
        (tester) async {
      await pumpAt(tester, const Size(600, 1600), '/feed/compose');
      await tester.enterText(find.byType(TextField).first, 'Hello Omelo');
      await tester.pumpAndSettle();
      repo.failWith =
          const PostgrestException(message: 'Check the post: body', code: '22023');
      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();
      expect(find.text('Check the post: body'), findsOneWidget);
      expect(find.text('Hello Omelo'), findsOneWidget);
    });

    testWidgets('attaching a job shows it in its own currency',
        (tester) async {
      await pumpAt(tester, const Size(600, 1800), '/feed/compose');
      await tester.tap(find.text('Attach a job'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Industrial electrician').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('€2,800'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Post'));
      await tester.pumpAndSettle();
      expect((repo.calls['create'] as Map)['job_id'], jobId);
    });

    testWidgets('editing changes only the words and the visibility',
        (tester) async {
      await pumpAt(tester, const Size(600, 1800), '/edit-test');
      expect(find.text('Edit post'), findsOneWidget);
      expect(
          find.text('Finished the panel wiring on the new line today.'),
          findsOneWidget);
      // Media and the job stay as they were, and the screen says so.
      expect(find.textContaining('stay as they were'), findsOneWidget);
      expect(find.text('Add photos'), findsNothing);

      await tester.enterText(
          find.byType(TextField).first, 'Finished the panel wiring. Rewired.');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(repo.calls['update'], {
        'post': postId,
        'body': 'Finished the panel wiring. Rewired.',
        'visibility': 'public',
      });
    });

    // -- My network ----------------------------------------------------------

    testWidgets('invitations can be accepted', (tester) async {
      repo.network[NetworkView.invitations] = parseNetwork([
        {
          'connection_id': connectionId,
          'message': 'We worked the same site.',
          'requested_at': '2026-10-07T10:00:00Z',
          'person': personAuthor(),
        },
      ], NetworkView.invitations);

      await pumpAt(tester, const Size(700, 1600), '/network/invitations');
      expect(find.text('My network'), findsOneWidget);
      expect(find.text('Priya Nair'), findsOneWidget);
      expect(find.text('We worked the same site.'), findsOneWidget);

      await tester.tap(find.text('Accept'));
      await tester.pumpAndSettle();
      expect(repo.calls['respond'], '$connectionId:true');
    });

    testWidgets('a sent request can be withdrawn', (tester) async {
      repo.network[NetworkView.sent] = parseNetwork([
        {
          'connection_id': connectionId,
          'requested_at': '2026-10-07T10:00:00Z',
          'person': personAuthor(),
        },
      ], NetworkView.sent);

      await pumpAt(tester, const Size(700, 1600), '/network/sent');
      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Withdraw'));
      await tester.pumpAndSettle();
      expect(repo.calls['remove'], personId);
    });

    testWidgets('people you may know show the reason and offer Connect',
        (tester) async {
      repo.suggestionList = parseSuggestions([
        {...personAuthor(), 'reason': 'Worked at the same organization'},
      ]);
      await pumpAt(tester, const Size(700, 1600), '/network');
      expect(find.text('People you may know'), findsOneWidget);
      expect(find.text('Worked at the same organization'), findsOneWidget);

      await tester.tap(find.text('Connect').first);
      await tester.pumpAndSettle();
      expect(find.text('Connect with Priya Nair?'), findsOneWidget);
      await tester.tap(find.text('Send request'));
      await tester.pumpAndSettle();
      expect((repo.calls['connect'] as Map)['person'], personId);
    });

    testWidgets('following someone from the followers list', (tester) async {
      repo.network[NetworkView.followers] =
          parseNetwork([personAuthor()], NetworkView.followers);
      await pumpAt(tester, const Size(700, 1600), '/network/followers');
      await tester.tap(find.text('Follow'));
      await tester.pumpAndSettle();
      expect(repo.calls['follow'], 'person:$personId:true');
      expect(find.text('Following'), findsWidgets);
    });

    // -- Organization and person pages ---------------------------------------

    for (final size in const [Size(360, 1800), Size(1400, 1400)]) {
      testWidgets(
          'organization page at ${size.width.toInt()}px shows followers',
          (tester) async {
        await pumpAt(tester, size, '/organizations/$companyId');
        expect(tester.takeException(), isNull);
        expect(find.text('Sunrise Facilities'), findsWidgets);
        expect(find.text('1,204 followers'), findsOneWidget);
        expect(find.text('Follow'), findsOneWidget);
        expect(find.text('Staffing agency'), findsOneWidget);
        expect(find.text('Looking for a mate on the Chakan site next week.'),
            findsOneWidget);
      });
    }

    testWidgets('a person page offers Connect and Follow', (tester) async {
      await pumpAt(tester, const Size(700, 1800), '/people/$personId');
      expect(find.text('Priya Nair'), findsWidgets);
      expect(find.text('Connect'), findsOneWidget);
      expect(find.text('Follow'), findsOneWidget);
      // Messaging between workers is not built; the screen says so plainly
      // instead of offering a button that does nothing.
      final message = tester.widget<OutlinedButton>(find.ancestor(
        of: find.text('Message'),
        matching: find.byWidgetPredicate((w) => w is OutlinedButton),
      ));
      expect(message.onPressed, isNull);
      expect(find.textContaining('not built yet'), findsOneWidget);
    });
  });
}
