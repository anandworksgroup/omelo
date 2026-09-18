import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/invitations_repository.dart';
import '../invitations/invitation_widgets.dart';

/// `/profile-views` — employers who opened one of my work identities in the
/// last 30 days.
class ProfileViewsScreen extends ConsumerWidget {
  const ProfileViewsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final views = ref.watch(profileViewsProvider);
    final scheme = Theme.of(context).colorScheme;

    Widget message(IconData icon, String title, String body,
            {String? action, VoidCallback? onAction}) =>
        ListView(
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
                  if (action != null) ...[
                    const SizedBox(height: 24),
                    FilledButton(onPressed: onAction, child: Text(action)),
                  ],
                ],
              ),
            ),
          ],
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Employers who viewed you')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(profileViewsProvider);
          try {
            await ref.read(profileViewsProvider.future);
          } catch (_) {}
        },
        child: views.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => message(Icons.cloud_off_outlined,
              'Could not load this', 'Check your internet and try again.',
              action: 'Try again',
              onAction: () => ref.invalidate(profileViewsProvider)),
          data: (rows) {
            if (rows.isEmpty) {
              return message(
                Icons.visibility_outlined,
                'No employer has viewed you yet',
                'In the last 30 days no employer opened your profile. '
                    'Employers can find you when an identity is visible to '
                    'them, and they see it when you apply.',
                action: 'Choose who can see me',
                onAction: () => context.push('/identities'),
              );
            }
            final groups = groupProfileViews(rows);
            final now = DateTime.now();
            final gutter = Breakpoints.of(context).gutter;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                ContentWidth.reading(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          groups.length == 1
                              ? '1 employer opened your profile in the last '
                                  '30 days.'
                              : '${groups.length} employers opened your '
                                  'profile in the last 30 days.',
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                      ),
                      for (final g in groups)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _CompanyCard(group: g, now: now),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        'Only the company is shown, never the person who '
                        'looked. Change who can see each identity in My work '
                        'identities.',
                        style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CompanyCard extends StatelessWidget {
  const _CompanyCard({required this.group, required this.now});
  final CompanyViews group;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CompanyAvatar(name: group.companyName, logoUrl: group.companyLogo),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CompanyName(group.companyName,
                      verified: group.companyVerified, fontSize: 16),
                  const SizedBox(height: 6),
                  for (final e in group.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(viewedLine(e),
                                style: const TextStyle(
                                    fontSize: 14.5, height: 1.35)),
                          ),
                          const SizedBox(width: 8),
                          Text(viewedWhen(e.lastViewedAt, now),
                              style: TextStyle(
                                  fontSize: 13.5,
                                  color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
