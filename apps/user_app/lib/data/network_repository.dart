import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/app_state.dart';
import 'network.dart';
import 'jobs_repository.dart' show supabaseProvider;

export 'network.dart';

/// The bucket post photos and videos live in. Public to read; a signed-in
/// person may only write inside their own folder.
const kPostMediaBucket = 'post-media';

/// Characters PostgREST reads as filter syntax, stripped out of a search
/// term so a stray comma or bracket cannot change the query.
final _escapes = RegExp(r'[%_,()\\]');

final networkRepositoryProvider = Provider<NetworkRepository>(
  (ref) => NetworkRepository(ref.watch(supabaseProvider)),
);

/// A photo or video chosen on the device, already in memory.
class PickedMedia {
  const PickedMedia({
    required this.bytes,
    required this.mimeType,
    required this.isVideo,
    this.name,
    this.width,
    this.height,
    this.durationSeconds,
    this.altText,
  });

  final Uint8List bytes;
  final String mimeType;
  final bool isVideo;
  final String? name;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final String? altText;

  PickedMedia withAltText(String? text) => PickedMedia(
        bytes: bytes,
        mimeType: mimeType,
        isVideo: isVideo,
        name: name,
        width: width,
        height: height,
        durationSeconds: durationSeconds,
        altText: (text ?? '').trim().isEmpty ? null : text!.trim(),
      );

  /// The extension the bucket will accept, taken from the MIME type rather
  /// than the file name, which on the web is often missing.
  String get extension => switch (mimeType) {
        'image/jpeg' => 'jpg',
        'image/png' => 'png',
        'image/webp' => 'webp',
        'image/gif' => 'gif',
        'video/mp4' => 'mp4',
        'video/webm' => 'webm',
        _ => isVideo ? 'mp4' : 'jpg',
      };

  int get sizeBytes => bytes.length;
}

/// What the bucket accepts, as migration 73 set it up.
const kPostMediaMimeTypes = <String>{
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'video/mp4',
  'video/webm',
};

/// 50 MB, the bucket's own limit.
const kPostMediaMaxBytes = 52428800;

/// At most ten items on one post, the way the database counts positions.
const kPostMediaMax = 10;

/// Already-uploaded media, ready to be sent with the post.
class UploadedMedia {
  const UploadedMedia({
    required this.storagePath,
    required this.kind,
    required this.mimeType,
    this.width,
    this.height,
    this.durationSeconds,
    this.altText,
  });

  final String storagePath;
  final MediaKind kind;
  final String mimeType;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final String? altText;

  Map<String, dynamic> toJson() => {
        'kind': kind == MediaKind.video ? 'video' : 'image',
        'storage_path': storagePath,
        'mime_type': mimeType,
        'width': ?width,
        'height': ?height,
        'duration_seconds': ?durationSeconds,
        'alt_text': ?altText,
      };
}

/// What the composer is about to send.
class PostDraft {
  const PostDraft({
    this.body = '',
    this.visibility = PostVisibility.public,
    this.jobId,
    this.sharedPostId,
    this.workIdentityId,
    this.media = const [],
    this.languageCode,
  });

  final String body;
  final PostVisibility visibility;
  final String? jobId;
  final String? sharedPostId;
  final String? workIdentityId;
  final List<UploadedMedia> media;
  final String? languageCode;

  /// `company_id` is never sent: a worker posts as themselves. Posting as an
  /// organization happens in the employer portal.
  Map<String, dynamic> toPayload() => {
        'body': body.trim().isEmpty ? null : body.trim(),
        'visibility': visibility.wire,
        'job_id': ?jobId,
        'shared_post_id': ?sharedPostId,
        'work_identity_id': ?workIdentityId,
        'language_code': ?languageCode,
        if (media.isNotEmpty) 'media': [for (final m in media) m.toJson()],
      };

  /// Editing only ever changes the words and who can read them; the server
  /// ignores everything else on an update.
  Map<String, dynamic> toEditPayload() => {
        'body': body.trim().isEmpty ? null : body.trim(),
        'visibility': visibility.wire,
      };
}

/// Posts, reactions, comments, connections and follows.
///
/// Every rule lives in the database: who may see a post, who may delete a
/// comment, how the feed is ranked. The app sends what the worker chose and
/// shows the server's words back.
class NetworkRepository {
  NetworkRepository(this._db);
  final SupabaseClient _db;

