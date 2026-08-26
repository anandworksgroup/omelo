import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/format.dart';
import '../../core/location.dart';
import '../../core/theme.dart';
import '../../data/job.dart';
import '../../data/jobs_repository.dart';

final jobDetailProvider =
    FutureProvider.family<JobDetail, String>((ref, jobId) async {
  final origin = ref.watch(originProvider).value;
  return ref.watch(jobsRepositoryProvider).detail(
        jobId,
        lat: origin?.lat,
        lng: origin?.lng,
      );
});

class JobDetailScreen extends ConsumerWidget {
  const JobDetailScreen({super.key, required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(jobDetailProvider(jobId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Job'),
        actions: [
          IconButton(
            onPressed: () => _report(context),
            icon: const Icon(Icons.flag_outlined),
            tooltip: 'Report this job',
          ),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'This job could not be loaded.\nIt may have been closed.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => ref.invalidate(jobDetailProvider(jobId)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (d) => _Content(detail: d),
      ),
      bottomNavigationBar: detail.maybeWhen(
        data: (d) => _ApplyBar(detail: d),
        orElse: () => null,
      ),
    );
  }

  void _report(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Report this job',
                  style:
                      TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final r in const [
                'Asked me for money',
                'Asked for bank or ID details',
                'Job does not exist',
                'Misleading pay or hours',
                'Discriminatory requirements',
                'Something else',
              ])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(r),
                  onTap: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Thanks. Our team will review this.')),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Content extends StatelessWidget {
  const _Content({required this.detail});
  final JobDetail detail;

  @override
  Widget build(BuildContext context) {
    final j = detail.job;
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(j.title,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        Row(
          children: [
            Flexible(
              child: Text(j.companyName,
                  style: TextStyle(
                      fontSize: 16,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600)),
            ),
            if (j.companyVerified) ...[
              const SizedBox(width: 6),
              const Icon(Icons.verified, size: 17, color: OmeloTheme.verified),
              const SizedBox(width: 3),
              const Text('Verified',
                  style: TextStyle(
                      fontSize: 12.5,
                      color: OmeloTheme.verified,
                      fontWeight: FontWeight.w700)),
            ],
          ],
        ),
        const SizedBox(height: 20),

        // Pay leads — it is what a worker decides on first.
        Text(
          Fmt.pay(
            min: j.payMin,
            max: j.payMax,
            currency: j.payCurrency,
            period: j.payPeriod,
            negotiable: j.payNegotiable,
          ),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 14),

        _Row(Icons.place_outlined, [
          if (j.distanceKm != null) '${Fmt.distance(j.distanceKm)} from you',
          j.locationText,
        ]),
        _Row(Icons.work_outline, [
          Fmt.workType(j.workType),
          Fmt.workplace(j.workplace),
          ...j.shiftTypes.map(Fmt.shift),
        ]),
        _Row(Icons.schedule, [
          if (detail.hoursPerWeek != null && detail.hoursPerWeek! > 0)
            '${detail.hoursPerWeek} hours/week',
          if (detail.workingDays != null && detail.workingDays! > 0)
            '${detail.workingDays} days/week',
          if (j.isImmediateStart) 'Starts immediately',
        ]),
        _Row(Icons.badge_outlined, [
          Fmt.experience(j.minExperienceMonths, j.acceptsNoExperience),
          if ((j.openings ?? 0) > 1) '${j.openings} openings',
        ]),

        if (j.benefits.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _Heading('What you get'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final b in j.benefits)
                OmeloPill(Fmt.benefit(b),
                    icon: Icons.check,
                    color: OmeloTheme.verified,
                    background: const Color(0x1412805C)),
            ],
          ),
        ],

        if (detail.requiredSkills.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _Heading('What you need'),
          const SizedBox(height: 6),
          Text(
            'Once you build your profile, Omelo will show which of these you '
            'already have.',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          for (final s in detail.requiredSkills)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.circle, size: 6, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s, style: const TextStyle(fontSize: 15))),
                ],
              ),
            ),
          if (detail.preferredSkills.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Helpful, not required',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final s in detail.preferredSkills) OmeloPill(s),
              ],
            ),
          ],
        ],

        if ((detail.description ?? '').isNotEmpty) ...[
          const SizedBox(height: 24),
          const _Heading('The work'),
          const SizedBox(height: 10),
          Text(detail.description!,
              style: const TextStyle(fontSize: 15, height: 1.5)),
        ],

        if (detail.uniformRequired == true ||
            detail.ownVehicleRequired == true ||
            detail.ownToolsRequired == true) ...[
          const SizedBox(height: 24),
          const _Heading('Working conditions'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (detail.ownVehicleRequired == true)
                const OmeloPill('Own vehicle needed',
                    icon: Icons.two_wheeler_outlined),
              if (detail.ownToolsRequired == true)
                const OmeloPill('Own tools needed',
                    icon: Icons.handyman_outlined),
              if (detail.uniformRequired == true)
                const OmeloPill('Uniform required', icon: Icons.checkroom),
            ],
          ),
        ],

        if (detail.stages.isNotEmpty) ...[
          const SizedBox(height: 24),
          const _Heading('Hiring process'),
          const SizedBox(height: 10),
          Text(
            detail.stages.join('  →  '),
            style: const TextStyle(fontSize: 14.5, height: 1.6),
          ),
          if (j.companyResponseHours != null) ...[
            const SizedBox(height: 8),
            Text(
              '${j.companyName} ${Fmt.responseTime(j.companyResponseHours)}.',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
          ],
        ],

        const SizedBox(height: 24),
        const _Heading('About the employer'),
        const SizedBox(height: 10),
        if ((detail.aboutCompany ?? '').isNotEmpty)
          Text(detail.aboutCompany!,
              style: const TextStyle(fontSize: 15, height: 1.5)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (j.companyVerified)
              const OmeloPill('Verified employer',
                  icon: Icons.verified,
                  color: OmeloTheme.verified,
                  background: Color(0x1412805C)),
            if (detail.companyTotalHires != null)
              OmeloPill('${detail.companyTotalHires} hires on Omelo'),
            if (detail.companyResponseRate != null)
              OmeloPill(
                  'Replies to ${detail.companyResponseRate!.round()}% of applications'),
          ],
        ),

        const SizedBox(height: 28),
        // Persistent, non-dismissible anti-fraud line (FR-702).
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.shield_outlined, size: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Omelo will never ask you to pay to apply, interview, or '
                  'start a job. No real employer asks for money, bank details, '
                  'or your original documents.',
                  style: TextStyle(fontSize: 13, height: 1.45),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Posted ${Fmt.posted(j.publishedAt).toLowerCase()}',
            style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700));
}

class _Row extends StatelessWidget {
  const _Row(this.icon, this.parts);
  final IconData icon;
  final List<String?> parts;

  @override
  Widget build(BuildContext context) {
    final text =
        parts.where((e) => e != null && e.isNotEmpty).join(' · ');
    if (text.isEmpty) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 15, height: 1.35))),
        ],
      ),
    );
  }
}

class _ApplyBar extends ConsumerWidget {
  const _ApplyBar({required this.detail});
  final JobDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _apply(context),
                  child: Text(detail.job.quickApplyEnabled
                      ? 'Apply — no resume needed'
                      : 'Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _apply(BuildContext context) {
    // Applying requires an account. The prompt appears here — at the moment
    // the value is obvious — never before the worker has seen real jobs.
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Sign in to apply',
                  style:
                      TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text(
                'It takes about 30 seconds with your phone number. '
                'Your application is saved and sends as soon as you verify.',
                style: TextStyle(fontSize: 15, height: 1.45),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                            'Phone sign-in is the next build step — not wired yet.'),
                      ),
                    );
                  },
                  child: const Text('Continue with phone'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
