/// Release 9 — the professional network, from the worker's side.
///
/// A feed of posts, the people and organizations behind them, connections,
/// follows, comments and reactions.
///
/// Rules that shape this file:
///  * The server owns the ranking. Every card carries the server's own `why`
///    line ("From a connection", "A job in your profession"); the app shows
///    it and never invents one.
///  * A job attached to a post keeps its own currency and its own pay
///    period. Money is never a bare number (A1 §1).
///  * Pagination is whatever the server sent back: an offset for the ranked
///    "For you" tab, a timestamp for the chronological ones. The app never
///    guesses the next page.
///  * Media comes back as a storage path, not a URL. Building the public URL
///    is the repository's job, so nothing here knows about Supabase.
///  * A post may be missing its author (deleted person, removed company),
///    and a feed row that cannot be read is dropped rather than shown half
///    built.
///
/// Everything here is pure (no Supabase, no widgets) so it can be tested.
library;

import 'package:intl/intl.dart';

import 'global.dart' show payRangeLine;

Map<String, dynamic>? _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.map(_map).whereType<Map<String, dynamic>>().toList()
    : const [];

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

num? _num(dynamic v) =>
    v == null ? null : (v is num ? v : num.tryParse(v.toString()));

int? _int(dynamic v) => _num(v)?.round();

int _count(dynamic v) {
  final n = _int(v) ?? 0;
  return n < 0 ? 0 : n;
}

bool _bool(dynamic v) => v == true || v?.toString() == 'true';

List<String> _strings(dynamic v) {
  if (v is! List) return const [];
  return v.map(_str).whereType<String>().toList();
}

/// Timestamps come back as UTC and are shown in the phone's own time.
DateTime? _date(dynamic v) {
  final s = _str(v);
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return s.length <= 10 ? d : d.toLocal();
}

final _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

bool isNetworkId(String? s) => s != null && _uuid.hasMatch(s);

// ---------------------------------------------------------------------------
// Words
// ---------------------------------------------------------------------------

/// How long a post may be, enforced by the database too.
const kPostBodyMax = 3000;

/// How long a comment may be, enforced by the database too.
const kCommentBodyMax = 2000;

/// How long a connection request note may be.
const kConnectionNoteMax = 300;

/// Lines of body text shown before "See more".
const kPostBodyLines = 6;

/// "Just now" · "5m" · "3h" · "2d" · "12 Sep" · "12 Sep 2025"
String postTime(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inSeconds < 60) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 7) return '${d.inDays}d';
  if (d.inDays < 28) return '${(d.inDays / 7).floor()}w';
  if (at.year == now.year) return DateFormat('d MMM').format(at);
  return DateFormat('d MMM yyyy').format(at);
}

/// "12 reactions" · "1 reaction" · null when there are none.
String? countWords(int n, String one, String many) {
  if (n <= 0) return null;
  return '$n ${n == 1 ? one : many}';
}

/// What the worker typed is allowed, or a reason it is not.
///
/// A post needs text unless it carries media, a job or a shared post —
/// the same rule the database enforces.
String? validatePostBody(
  String body, {
  bool hasMedia = false,
  bool hasJob = false,
  bool hasSharedPost = false,
}) {
  final t = body.trim();
  if (t.isEmpty && !hasMedia && !hasJob && !hasSharedPost) {
    return 'Write something, or add a photo, a video or a job.';
  }
  if (body.runes.length > kPostBodyMax) {
    return 'That is longer than $kPostBodyMax characters.';
  }
  return null;
}

String? validateComment(String body) {
  final t = body.trim();
  if (t.isEmpty) return 'Write your comment first.';
  if (body.runes.length > kCommentBodyMax) {
    return 'A comment is at most $kCommentBodyMax characters.';
  }
  return null;
}

/// How many characters are left, as the counter shows it.
int charactersLeft(String body, int max) => max - body.runes.length;

// ---------------------------------------------------------------------------
// Who wrote it
// ---------------------------------------------------------------------------

enum AuthorType { person, organization }

/// A person or an organization as it appears on a post, a comment or a
/// network list. Nothing beyond name, photo and one line travels with it.
class PostAuthor {
  const PostAuthor({
    required this.type,
    required this.id,
    required this.name,
    this.avatarUrl,
    this.headline,
    this.slug,
    this.verified = false,
    this.organizationType,
  });

