import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../data/global_repository.dart';
import '../representations/representation_widgets.dart'
    show RepresentationMessage;
import '../work/work_widgets.dart' show workBackButton;
import 'global_widgets.dart';

/// `/countries/:code` — plain facts about working in a country, with links to
/// the official sources. Information only, never advice.
class CountryGuideScreen extends ConsumerWidget {
  const CountryGuideScreen({super.key, required this.code});
  final String code;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final upper = code.toUpperCase();
    final async = ref.watch(countryGuideProvider(upper));
    return Scaffold(
      appBar: AppBar(
        title: Text(async.valueOrNull?.name ?? 'Country guide'),
        leading: workBackButton(context, '/jobs/global'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RepresentationMessage(
          icon: Icons.cloud_off_outlined,
          title: 'Could not load this country',
          body: globalError(e),
          actionLabel: 'Try again',
          onAction: () => ref.invalidate(countryGuideProvider(upper)),
        ),
        data: (g) => g == null
            ? const RepresentationMessage(
                icon: Icons.public_off,
                title: 'Country not found',
                body: 'Omelo has no guide for this country yet.',
              )
            : CountryGuideView(guide: g),
      ),
    );
  }
}

class CountryGuideView extends StatelessWidget {
  const CountryGuideView({super.key, required this.guide});
  final CountryGuide guide;

  @override
  Widget build(BuildContext context) {
    final g = guide;
    final gutter = Breakpoints.of(context).gutter;
    final scheme = Theme.of(context).colorScheme;
    final facts = <(IconData, String, String)>[
      if (g.currency != null)
        (
          Icons.payments_outlined,
          'Currency',
          g.currencyName == null ? g.currency! : '${g.currencyName} (${g.currency})',
        ),
      if (g.language != null)
        (Icons.translate, 'Main language', languageName(g.language)),
      if (g.timezone != null)
        (Icons.schedule, 'Time zone', g.timezone!.replaceAll('_', ' ')),
      if (g.dialCode != null) (Icons.call_outlined, 'Phone code', g.dialCode!),
      if (g.region != null)
        (Icons.public, 'Region', g.region!.replaceAll('_', ' ')),
    ];

    return ListView(
      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 32),
      children: [
        ContentWidth(
          maxWidth: 900,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LegalNotice(
                informationOnlyBanner,
                body: 'Rules change. Check the official source, or a licensed '
                    'adviser, before you act.',
              ),
              const SizedBox(height: 16),
              Text(g.name,
                  style: const TextStyle(
                      fontSize: 26, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, c) {
                  final cols = c.maxWidth >= 640 ? 3 : (c.maxWidth >= 400 ? 2 : 1);
                  final w = (c.maxWidth - (cols - 1) * 10) / cols;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (final f in facts)
                        SizedBox(
                          width: w,
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(f.$1, color: scheme.primary),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(f.$2,
                                          style: TextStyle(
                                              fontSize: 12.5,
                                              color: scheme.onSurfaceVariant)),
                                      Text(f.$3,
                                          style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: FilledButton.tonalIcon(
                  onPressed: () => context.push(
                      '/jobs/global?tab=international&country=${g.code}'),
                  icon: const Icon(Icons.work_outline),
                  label: Text('Jobs in ${g.name}'),
                ),
              ),
              if (g.information.isEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'No official sources added for ${g.name} yet.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
              for (final topic in g.byTopic.entries) ...[
                const SizedBox(height: 22),
                Text(topic.key,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                ResponsiveCardGrid(
                  minCardWidth: 380,
                  spacing: 0,
                  children: [
                    for (final s in topic.value)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: OfficialSourceTile(s),
                      ),
                  ],
                ),
              ],
              if (g.licences.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Text('Licences for some jobs',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                const SizedBox(height: 10),
                for (final l in g.licences) LicenceTile(l),
              ],
              const SizedBox(height: 20),
              Text(
                g.disclaimer ?? informationOnlyBanner,
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
