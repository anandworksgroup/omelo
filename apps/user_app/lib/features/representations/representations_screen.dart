import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/representations_repository.dart';
import 'representation_widgets.dart';

/// `/representations` — recruiters and agencies who asked to represent me.
/// Waiting ones first. `?agency=<id>` shows one agency only.
class RepresentationsScreen extends ConsumerWidget {
  const RepresentationsScreen({super.key, this.agency});

  /// Agency key (id) to filter by, from the recruiters screen.
  final String? agency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myRepresentationsProvider);
    final all = list.valueOrNull ?? const <Representation>[];
    final filtered = agency == null
        ? all
        : all.where((r) => agencyKey(r) == agency).toList();
    final title = agency != null && filtered.isNotEmpty
        ? filtered.first.agencyName
        : 'Requests to represent you';

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: context.canPop()
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'Back',
                onPressed: () => context.go('/recruiters'),
              ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(myRepresentationsProvider);
          try {
            await ref.read(myRepresentationsProvider.future);
          } catch (_) {
            // The error state shows its own message.
          }
        },
        child: list.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => RepresentationMessage(
            icon: Icons.cloud_off_outlined,
            title: 'Could not load your requests',
            body: 'Check your internet and try again.',
            actionLabel: 'Try again',
            onAction: () => ref.invalidate(myRepresentationsProvider),
          ),
          data: (_) {
            if (filtered.isEmpty) {
              return RepresentationMessage(
                icon: Icons.handshake_outlined,
                title: 'No requests from recruiters yet',
                body:
                    'Recruiters and agencies can ask to represent you for '
                    'a job. They can only find a work identity that is set '
                    'to "Employers and agencies" (or "Anyone with the link") '
                    'and that lets recruiters ask.',
                actionLabel: 'Choose who can see me',
                onAction: () => context.push('/identities'),
              );
            }
            final gutter = Breakpoints.of(context).gutter;
            final pending = pendingRepresentations(
              filtered,
              DateTime.now(),
            ).length;
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
              children: [
                ContentWidth.reading(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (pending > 0)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Badge(
                                label: Text('$pending'),
                                largeSize: 22,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  pending == 1
                                      ? '1 request is waiting for your answer.'
                                      : '$pending requests are waiting for '
                                            'your answer.',
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      for (final r in filtered)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: RepresentationCard(
                            representation: r,
                            onTap: () =>
                                context.push('/representations/${r.id}'),
                          ),
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