  String? get myId => _db.auth.currentUser?.id;

  // -- The feed ----------------------------------------------------------------

  Future<FeedPage> feed(
    FeedTab tab, {
    int limit = 20,
    DateTime? before,
    int? offset,
  }) async {
    final res = await _db.rpc('omelo_feed', params: {
      'p_tab': tab.wire,
      'p_limit': limit,
      'p_before': before?.toUtc().toIso8601String(),
      'p_offset': offset ?? 0,
    });
    return FeedPage.fromJson(res, fallbackTab: tab);
  }

  Future<FeedPost?> postDetail(String postId) async {
    final res = await _db.rpc('omelo_post_detail', params: {'p_post': postId});
    return FeedPost.fromJson(res);
  }

  Future<List<FeedPost>> personPosts(
    String personId, {
    int limit = 20,
    DateTime? before,
  }) async {
    final res = await _db.rpc('omelo_person_posts', params: {
      'p_person': personId,
      'p_limit': limit,
      'p_before': before?.toUtc().toIso8601String(),
    });
    return parsePosts(res);
  }

  Future<OrganizationFeed?> organizationFeed(
    String companyId, {
    int limit = 20,
    DateTime? before,
  }) async {
    final res = await _db.rpc('omelo_organization_feed', params: {
      'p_company': companyId,
      'p_limit': limit,
      'p_before': before?.toUtc().toIso8601String(),
    });
    return OrganizationFeed.fromJson(res);
  }

  /// Published jobs the worker can see, for the composer's job picker.
  ///
  /// Read straight off `jobs` through RLS, which already limits this to
  /// what is public. An empty query lists the newest; two letters or more
  /// searches by title.
  Future<List<PostJob>> jobsToShare({String? query, int limit = 20}) async {
    const columns =
        'id, title, location_text, country_code, workplace_type, work_type, '
        'status, pay_min, pay_max, pay_period, pay_currency, pay_disclosed, '
        'published_at, companies ( display_name )';
    final q = (query ?? '').trim();
    var sel = _db.from('jobs').select(columns).eq('status', 'published');
    if (q.length >= 2) {
      sel = sel.ilike('title', '%${q.replaceAll(_escapes, ' ')}%');
    }
    final rows = await sel.order('published_at', ascending: false).limit(limit);
    return (rows as List)
        .map((r) => PostJob.fromRow(Map<String, dynamic>.from(r as Map)))
        .whereType<PostJob>()
        .toList();
  }

  // -- Writing -----------------------------------------------------------------

  Future<FeedPost?> createPost(PostDraft d) async {
    final res = await _db.rpc('omelo_create_post', params: {'p': d.toPayload()});
    return FeedPost.fromJson(res);
  }

  Future<FeedPost?> updatePost(String postId, PostDraft d) async {
    final res = await _db.rpc('omelo_update_post', params: {
      'p_post': postId,
      'p': d.toEditPayload(),
    });
    return FeedPost.fromJson(res);
  }

  Future<void> deletePost(String postId) =>
      _db.rpc('omelo_delete_post', params: {'p_post': postId});

  Future<FeedPost?> sharePost(
    String postId, {
    String? body,
    PostVisibility visibility = PostVisibility.public,
  }) async {
    final res = await _db.rpc('omelo_share_post', params: {
      'p_post': postId,
      'p_body': (body ?? '').trim().isEmpty ? null : body!.trim(),
      'p_visibility': visibility.wire,
    });
    return FeedPost.fromJson(res);
  }

  // -- Engagement --------------------------------------------------------------

  /// Null removes whatever reaction was there.
  Future<void> react(String postId, ReactionKind? kind) => _db.rpc(
        'omelo_react_to_post',
        params: {'p_post': postId, 'p_kind': kind?.wire},
      );

  Future<void> savePost(String postId, bool save) => _db.rpc(
        'omelo_save_post',
        params: {'p_post': postId, 'p_save': save},
      );

  Future<List<PostCommentItem>> comments(
    String postId, {
    int limit = 30,
    DateTime? after,
  }) async {
    final res = await _db.rpc('omelo_post_comments', params: {
      'p_post': postId,
      'p_limit': limit,
      'p_after': after?.toUtc().toIso8601String(),
    });
    return parseComments(res);
  }

  Future<void> comment(String postId, String body, {String? parentId}) =>
      _db.rpc('omelo_comment_on_post', params: {
        'p_post': postId,
        'p_body': body.trim(),
        'p_parent': ?parentId,
      });

