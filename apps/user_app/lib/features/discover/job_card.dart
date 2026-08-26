import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../core/theme.dart';
import '../../data/job.dart';

/// The single most-seen component in the app.
///
/// Mandatory on every card (A1 §6.4): distance, pay WITH period, benefits,
/// verification badge, and the employer's real response behaviour. The last
/// one is what makes the marketplace honest — an employer who ignores
/// applications carries that number on every job they post.
class JobCard extends StatelessWidget {
  const JobCard({
    super.key,
    required this.job,
    required this.onTap,
    this.onSave,
    this.saved = false,
  });

  final Job job;
  final VoidCallback onTap;
  final VoidCallback? onSave;
  final bool saved;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final responseText = Fmt.responseTime(job.companyResponseHours);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + save
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      job.title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700, height: 1.25),
                    ),
                  ),
                  if (onSave != null)
                    IconButton(
                      onPressed: onSave,
                      visualDensity: VisualDensity.compact,
                      icon: Icon(
                        saved ? Icons.bookmark : Icons.bookmark_border,
                        color: saved ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      tooltip: saved ? 'Saved' : 'Save job',
                    ),
                ],
              ),

              // Company + verification
              Row(
                children: [
                  Flexible(
                    child: Text(
                      job.companyName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (job.companyVerified) ...[
                    const SizedBox(width: 6),
                    const Icon(Icons.verified,
                        size: 15, color: OmeloTheme.verified),
                  ],
                ],
              ),
              const SizedBox(height: 8),

              // Distance + location — the primary filter for most workers
              Row(
                children: [
                  Icon(Icons.place_outlined,
                      size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  if (job.distanceKm != null) ...[
                    Text(
                      Fmt.distance(job.distanceKm),
                      style: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w700),
                    ),
                    Text(' · ',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ],
                  Expanded(
                    child: Text(
                      job.locationText ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 13.5, color: scheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Pay — always with its period
              Text(
                Fmt.pay(
                  min: job.payMin,
                  max: job.payMax,
                  currency: job.payCurrency,
                  period: job.payPeriod,
                  negotiable: job.payNegotiable,
                ),
                style: const TextStyle(
                    fontSize: 16.5, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),

              // Work type, shift, and the badges that matter most
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  OmeloPill(Fmt.workType(job.workType)),
                  for (final s in job.shiftTypes.take(1)) OmeloPill(Fmt.shift(s)),
                  if (job.acceptsNoExperience)
                    const OmeloPill(
                      'No experience needed',
                      icon: Icons.check_circle_outline,
                      color: OmeloTheme.verified,
                      background: Color(0x1A12805C),
                    ),
                  if (job.isImmediateStart)
                    const OmeloPill('Immediate start',
                        icon: Icons.bolt_outlined),
                ],
              ),

              if (job.benefits.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final b in job.benefits.take(3))
                      OmeloPill('+ ${Fmt.benefit(b)}'),
                    if (job.benefits.length > 3)
                      OmeloPill('+${job.benefits.length - 3} more'),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              Divider(color: scheme.outlineVariant, height: 1),
              const SizedBox(height: 10),

              // Freshness + employer honesty signal
              Row(
                children: [
                  Text(
                    Fmt.posted(job.publishedAt),
                    style: TextStyle(
                        fontSize: 12.5, color: scheme.onSurfaceVariant),
                  ),
                  if (responseText != null) ...[
                    Text(' · ',
                        style: TextStyle(
                            fontSize: 12.5, color: scheme.onSurfaceVariant)),
                    Flexible(
                      child: Text(
                        responseText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                            fontStyle: FontStyle.italic),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    'View',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                  Icon(Icons.chevron_right, size: 18, color: scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
