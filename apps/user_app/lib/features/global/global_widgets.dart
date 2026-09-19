import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme.dart';
import '../../data/global_repository.dart';
import '../../data/identity_repository.dart' show TaxonomyHit;
import '../../data/work.dart' show ensureTimeZones;
import '../identities/search_picker.dart';

void showGlobalSnack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

// ---------------------------------------------------------------------------
// Eligibility
// ---------------------------------------------------------------------------

(IconData, Color) eligibilityLook(EligibilityStatus? s, ColorScheme scheme) =>
    switch (s) {
      EligibilityStatus.eligible => (Icons.check_circle, OmeloTheme.verified),
      EligibilityStatus.potentiallyEligible => (
        Icons.help_outline,
        OmeloTheme.warning,
      ),
      EligibilityStatus.notEligible => (Icons.block, OmeloTheme.danger),
      null => (Icons.help_outline, scheme.onSurfaceVariant),
    };

/// "Eligible" · "Potentially eligible" · "Not currently eligible"
class EligibilityChip extends StatelessWidget {
  const EligibilityChip(this.eligibility, {super.key});
  final JobEligibility eligibility;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = eligibilityLook(
      eligibility.status,
      Theme.of(context).colorScheme,
    );
    final chip = OmeloPill(
      eligibility.label,
      icon: icon,
      color: color,
      background: color.withValues(alpha: 0.12),
    );
    if (eligibility.missing.isEmpty) return chip;
    return Tooltip(
      message: eligibility.headline,
      triggerMode: TooltipTriggerMode.tap,
      child: chip,
    );
  }
}

// ---------------------------------------------------------------------------
// Converted pay
// ---------------------------------------------------------------------------

/// "≈ ₹3,10,000 a month in INR" with an info button that says which rate
/// and source were used. Nothing when there is no conversion.
class ApproxPayLine extends StatelessWidget {
  const ApproxPayLine({
    super.key,
    required this.text,
    required this.source,
    this.fontSize = 13.5,
  });

