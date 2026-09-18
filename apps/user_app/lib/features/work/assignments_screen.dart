import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/work_repository.dart';
import 'work_widgets.dart';

/// `/work/assignments` — work I was offered or am doing. Offers waiting for
/// an answer first.
class AssignmentsScreen extends ConsumerWidget {
  const AssignmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForWorkNotices(ref);
    final async = ref.watch(myAssignmentsProvider);
    final now = workNow(ref);
    return Scaffold(
      appBar: AppBar(
        title: const Text('My assignments'),
        leading: workBackButton(context, '/work'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myAssignmentsProvider);
          try {
            await ref.read(myAssignmentsProvider.future);
          } catch (_) {}
        },
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => RepresentationMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load your assignments',
            body: workError(e),
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(myAssignmentsProvider),
          ),
          data: (list) {
            if (list.isEmpty) {
              return RepresentationMessage(
                icon: Icons.assignment_ind_outlined,
                title: 'No assignments yet',
                body:
                    'When an employer or agency offers you work, you will '
                    'see the full offer here and can say yes or no.',
                actionLabel: 'Find work',
                onAction: () => context.go('/discover'),
              );
            }
            final sorted = sortAssignments(list, now);
            final gutter = Breakpoints.of(context).gutter;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                ContentWidth.reading(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final a in sorted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: AssignmentCard(assignment: a, now: now),
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
