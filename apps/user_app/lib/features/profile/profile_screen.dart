import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme.dart';
import '../../core/responsive.dart';
import '../../data/auth_repository.dart';
import '../applications/applications_screen.dart';

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
        appBar: AppBar(title: const Text('My Omelo')),
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
      appBar: AppBar(title: const Text('My Omelo')),
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
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.work_outline, size: 20),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'A work identity was created for you automatically. You can '
                    'apply right now.',
                    style: TextStyle(fontSize: 13.5, height: 1.4),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 26),
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

          const SizedBox(height: 26),
          Text('Not built yet',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          for (final item in const [
            ('Skills, experience and education', 'A1 §11'),
            ('Multiple kinds of work (up to 5)', 'A1 §11.2'),
            ('Resume builder', 'A1 §11.3'),
            ('Documents and sharing', 'A1 §11.4'),
            ('Verification centre', 'A1 §11.5'),
            ('Who can find me', 'A1 §11.6'),
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
  const _Tile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label,
          style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600)),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
