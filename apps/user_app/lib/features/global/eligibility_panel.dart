import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_state.dart';
import '../../data/global_repository.dart';
import 'global_widgets.dart';

/// "Can I apply?" on a job page. A guide, never a gate: the apply button
/// stays whatever this says, and it always says it is not legal advice.
class EligibilityPanel extends ConsumerWidget {
  const EligibilityPanel({super.key, required this.jobId});
  final String jobId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final signedIn = ref.watch(isSignedInProvider);

    Widget frame(List<Widget> children) => Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('Can I apply?',
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                ...children,
              ],
            ),
          ),
        );

    if (!signedIn) {
      return frame([
        const Text(
          'Sign in to check whether you can work in this job\'s country.',
          style: TextStyle(fontSize: 14.5, height: 1.4),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => context.push(
                '/sign-in?next=${Uri.encodeComponent('/job/$jobId')}'),
            child: const Text('Sign in'),
          ),
        ),
      ]);
    }

    final async = ref.watch(jobEligibilityProvider(jobId));
    return async.when(
      loading: () => frame(const [LinearProgressIndicator(minHeight: 2)]),
      error: (e, _) => frame([
        Text('Could not check this right now. ${globalError(e)}',
            style: const TextStyle(fontSize: 14)),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: () => ref.invalidate(jobEligibilityProvider(jobId)),
            child: const Text('Try again'),
          ),
        ),
        const LegalNotice(notLegalAdvice),
      ]),
      data: (e) => e == null
          ? const SizedBox.shrink()
          : frame([EligibilityDetails(eligibility: e)]),
    );
  }
}

class EligibilityDetails extends StatelessWidget {
  const EligibilityDetails({super.key, required this.eligibility});
  final JobEligibility eligibility;

  @override
  Widget build(BuildContext context) {
    final e = eligibility;
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = eligibilityLook(e.status, scheme);
    final pay = e.pay;
    final approx = approxPayLine(pay);

    Widget bullet(IconData i, Color c, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(i, size: 18, color: c),
              ),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(text,
                      style: const TextStyle(fontSize: 14.5, height: 1.35))),
            ],
          ),
        );

    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 14, bottom: 8),
          child: Text(t,
              style:
                  const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                e.headline,
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: color,
                    height: 1.3),
              ),
            ),
          ],
        ),
        if (e.status == EligibilityStatus.potentiallyEligible) ...[
          const SizedBox(height: 6),
          const Text(
            'You can still apply. The employer decides, and may help with '
            'what is missing.',
            style: TextStyle(fontSize: 13.5, height: 1.4),
          ),
        ],
        if (e.notes.isNotEmpty) ...[
          heading('Good to know'),
          for (final n in e.notes)
            bullet(Icons.info_outline, scheme.onSurfaceVariant, n),
        ],
        if (e.licences.isNotEmpty) ...[
          heading('Licences for this work'),
          for (final l in e.licences) LicenceTile(l),
        ],
        if (pay != null && approx != null) ...[
          heading('Pay in your currency'),
          Text(
            'Converted from '
            '${payRangeLine(pay.amount, null, pay.currency, pay.period)}. '
            'The job pays in ${pay.currency}.',
            style: const TextStyle(fontSize: 14.5, height: 1.4),
          ),
          const SizedBox(height: 4),
          Text(approx,
              style: const TextStyle(
                  fontSize: 15.5, fontWeight: FontWeight.w800)),
          if (conversionSource(pay) != null)
            Text(
              conversionSource(pay)!,
              style: TextStyle(
                  fontSize: 12.5, height: 1.4, color: scheme.onSurfaceVariant),
            ),
        ],
        if (e.officialSources.isNotEmpty) ...[
          heading('Official sources'),
          for (final s in e.officialSources)
            OfficialSourceTile(s, showSummary: false),
        ],
        if (e.country != null)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.push('/countries/${e.country}'),
              icon: const Icon(Icons.menu_book_outlined),
              label: const Text('Read the country guide'),
            ),
          ),
        const SizedBox(height: 8),
        LegalNotice(notLegalAdvice, body: e.disclaimer),
      ],
    );
  }
}