  final AuthorType type;
  final String id;
  final String name;
  final String? avatarUrl;

  /// A person's headline ("Industrial electrician, Pune"). Organizations
  /// have none.
  final String? headline;
  final String? slug;
  final bool verified;
  final String? organizationType;

  bool get isOrganization => type == AuthorType.organization;

  /// First letter for the fallback avatar. Counted in runes, so a name
  /// starting with an emoji or a Devanagari letter is not cut in half.
  String get initial {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return String.fromCharCode(t.runes.first).toUpperCase();
  }

  /// Where tapping this name goes.
  String get route =>
      isOrganization ? '/organizations/$id' : '/people/$id';

  static PostAuthor? fromJson(dynamic v) {
    final m = _map(v);
    final id = _str(m?['id']);
    if (m == null || id == null) return null;
    return PostAuthor(
      type: _str(m['type']) == 'organization'
          ? AuthorType.organization
          : AuthorType.person,
      id: id,
      name: _str(m['name']) ?? 'Someone on Omelo',
      avatarUrl: _str(m['avatar_url']),
      headline: _str(m['headline']),
      slug: _str(m['slug']),
      verified: _bool(m['verified']),
      organizationType: _str(m['organization_type']),
    );
  }
}

// ---------------------------------------------------------------------------
// Media
// ---------------------------------------------------------------------------

enum MediaKind { image, video }

/// One photo or video on a post. [path] is the object's path inside the
/// `post-media` bucket, not a URL: the repository turns it into one.
class PostMedia {
  const PostMedia({
    required this.kind,
    required this.path,
    this.altText,
    this.width,
    this.height,
    this.durationSeconds,
  });

  final MediaKind kind;
  final String path;
  final String? altText;
  final int? width;
  final int? height;
  final int? durationSeconds;

  bool get isVideo => kind == MediaKind.video;

  /// Width ÷ height when the server knows both, else a safe 4:3.
  double get aspectRatio {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return 4 / 3;
    return w / h;
  }

  /// "0:45" · "2:05" · null when the length is unknown.
  String? get durationLabel {
    final s = durationSeconds;
    if (s == null || s <= 0) return null;
    final m = s ~/ 60;
    return '$m:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// What a screen reader says. Falls back to the kind so a photo without
  /// alt text is still announced as a photo.
  String get semanticLabel =>
      altText ?? (isVideo ? 'Video on this post' : 'Photo on this post');

  static PostMedia? fromJson(dynamic v) {
    final m = _map(v);
    final path = _str(m?['url']) ?? _str(m?['storage_path']);
    if (m == null || path == null) return null;
    return PostMedia(
      kind: _str(m['kind']) == 'video' ? MediaKind.video : MediaKind.image,
      path: path,
      altText: _str(m['alt_text']),
      width: _int(m['width']),
      height: _int(m['height']),
      durationSeconds: _int(m['duration_seconds']),
    );
  }
}

List<PostMedia> parseMedia(dynamic v) =>
    _maps(v).map(PostMedia.fromJson).whereType<PostMedia>().toList();

// ---------------------------------------------------------------------------
// A job carried by a post
// ---------------------------------------------------------------------------

/// The job card inside a post. Pay stays in the job's own currency and
/// period — never converted, never flattened to a monthly figure.
class PostJob {
  const PostJob({
    required this.id,
    required this.title,
    this.company,
    this.locationText,
    this.country,
    this.workplaceType,
    this.workType,
    this.status,
    this.payMin,
    this.payMax,
    this.payPeriod,
    this.payCurrency,
  });

  final String id;
  final String title;
  final String? company;
  final String? locationText;
  final String? country;
  final String? workplaceType;
  final String? workType;
  final String? status;
  final num? payMin;
  final num? payMax;
  final String? payPeriod;
  final String? payCurrency;

  /// True once the employer closed it: the card says so instead of
  /// inviting a wasted application.
  bool get isOpen => status == null || status == 'published';

  /// "₹18,000 – ₹28,000 per month", in the job's own currency, or
  /// "Pay not shown".
  String get payLine {
    final cur = payCurrency;
    if (cur == null || (payMin == null && payMax == null)) {
      return 'Pay not shown';
    }
    return payRangeLine(payMin, payMax, cur, payPeriod);
  }

