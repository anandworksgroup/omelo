import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/responsive.dart';
import '../../data/messaging_repository.dart';
import '../notifications/notifications_screen.dart';
import 'inbox_providers.dart';

final conversationsProvider =
    FutureProvider.autoDispose<List<Conversation>>((ref) async {
  ref.watch(authStateProvider);
  ref.watch(messagesChangedProvider);
  return ref.watch(messagingRepositoryProvider).conversations();
});

/// `/messages` — one conversation per job I applied to.
class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});

  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final signedIn = ref.watch(isSignedInProvider);
    // Keeps the badge (and its realtime feed) alive while this is open.
    ref.watch(unreadMessagesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Messages'),
        actions: const [NotificationBell(), SizedBox(width: 8)],
      ),
      body: !signedIn
          ? _Empty(
              icon: Icons.chat_bubble_outline,
              title: 'Talk to employers here',
              body: 'Sign in to see messages from employers about jobs you '
                  'applied to.',
              button: 'Sign in',
              onPressed: () => context.push('/sign-in?next=/messages'),
            )
          : _list(context),
    );
  }

  Widget _list(BuildContext context) {
    final async = ref.watch(conversationsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => _Empty(
        icon: Icons.cloud_off_outlined,
        title: 'Could not load messages',
        body: 'Check your internet and try again.',
        button: 'Try again',
        onPressed: () => ref.invalidate(conversationsProvider),
      ),
      data: (all) {
        final list = Messaging.visible(all, showArchived: _showArchived);
        final archivedCount = all.where((c) => c.archived).length;

        return RefreshIndicator(
          onRefresh: () async {
            ref.read(unreadMessagesProvider.notifier).refresh();
            return ref.refresh(conversationsProvider.future);
          },
          child: all.isEmpty
              ? const _Empty(
                  icon: Icons.forum_outlined,
                  title: 'No messages yet',
                  body: 'After you apply for a job, the employer can message '
                      'you here. You can also message them from your '
                      'application.',
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.only(bottom: 24),
                  children: [
                    if (list.isEmpty)
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 40, 24, 16),
                        child: Text(
                          'No messages here. Archived chats are hidden.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 15.5),
                        ),
                      ),
                    for (final c in list)
                      ContentWidth.reading(
                        child: _ConversationTile(
                          c: c,
                          onTap: () async {
                            await context.push('/messages/${c.id}');
                            if (mounted) ref.invalidate(conversationsProvider);
                          },
                          onArchive: () => _archive(c, !c.archived),
                        ),
                      ),
                    if (archivedCount > 0)
                      ContentWidth.reading(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: OutlinedButton.icon(
                            onPressed: () => setState(
                                () => _showArchived = !_showArchived),
                            icon: Icon(_showArchived
                                ? Icons.visibility_off_outlined
                                : Icons.archive_outlined),
                            label: Text(_showArchived
                                ? 'Hide archived'
                                : 'Show archived ($archivedCount)'),
                          ),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Future<void> _archive(Conversation c, bool archived) async {
    try {
      await ref.read(messagingRepositoryProvider).setArchived(c.id, archived);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(archived ? 'Chat archived' : 'Chat moved back'),
        action: archived
            ? SnackBarAction(
                label: 'Undo', onPressed: () => _archive(c, false))
            : null,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(messagingError(e))));
    } finally {
      if (mounted) ref.invalidate(conversationsProvider);
    }
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.c,
    required this.onTap,
    required this.onArchive,
  });

  final Conversation c;
  final VoidCallback onTap;
  final VoidCallback onArchive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final unread = c.unread > 0;
    final time = c.lastMessage?.sentAt ?? c.lastMessageAt;

    return InkWell(
      onTap: onTap,
      onLongPress: onArchive,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 76),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
          child: Row(
            children: [
              _Logo(url: c.companyLogoUrl, name: c.companyOrEmployer),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            c.companyOrEmployer,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16.5,
                              fontWeight:
                                  unread ? FontWeight.w800 : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (time != null)
                          Text(
                            Messaging.listTime(time, DateTime.now()),
                            style: TextStyle(
                              fontSize: 13,
                              color: unread
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                              fontWeight:
                                  unread ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      c.jobOrSubject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 14, color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            Messaging.preview(c.lastMessage),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              color: unread
                                  ? scheme.onSurface
                                  : scheme.onSurfaceVariant,
                              fontWeight:
                                  unread ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (c.archived)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.archive_outlined,
                                size: 16, color: scheme.onSurfaceVariant),
                          ),
                        if (unread)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Badge(
                              label: Text(badgeLabel(c.unread)!),
                              backgroundColor: scheme.primary,
                              textColor: scheme.onPrimary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                onSelected: (_) => onArchive(),
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'archive',
                    child: Text(c.archived ? 'Move back to inbox' : 'Archive'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url, required this.name});
  final String? url;
  final String name;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final letter = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    final fallback = CircleAvatar(
      radius: 24,
      backgroundColor: scheme.primaryContainer,
      foregroundColor: scheme.onPrimaryContainer,
      child: Text(letter,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
    );
    if (url == null) return fallback;
    return ClipOval(
      child: Image.network(
        url!,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => fallback,
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.icon,
    required this.title,
    required this.body,
    this.button,
    this.onPressed,
  });

  final IconData icon;
  final String title;
  final String body;
  final String? button;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(32, 64, 32, 32),
      children: [
        ContentWidth.reading(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
              if (button != null) ...[
                const SizedBox(height: 24),
                FilledButton(onPressed: onPressed, child: Text(button!)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
