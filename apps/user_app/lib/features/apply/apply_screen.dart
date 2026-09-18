import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/responsive.dart';
import '../../data/applications_repository.dart';
import '../../data/auth_repository.dart';
import '../../data/identity_repository.dart';
import '../../data/job.dart';
import '../applications/applications_screen.dart';
import '../discover/job_detail_screen.dart';

/// U-50 — Quick apply.
///
/// The contract (A1 §8.1): the worker sees exactly what the employer will
/// receive, AND an explicit statement of what they will not. Naming the limit
/// is what builds trust, not just listing the disclosure.
class ApplyScreen extends ConsumerStatefulWidget {
  const ApplyScreen({super.key, required this.jobId});
  final String jobId;

  @override
  ConsumerState<ApplyScreen> createState() => _ApplyScreenState();
}

class _ApplyScreenState extends ConsumerState<ApplyScreen> {
  bool? _answer;
  bool _busy = false;
  String? _error;

  /// The identity the person picked; null means the default for this job.
  String? _identityId;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(jobDetailProvider(widget.jobId));
    final signedIn = ref.watch(authRepositoryProvider).isSignedIn;
    final scheme = Theme.of(context).colorScheme;

    if (!signedIn) {
      // Should not normally happen — the job screen gates this — but never
      // dead-end (UC-6).
      return Scaffold(
        appBar: AppBar(title: const Text('Apply')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('Sign in to apply', style: TextStyle(fontSize: 18)),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () =>
                      context.push('/sign-in?next=/apply/${widget.jobId}'),
                  child: const Text('Sign in'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Apply')),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) =>
            const Center(child: Text('Could not load this job.')),
        data: (d) {
          final j = d.job;
          final question = d.questions.isEmpty ? null : d.questions.first;
          final identities = (ref.watch(myIdentitiesProvider).value ?? const [])
              .where((i) => i.isActive)
              .toList();
          final identity = _selectedIdentity(identities, j);

          return ContentWidth.reading(
            child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Text(j.title,
                  style: const TextStyle(
                      fontSize: 21, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(j.companyName,
                  style: TextStyle(
                      fontSize: 15, color: scheme.onSurfaceVariant)),
              const SizedBox(height: 6),
              Text(
                Fmt.pay(
                  min: j.payMin,
                  max: j.payMax,
                  currency: j.payCurrency,
                  period: j.payPeriod,
                ),
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),

              if (identities.length > 1) ...[
                const SizedBox(height: 26),
                const _Heading('Apply as'),
                const SizedBox(height: 10),
                for (final i in identities)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _IdentityOption(
                      identity: i,
                      selected: i.id == identity?.id,
                      onTap: () => setState(() => _identityId = i.id),
                    ),
                  ),
              ],
              if (identity != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.visibility_outlined,
                        size: 18, color: scheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(applyPreviewLine(identity),
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 26),
              const _Heading('What the employer will see'),
              const SizedBox(height: 10),
              _Bullet(Icons.person_outline, 'Your name and contact details'),
              _Bullet(
                  Icons.work_outline,
                  identity != null
                      ? 'Your ${identity.label} profile — its skills and experience'
                      : 'Your work profile${j.professionName != null ? ' as ${j.professionName}' : ''}'),
              _Bullet(Icons.place_outlined, 'Your area — not your exact address'),
              if (question != null)
                _Bullet(Icons.help_outline, 'Your answer to their question'),

              const SizedBox(height: 22),
              const _Heading('What they will NOT see'),
              const SizedBox(height: 10),
              _Bullet(Icons.description_outlined,
                  'Your documents — ID, licence or certificates',
                  negative: true),
              _Bullet(Icons.visibility_off_outlined,
                  'Anything you have not chosen to share',
                  negative: true),
              if (identities.length > 1)
                _Bullet(Icons.layers_outlined,
                    'Your other work identities', negative: true),
              const SizedBox(height: 6),
              Text(
                'If they need a document later, they have to ask, and you can '
                'say no or take the access back at any time.',
                style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: scheme.onSurfaceVariant),
              ),

              if (question != null) ...[
                const SizedBox(height: 28),
                const _Heading('One question from this employer'),
                const SizedBox(height: 12),
                Text(question.prompt,
                    style: const TextStyle(
                        fontSize: 15.5, fontWeight: FontWeight.w600)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _Choice(
                        label: 'Yes',
                        selected: _answer == true,
                        onTap: () => setState(() => _answer = true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Choice(
                        label: 'No',
                        selected: _answer == false,
                        onTap: () => setState(() => _answer = false),
                      ),
                    ),
                  ],
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 20),
                Text(_error!,
                    style: TextStyle(color: scheme.error, fontSize: 14)),
              ],

              const SizedBox(height: 30),
              FilledButton(
                onPressed: _busy ||
                        (question != null &&
                            question.isRequired &&
                            _answer == null)
                    ? null
                    : () => _submit(d, question, identity),
                child: _busy
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Send application'),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.shield_outlined, size: 18),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Omelo will never ask you to pay to apply. No real '
                        'employer asks for money to give you a job.',
                        style: TextStyle(fontSize: 12.5, height: 1.45),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            ),
          );
        },
      ),
    );
  }

  WorkIdentity? _selectedIdentity(List<WorkIdentity> active, Job j) {
    for (final i in active) {
      if (i.id == _identityId) return i;
    }
    return defaultIdentityForJob(active,
        jobProfessionId: j.professionId, jobProfessionName: j.professionName);
  }

  Future<void> _submit(
      JobDetail d, JobQuestion? question, WorkIdentity? identity) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    final res = await ref.read(applicationsRepositoryProvider).apply(
          jobId: d.job.id,
          companyId: d.job.companyId!,
          workIdentityId: identity?.id,
          answers: question == null
              ? null
              : {
                  'question_id': question.id,
                  'prompt': question.prompt,
                  'answer': _answer,
                },
        );

    if (!mounted) return;

    if (!res.ok) {
      setState(() {
        _busy = false;
        _error = res.error;
      });
      return;
    }

    ref.invalidate(myApplicationsProvider);
    setState(() => _busy = false);

    if (!mounted) return;
    await showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _SentSheet(companyName: d.job.companyName),
    );
    if (mounted) context.go('/applications');
  }
}