  /// "Pune, India" — whatever of the two the server knows.
  String get placeLine => [
        if (locationText != null) locationText!,
        if (country != null) country!,
      ].join(' · ');

  /// A row straight from `jobs`, for the picker that attaches a job to a
  /// post. `pay_disclosed = false` means the employer chose not to show pay,
  /// so none is carried.
  static PostJob? fromRow(Map<String, dynamic> m) {
    final id = _str(m['id']);
    if (id == null) return null;
    final shown = m['pay_disclosed'] != false;
    final company = _map(m['companies']);
    return PostJob(
      id: id,
      title: _str(m['title']) ?? 'Job',
      company: _str(company?['display_name']),
      locationText: _str(m['location_text']),
      country: _str(m['country_code'])?.toUpperCase(),
      workplaceType: _str(m['workplace_type']),
      workType: _str(m['work_type']),
      status: _str(m['status']),
      payMin: shown ? _num(m['pay_min']) : null,
      payMax: shown ? _num(m['pay_max']) : null,
      payPeriod: shown ? _str(m['pay_period']) : null,
      payCurrency: shown ? _str(m['pay_currency'])?.toUpperCase() : null,
    );
  }

  static PostJob? fromJson(dynamic v) {
    final m = _map(v);
    final id = _str(m?['id']);
    if (m == null || id == null) return null;
    final pay = _map(m['pay']);
    return PostJob(
      id: id,
      title: _str(m['title']) ?? 'Job',
      company: _str(m['company']),
      locationText: _str(m['location_text']),
      country: _str(m['country'])?.toUpperCase(),
      workplaceType: _str(m['workplace_type']),
      workType: _str(m['work_type']),
      status: _str(m['status']),
      payMin: _num(pay?['min']),
      payMax: _num(pay?['max']),
      payPeriod: _str(pay?['period']),
      payCurrency: _str(pay?['currency'])?.toUpperCase(),
    );
  }
}

// ---------------------------------------------------------------------------
// A quoted post
// ---------------------------------------------------------------------------

/// The original post inside a share. One level only: the server refuses to
/// share a share.
class QuotedPost {
  const QuotedPost({
    required this.id,
    this.body,
    this.createdAt,
    this.author,
    this.media = const [],
  });

  final String id;
  final String? body;
  final DateTime? createdAt;
  final PostAuthor? author;
  final List<PostMedia> media;

  static QuotedPost? fromJson(dynamic v) {
    final m = _map(v);
    final id = _str(m?['id']);
    if (m == null || id == null) return null;
    return QuotedPost(
      id: id,
      body: _str(m['body']),
      createdAt: _date(m['created_at']),
      author: PostAuthor.fromJson(m['author']),
      media: parseMedia(m['media']),
    );
  }
}

// ---------------------------------------------------------------------------
// Reactions
// ---------------------------------------------------------------------------

enum ReactionKind { like, celebrate, support, insightful, curious }

extension ReactionKindX on ReactionKind {
  String get wire => switch (this) {
        ReactionKind.like => 'like',
        ReactionKind.celebrate => 'celebrate',
        ReactionKind.support => 'support',
        ReactionKind.insightful => 'insightful',
        ReactionKind.curious => 'curious',
      };

  String get label => switch (this) {
        ReactionKind.like => 'Like',
        ReactionKind.celebrate => 'Celebrate',
        ReactionKind.support => 'Support',
        ReactionKind.insightful => 'Insightful',
        ReactionKind.curious => 'Curious',
      };

  /// What the button says once it is chosen: "Liked", "Celebrated".
  String get chosenLabel => switch (this) {
        ReactionKind.like => 'Liked',
        ReactionKind.celebrate => 'Celebrated',
        ReactionKind.support => 'Supported',
        ReactionKind.insightful => 'Insightful',
        ReactionKind.curious => 'Curious',
      };

