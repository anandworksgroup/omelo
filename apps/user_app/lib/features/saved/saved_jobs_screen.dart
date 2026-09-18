import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/job_events.dart' show JobSurface;
import '../../data/saved_jobs_repository.dart';
import '../discover/tracked_job_card.dart';

/// `/saved` — jobs I bookmarked, newest first.
class SavedJobsScreen extends ConsumerWidget {
  const SavedJobsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final jobs = ref.watch(savedJobsProvider);
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
      appBar: AppBar(title: const Text('Saved jobs')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(savedJobsProvider);
          try {
            await ref.read(savedJobsProvider.future);
          } catch (_) {}
        },
        child: jobs.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => message(Icons.cloud_off_outlined,
              'Could not load saved jobs', 'Check your internet and try again.',
              action: 'Try again',
              onAction: () => ref.invalidate(savedJobsProvider)),
          data: (list) {
            if (list.isEmpty) {
              return message(
                Icons.bookmark_border,
                'No saved jobs',
                'Tap the bookmark on a job to keep it here for later.',
                action: 'Find work',
                onAction: () => context.go('/discover'),
              );
            }
            final gutter = Breakpoints.of(context).gutter;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                ContentWidth(
                  child: ResponsiveCardGrid(
                    children: [
                      for (var i = 0; i < list.length; i++)
                        TrackedJobCard(
                          key: ValueKey('saved-${list[i].id}'),
                          job: list[i],
                          surface: JobSurface.saved,
                          rank: i + 1,
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
