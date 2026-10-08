import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/responsive.dart';
import '../../core/theme.dart';
import '../../data/career_repository.dart';
import '../../data/global_repository.dart'
    show Country, countriesProvider, countryName;
import '../../data/identity.dart' show WorkIdentity;
import '../../data/identity_repository.dart' show myIdentitiesProvider;
import '../../data/invitations.dart' show shortDate;
import '../work/work_widgets.dart'
    show WorkNote, WorkPill, WorkTone, workBackButton;
import 'career_widgets.dart';
import 'goal_editor.dart';
import 'plan_checklist.dart';
import '../../core/ui.dart';

/// `/career` — My career.
///
/// Where I am (identity, skills, experience, evidence), where I want to go
/// (a goal), how ready I am, what to build next (courses and Omelo tests),
/// and better jobs for the goal. Without a goal it suggests typical next
/// roles.
class CareerScreen extends ConsumerStatefulWidget {
  const CareerScreen({super.key, this.goalId, this.identityId});

  final String? goalId;
  final String? identityId;

  @override
  ConsumerState<CareerScreen> createState() => _CareerScreenState();
}

class _CareerScreenState extends ConsumerState<CareerScreen> {
  late String? _goalId = widget.goalId;
  late String? _identityId = widget.identityId;
  String? _savingProfession;

  CareerKey get _key => (goal: _goalId, identity: _identityId);

  void _reload() => invalidateCareer(ref);

  // -- Goal actions ------------------------------------------------------------

  Future<void> _setGoal(CareerPath path, String professionId) async {
    final g = path.goal;
    final draft = g == null
        ? GoalDraft(
            workIdentityId: path.identityId,
            professionId: professionId,
            generatePlan: true,
          )
        : GoalDraft(
            id: g.id,
            workIdentityId: g.workIdentityId ?? path.identityId,
            professionId: professionId,
            goalText: g.goalText,
            targetCountries: g.targetCountries,
            targetPayAmount: g.targetPayAmount,
            targetPayPeriod: g.targetPayPeriod,
            targetCurrency: g.targetCurrency,
            targetDate: g.targetDate,
            generatePlan: true,
          );
    setState(() => _savingProfession = professionId);
    try {
      final saved = await ref.read(careerRepositoryProvider).saveGoal(draft);
      if (!mounted) return;
      setState(() => _goalId = saved?.id);
      _reload();
      showCareerSnack(
        context,
        'Goal set. Your plan starts with the skills to build.',
      );
    } catch (e) {
      if (mounted) showCareerSnack(context, careerError(e));
    } finally {
      if (mounted) setState(() => _savingProfession = null);
    }
  }

  Future<void> _chooseAnyRole(CareerPath path) async {
    final hit = await pickProfession(context, ref);
    if (hit != null && mounted) await _setGoal(path, hit.id);
  }

  Future<void> _edit(CareerPath path) async {
    final g = path.goal;
    if (g == null) return;
    final d = GoalDraft.fromGoal(g);
    final saved = await showGoalEditor(
      context,
      initial: GoalDraft(
        id: d.id,
        workIdentityId: d.workIdentityId ?? path.identityId,
        professionId: d.professionId,
        professionName: d.professionName,
        goalText: d.goalText,
        targetCountries: d.targetCountries,
        targetPayAmount: d.targetPayAmount,
        targetPayPeriod: d.targetPayPeriod,
        targetCurrency: d.targetCurrency,
        targetDate: d.targetDate,
        generatePlan: false,
      ),
    );
    if (saved == null || !mounted) return;
    _reload();
    showCareerSnack(context, 'Goal saved.');
  }

  Future<void> _setStatus(CareerGoal g, GoalStatus s) async {
    if (s != GoalStatus.active) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(
            s == GoalStatus.achieved
                ? 'Mark "${g.title}" achieved?'
                : 'Archive "${g.title}"?',
          ),
          content: Text(
            s == GoalStatus.achieved
                ? 'Well done. The goal moves to your past goals, and you can '
                      'choose your next one.'
                : 'The goal and its plan are kept in your past goals. You can '
                      'make it active again later.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                s == GoalStatus.achieved ? 'Mark achieved' : 'Archive',
              ),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    try {
      await ref.read(careerRepositoryProvider).setGoalStatus(g, s);
      if (!mounted) return;
      setState(() => _goalId = s == GoalStatus.active ? g.id : null);
      _reload();
      showCareerSnack(context, switch (s) {
        GoalStatus.achieved => 'Goal achieved. Congratulations!',
        GoalStatus.archived => 'Goal archived.',
        GoalStatus.active => 'Goal is active again.',
      });
    } catch (e) {
      if (mounted) showCareerSnack(context, careerError(e));
    }
  }