  static ReactionKind? fromWire(String? w) {
    if (w == null) return null;
    for (final k in ReactionKind.values) {
      if (k.wire == w) return k;
    }
    return null;
  }
}

ReactionKind? reactionFromWire(String? w) => ReactionKindX.fromWire(w);

/// Tapping the reaction already chosen removes it; tapping another replaces
/// it. Null means "no reaction", which the server takes as remove.
ReactionKind? toggledReaction(ReactionKind? current, ReactionKind tapped) =>
    current == tapped ? null : tapped;

/// The count after a reaction changed, so the card can update without a
/// refetch. Never goes below zero.
int reactionCountAfter(int before, ReactionKind? was, ReactionKind? now) {
  if (was == null && now != null) return before + 1;
  if (was != null && now == null) return before < 1 ? 0 : before - 1;
  return before < 0 ? 0 : before;
}

// ---------------------------------------------------------------------------
// Visibility
// ---------------------------------------------------------------------------

enum PostVisibility { public, followers, connections }

extension PostVisibilityX on PostVisibility {
  String get wire => switch (this) {
        PostVisibility.public => 'public',
        PostVisibility.followers => 'followers',
        PostVisibility.connections => 'connections',
      };

  String get label => switch (this) {
        PostVisibility.public => 'Public',
        PostVisibility.followers => 'Followers',
        PostVisibility.connections => 'Connections',
      };

  /// Said plainly, because this decides who can read it.
  String get description => switch (this) {
        PostVisibility.public => 'Anyone on Omelo can see this, and it can be '
            'shared on.',
        PostVisibility.followers =>
          'Only people who follow you can see this.',
        PostVisibility.connections =>
          'Only people you are connected with can see this.',
      };

  static PostVisibility fromWire(String? w) => switch (w) {
        'followers' => PostVisibility.followers,
        'connections' => PostVisibility.connections,
        // 'organization' only happens on a post written by an organization,
        // which a worker never writes. It reads as public here.
        _ => PostVisibility.public,
      };
}

PostVisibility visibilityFromWire(String? w) => PostVisibilityX.fromWire(w);

// ---------------------------------------------------------------------------
// The post card
// ---------------------------------------------------------------------------

class PostEngagement {
  const PostEngagement({
    this.reactions = 0,
    this.comments = 0,
    this.shares = 0,
    this.saves = 0,
  });

  final int reactions;
  final int comments;
  final int shares;
  final int saves;

  PostEngagement copyWith({int? reactions, int? comments, int? shares, int? saves}) =>
      PostEngagement(
        reactions: reactions ?? this.reactions,
        comments: comments ?? this.comments,
        shares: shares ?? this.shares,
        saves: saves ?? this.saves,
      );

  static PostEngagement fromJson(dynamic v) {
    final m = _map(v);
    if (m == null) return const PostEngagement();
    return PostEngagement(
      reactions: _count(m['reactions']),
      comments: _count(m['comments']),
      shares: _count(m['shares']),
      saves: _count(m['saves']),
    );
  }
}

/// What I did with this post.
class MyPostState {
  const MyPostState({this.reaction, this.saved = false, this.mine = false});

  final ReactionKind? reaction;
  final bool saved;

  /// True when I wrote it, or when I may act for the organization that did.
  final bool mine;

  MyPostState copyWith({
    ReactionKind? reaction,
    bool clearReaction = false,
    bool? saved,
    bool? mine,
  }) =>
      MyPostState(
        reaction: clearReaction ? null : (reaction ?? this.reaction),
        saved: saved ?? this.saved,
        mine: mine ?? this.mine,
      );

  static MyPostState fromJson(dynamic v) {
    final m = _map(v);
    if (m == null) return const MyPostState();
    return MyPostState(
      reaction: reactionFromWire(_str(m['reaction'])),
      saved: _bool(m['saved']),
      mine: _bool(m['mine']),
    );
  }
}

/// One card in the feed.
class FeedPost {
  const FeedPost({
    required this.id,
    required this.createdAt,
    this.kind,
    this.body,
    this.visibility = PostVisibility.public,
    this.editedAt,
    this.author,
    this.media = const [],
    this.job,
    this.quoted,
    this.engagement = const PostEngagement(),
    this.my = const MyPostState(),
    this.why,
    this.score,
  });

  final String id;
  final String? kind;
  final String? body;
  final PostVisibility visibility;
  final DateTime createdAt;
  final DateTime? editedAt;
  final PostAuthor? author;
  final List<PostMedia> media;
  final PostJob? job;
  final QuotedPost? quoted;
  final PostEngagement engagement;
  final MyPostState my;

  /// The server's own explanation of why this is here. Shown as sent.
  final String? why;
  final num? score;

  bool get isEdited => editedAt != null;
  bool get hasBody => (body ?? '').trim().isNotEmpty;