class _SentSheet extends StatelessWidget {
  const _SentSheet({required this.companyName});
  final String companyName;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.check_circle,
                size: 44, color: OmeloTheme.verified),
            const SizedBox(height: 16),
            const Text('Application sent',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(
              'You will see exactly what happens next — including when '
              '$companyName opens it. If nothing happens, we will tell you '
              'that too.',
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('See my applications'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700));
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.icon, this.text, {this.negative = false});
  final IconData icon;
  final String text;
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            negative ? Icons.block : icon,
            size: 17,
            color: negative ? scheme.onSurfaceVariant : OmeloTheme.verified,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Text(text,
                style: const TextStyle(fontSize: 14.5, height: 1.4)),
          ),
        ],
      ),
    );
  }
}

class _IdentityOption extends StatelessWidget {
  const _IdentityOption({
    required this.identity,
    required this.selected,
    required this.onTap,
  });
  final WorkIdentity identity;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer.withValues(alpha: 0.5) : null,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: selected ? scheme.primary : scheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(identity.label,
                      style: const TextStyle(
                          fontSize: 15.5, fontWeight: FontWeight.w700)),
                  if (identity.professionName != null &&
                      identity.professionName != identity.label)
                    Text(identity.professionName!,
                        style: TextStyle(
                            fontSize: 13, color: scheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (identity.isPrimary) const OmeloPill('Main'),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 52,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : null,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: selected ? scheme.onPrimaryContainer : null,
          ),
        ),
      ),
    );
  }
}
