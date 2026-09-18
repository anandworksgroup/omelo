import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'job.dart';

final supabaseProvider = Provider<SupabaseClient>((_) => Supabase.instance.client);

final jobsRepositoryProvider = Provider<JobsRepository>(
  (ref) => JobsRepository(ref.watch(supabaseProvider)),
);

/// Filters applied to discovery. Every field maps to a parameter of
/// `omelo_nearby_jobs`, so filtering happens in the database, never by
/// discarding rows the server already sent.
class JobFilters {
  const JobFilters({
    this.radiusKm = 15,
    this.categoryId,
    this.workTypes,
    this.shiftTypes,
    this.search,
    this.noExperienceOnly = false,
    this.minPayMonthly,
  });

  final int radiusKm;
  final String? categoryId;
  final List<String>? workTypes;
  final List<String>? shiftTypes;
  final String? search;
  final bool noExperienceOnly;
  final num? minPayMonthly;

  JobFilters copyWith({
    int? radiusKm,
    String? categoryId,
    List<String>? workTypes,
    List<String>? shiftTypes,
    String? search,
    bool? noExperienceOnly,
    num? minPayMonthly,
    bool clearCategory = false,
    bool clearSearch = false,
    bool clearPay = false,
  }) =>
      JobFilters(
        radiusKm: radiusKm ?? this.radiusKm,
        categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
        workTypes: workTypes ?? this.workTypes,
        shiftTypes: shiftTypes ?? this.shiftTypes,
        search: clearSearch ? null : (search ?? this.search),
        noExperienceOnly: noExperienceOnly ?? this.noExperienceOnly,
        minPayMonthly: clearPay ? null : (minPayMonthly ?? this.minPayMonthly),
      );

  /// Count of filters the user actively set, for the filter button badge.
  int get activeCount => [
        categoryId != null,
        (workTypes ?? const []).isNotEmpty,
        (shiftTypes ?? const []).isNotEmpty,
        noExperienceOnly,
        minPayMonthly != null,
        radiusKm != 15,
      ].where((e) => e).length;
}

class JobsRepository {
  JobsRepository(this._db);
  final SupabaseClient _db;

  /// Distance-sorted discovery. Callable while signed out (UC-1) — a worker
  /// must see real jobs before being asked to create an account.
  Future<List<Job>> nearby({
    required double lat,
    required double lng,
    JobFilters filters = const JobFilters(),
    int limit = 20,
    int offset = 0,
  }) async {
    final rows = await _db.rpc('omelo_nearby_jobs', params: {
      'p_lat': lat,
      'p_lng': lng,
      'p_radius_km': filters.radiusKm,
      'p_category_id': filters.categoryId,
      'p_work_types': filters.workTypes,
      'p_shift_types': filters.shiftTypes,
      'p_limit': limit,
      'p_offset': offset,
      'p_search': filters.search,
      'p_no_experience': filters.noExperienceOnly,
      'p_min_pay_monthly': filters.minPayMonthly,
    });

    return (rows as List)
        .map((r) => Job.fromRpc(Map<String, dynamic>.from(r as Map)))
        .toList();
  }