  /// Only my own posts can be edited from the worker app; an organization's
  /// post is edited from the employer portal.
  bool get canEdit => my.mine && author?.type == AuthorType.person;

  /// A share of someone else's post: the quote is the point, so the card
  /// shows the quoted post even when the sharer wrote nothing.
  bool get isShare => quoted != null;

  FeedPost copyWith({
    String? body,
    PostVisibility? visibility,
    DateTime? editedAt,
    PostEngagement? engagement,
    MyPostState? my,
  }) =>
      FeedPost(
        id: id,
        kind: kind,
        body: body ?? this.body,
        visibility: visibility ?? this.visibility,
        createdAt: createdAt,
        editedAt: editedAt ?? this.editedAt,
        author: author,
        media: media,
        job: job,
        quoted: quoted,
        engagement: engagement ?? this.engagement,
        my: my ?? this.my,
        why: why,
        score: score,
      );

  static FeedPost? fromJson(dynamic v) {
    final m = _map(v);
    final id = _str(m?['id']);
    final at = _date(m?['created_at']);
    if (m == null || id == null || at == null) return null;
    return FeedPost(
      id: id,
      kind: _str(m['kind']),
      body: _str(m['body']),
      visibility: visibilityFromWire(_str(m['visibility'])),
      createdAt: at,
      editedAt: _date(m['edited_at']),
      author: PostAuthor.fromJson(m['author']),
      media: parseMedia(m['media']),
      job: PostJob.fromJson(m['job']),
      quoted: QuotedPost.fromJson(m['shared_post']),
      engagement: PostEngagement.fromJson(m['engagement']),
      my: MyPostState.fromJson(m['my']),
      why: _str(m['why']),
      score: _num(m['score']),
    );
  }
}

List<FeedPost> parsePosts(dynamic v) =>
    _maps(v).map(FeedPost.fromJson).whereType<FeedPost>().toList();

// ---------------------------------------------------------------------------
// The feed
// ---------------------------------------------------------------------------

enum FeedTab { forYou, following, organizations, jobs, saved }

extension FeedTabX on FeedTab {
  String get wire => switch (this) {
        FeedTab.forYou => 'for_you',
        FeedTab.following => 'following',
        FeedTab.organizations => 'organizations',
        FeedTab.jobs => 'jobs',
        FeedTab.saved => 'saved',
      };

  String get label => switch (this) {
        FeedTab.forYou => 'For you',
        FeedTab.following => 'Following',
        FeedTab.organizations => 'Organizations',
        FeedTab.jobs => 'Jobs',
        FeedTab.saved => 'Saved',
      };

  /// "For you" is ranked, so it pages by offset. The rest are newest-first,
  /// so they page by the oldest timestamp on screen.
  bool get pagesByOffset => this == FeedTab.forYou;

  String get emptyTitle => switch (this) {
        FeedTab.forYou => 'Nothing here yet',
        FeedTab.following => 'You are not following anyone yet',
        FeedTab.organizations => 'No organization posts yet',
        FeedTab.jobs => 'No job posts yet',
        FeedTab.saved => 'Nothing saved yet',
      };

  String get emptyBody => switch (this) {
        FeedTab.forYou =>
          'Follow a few people and organizations, and connect with people '
              'you have worked with. Their updates will show up here.',
        FeedTab.following =>
          'Follow people and organizations whose work you want to keep up '
              'with.',
        FeedTab.organizations =>
          'Follow the organizations you would work for and their updates '
              'land here.',
        FeedTab.jobs =>
          'When someone shares a job you can see, it shows up here.',
        FeedTab.saved => 'Save a post and it waits for you here.',
      };

  static FeedTab fromWire(String? w) {
    for (final t in FeedTab.values) {
      if (t.wire == w) return t;
    }
    return FeedTab.forYou;
  }
}

FeedTab feedTabFromWire(String? w) => FeedTabX.fromWire(w);

/// What the worker chose to see in the feed.
class FeedPreferences {
  const FeedPreferences({
    this.showJobs = true,
    this.showOrganizations = true,
    this.showCareerContent = true,
    this.showNetworkActivity = true,
    this.preferredLanguages = const [],
  });

  final bool showJobs;
  final bool showOrganizations;
  final bool showCareerContent;
  final bool showNetworkActivity;
  final List<String> preferredLanguages;

