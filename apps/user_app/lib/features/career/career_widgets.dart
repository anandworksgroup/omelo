import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../core/theme.dart';
import '../../data/career_repository.dart';
import '../../data/global_repository.dart'
    show Country, countriesProvider, countryName, myMobilityProvider;
import '../../data/identity_repository.dart' show myIdentitiesProvider;
import '../global/global_widgets.dart' show eligibilityLook, openOfficialLink;
import '../work/work_widgets.dart' show WorkPill, WorkTone;

void showCareerSnack(BuildContext context, String text) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// The phone's clock, replaceable in tests (assessment countdown, "today").
final careerClockProvider = Provider<DateTime Function()>((_) => DateTime.now);

/// Where the worker lives: the mobility profile, else the onboarding choice.
final homeCountryProvider = Provider.autoDispose<String?>((ref) {
  final mobility = ref.watch(myMobilityProvider).valueOrNull;
  return mobility?.profile.currentCountry ??
      ref.watch(appPrefsProvider).valueOrNull?.country.toUpperCase();
});

/// Opens an Omelo skill assessment. Returns true when one was submitted.
Future<bool> openAssessment(
  BuildContext context, {
  required String skillId,
  required String skillName,
  String? identityId,
}) async {
  final uri = Uri(
    path: '/career/assessment/$skillId',
    queryParameters: {
      'name': skillName,
      'identity': ?identityId,
    },
  );
  final done = await context.push<bool>(uri.toString());
  return done == true;
}

// ---------------------------------------------------------------------------
// Small pieces
// ---------------------------------------------------------------------------

