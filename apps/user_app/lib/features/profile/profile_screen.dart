import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../notifications/notifications_screen.dart' show NotificationBell;
import '../../core/theme.dart';
import '../../core/responsive.dart';
import '../../data/auth_repository.dart';
import '../../data/identity_repository.dart';
import '../../data/invitations_repository.dart';
import '../../data/job_events.dart' show flushJobEvents;
import '../../data/representations_repository.dart'
    show pendingRepresentationsProvider;
import '../../data/messaging.dart' show badgeLabel;
import '../applications/applications_screen.dart';
import '../identities/identity_widgets.dart';

/// U-80 — "My Omelo".
///
/// Only the parts backed by real data are shown. Everything specified but not
/// implemented is listed plainly rather than mocked up, because a placeholder
/// that looks functional is worse than one that is honest.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;
    final user = auth.currentUser;

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
        title: const Text('My Omelo'),
        actions: const [NotificationBell(), SizedBox(width: 8)],
      ),
        body: ContentWidth.reading(
          child: ListView(
          padding: const EdgeInsets.fromLTRB(32, 60, 32, 32),
          children: [
            Icon(Icons.person_outline,
                size: 52, color: scheme.onSurfaceVariant),
            const SizedBox(height: 22),
            const Text('Your work identity',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(
              'No resume needed. No degree needed. Build it once and apply to '
              'anything.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 14.5, height: 1.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 30),
            FilledButton(
              onPressed: () => context.push('/sign-in?next=/profile'),
              child: const Text('Sign in or create an account'),
            ),
          ],
          ),
        ),
      );
    }

    final name = (user.userMetadata?['full_name'] as String?)?.trim();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Omelo'),
        actions: const [NotificationBell(), SizedBox(width: 8)],
      ),
      body: ContentWidth.reading(
        child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: scheme.primaryContainer,
                child: Text(
                  (name?.isNotEmpty == true
                          ? name!.characters.first
                          : (user.email ?? '?').characters.first)
                      .toUpperCase(),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name?.isNotEmpty == true ? name! : 'Your profile',
                        style: const TextStyle(
                            fontSize: 19, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 2),
                    Text(user.email ?? '',
                        style: TextStyle(
                            fontSize: 13.5, color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),
          const _IdentitiesSummary(),

          const SizedBox(height: 18),
          _Tile(
            icon: Icons.mail_outline,
            label: 'Job invitations',
            badge: ref.watch(pendingInvitationsProvider),
            onTap: () => context.push('/invitations'),
          ),
          _Tile(
            icon: Icons.handshake_outlined,
            label: 'Recruiters & agencies',
            badge: ref.watch(pendingRepresentationsProvider).length,
            onTap: () => context.push('/recruiters'),
          ),
          _Tile(
            icon: Icons.visibility_outlined,
            label: 'Employers who viewed you',
            onTap: () => context.push('/profile-views'),
          ),
          _Tile(
            icon: Icons.bookmark_border,
            label: 'Saved jobs',
            onTap: () => context.push('/saved'),
          ),
          _Tile(
            icon: Icons.assignment_outlined,
            label: 'My applications',
            onTap: () => context.go('/applications'),
          ),
          _Tile(
            icon: Icons.search,
            label: 'Find work',
            onTap: () => context.go('/discover'),
          ),
          _Tile(
            icon: Icons.settings_outlined,
            label: 'Settings',
            onTap: () => context.push('/settings'),
          ),

          const SizedBox(height: 26),
          Text('Not built yet',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final item in const [
            ('Education', 'A1 §11'),
            ('Resume builder', 'A1 §11.3'),
            ('Documents and sharing', 'A1 §11.4'),
            ('Verification centre', 'A1 §11.5'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Icon(Icons.remove, size: 14, color: scheme.outlineVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(item.$1,
                        style: TextStyle(
                            fontSize: 13.5, color: scheme.onSurfaceVariant)),
                  ),
                  OmeloPill(item.$2),
                ],
              ),
            ),

          const SizedBox(height: 30),
          OutlinedButton(
            onPressed: () async {
              // Send waiting funnel events while the session is still valid.
              await flushJobEvents(ref);
              await ref.read(authRepositoryProvider).signOut();
              ref.invalidate(myApplicationsProvider);
              if (context.mounted) context.go('/discover');
            },
            child: const Text('Sign out'),
          ),
        ],
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge = 0,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Count waiting for the worker, shown as a badge when above zero.
  final int badge;

  @override
  Widget build(BuildContext context) {
    final text = badgeLabel(badge);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 56,
      leading: Icon(icon),
      title: Text(label,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (text != null)
            Badge(
              label: Text(text, semanticsLabel: '$badge waiting'),
              largeSize: 22,
              padding: const EdgeInsets.symmetric(horizontal: 7),
            ),
          const Icon(Icons.chevron_right),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// "My work identities" entry: the main identity at a glance.
class _IdentitiesSummary extends ConsumerWidget {
  const _IdentitiesSummary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final list = ref.watch(myIdentitiesProvider).value ?? const [];
    final main = list.where((i) => i.isPrimary).firstOrNull;
    final active = list.where((i) => i.isActive).length;

    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/identities'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (main != null)
                CompletenessRing(score: main.completenessScore, size: 46)
              else
                const Icon(Icons.work_outline, size: 26),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('My work identities',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(
                      main == null
                          ? 'One profile for each kind of work you do.'
                          : active > 1
                              ? 'Main: ${main.label} · $active active'
                              : 'Main: ${main.label} · add another kind of work',
                      style: TextStyle(
                          fontSize: 13.5, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