  Future<void> _addToPlan(
    CareerPath path, {
    required PlanKind kind,
    required String title,
    String? resourceId,
    String? jobId,
  }) async {
    final g = path.goal;
    if (g == null) return;
    try {
      await ref
          .read(careerRepositoryProvider)
          .addPlanItem(
            goalId: g.id,
            kind: kind,
            title: title,
            position: nextPlanPosition(path.plan),
            resourceId: resourceId,
            jobId: jobId,
          );
      if (!mounted) return;
      _reload();
      showCareerSnack(context, 'Added to your plan.');
    } catch (e) {
      if (mounted) showCareerSnack(context, careerError(e));
    }
  }

  Future<void> _takeTest(CareerPath path, String skillId, String name) async {
    final done = await openAssessment(
      context,
      skillId: skillId,
      skillName: name,
      identityId: path.identityId,
    );
    if (done && mounted) _reload();
  }

  // -- Build -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(careerPathProvider(_key));
    final path = async.valueOrNull;
    final goal = path?.goal;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My career'),
        leading: workBackButton(context, '/profile'),
        actions: [
          if (path != null && goal != null)
            PopupMenuButton<String>(
              tooltip: 'Goal options',
              onSelected: (v) => switch (v) {
                'edit' => _edit(path),
                'achieved' => _setStatus(goal, GoalStatus.achieved),
                'archive' => _setStatus(goal, GoalStatus.archived),
                'active' => _setStatus(goal, GoalStatus.active),
                _ => null,
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit goal')),
                if (goal.isActive) ...[
                  const PopupMenuItem(
                    value: 'achieved',
                    child: Text('Mark achieved'),
                  ),
                  const PopupMenuItem(
                    value: 'archive',
                    child: Text('Archive goal'),
                  ),
                ] else
                  const PopupMenuItem(
                    value: 'active',
                    child: Text('Make active again'),
                  ),
              ],
            ),
        ],
      ),
      body: async.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => needsIdentity(e)
            ? OmeloMessage(
                icon: Icons.badge_outlined,
                title: 'Start with your work identity',
                body:
                    'Your career path starts from the work you do today. '
                    'Add a work identity with your skills first.',
                actionLabel: 'Add a work identity',
                onAction: () => context.push('/identities'),
              )
            : OmeloMessage(
                icon: Icons.cloud_off_outlined,
                title: 'Could not load your career path',
                body: careerError(e),
                actionLabel: 'Try again',
                onAction: _reload,
              ),
        data: (p) => RefreshIndicator(
          onRefresh: () async {
            _reload();
            await ref
                .read(careerPathProvider(_key).future)
                .catchError((_) => p);
          },
          child: _body(context, p),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, CareerPath p) {
    final gutter = Breakpoints.of(context).gutter;
    final countries =
        ref.watch(countriesProvider).valueOrNull ?? const <Country>[];
    final identities =
        (ref.watch(myIdentitiesProvider).valueOrNull ?? const <WorkIdentity>[])
            .where((i) => i.isActive)
            .toList();
    final identity = identities.where((i) => i.id == p.identityId).firstOrNull;
    final home = ref.watch(homeCountryProvider);
    final currentProfessionId = p.currentProfessionId ?? identity?.professionId;

    final market = currentProfessionId == null
        ? null
        : MarketInsightsCard(
            professionId: currentProfessionId,
            professionName: p.currentProfession,
            country: home,
          );

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(gutter, 8, gutter, 40),
      children: [
        ContentWidth(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (identities.length > 1)
                _IdentityChooser(
                  identities: identities,
                  selected: p.identityId,
                  onChanged: (id) => setState(() {
                    _identityId = id;
                    _goalId = null;
                  }),
                ),
              _Header(path: p, countries: countries),
              if (p.hasPath)
                _pathBody(context, p, countries, market)
              else
                _noGoalBody(context, p, market),
              _OtherGoals(
                currentGoalId: p.goal?.id,
                onOpen: (g) => setState(() => _goalId = g.id),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -- No goal: suggestions ------------------------------------------------------

  Widget _noGoalBody(BuildContext context, CareerPath p, Widget? market) {
    final scheme = Theme.of(context).colorScheme;
    final g = p.goal;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (g != null && g.goalText != null) ...[
          const SizedBox(height: 14),
          WorkNote(
            'Your goal: "${g.goalText}". Choose the role it leads to, so '
            'Omelo can show your path.',
            tone: WorkTone.waiting,
            icon: Icons.flag_outlined,
          ),
        ],
        if (market != null) ...[const SizedBox(height: 18), market],
        CareerSection(
          title: 'Roles you could grow into',
          subtitle: p.currentProfession == null
              ? 'Add your profession to your work identity to see typical next steps.'
              : 'Typical next steps from ${p.currentProfession}, and how ready you are.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (p.suggestions.isEmpty)
                Text(
                  p.currentProfession == null
                      ? 'No suggestions yet.'
                      : 'Omelo has no typical next steps for ${p.currentProfession} '
                            'yet. Choose any role you are aiming for.',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              else
                ResponsiveCardGrid(
                  minCardWidth: 300,
                  children: [
                    for (final s in p.suggestions)
                      SuggestionCard(
                        suggestion: s,
                        busy: _savingProfession == s.professionId,
                        onChoose: _savingProfession != null
                            ? null
                            : () => _setGoal(p, s.professionId),
                      ),
                  ],
                ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _savingProfession != null
                      ? null
                      : () => _chooseAnyRole(p),
                  icon: const Icon(Icons.search),
                  label: const Text('Choose any role'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // -- Goal: the path ------------------------------------------------------------

  Widget _pathBody(
    BuildContext context,
    CareerPath p,
    List<Country> countries,
    Widget? market,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final goal = p.goal!;
    final plannedResources = {for (final i in p.plan) ?i.resourceId};
    final plannedJobs = {for (final i in p.plan) ?i.jobId};
    final skillNames = {for (final s in p.skills) s.skillId: s.name};

    final skills = CareerSection(
      title: 'Your skills for ${goal.title}',
      subtitle: p.note,
      trailing: p.identityId == null
          ? null
          : TextButton(
              onPressed: () =>
                  context.push('/identities/${p.identityId}?section=skills'),
              child: const Text('Update skills'),
            ),
      child: SkillGroups(skills: p.skills),
    );

    final development = CareerSection(
      title: 'What to build next',
      subtitle: 'Courses, practice and Omelo tests for each skill to build.',
      child: p.recommended.isEmpty
          ? const WorkNote(
              'You have every skill this role asks for, with good evidence. '
              'Apply to the jobs for your goal.',
              tone: WorkTone.good,
              icon: Icons.celebration_outlined,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in p.recommended)
                  RecommendationCard(
                    recommendation: r,
                    plannedResourceIds: plannedResources,
                    onTakeTest: r.assessment == null
                        ? null
                        : () => _takeTest(p, r.skillId, r.skill),
                    onAddResource: (res) => _addToPlan(
                      p,
                      kind: PlanKind.resource,
                      title: res.title,
                      resourceId: res.id,
                    ),
                  ),
              ],
            ),
    );

    final plan = CareerSection(
      title: 'My plan',
      child: PlanChecklist(
        goalId: goal.id,
        items: p.plan,
        identityId: p.identityId,
        skillNames: skillNames,
        onChanged: _reload,
      ),
    );

    final jobs = CareerSection(
      title: 'Best open jobs for ${goal.title}',
      subtitle: 'Scored for your profile. Apply when you are ready.',
      child: p.jobs.isEmpty
          ? Text(
              'No open jobs for this role right now'
              '${goal.targetCountries.isEmpty ? '' : ' in the countries you chose'}. '
              'Omelo will show them here when they are posted.',
              style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < p.jobs.length; i++)
                  PathJobTile(
                    job: p.jobs[i],
                    rank: i + 1,
                    countries: countries,
                    planned: plannedJobs.contains(p.jobs[i].jobId),
                    onAdd: () => _addToPlan(
                      p,
                      kind: PlanKind.job,
                      title: 'Apply: ${p.jobs[i].title}',
                      jobId: p.jobs[i].jobId,
                    ),
                  ),
              ],
            ),
    );

    final targetMarket = CareerSection(
      title: 'Pay for ${goal.title}',
      subtitle: goal.targetCountries.isEmpty
          ? 'Across open jobs, in your currency.'
          : 'In ${goal.targetCountries.map((c) => countryName(c, countries)).join(', ')} '
                'and remote, in your currency.',
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: MarketPayBlock(pay: p.marketPay, openJobs: p.openJobs),
        ),
      ),
    );

    final licences = p.licences.isEmpty
        ? null
        : CareerSection(
            title: 'Licences you may need',
            subtitle: 'Information only — check the official source.',
            child: Column(
              children: [
                for (final l in p.licences)
                  CareerLicenceTile(licence: l, countries: countries),
              ],
            ),
          );

    final left = [skills, development];
    final right = [
      plan,
      jobs,
      targetMarket,
      ?licences,
      if (market != null)
        Padding(padding: const EdgeInsets.only(top: 24), child: market),
    ];

    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth < Breakpoints.expanded) {
          // Phone: plan first (what to do), then the why.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              plan,
              development,
              skills,
              jobs,
              targetMarket,
              ?licences,
              if (market != null)
                Padding(padding: const EdgeInsets.only(top: 24), child: market),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 11,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: left,
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 10,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: right,
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------

class _IdentityChooser extends StatelessWidget {
  const _IdentityChooser({
    required this.identities,
    required this.selected,
    required this.onChanged,
  });

  final List<WorkIdentity> identities;
  final String? selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text(
          'Career path for',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        for (final i in identities)
          ChoiceChip(
            label: Text(i.label),
            selected: i.id == selected,
            onSelected: (_) {
              if (i.id != selected) onChanged(i.id);
            },
          ),
      ],
    ),
  );
}

/// Where I am → where I want to go, with readiness.
class _Header extends ConsumerWidget {
  const _Header({required this.path, required this.countries});
  final CareerPath path;
  final List<Country> countries;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = path;
    final g = p.goal;
    final scheme = Theme.of(context).colorScheme;
    final now = ref.watch(careerClockProvider)();
    final exp = experienceLine(p.experienceMonths);
    final verified = p.verifiedEmployers ?? 0;
    final wide = Breakpoints.of(context).index >= WindowSize.medium.index;

    final now_ = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('NOW', style: _eyebrow(scheme)),
        const SizedBox(height: 2),
        Text(
          p.currentProfession ?? 'Your work',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        if (exp != null || verified > 0)
          Text(
            [
              ?exp,
              if (verified > 0)
                '$verified verified employer${verified == 1 ? '' : 's'}',
            ].join(' · '),
            style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
          ),
      ],
    );

    if (!p.hasPath) {
      return Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              now_,
              const SizedBox(height: 10),
              Text(
                p.message ?? 'Choose a career goal to see your path.',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final goal = g!;
    final pills = [
      if (!goal.isActive)
        WorkPill(
          goal.status.label,
          tone: goal.status == GoalStatus.achieved
              ? WorkTone.good
              : WorkTone.neutral,
        ),
      for (final c in goal.targetCountries)
        OmeloPill(countryName(c, countries), icon: Icons.place_outlined),
      if (goal.targetPayLine != null)
        OmeloPill(
          'Target ${goal.targetPayLine}',
          icon: Icons.payments_outlined,
        ),
      if (goal.targetDate != null)
        OmeloPill(
          'By ${shortDate(goal.targetDate!, now)}',
          icon: Icons.event_outlined,
        ),
    ];

    final target = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('GOAL', style: _eyebrow(scheme)),
        const SizedBox(height: 2),
        Text(
          goal.title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: scheme.primary,
          ),
        ),
        if (goal.goalText != null && goal.profession != null)
          Text(
            goal.goalText!,
            style: const TextStyle(fontSize: 13.5, height: 1.35),
          ),
      ],
    );

    final transition = Text(
      p.transition?.line ?? 'Omelo has no typical timeline for this move yet.',
      style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
    );

    final arrow = Icon(
      wide ? Icons.arrow_forward : Icons.arrow_downward,
      color: scheme.onSurfaceVariant,
    );

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                ReadinessRing(readiness: p.readiness, size: wide ? 104 : 84),
                const SizedBox(width: 16),
                Expanded(
                  child: wide
                      ? Row(
                          children: [
                            Expanded(child: now_),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: arrow,
                            ),
                            Expanded(child: target),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            now_,
                            const SizedBox(height: 4),
                            arrow,
                            target,
                          ],
                        ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            transition,
            if (pills.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: pills),
            ],
          ],
        ),
      ),
    );
  }

  static TextStyle _eyebrow(ColorScheme scheme) => TextStyle(
    fontSize: 11.5,
    letterSpacing: 1.1,
    fontWeight: FontWeight.w800,
    color: scheme.onSurfaceVariant,
  );
}

/// My other goals (active, achieved or archived): tap to open one.
class _OtherGoals extends ConsumerWidget {
  const _OtherGoals({required this.currentGoalId, required this.onOpen});
  final String? currentGoalId;
  final ValueChanged<CareerGoal> onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final goals =
        (ref.watch(myGoalsProvider).valueOrNull ?? const <CareerGoal>[])
            .where((g) => g.id != currentGoalId)
            .toList();
    if (goals.isEmpty) return const SizedBox.shrink();
    final now = ref.watch(careerClockProvider)();
    return CareerSection(
      title: 'Your other goals',
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          children: [
            for (var i = 0; i < goals.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              ListTile(
                leading: Icon(switch (goals[i].status) {
                  GoalStatus.achieved => Icons.emoji_events_outlined,
                  GoalStatus.archived => Icons.inventory_2_outlined,
                  GoalStatus.active => Icons.flag_outlined,
                }),
                title: Text(
                  goals[i].title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  [
                    goals[i].status.label,
                    if (goals[i].createdAt != null)
                      'set ${shortDate(goals[i].createdAt!, now)}',
                  ].join(' · '),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => onOpen(goals[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