  FeedPreferences copyWith({
    bool? showJobs,
    bool? showOrganizations,
    bool? showCareerContent,
    bool? showNetworkActivity,
    List<String>? preferredLanguages,
  }) =>
      FeedPreferences(
        showJobs: showJobs ?? this.showJobs,
        showOrganizations: showOrganizations ?? this.showOrganizations,
        showCareerContent: showCareerContent ?? this.showCareerContent,
        showNetworkActivity: showNetworkActivity ?? this.showNetworkActivity,
        preferredLanguages: preferredLanguages ?? this.preferredLanguages,
      );

  Map<String, dynamic> toPayload() => {
        'show_jobs': showJobs,
        'show_organizations': showOrganizations,
        'show_career_content': showCareerContent,
        'show_network_activity': showNetworkActivity,
        'preferred_languages': preferredLanguages,
      };

  /// A missing row means everything is on, which is what the server does.
  static FeedPreferences fromJson(dynamic v) {
    final m = _map(v);
    if (m == null) return const FeedPreferences();
    bool on(String key) => m[key] == null ? true : _bool(m[key]);
    return FeedPreferences(
      showJobs: on('show_jobs'),
      showOrganizations: on('show_organizations'),
      showCareerContent: on('show_career_content'),
      showNetworkActivity: on('show_network_activity'),
      preferredLanguages: _strings(m['preferred_languages']),
    );
  }
}

/// One page of the feed, plus how to ask for the next one.
class FeedPage {
  const FeedPage({
    required this.tab,
    this.posts = const [],
    this.nextBefore,
    this.nextOffset,
    this.preferences = const FeedPreferences(),
    this.ranking,
  });

  final FeedTab tab;
  final List<FeedPost> posts;

  /// Chronological tabs: ask for posts written before this.
  final DateTime? nextBefore;

  /// The ranked tab: ask for this offset next.
  final int? nextOffset;

  final FeedPreferences preferences;

  /// The server's plain-words explanation of how "For you" is ordered.
  final String? ranking;

  /// A short page means the end: nothing more to ask for.
  bool hasMore(int requested) => posts.length >= requested;

  static FeedPage fromJson(dynamic v, {FeedTab? fallbackTab}) {
    final m = _map(v);
    if (m == null) {
      return FeedPage(tab: fallbackTab ?? FeedTab.forYou);
    }
    return FeedPage(
      tab: m['tab'] == null
          ? (fallbackTab ?? FeedTab.forYou)
          : feedTabFromWire(_str(m['tab'])),
      posts: parsePosts(m['posts']),
      // The server sends `next_before` as UTC; it is sent straight back.
      nextBefore: _date(m['next_before'])?.toUtc(),
      nextOffset: _int(m['next_offset']),
      preferences: FeedPreferences.fromJson(m['preferences']),
      ranking: _str(m['ranking']),
    );
  }
}

// ---------------------------------------------------------------------------
// Comments
// ---------------------------------------------------------------------------

/// A reply. Threads go one level deep, so a reply has no replies of its own.
class CommentReply {
  const CommentReply({
    required this.id,
    required this.body,
    required this.createdAt,
    this.author,
    this.reactions = 0,
    this.mine = false,
  });

  final String id;
  final String body;
  final DateTime createdAt;
  final PostAuthor? author;
  final int reactions;
  final bool mine;

  static CommentReply? fromJson(dynamic v) {
    final m = _map(v);
    final id = _str(m?['id']);
    final at = _date(m?['created_at']);
    if (m == null || id == null || at == null) return null;
    return CommentReply(
      id: id,
      body: _str(m['body']) ?? '',
      createdAt: at,
      author: PostAuthor.fromJson(m['author']),
      reactions: _count(m['reactions']),
      mine: _bool(m['mine']),
    );
  }
}

class PostCommentItem {
  const PostCommentItem({
    required this.id,
    required this.body,
    required this.createdAt,
    this.editedAt,
    this.author,
    this.reactions = 0,
    this.replyCount = 0,
    this.mine = false,
    this.myReaction,
    this.thread = const [],
  });

  final String id;
  final String body;
  final DateTime createdAt;
  final DateTime? editedAt;
  final PostAuthor? author;
  final int reactions;

  /// What the server counted, which can run ahead of [thread] when a reply
  /// was deleted.
  final int replyCount;
  final bool mine;
  final ReactionKind? myReaction;
  final List<CommentReply> thread;

