import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/messaging.dart';
import '../messages/inbox_providers.dart';

/// Bell with the unread count, for the app bar of every main tab.
/// Hidden when signed out: there is nothing to be notified about.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isSignedInProvider)) return const SizedBox.shrink();
    final unread = ref.watch(notificationsProvider.select((s) => s.unread));
    final label = badgeLabel(unread);
    return IconButton(
      tooltip: unread > 0 ? 'Notifications, $unread new' : 'Notifications',
      iconSize: 26,
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      onPressed: () => context.push('/notifications'),
      icon: Badge(
        isLabelVisible: label != null,
        label: Text(label ?? ''),
        child: Icon(unread > 0
            ? Icons.notifications_active_outlined
            : Icons.notifications_outlined),
      ),
    );
  }
}

/// `/notifications` — everything Omelo told me, newest first.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(notificationsProvider);
    final ctl = ref.read(notificationsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: context.canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => context.go('/discover'),
              ),
        actions: [
          if (s.unread > 0)
            TextButton(
              onPressed: () async {
                try {
                  await ctl.markAllRead();
                } catch (_) {
                  if (context.mounted) {
                    _snack(context, 'Could not mark them read. Try again.');
                  }
                }
              },
              child: const Text('Mark all read'),
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: ctl.refresh,
        child: _body(context, ref, s),
      ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, NotificationsState s) {
    if (s.loading && s.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (s.items.isEmpty) {
      return _Empty(
        icon: s.failed ? Icons.cloud_off_outlined : Icons.notifications_none,
        title: s.failed
            ? 'Could not load notifications'
            : 'No notifications yet',
        body: s.failed
            ? 'Check your internet and pull down to try again.'
            : 'When an employer invites you to apply, an agency asks to '
                'represent you, an employer views your application, invites '
                'you to an interview or sends a message, you will see it '
                'here.',
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: s.items.length,
      separatorBuilder: (_, __) => const ContentWidth.reading(child: Divider()),
      itemBuilder: (context, i) {
        final n = s.items[i];
        return ContentWidth.reading(
          child: Dismissible(
            key: ValueKey('n-${n.id}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: OmeloTheme.danger,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('Delete',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                  SizedBox(width: 8),
                  Icon(Icons.delete_outline, color: Colors.white),
                ],
              ),
            ),
            onDismissed: (_) async {
              try {
                await ref.read(notificationsProvider.notifier).delete(n);
              } catch (_) {
                if (context.mounted) {
                  _snack(context, 'Could not delete it. Try again.');
                }
              }
            },
            child: _NotificationTile(
              n: n,
              onTap: () => _open(context, ref, n),
            ),
          ),
        );
      },
    );
  }

  Future<void> _open(
      BuildContext context, WidgetRef ref, AppNotification n) async {
    // Mark read first so the badge drops even if the target fails to load.
    ref.read(notificationsProvider.notifier).markRead(n);
    final target = n.target;
    if (target == null) return;
    context.go(target);
  }
}

void _snack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
      ?.showSnackBar(SnackBar(content: Text(text)));
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.n, required this.onTap});
  final AppNotification n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = !n.isRead;
    final icon = switch (notificationKind(n.type)) {
      NotificationKind.interview => Icons.event_outlined,
      NotificationKind.application => Icons.assignment_outlined,
      NotificationKind.offer => Icons.workspace_premium_outlined,
      NotificationKind.message => Icons.chat_bubble_outline,
      NotificationKind.invitation => Icons.mail_outline,
      NotificationKind.representation => Icons.handshake_outlined,
      NotificationKind.other => Icons.notifications_outlined,
    };

    return Material(
      color: unread
          ? scheme.primaryContainer.withValues(alpha: 0.35)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: unread
                      ? scheme.primary
                      : scheme.surfaceContainerHighest,
                  foregroundColor:
                      unread ? scheme.onPrimary : scheme.onSurfaceVariant,
                  child: Icon(icon, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        n.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight:
                              unread ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      if (n.body != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          n.body!,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 14.5,
                              height: 1.35,
                              color: scheme.onSurfaceVariant),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        Messaging.listTime(n.createdAt, DateTime.now()),
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (unread)
                  Padding(
                    padding: const EdgeInsets.only(left: 8, top: 6),
                    child: Semantics(
                      label: 'New',
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: scheme.primary, shape: BoxShape.circle),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      children: [
        ContentWidth.reading(
          child: Column(
            children: [
              Icon(icon, size: 56, color: scheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(body,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 15.5, height: 1.45)),
            ],
          ),
        ),
      ],
    );
  }
}