/// A titled block.
class CareerSection extends StatelessWidget {
  const CareerSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 17.5, fontWeight: FontWeight.w800),
                ),
              ),
              ?trailing,
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 3),
            Text(
              subtitle!,
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

/// Big readiness ring: "62%" with "ready" underneath.
class ReadinessRing extends StatelessWidget {
  const ReadinessRing({super.key, required this.readiness, this.size = 96});
  final int? readiness;
  final double size;

  static Color colorFor(int? r, ColorScheme scheme) {
    if (r == null) return scheme.outline;
    if (r >= 75) return OmeloTheme.verified;
    if (r >= 40) return scheme.primary;
    return OmeloTheme.warning;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final r = readiness;
    return Semantics(
      label: r == null ? 'Readiness not measured yet' : 'You are $r percent ready',
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: size,
              height: size,
              child: CircularProgressIndicator(
                value: (r ?? 0) / 100,
                strokeWidth: size / 11,
                backgroundColor: scheme.surfaceContainerHighest,
                color: colorFor(r, scheme),
              ),
            ),
            ExcludeSemantics(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r == null ? '–' : '$r%',
                    style: TextStyle(fontSize: size * 0.24, fontWeight: FontWeight.w900),
                  ),
                  Text(
                    'ready',
                    style: TextStyle(
                      fontSize: size * 0.12,
                      color: scheme.onSurfaceVariant,
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

/// A slim bar with "62% ready" beside it.
class ReadinessBar extends StatelessWidget {
  const ReadinessBar({super.key, required this.readiness});
  final int? readiness;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (readiness ?? 0) / 100,
              minHeight: 8,
              backgroundColor: scheme.surfaceContainerHighest,
              color: ReadinessRing.colorFor(readiness, scheme),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          readiness == null ? 'Not measured' : '$readiness% ready',
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Suggestions (no goal yet)
// ---------------------------------------------------------------------------

class SuggestionCard extends StatelessWidget {
  const SuggestionCard({
    super.key,
    required this.suggestion,
    required this.onChoose,
    this.busy = false,
  });

  final CareerSuggestion suggestion;
  final VoidCallback? onChoose;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              s.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ReadinessBar(readiness: s.readiness),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                WorkPill(typicalTimeLabel(s.typicalMonths), icon: Icons.schedule),
                WorkPill(
                  openJobsLabel(s.openJobs),
                  icon: Icons.work_outline,
                  tone: s.openJobs > 0 ? WorkTone.waiting : WorkTone.neutral,
                ),
              ],
            ),
            if (s.missing.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                'Skills to build: ${s.missing.take(4).join(', ')}'
                '${s.missing.length > 4 ? ' and ${s.missing.length - 4} more' : ''}',
                style: TextStyle(fontSize: 13.5, height: 1.35, color: scheme.onSurfaceVariant),
              ),
            ] else if (s.readiness != null) ...[
              const SizedBox(height: 10),
              Text(
                'You already list every skill this role needs.',
                style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.tonal(
              onPressed: busy ? null : onChoose,
              child: Text(busy ? 'Saving…' : 'Set as my goal'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skills
// ---------------------------------------------------------------------------

(IconData, Color) skillLook(SkillStatus s, ColorScheme scheme) => switch (s) {
  SkillStatus.strong => (Icons.check_circle, OmeloTheme.verified),
  SkillStatus.weak => (Icons.trending_up, OmeloTheme.warning),
  SkillStatus.missing => (Icons.radio_button_unchecked, scheme.onSurfaceVariant),
};

/// Skills grouped Strong / Weak / Missing, with what backs each one.
class SkillGroups extends StatelessWidget {
  const SkillGroups({super.key, required this.skills});
  final List<PathSkill> skills;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final groups = groupSkills(skills);
    if (groups.isEmpty) {
      return Text(
        'Omelo does not have a skill list for this role yet.',
        style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (status, list) in groups) ...[
          Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 6),
            child: Text(
              '${status.label} (${list.length})',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: skillLook(status, scheme).$2,
              ),
            ),
          ),
          Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: Column(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0) const Divider(height: 1),
                  _SkillRow(list[i]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SkillRow extends StatelessWidget {
  const _SkillRow(this.skill);
  final PathSkill skill;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = skillLook(skill.status, scheme);
    final level = proficiencyWords(skill.proficiency);
    final evidence = skill.evidenceLabel;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  skill.name,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OmeloPill(importanceLabel(skill.importance)),
                    if (evidence != null)
                      WorkPill(
                        evidence,
                        icon: skill.verified || skill.evidence == 'assessment'
                            ? Icons.verified
                            : null,
                        tone: skill.status == SkillStatus.strong
                            ? WorkTone.good
                            : WorkTone.neutral,
                      ),
                    if (level != null) OmeloPill('Level: $level'),
                  ],
                ),
                if (skill.weakReason != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    skill.weakReason!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Recommended development
// ---------------------------------------------------------------------------

class RecommendationCard extends ConsumerWidget {
  const RecommendationCard({
    super.key,
    required this.recommendation,
    required this.onTakeTest,
    this.onAddResource,
    this.plannedResourceIds = const {},
  });

  final Recommendation recommendation;
  final VoidCallback? onTakeTest;
  final ValueChanged<LearningResource>? onAddResource;
  final Set<String> plannedResourceIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = recommendation;
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(careerClockProvider)();
    final a = r.assessment;
    final passed = a?.last?.passed ?? false;
    final others = r.otherResources;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.skill,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                WorkPill(
                  r.status == SkillStatus.missing ? 'Missing' : 'Weak',
                  tone: r.status == SkillStatus.missing
                      ? WorkTone.neutral
                      : WorkTone.warning,
                ),
              ],
            ),
            if (a != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.quiz_outlined, color: scheme.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            a.title,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (a.detailLine.isNotEmpty) a.detailLine,
                        'Pass to add "Passed Omelo test" evidence to this skill.',
                      ].join('. '),
                      style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                    if (a.lastLine(now) != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        a.lastLine(now)!,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: passed ? OmeloTheme.verified : scheme.onSurface,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.icon(
                        onPressed: onTakeTest,
                        icon: const Icon(Icons.play_arrow, size: 20),
                        label: Text(switch (a.last?.status) {
                          'in_progress' => 'Continue the test',
                          'failed' || 'expired' => 'Try the test again',
                          'passed' => 'Take the test again',
                          _ => 'Take the test',
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (others.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final res in others)
                ResourceTile(
                  resource: res,
                  planned: plannedResourceIds.contains(res.id),
                  onAdd: onAddResource == null ? null : () => onAddResource!(res),
                ),
            ],
            if (a == null && others.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'No course or test listed for this skill yet. Ask your '
                  'employer about training on the job, or add it to your '
                  'profile once you have used it.',
                  style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class ResourceTile extends StatelessWidget {
  const ResourceTile({
    super.key,
    required this.resource,
    this.onAdd,
    this.planned = false,
  });

  final LearningResource resource;
  final VoidCallback? onAdd;
  final bool planned;

  @override
  Widget build(BuildContext context) {
    final r = resource;
    final scheme = Theme.of(context).colorScheme;
    final link = r.link;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Icons.school_outlined, size: 20, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.title,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
                if (r.description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    r.description!,
                    style: const TextStyle(fontSize: 13.5, height: 1.35),
                  ),
                ],
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OmeloPill(r.kindLabel),
                    if (r.costLabel != null)
                      WorkPill(
                        r.costLabel!,
                        icon: Icons.payments_outlined,
                        tone: r.cost == 'free' || r.cost == 'employer_sponsored'
                            ? WorkTone.good
                            : WorkTone.neutral,
                      ),
                    if (r.hoursLabel != null)
                      OmeloPill(r.hoursLabel!, icon: Icons.schedule),
                    if (r.provider != null) OmeloPill(r.provider!),
                  ],
                ),
                if (link != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 36),
                    ),
                    onPressed: () => openOfficialLink(context, link),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: Text('Open ${link.host}'),
                  ),
              ],
            ),
          ),
          if (onAdd != null)
            planned
                ? const Tooltip(
                    message: 'In your plan',
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.playlist_add_check, color: OmeloTheme.verified),
                    ),
                  )
                : IconButton(
                    tooltip: 'Add to my plan',
                    icon: const Icon(Icons.playlist_add),
                    onPressed: onAdd,
                  ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Licences, market, jobs
// ---------------------------------------------------------------------------

class CareerLicenceTile extends StatelessWidget {
  const CareerLicenceTile({super.key, required this.licence, required this.countries});
  final CareerLicence licence;
  final List<Country> countries;

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
                children: [
                  Expanded(
                    child: Text(
                      l.name,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (l.country != null) OmeloPill(countryName(l.country, countries)),
                ],
              ),
              if (l.description != null) ...[
                const SizedBox(height: 4),
                Text(l.description!, style: const TextStyle(fontSize: 14, height: 1.4)),
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
                          color: link == null ? scheme.onSurfaceVariant : scheme.primary,
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

/// Pay range for a role, in its own currency, or "Not enough data".
class MarketPayBlock extends StatelessWidget {
  const MarketPayBlock({super.key, required this.pay, this.openJobs, this.note});
  final MarketPay? pay;
  final int? openJobs;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final detail = marketPayDetail(pay);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Monthly pay (middle half of jobs)',
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 2),
        Text(
          marketPayRange(pay),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: pay == null ? scheme.onSurfaceVariant : null,
          ),
        ),
        if (detail != null && detail.isNotEmpty)
          Text(detail, style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)),
        if (pay == null)
          Text(
            note ?? 'Too few open jobs show pay to give a fair range.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        if (openJobs != null) ...[
          const SizedBox(height: 8),
          WorkPill(openJobsLabel(openJobs!), icon: Icons.work_outline),
        ],
      ],
    );
  }
}

class PathJobTile extends StatelessWidget {
  const PathJobTile({
    super.key,
    required this.job,
    required this.rank,
    required this.countries,
    this.onAdd,
    this.planned = false,
  });

  final PathJob job;
  final int rank;
  final List<Country> countries;
  final VoidCallback? onAdd;
  final bool planned;

  @override
  Widget build(BuildContext context) {
    final j = job;
    final scheme = Theme.of(context).colorScheme;
    final place = [
      ?j.locationText,
      if (j.country != null) countryName(j.country, countries),
    ].join(', ');
    final elig = j.eligibility;
    final (eIcon, eColor) = eligibilityLook(elig, scheme);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/job/${j.jobId}?from=recommended&rank=$rank'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      j.title,
                      style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
                    ),
                    if (j.company != null || place.isNotEmpty)
                      Text(
                        [?j.company, if (place.isNotEmpty) place].join(' · '),
                        style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        if (j.scoreLabel != null)
                          OmeloPill(
                            j.scoreLabel!,
                            icon: Icons.auto_awesome,
                            color: scheme.onPrimaryContainer,
                            background: scheme.primaryContainer,
                          ),
                        if (elig != null)
                          OmeloPill(
                            elig.label,
                            icon: eIcon,
                            color: eColor,
                            background: eColor.withValues(alpha: 0.12),
                          ),
                      ],
                    ),
                    if (j.missingSkills.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Skills to build: ${j.missingSkills.join(', ')}',
                        style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              if (onAdd != null)
                planned
                    ? const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.playlist_add_check, color: OmeloTheme.verified),
                      )
                    : IconButton(
                        tooltip: 'Add to my plan',
                        icon: const Icon(Icons.playlist_add),
                        onPressed: onAdd,
                      ),
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Icon(Icons.chevron_right),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Market for your role
// ---------------------------------------------------------------------------

/// Open jobs, pay and wanted skills for a role in one country.
class MarketInsightsCard extends ConsumerWidget {
  const MarketInsightsCard({
    super.key,
    required this.professionId,
    this.professionName,
    this.country,
  });

  final String professionId;
  final String? professionName;
  final String? country;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final countries = ref.watch(countriesProvider).valueOrNull ?? const <Country>[];
    final async = ref.watch(
      marketInsightsProvider((profession: professionId, country: country)),
    );
    final role = async.valueOrNull?.profession ?? professionName ?? 'your role';
    final where = country == null ? '' : ' in ${countryName(country, countries)}';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.insights_outlined, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Market for $role$where',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: LinearProgressIndicator(),
              ),
              error: (e, _) => Text(
                careerError(e),
                style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
              ),
              data: (m) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MarketPayBlock(pay: m.pay, note: m.note),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      WorkPill(openJobsLabel(m.openJobs), icon: Icons.work_outline),
                      if (m.remoteJobs > 0) OmeloPill('${m.remoteJobs} remote'),
                      if (m.sponsoredJobs > 0)
                        OmeloPill('${m.sponsoredJobs} with visa sponsorship'),
                    ],
                  ),
                  if (m.skillsInDemand.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      'Skills employers ask for',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final s in m.skillsInDemand.take(6))
                          OmeloPill('${s.name} · ${s.jobs}'),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home card
// ---------------------------------------------------------------------------

/// Home: "Your goal: Industrial Electrician" or "Where next?" — only for a
/// signed-in worker with a work identity. Opens My career.
class CareerHomeCard extends ConsumerWidget {
  const CareerHomeCard({super.key, this.padding = EdgeInsets.zero});
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identities = ref.watch(myIdentitiesProvider).valueOrNull;
    if (identities == null || !identities.any((i) => i.isActive)) {
      return const SizedBox.shrink();
    }
    final goals = ref.watch(myGoalsProvider).valueOrNull ?? const <CareerGoal>[];
    final active = goals.where((g) => g.isActive).firstOrNull;
    final scheme = Theme.of(context).colorScheme;
    final title = active == null ? 'Where next in your career?' : 'Your goal: ${active.title}';
    final body = active == null
        ? 'See roles you could grow into, and what it takes to get there.'
        : 'See how ready you are, the skills to build and better jobs.';
    return Padding(
      padding: padding,
      child: Material(
        color: scheme.secondaryContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.push('/career'),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Icon(Icons.trending_up, size: 30, color: scheme.onSecondaryContainer),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          body,
                          style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
                        ),
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