  static PostCommentItem? fromJson(dynamic v) {
    final m = _map(v);
    final id = _str(m?['id']);
    final at = _date(m?['created_at']);
    if (m == null || id == null || at == null) return null;
    return PostCommentItem(
      id: id,
      body: _str(m['body']) ?? '',
      createdAt: at,
      editedAt: _date(m['edited_at']),
      author: PostAuthor.fromJson(m['author']),
      reactions: _count(m['reactions']),
      replyCount: _count(m['replies']),
      mine: _bool(m['mine']),
      myReaction: reactionFromWire(_str(m['my_reaction'])),
      thread: _maps(m['thread'])
          .map(CommentReply.fromJson)
          .whereType<CommentReply>()
          .toList(),
    );
  }
}

List<PostCommentItem> parseComments(dynamic v) => _maps(v)
    .map(PostCommentItem.fromJson)
    .whereType<PostCommentItem>()
    .toList();

/// A comment can be removed by whoever wrote it, and by the author of the
/// post it sits on.
bool canDeleteComment({required bool mine, required bool iOwnThePost}) =>
    mine || iOwnThePost;

// ---------------------------------------------------------------------------
// My network
// ---------------------------------------------------------------------------

enum NetworkView { connections, invitations, sent, followers, following }

extension NetworkViewX on NetworkView {
  String get wire => switch (this) {
        NetworkView.connections => 'connections',
        NetworkView.invitations => 'invitations',
        NetworkView.sent => 'sent',
        NetworkView.followers => 'followers',
        NetworkView.following => 'following',
      };

  String get label => switch (this) {
        NetworkView.connections => 'Connections',
        NetworkView.invitations => 'Invitations',
        NetworkView.sent => 'Sent',
        NetworkView.followers => 'Followers',
        NetworkView.following => 'Following',
      };

  String get emptyTitle => switch (this) {
        NetworkView.connections => 'No connections yet',
        NetworkView.invitations => 'No invitations waiting',
        NetworkView.sent => 'No requests waiting',
        NetworkView.followers => 'No followers yet',
        NetworkView.following => 'You are not following anyone yet',
      };

  String get emptyBody => switch (this) {
        NetworkView.connections =>
          'Connect with people you have worked with. They see your updates '
              'and you see theirs.',
        NetworkView.invitations =>
          'When someone asks to connect, their request waits here.',
        NetworkView.sent => 'Requests you send wait here until they answer.',
        NetworkView.followers =>
          'People who follow you see your public posts.',
        NetworkView.following =>
          'Follow people and organizations to see their updates.',
      };

  static NetworkView fromWire(String? w) {
    for (final v in NetworkView.values) {
      if (v.wire == w) return v;
    }
    return NetworkView.connections;
  }
}

NetworkView networkViewFromWire(String? w) => NetworkViewX.fromWire(w);

/// One row in a network list: always a person or organization, sometimes
/// with a pending connection attached and sometimes with the server's own
/// reason for suggesting them.
class NetworkEntry {
  const NetworkEntry({
    required this.person,
    this.connectionId,
    this.message,
    this.requestedAt,
    this.connectedAt,
    this.reason,
  });

  final PostAuthor person;

  /// Set on an invitation or a sent request; what accept, decline and
  /// withdraw act on.
  final String? connectionId;

  /// The note the other person wrote with their request.
  final String? message;
  final DateTime? requestedAt;
  final DateTime? connectedAt;

  /// Why Omelo suggested this person, in the server's own words.
  final String? reason;

  /// A plain author card, as `connections`, `followers`, `following` and the
  /// suggestions send it.
  static NetworkEntry? fromAuthorJson(dynamic v) {
    final person = PostAuthor.fromJson(v);
    if (person == null) return null;
    final m = _map(v)!;
    return NetworkEntry(
      person: person,
      connectedAt: _date(m['connected_at']),
      reason: _str(m['reason']),
    );
  }