  final String? text;
  final String? source;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: source ?? 'Converted for comparison only.',
      triggerMode: TooltipTriggerMode.tap,
      showDuration: const Duration(seconds: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              text!,
              style: TextStyle(
                fontSize: fontSize,
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(
            Icons.info_outline,
            size: fontSize + 2,
            color: scheme.onSurfaceVariant,
            semanticLabel: 'How this was converted',
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Notices and links
// ---------------------------------------------------------------------------

/// The always-visible "not legal advice" notice.
class LegalNotice extends StatelessWidget {
  const LegalNotice(this.title, {super.key, this.body});
  final String title;
  final String? body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.gavel_outlined, size: 20, color: scheme.onTertiaryContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (body != null) ...[
                  const SizedBox(height: 3),
                  Text(body!, style: const TextStyle(fontSize: 13, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> openOfficialLink(BuildContext context, Uri? link) async {
  if (link == null) return;
  var ok = false;
  try {
    ok = await launchUrl(link, mode: LaunchMode.externalApplication);
  } catch (_) {}
  if (!ok && context.mounted) {
    showGlobalSnack(context, 'Could not open the link. It is ${link.host}.');
  }
}

String? _reviewed(DateTime? at) => at == null
    ? null
    : 'Checked ${at.day} ${const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][at.month - 1]} ${at.year}';

/// An official source, tappable when it has a secure link.
class OfficialSourceTile extends StatelessWidget {
  const OfficialSourceTile(this.source, {super.key, this.showSummary = true});
  final OfficialSource source;
  final bool showSummary;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final link = source.link;
    final sub = [
      ?source.source,
      ?link?.host,
      ?_reviewed(source.reviewedAt),
    ].join(' · ');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: link == null ? null : () => openOfficialLink(context, link),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: link == null ? null : scheme.primary,
                      ),
                    ),
                    if (showSummary && source.summary != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        source.summary!,
                        style: const TextStyle(fontSize: 14, height: 1.4),
                      ),
                    ],
                    if (sub.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        sub,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (link != null) ...[
                const SizedBox(width: 8),
                Icon(Icons.open_in_new, size: 18, color: scheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class LicenceTile extends StatelessWidget {
  const LicenceTile(this.licence, {super.key});
  final LicenceRequirement licence;

  @override
  Widget build(BuildContext context) {
    final l = licence;
    final scheme = Theme.of(context).colorScheme;
    final link = l.link;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: link == null ? null : () => openOfficialLink(context, link),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      l.profession == null ? l.name : '${l.name} · ${l.profession}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OmeloPill(l.isRequired ? 'Required' : 'Recommended'),
                ],
              ),
              if (l.description != null) ...[
                const SizedBox(height: 4),
                Text(l.description!,
                    style: const TextStyle(fontSize: 14, height: 1.4)),
              ],
              if (link != null || l.source != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        [?l.source, ?link?.host].join(' · '),
                        style: TextStyle(
                          fontSize: 12.5,
                          color: link == null
                              ? scheme.onSurfaceVariant
                              : scheme.primary,
                        ),
                      ),
                    ),
                    if (link != null)
                      Icon(Icons.open_in_new, size: 16, color: scheme.primary),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pickers
// ---------------------------------------------------------------------------

Future<Country?> pickCountry(
  BuildContext context,
  List<Country> countries, {
  String title = 'Choose a country',
  Iterable<String> exclude = const [],
}) async {
  final hit = await showSearchPicker(
    context,
    title: title,
    hint: 'Country name',
    search: (q) async => [
      for (final c in searchCountries(countries, q))
        if (!exclude.contains(c.code)) TaxonomyHit(id: c.code, name: c.name),
    ],
  );
  if (hit == null) return null;
  return countries.where((c) => c.code == hit.id).firstOrNull;
}

/// All IANA time zones, with [suggested] first.
List<String> timeZoneNames({Iterable<String> suggested = const []}) {
  ensureTimeZones();
  final all = tz.timeZoneDatabase.locations.keys
      .where((z) => z.contains('/') && !z.startsWith('Etc/'))
      .toList()
    ..sort();
  final first = suggested.where(all.contains).toSet().toList();
  return [...first, ...all.where((z) => !first.contains(z))];
}

Future<String?> pickTimeZone(
  BuildContext context, {
  Iterable<String> suggested = const [],
}) async {
  final names = timeZoneNames(suggested: suggested);
  final hit = await showSearchPicker(
    context,
    title: 'Your time zone',
    hint: 'City or region, e.g. Kolkata',
    search: (q) async {
      final s = q.trim().toLowerCase().replaceAll(' ', '_');
      return [
        for (final z in names)
          if (s.isEmpty || z.toLowerCase().contains(s))
            TaxonomyHit(id: z, name: z.replaceAll('_', ' ')),
      ].take(80).toList();
    },
  );
  return hit?.id;
}

/// A list of countries as removable chips, with an "Add" chip.
class CountryChips extends StatelessWidget {
  const CountryChips({
    super.key,
    required this.codes,
    required this.countries,
    required this.onChanged,
    required this.addLabel,
    required this.max,
    this.pickerTitle = 'Choose a country',
  });

  final List<String> codes;
  final List<Country> countries;
  final ValueChanged<List<String>> onChanged;
  final String addLabel;
  final int max;
  final String pickerTitle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in codes)
          InputChip(
            label: Text(countryName(c, countries)),
            onDeleted: () => onChanged([...codes]..remove(c)),
            deleteButtonTooltipMessage: 'Remove ${countryName(c, countries)}',
          ),
        if (codes.length < max)
          ActionChip(
            avatar: const Icon(Icons.add, size: 18),
            label: Text(addLabel),
            onPressed: () async {
              final picked = await pickCountry(
                context,
                countries,
                title: pickerTitle,
                exclude: codes,
              );
              if (picked != null) onChanged([...codes, picked.code]);
            },
          ),
      ],
    );
  }
}
