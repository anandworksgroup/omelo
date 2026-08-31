import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/responsive.dart';
import '../../core/location.dart';

/// U-02 — Language.
/// First screen with a choice, because everything after it is words.
class LanguageScreen extends ConsumerWidget {
  const LanguageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final langs = ref.watch(languagesProvider);
    final current = ref.watch(appPrefsProvider).value?.locale ?? 'en';

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 32, 24, 8),
              child: Text('Choose your language',
                  style:
                      TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text('आप अपनी भाषा चुन सकते हैं',
                  style: TextStyle(fontSize: 15)),
            ),
            Expanded(
              child: ContentWidth.reading(
                child: langs.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) => _LangFallback(current: current),
                data: (list) => ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (context, i) {
                    final l = list[i];
                    final code = (l['code'] ?? '') as String;
                    final selected = current == code ||
                        (current == 'en' && code == 'eng');
                    return ListTile(
                      title: Text((l['native_name'] ?? l['name']) as String,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600)),
                      subtitle: Text((l['name'] ?? '') as String),
                      trailing: selected
                          ? const Icon(Icons.check_circle,
                              color: Color(0xFF12805C))
                          : null,
                      onTap: () async {
                        await ref
                            .read(appPrefsProvider.notifier)
                            .setLocale(code);
                        if (context.mounted) context.go('/onboarding/country');
                      },
                    );
                  },
                ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LangFallback extends ConsumerWidget {
  const _LangFallback({required this.current});
  final String current;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListView(
        children: [
          ListTile(
            title: const Text('English',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
            onTap: () => context.go('/onboarding/country'),
          ),
        ],
      );
}

/// U-03 — Country. Drives currency, pay period and auth method via
/// `country_policies`. Never assume a US- or Europe-shaped market.
class CountryScreen extends ConsumerWidget {
  const CountryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countries = ref.watch(supportedCountriesProvider);
    final current = ref.watch(appPrefsProvider).value?.country ?? 'IN';

    return Scaffold(
      appBar: AppBar(leading: BackButton(onPressed: () => context.go('/onboarding/language'))),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Text('Where are you looking for work?',
                  style:
                      TextStyle(fontSize: 26, fontWeight: FontWeight.w800)),
            ),
            Expanded(
              child: ContentWidth.reading(
                child: countries.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (_, __) => const Center(
                    child: Text('Could not load countries. Try again.')),
                data: (list) {
                  final supported =
                      list.where((c) => c['supported'] == true).toList();
                  return ListView.builder(
                    itemCount: supported.length,
                    itemBuilder: (context, i) {
                      final c = supported[i];
                      final code = (c['country_code'] ?? '') as String;
                      return ListTile(
                        title: Text((c['name'] ?? '') as String,
                            style: const TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w600)),
                        subtitle: Text((c['default_currency'] ?? '') as String),
                        trailing: current == code
                            ? const Icon(Icons.check_circle,
                                color: Color(0xFF12805C))
                            : null,
                        onTap: () async {
                          await ref
                              .read(appPrefsProvider.notifier)
                              .setCountry(code);
                          if (context.mounted) {
                            context.go('/onboarding/welcome');
                          }
                        },
                      );
                    },
                  );
                },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// U-04 — Welcome.
///
/// The load-bearing screen. "Find work now" leads straight to real jobs with
/// no account. A worker who has been burned by fake job sites will not
/// register on faith (UC-1).
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ContentWidth.reading(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Text('Omelo',
                  style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: scheme.primary,
                      letterSpacing: -1)),
              const SizedBox(height: 12),
              const Text(
                'Find work that fits your life.',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 28),
              const _Point(
                  Icons.place_outlined, 'Real jobs near you, sorted by distance'),
              const _Point(Icons.description_outlined,
                  'No resume needed for most jobs'),
              const _Point(Icons.visibility_outlined,
                  'See exactly what happens to every application'),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () async {
                    await ref.read(appPrefsProvider.notifier).completeOnboarding();
                    // Ask for location here, in context, not on a cold start.
                    await ref.read(originProvider.notifier).useDeviceLocation();
                    if (context.mounted) context.go('/discover');
                  },
                  child: const Text('Find work now'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () async {
                    await ref.read(appPrefsProvider.notifier).completeOnboarding();
                    if (context.mounted) context.go('/discover');
                  },
                  child: const Text('Sign in'),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  'No account needed to look around.',
                  style:
                      TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 15.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}