  /// React to a comment, or clear my reaction when [kind] is null.
  ///
  /// There is no RPC for this one: `comment_reactions` is an ordinary table
  /// with a policy that already limits it to my own row on a comment I can
  /// see. The count on the comment is kept by a trigger, so the app shows
  /// what it knows until the next reload.
  Future<void> reactToComment(String commentId, ReactionKind? kind) async {
    final me = myId;
    if (me == null) throw const AuthException('Sign in first');
    if (kind == null) {
      await _db
          .from('comment_reactions')
          .delete()
          .eq('comment_id', commentId)
          .eq('person_id', me);
      return;
    }
    await _db.from('comment_reactions').upsert({
      'comment_id': commentId,
      'person_id': me,
      'kind': kind.wire,
    }, onConflict: 'comment_id,person_id');
  }

  Future<void> deleteComment(String commentId) =>
      _db.rpc('omelo_delete_comment', params: {'p_comment': commentId});

  // -- People ------------------------------------------------------------------

  Future<void> follow(AuthorType type, String id, bool follow) =>
      _db.rpc('omelo_follow', params: {
        'p_target_type': followTargetWire(type),
        'p_target_id': id,
        'p_follow': follow,
      });

  Future<void> requestConnection(String personId, {String? message}) =>
      _db.rpc('omelo_request_connection', params: {
        'p_person': personId,
        'p_message':
            (message ?? '').trim().isEmpty ? null : message!.trim(),
      });

  Future<void> respondConnection(String connectionId, bool accept) =>
      _db.rpc('omelo_respond_connection', params: {
        'p_connection': connectionId,
        'p_accept': accept,
      });

  /// Also withdraws a request I sent that is still waiting.
  Future<void> removeConnection(String personId) =>
      _db.rpc('omelo_remove_connection', params: {'p_person': personId});

  Future<List<NetworkEntry>> myNetwork(NetworkView view) async {
    final res = await _db.rpc('omelo_my_network', params: {'p_view': view.wire});
    return parseNetwork(res, view);
  }

  Future<List<NetworkEntry>> suggestions({int limit = 10}) async {
    final res =
        await _db.rpc('omelo_connection_suggestions', params: {'p_limit': limit});
    return parseSuggestions(res);
  }

  // -- Preferences, muting, blocking, reporting --------------------------------

  Future<FeedPreferences> saveFeedPreferences(FeedPreferences p) async {
    final res = await _db
        .rpc('omelo_save_feed_preferences', params: {'p': p.toPayload()});
    return FeedPreferences.fromJson(res);
  }

  Future<void> mute(MuteTarget target, String id, {bool mute = true}) =>
      _db.rpc('omelo_mute_from_feed', params: {
        'p_target_type': target.wire,
        'p_target_id': id,
        'p_mute': mute,
      });

  /// Blocking is an ordinary row in `blocks`, through RLS.
  Future<void> block(BlockTarget target, String id, {String? reason}) async {
    final me = myId;
    if (me == null) throw const AuthException('Sign in first');
    await _db.from('blocks').insert({
      'person_id': me,
      'target_type': target.wire,
      'target_id': id,
      'reason': (reason ?? '').trim().isEmpty ? null : reason!.trim(),
    });
  }

  /// Reporting is an ordinary row in `reports`, through RLS. Trust & safety
  /// read it; the worker only has to say what is wrong.
  Future<void> report({
    required ReportSubject subject,
    required String subjectId,
    required ReportReason reason,
    String? details,
  }) async {
    final me = myId;
    if (me == null) throw const AuthException('Sign in first');
    await _db.from('reports').insert({
      'reporter_id': me,
      'subject_type': subject.wire,
      'subject_id': subjectId,
      'reason': reason.wire,
      'details': (details ?? '').trim().isEmpty ? null : details!.trim(),
    });
  }

  // -- Media -------------------------------------------------------------------

  /// The public URL for a storage path the server sent back.
  String mediaUrl(String storagePath) =>
      _db.storage.from(kPostMediaBucket).getPublicUrl(storagePath);

