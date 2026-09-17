import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_state.dart';
import '../../data/messaging_repository.dart';

/// Unread employer messages across all my conversations, kept live by
/// realtime with a slow poll as a fallback (realtime can drop quietly on
/// mobile networks). Drives the Messages badge.
final unreadMessagesProvider =
    NotifierProvider<UnreadMessagesController, int>(UnreadMessagesController.new);

/// Bumps whenever something in my conversations changed, so open lists can
/// refetch without holding their own realtime channel.
final messagesChangedProvider = StateProvider<int>((_) => 0);

class UnreadMessagesController extends Notifier<int> {
  Timer? _debounce;

  @override
  int build() {
    final user = ref.watch(currentUserProvider);
    if (user == null) return 0;

    final repo = ref.watch(messagingRepositoryProvider);
    final channel = repo.watchAll(_changed);
    final poll = Timer.periodic(const Duration(minutes: 1), (_) => refresh());
    ref.onDispose(() {
      _debounce?.cancel();
      poll.cancel();
      repo.unsubscribe(channel);
    });
    Future.microtask(refresh);
    return 0;
  }

  void _changed() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      refresh();
      ref.read(messagesChangedProvider.notifier).state++;
    });
  }

  Future<void> refresh() async {
    try {
      final n = await ref.read(messagingRepositoryProvider).unreadCount();
      state = n;
    } catch (_) {
      // Keep the last known count; the next event or poll retries.
    }
  }
}

class NotificationsState {
  const NotificationsState({
    this.items = const [],
    this.unread = 0,
    this.loading = true,
    this.failed = false,
  });

  final List<AppNotification> items;
  final int unread;
  final bool loading;
  final bool failed;

  NotificationsState copyWith({
    List<AppNotification>? items,
    int? unread,
    bool? loading,
    bool? failed,
  }) =>
      NotificationsState(
        items: items ?? this.items,
        unread: unread ?? this.unread,
        loading: loading ?? this.loading,
        failed: failed ?? this.failed,
      );
}

/// The notification inbox and the bell's unread count, live.
final notificationsProvider =
    NotifierProvider<NotificationsController, NotificationsState>(
        NotificationsController.new);

class NotificationsController extends Notifier<NotificationsState> {
  Timer? _debounce;

  NotificationsRepository get _repo => ref.read(notificationsRepositoryProvider);

  @override
  NotificationsState build() {
    final user = ref.watch(currentUserProvider);
    if (user == null) {
      return const NotificationsState(loading: false);
    }
    final repo = ref.watch(notificationsRepositoryProvider);
    final channel = repo.watch(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 300), refresh);
    });
    final poll = Timer.periodic(const Duration(minutes: 2), (_) => refresh());
    ref.onDispose(() {
      _debounce?.cancel();
      poll.cancel();
      repo.unsubscribe(channel);
    });
    Future.microtask(refresh);
    return const NotificationsState();
  }

  Future<void> refresh() async {
    try {
      final results = await Future.wait([_repo.list(), _repo.unreadCount()]);
      state = NotificationsState(
        items: results[0] as List<AppNotification>,
        unread: results[1] as int,
        loading: false,
      );
    } catch (_) {
      state = state.copyWith(loading: false, failed: state.items.isEmpty);
    }
  }

  Future<void> markRead(AppNotification n) async {
    if (n.isRead) return;
    final now = DateTime.now();
    state = state.copyWith(
      items: [for (final x in state.items) x.id == n.id ? x.markedRead(now) : x],
      unread: state.unread > 0 ? state.unread - 1 : 0,
    );
    try {
      await _repo.markRead(n.id);
    } catch (_) {
      await refresh();
    }
  }

  Future<void> markAllRead() async {
    final now = DateTime.now();
    final before = state;
    state = state.copyWith(
      items: [for (final x in state.items) x.markedRead(now)],
      unread: 0,
    );
    try {
      await _repo.markAllRead();
    } catch (_) {
      state = before;
      rethrow;
    }
  }

  Future<void> delete(AppNotification n) async {
    final before = state;
    state = state.copyWith(
      items: state.items.where((x) => x.id != n.id).toList(),
      unread: !n.isRead && state.unread > 0 ? state.unread - 1 : state.unread,
    );
    try {
      await _repo.delete(n.id);
    } catch (_) {
      state = before;
      rethrow;
    }
  }
}
