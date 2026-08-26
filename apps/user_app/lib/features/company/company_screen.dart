import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/location.dart';
import '../../core/theme.dart';
import '../../data/job.dart';
import '../../data/jobs_repository.dart';
import '../discover/job_card.dart';

class CompanyView {
  CompanyView({
    required this.id,
    required this.name,
    required this.about,
    required this.isVerified,
    required this.sizeBand,
    required this.foundedYear,
    required this.website,
    required this.totalHires,
    required this.responseRatePct,
    required this.medianResponseHours,
    required this.industry,
    required this.openJobs,
  });

  final String id;
  final String name;
  final String? about;
  final bool isVerified;
  final String? sizeBand;
  final int? foundedYear;
  final String? website;
  final int totalHires;
  final num? responseRatePct;
  final int? medianResponseHours;
  final String? industry;
  final List<Job> openJobs;
}

final companyProvider =
    FutureProvider.family<CompanyView, String>((ref, companyId) async {
  final db = ref.watch(supabaseProvider);
  final origin = ref.watch(originProvider).value;

  final row = await db
      .from('companies')
      .select('''
        id, display_name, about, is_verified, size_band, founded_year, website,
        total_hires, response_rate_pct, median_response_hours,
        industries ( name )
      ''')
      .eq('id', companyId)
      .single();

  // Reuse the discovery RPC so distances are computed the same way
  // everywhere, then filter to this employer.
  final repo = ref.watch(jobsRepositoryProvider);
  final near = await repo.nearby(
    lat: origin?.lat ?? 28.6315,
    lng: origin?.lng ?? 77.2167,
    filters: const JobFilters(radiusKm: 200),
    limit: 200,
  );

  return CompanyView(
    id: row['id'] as String,
    name: (row['display_name'] ?? '') as String,
    about: row['about'] as String?,
    isVerified: (row['is_verified'] ?? false) as bool,
    sizeBand: row['size_band'] as String?,
    foundedYear: (row['founded_year'] as num?)?.toInt(),
    website: row['website'] as String?,
    totalHires: (row['total_hires'] as num?)?.toInt() ?? 0,
    responseRatePct: row['response_rate_pct'] as num?,
    medianResponseHours: (row['median_response_hours'] as num?)?.toInt(),
    industry: row['industries'] == null
        ? null
        : Map<String, dynamic>.from(row['industries'] as Map)['name'] as String?,
    openJobs: near.where((j) => j.companyId == companyId).toList(),
  );
});

class CompanyScreen extends ConsumerWidget {
  const CompanyScreen({super.key, required this.companyId});
  final String companyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(companyProvider(companyId));
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Employer')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.business_outlined, size: 48),
                const SizedBox(height: 16),
                const Text('Could not load this employer.',
                    style: TextStyle(fontSize: 16)),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => ref.invalidate(companyProvider(companyId)),
                  child: const Text('Try again'),
                ),
              ],
            ),
          ),
        ),
        data: (c) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 52,
                  width: 52,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    c.name.isEmpty ? '?' : c.name.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.name,
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            c.isVerified
                                ? Icons.verified
                                : Icons.verified_outlined,
                            size: 15,
                            color: c.isVerified
                                ? OmeloTheme.verified
                                : scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            c.isVerified ? 'Verified employer' : 'Not verified',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: c.isVerified
                                  ? OmeloTheme.verified
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (!c.isVerified) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(13),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  'Omelo has not confirmed this employer yet. Be careful, and '
                  'never pay money or hand over original documents to get a job.',
                  style: TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: scheme.onSurfaceVariant),
                ),
              ),
            ],

            const SizedBox(height: 22),

            // Hiring behaviour — the honesty signal (FR-334)
            Row(
              children: [
                Expanded(
                  child: _Stat(
                    value: c.responseRatePct != null
                        ? '${c.responseRatePct!.round()}%'
                        : '—',
                    label: 'Replies to\napplications',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    value: c.medianResponseHours != null
                        ? '${(c.medianResponseHours! / 24).round()}d'
                        : '—',
                    label: 'Typical\nreply time',
                  ),
                ),
                Expanded(
                  child: _Stat(
                    value: '${c.totalHires}',
                    label: 'Hired\nthrough Omelo',
                  ),
                ),
              ],
            ),

            if ((c.about ?? '').isNotEmpty) ...[
              const SizedBox(height: 26),
              const Text('About',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(c.about!,
                  style: const TextStyle(fontSize: 15, height: 1.5)),
            ],

            const SizedBox(height: 20),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (c.industry != null) OmeloPill(c.industry!),
                if (c.sizeBand != null) OmeloPill('${c.sizeBand} people'),
                if (c.foundedYear != null) OmeloPill('Since ${c.foundedYear}'),
              ],
            ),

            const SizedBox(height: 30),
            Text(
              c.openJobs.isEmpty
                  ? 'No open jobs right now'
                  : '${c.openJobs.length} open job${c.openJobs.length == 1 ? '' : 's'}',
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),

            if (c.openJobs.isEmpty)
              Text(
                'This employer has nothing posted at the moment.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14),
              )
            else
              for (final j in c.openJobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: JobCard(
                    job: j,
                    onTap: () => context.push('/job/${j.id}'),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
              fontSize: 11.5, height: 1.3, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