  /// Uploads one photo or video into my own folder and returns what to send
  /// with the post.
  ///
  /// The path always starts with my person id, because that is the only
  /// place the storage policy lets me write. Building it here rather than
  /// trusting a caller keeps that rule in one place.
  Future<UploadedMedia> uploadMedia(PickedMedia m, {int index = 0}) async {
    final me = myId;
    if (me == null) throw const AuthException('Sign in first');
    if (!kPostMediaMimeTypes.contains(m.mimeType)) {
      throw StorageException(
        'Omelo takes JPG, PNG, WebP or GIF photos and MP4 or WebM video.',
      );
    }
    if (m.sizeBytes > kPostMediaMaxBytes) {
      throw StorageException('That file is larger than 50 MB.');
    }
    final path = mediaPath(me, index: index, extension: m.extension);
    await _db.storage.from(kPostMediaBucket).uploadBinary(
          path,
          m.bytes,
          fileOptions: FileOptions(contentType: m.mimeType, upsert: false),
        );
    return UploadedMedia(
      storagePath: path,
      kind: m.isVideo ? MediaKind.video : MediaKind.image,
      mimeType: m.mimeType,
      width: m.width,
      height: m.height,
      durationSeconds: m.durationSeconds,
      altText: m.altText,
    );
  }

  /// `<my person id>/<time>-<n>.<ext>` — the only shape the bucket policy
  /// accepts from me.
  static String mediaPath(
    String personId, {
    required int index,
    required String extension,
    DateTime? now,
  }) {
    final stamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return '$personId/$stamp-$index.$extension';
  }
}

/// A server refusal in its own words, with database codes turned into plain
/// ones. The server's message is kept whenever it has one, because it is
/// written for the worker ("Replies go one level deep").
String networkError(Object e) {
  if (e is PostgrestException) {
    switch (e.code) {
      case '23505':
        return 'You already did that.';
      case '23514':
        return 'Check what you wrote and try again.';
      case '42501':
        if (e.message.trim().isEmpty) return 'You cannot do that.';
    }
    if (e.message.trim().isNotEmpty) return e.message.trim();
  }
  if (e is StorageException && e.message.trim().isNotEmpty) {
    return e.message.trim();
  }
  if (e is AuthException && e.message.trim().isNotEmpty) return e.message.trim();
  return 'Could not reach Omelo. Check your internet and try again.';
}

/// True when the worker has to sign in before this makes sense.
bool needsSignIn(Object e) =>
    (e is PostgrestException && e.message.contains('Sign in first')) ||
    e is AuthException;

// -- Providers -------------------------------------------------------------------

/// Now, so tests can fix it. Post times are relative ("3h"), which is
/// untestable against a moving clock.
final networkClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Turns a storage path into something an `Image.network` can load.
/// Overridden in tests so no widget reaches the network.
final mediaUrlProvider = Provider<String Function(String)>(
  (ref) => ref.watch(networkRepositoryProvider).mediaUrl,
);

final myNetworkProvider = FutureProvider.autoDispose
    .family<List<NetworkEntry>, NetworkView>((ref, view) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(networkRepositoryProvider).myNetwork(view);
});

final connectionSuggestionsProvider =
    FutureProvider.autoDispose<List<NetworkEntry>>((ref) async {
  if (!ref.watch(isSignedInProvider)) return const [];
  return ref.watch(networkRepositoryProvider).suggestions();
});

/// How many connection invitations are waiting, for the badge on Profile.
final pendingInvitationsCountProvider = Provider.autoDispose<int>((ref) {
  return ref
          .watch(myNetworkProvider(NetworkView.invitations))
          .valueOrNull
          ?.length ??
      0;
});

final organizationFeedProvider = FutureProvider.autoDispose
    .family<OrganizationFeed?, String>(
  (ref, id) => ref.watch(networkRepositoryProvider).organizationFeed(id),
);

final personPostsProvider = FutureProvider.autoDispose
    .family<List<FeedPost>, String>(
  (ref, id) => ref.watch(networkRepositoryProvider).personPosts(id),
);

final postDetailProvider =
    FutureProvider.autoDispose.family<FeedPost?, String>(
  (ref, id) => ref.watch(networkRepositoryProvider).postDetail(id),
);

/// Reload everything network after a change (a post written, a connection
/// accepted, someone followed).
void invalidateNetwork(WidgetRef ref) {
  ref.invalidate(myNetworkProvider);
  ref.invalidate(connectionSuggestionsProvider);
  ref.invalidate(organizationFeedProvider);
  ref.invalidate(personPostsProvider);
  ref.invalidate(postDetailProvider);
}
