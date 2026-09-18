import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../messages/inbox_providers.dart' show notificationsProvider;
import '../notifications/notifications_screen.dart' show NotificationBell;
import '../../core/app_state.dart';
import '../../core/location.dart';
import '../../core/responsive.dart';
import '../discover/discover_controller.dart';
import '../../data/invitations_repository.dart';
import '../../data/job_events.dart' show JobSurface;
import '../discover/tracked_job_card.dart';
import '../identities/identity_widgets.dart' show IdentityNudgeCard;
import '../settings/account_widgets.dart' show DeletionBanner;

/// U-20 — Home.
///
/// Answers one question: what changed that affects my work? Not a feed.
/// For a signed-out or brand-new user it is mostly "here is real work near
/// you", because that is the only honest thing it can say.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(discoverProvider);
    final origin = ref.watch(originProvider).value;
    final signedIn = ref.watch(isSignedInProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => ref.read(discoverProvider.notifier).load(),
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                Breakpoints.of(context).gutter, 12,
                Breakpoints.of(context).gutter, 32),
            children: [
              ContentWidth(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
              if (signedIn)
                const DeletionBanner(padding: EdgeInsets.only(bottom: 16)),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      signedIn ? 'Your work' : 'Welcome to Omelo',
                      style: const TextStyle(
                          fontSize: 26, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const NotificationBell(),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                origin == null
                    ? 'Finding jobs near you…'
                    : origin.isPrecise
                        ? 'Jobs near your location'
                        : 'Jobs near ${origin.label ?? "your area"}',
                style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.go('/discover'),
                  icon: const Icon(Icons.search),
                  label: const Text('Search jobs'),
                ),
              ),

              if (signedIn)
                const InvitationsHomeCard(padding: EdgeInsets.only(top: 20)),
              if (signedIn)
                const IdentityNudgeCard(padding: EdgeInsets.only(top: 20)),

              if (!signedIn) ...[
                const SizedBox(height: 20),
                _Callout(
                  icon: Icons.person_add_alt,
                  title: 'Build your profile to apply',
                  body: 'Takes a few minutes. No resume, no degree needed.',
                  actionLabel: 'Get started',
                  onAction: () => ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                          'Profile building is the next build step — not wired yet.'),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 28),
              Row(
                children: [
                  const Text('Jobs near you',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => context.go('/discover'),
                    child: const Text('See all'),
                  ),
                ],
              ),
              const SizedBox(height: 4),

              if (state.loading && state.jobs.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.jobs.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  child: Column(
                    children: [
                      Icon(Icons.search_off,
                          size: 40, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      const Text('No jobs found nearby yet',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () => context.go('/discover'),
                        child: const Text('Widen the search'),
                      ),
                    ],
                  ),
                )
              else
                ResponsiveCardGrid(
                  children: [
                    for (var i = 0; i < state.jobs.length && i < 6; i++)
                      TrackedJobCard(
                        key: ValueKey('home-${state.jobs[i].id}'),
                        job: state.jobs[i],
                        surface: JobSurface.recommended,
                        rank: i + 1,
                      ),
                  ],
                ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(body, style: const TextStyle(fontSize: 13.5, height: 1.4)),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "2 employers invited you to apply" — only while some are waiting.
class InvitationsHomeCard extends ConsumerWidget {
  const InvitationsHomeCard({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A new "invited you to apply" notification means a new invitation.
    ref.listen<int>(
        notificationsProvider.select(
            (s) => s.items.where((n) => n.type == 'job_invitation').length),
        (_, __) => ref.invalidate(myInvitationsProvider));
    final pending = ref.watch(pendingInvitationsProvider);
    if (pending <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: padding,
      child: Material(
        color: scheme.tertiaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/invitations'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Badge(
                    label: Text('$pending'),
                    child: Icon(Icons.mail_outline,
                        size: 30, color: scheme.onTertiaryContainer),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(invitedYouTitle(pending),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text('See the jobs and answer them.',
                            style: TextStyle(
                                fontSize: 13.5,
                                color: scheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