  /// An `invitations` or `sent` row, which wraps the person.
  static NetworkEntry? fromConnectionJson(dynamic v) {
    final m = _map(v);
    final person = PostAuthor.fromJson(m?['person']);
    if (m == null || person == null) return null;
    return NetworkEntry(
      person: person,
      connectionId: _str(m['connection_id']),
      message: _str(m['message']),
      requestedAt: _date(m['requested_at']),
    );
  }
}

/// Picks the right shape for [view] — the server sends author cards for
/// three of the five views and wrapped rows for the other two.
List<NetworkEntry> parseNetwork(dynamic v, NetworkView view) {
  final wrapped = view == NetworkView.invitations || view == NetworkView.sent;
  return _maps(v)
      .map(wrapped ? NetworkEntry.fromConnectionJson : NetworkEntry.fromAuthorJson)
      .whereType<NetworkEntry>()
      .toList();
}

List<NetworkEntry> parseSuggestions(dynamic v) => _maps(v)
    .map(NetworkEntry.fromAuthorJson)
    .whereType<NetworkEntry>()
    .toList();

// ---------------------------------------------------------------------------
// An organization's page
// ---------------------------------------------------------------------------

class OrganizationFeed {
  const OrganizationFeed({
    this.organization,
    this.followers = 0,
    this.following = false,
    this.posts = const [],
  });

  final PostAuthor? organization;
  final int followers;

  /// True when I follow it.
  final bool following;
  final List<FeedPost> posts;

  /// "1,204 followers" · "1 follower" · "No followers yet"
  String get followerLine => followers <= 0
      ? 'No followers yet'
      : '${NumberFormat.decimalPattern('en').format(followers)} '
          'follower${followers == 1 ? '' : 's'}';

  static OrganizationFeed? fromJson(dynamic v) {
    final m = _map(v);
    if (m == null) return null;
    final org = PostAuthor.fromJson(m['organization']);
    if (org == null) return null;
    return OrganizationFeed(
      organization: org,
      followers: _count(m['followers']),
      following: _bool(m['following']),
      posts: parsePosts(m['posts']),
    );
  }
}

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------

/// What Omelo lets a worker report, in the worker's words. The wire values
/// are the `report_reason` enum the database already has.
enum ReportReason {
  fraud,
  paymentRequest,
  discrimination,
  harassment,
  misleadingJob,
  fakeCompany,
  spam,
  inappropriateContent,
  dataMisuse,
  other,
}

extension ReportReasonX on ReportReason {
  String get wire => switch (this) {
        ReportReason.fraud => 'fraud',
        ReportReason.paymentRequest => 'payment_request',
        ReportReason.discrimination => 'discrimination',
        ReportReason.harassment => 'harassment',
        ReportReason.misleadingJob => 'misleading_job',
        ReportReason.fakeCompany => 'fake_company',
        ReportReason.spam => 'spam',
        ReportReason.inappropriateContent => 'inappropriate_content',
        ReportReason.dataMisuse => 'data_misuse',
        ReportReason.other => 'other',
      };

  String get label => switch (this) {
        ReportReason.fraud => 'It looks like a scam',
        ReportReason.paymentRequest => 'It asks me for money',
        ReportReason.discrimination => 'It discriminates',
        ReportReason.harassment => 'It harasses someone',
        ReportReason.misleadingJob => 'The job is not real or is misleading',
        ReportReason.fakeCompany => 'The organization is not real',
        ReportReason.spam => 'It is spam',
        ReportReason.inappropriateContent => 'It is offensive or explicit',
        ReportReason.dataMisuse => 'It misuses personal information',
        ReportReason.other => 'Something else',
      };
}

/// What a report is about.
enum ReportSubject { post, comment, person, company }

extension ReportSubjectX on ReportSubject {
  String get wire => switch (this) {
        ReportSubject.post => 'post',
        ReportSubject.comment => 'comment',
        ReportSubject.person => 'person',
        ReportSubject.company => 'company',
      };
}

/// What a block is about. A post cannot be blocked, only its author.
enum BlockTarget { person, company }

extension BlockTargetX on BlockTarget {
  String get wire => this == BlockTarget.company ? 'company' : 'person';
}

/// What `omelo_mute_from_feed` accepts.
enum MuteTarget { person, company, post }

extension MuteTargetX on MuteTarget {
  String get wire => switch (this) {
        MuteTarget.person => 'person',
        MuteTarget.company => 'company',
        MuteTarget.post => 'post',
      };
}

/// What omelo_follow accepts: a person or an organization.
String followTargetWire(AuthorType t) =>
    t == AuthorType.organization ? 'company' : 'person';