  /// Full detail for one job. Uses PostgREST embeds so it is a single
  /// round trip; RLS decides what comes back.
  Future<JobDetail> detail(String jobId, {double? lat, double? lng}) async {
    final row = await _db.from('jobs').select('''
          id, title, description, responsibilities, hours_per_week, working_days,
          pay_min, pay_max, pay_period, pay_currency, pay_negotiable,
          work_type, workplace_type, shift_types, location_text,
          accepts_no_experience, min_experience_months, is_immediate_start,
          quick_apply_enabled, openings, application_method, walk_in_details,
          contact_phone, uniform_required, own_vehicle_required,
          own_tools_required, visa_sponsorship, published_at, profession_id,
          companies!inner ( id, slug, display_name, about, is_verified,
                            total_hires, response_rate_pct, median_response_hours ),
          job_categories ( slug ),
          professions ( name ),
          job_benefits ( benefit_type ),
          job_skills ( requirement_level, skills ( name ) ),
          job_questions ( id, prompt, answer_type, is_required, is_knockout, options, position ),
          job_stages ( name, position, maps_to_state )
        ''').eq('id', jobId).single();

    final company = Map<String, dynamic>.from(row['companies'] as Map);
    final skills = (row['job_skills'] as List? ?? const []);
    final stages = (row['job_stages'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));
    final questions = (row['job_questions'] as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      ..sort((a, b) => (a['position'] as int).compareTo(b['position'] as int));

    double? distance;
    if (lat != null && lng != null) {
      final near = await nearby(
        lat: lat,
        lng: lng,
        filters: const JobFilters(radiusKm: 200),
        limit: 200,
      );
      for (final j in near) {
        if (j.id == jobId) {
          distance = j.distanceKm;
          break;
        }
      }
    }

    String? skillName(dynamic s) {
      final m = Map<String, dynamic>.from(s as Map);
      final sk = m['skills'];
      return sk == null ? null : (Map<String, dynamic>.from(sk as Map)['name'] as String?);
    }

    final job = Job(
      id: row['id'] as String,
      title: (row['title'] ?? '') as String,
      companyId: company['id'] as String?,
      companyName: (company['display_name'] ?? '') as String,
      companySlug: company['slug'] as String?,
      companyVerified: (company['is_verified'] ?? false) as bool,
      companyResponseHours:
          (company['median_response_hours'] as num?)?.toInt(),
      distanceKm: distance,
      locationText: row['location_text'] as String?,
      payMin: row['pay_min'] as num?,
      payMax: row['pay_max'] as num?,
      payPeriod: row['pay_period'] as String?,
      payCurrency: (row['pay_currency'] as String?)?.trim(),
      payNegotiable: (row['pay_negotiable'] ?? false) as bool,
      payMonthlyMin: null,
      workType: row['work_type'] as String?,
      workplace: row['workplace_type'] as String?,
      shiftTypes: Job.parseStrList(row['shift_types']),
      acceptsNoExperience: (row['accepts_no_experience'] ?? false) as bool,
      minExperienceMonths: (row['min_experience_months'] as num?)?.toInt(),
      isImmediateStart: (row['is_immediate_start'] ?? false) as bool,
      quickApplyEnabled: (row['quick_apply_enabled'] ?? true) as bool,
      openings: (row['openings'] as num?)?.toInt(),
      categorySlug: row['job_categories'] == null
          ? null
          : Map<String, dynamic>.from(row['job_categories'] as Map)['slug']
              as String?,
      professionId: row['profession_id']?.toString(),
      professionName: row['professions'] == null
          ? null
          : Map<String, dynamic>.from(row['professions'] as Map)['name']
              as String?,
      benefits: (row['job_benefits'] as List? ?? const [])
          .map((e) =>
              Map<String, dynamic>.from(e as Map)['benefit_type'].toString())
          .toList(),
      publishedAt: row['published_at'] == null
          ? null
          : DateTime.tryParse(row['published_at'].toString())?.toLocal(),
    );

    return JobDetail(
      job: job,
      description: row['description'] as String?,
      responsibilities: (row['responsibilities'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
      requiredSkills: skills
          .where((s) =>
              Map<String, dynamic>.from(s as Map)['requirement_level'] ==
              'required')
          .map(skillName)
          .whereType<String>()
          .toList(),
      preferredSkills: skills
          .where((s) =>
              Map<String, dynamic>.from(s as Map)['requirement_level'] !=
              'required')
          .map(skillName)
          .whereType<String>()
          .toList(),
      questions: questions.map(JobQuestion.fromRow).toList(),
      stages: stages
          .where((s) => s['maps_to_state'] != 'rejected')
          .map((s) => s['name'].toString())
          .toList(),
      hoursPerWeek: (row['hours_per_week'] as num?)?.toInt(),
      workingDays: (row['working_days'] as num?)?.toInt(),
      applicationMethod: row['application_method'] as String?,
      walkInDetails: row['walk_in_details'] as String?,
      contactPhone: row['contact_phone'] as String?,
      aboutCompany: company['about'] as String?,
      companyTotalHires: (company['total_hires'] as num?)?.toInt(),
      companyResponseRate: company['response_rate_pct'] as num?,
      uniformRequired: row['uniform_required'] as bool?,
      ownVehicleRequired: row['own_vehicle_required'] as bool?,
      ownToolsRequired: row['own_tools_required'] as bool?,
      visaSponsorship: row['visa_sponsorship'] as bool?,
    );
  }

  Future<List<JobCategory>> categories() async {
    final rows = await _db
        .from('job_categories')
        .select('id, slug, name, position')
        .eq('status', 'active')
        .order('position');
    return (rows as List)
        .map((r) => JobCategory.fromRow(Map<String, dynamic>.from(r as Map)))
        .toList();
  }
}
