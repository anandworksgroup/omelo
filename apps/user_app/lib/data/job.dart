/// A job as returned by `omelo_nearby_jobs`.
///
/// Mirrors the RPC return shape exactly. If the RPC changes, this changes —
/// there is no hand-maintained mapping layer to drift out of sync.
class Job {
  Job({
    required this.id,
    required this.title,
    required this.companyId,
    required this.companyName,
    required this.companySlug,
    required this.companyVerified,
    required this.companyResponseHours,
    required this.distanceKm,
    required this.locationText,
    required this.payMin,
    required this.payMax,
    required this.payPeriod,
    required this.payCurrency,
    required this.payNegotiable,
    required this.payMonthlyMin,
    required this.workType,
    required this.workplace,
    required this.shiftTypes,
    required this.acceptsNoExperience,
    required this.minExperienceMonths,
    required this.isImmediateStart,
    required this.quickApplyEnabled,
    required this.openings,
    required this.categorySlug,
    required this.professionName,
    required this.benefits,
    required this.publishedAt,
    this.professionId,
  });

  final String id;
  final String title;
  final String? companyId;
  final String companyName;
  final String? companySlug;
  final bool companyVerified;
  final int? companyResponseHours;
  final double? distanceKm;
  final String? locationText;
  final num? payMin;
  final num? payMax;
  final String? payPeriod;
  final String? payCurrency;
  final bool payNegotiable;
  final num? payMonthlyMin;
  final String? workType;
  final String? workplace;
  final List<String> shiftTypes;
  final bool acceptsNoExperience;
  final int? minExperienceMonths;
  final bool isImmediateStart;
  final bool quickApplyEnabled;
  final int? openings;
  final String? categorySlug;
  final String? professionName;

  /// Set on job detail; used to pick the matching work identity to apply as.
  final String? professionId;
  final List<String> benefits;
  final DateTime? publishedAt;

  static List<String> parseStrList(dynamic v) {
    if (v == null) return const [];
    if (v is List) return v.map((e) => e.toString()).toList();
    // Postgres array literal fallback: {a,b,c}
    final s = v.toString();
    if (s.startsWith('{') && s.endsWith('}')) {
      final inner = s.substring(1, s.length - 1);
      if (inner.isEmpty) return const [];
      return inner.split(',').map((e) => e.replaceAll('"', '').trim()).toList();
    }
    return const [];
  }

  static num? _num(dynamic v) =>
      v == null ? null : (v is num ? v : num.tryParse(v.toString()));

  factory Job.fromRpc(Map<String, dynamic> m) => Job(
        id: m['job_id'] as String,
        title: (m['title'] ?? '') as String,
        companyId: m['company_id'] as String?,
        companyName: (m['company_name'] ?? '') as String,
        companySlug: m['company_slug'] as String?,
        companyVerified: (m['company_verified'] ?? false) as bool,
        companyResponseHours: _num(m['company_response_hours'])?.toInt(),
        distanceKm: _num(m['distance_km'])?.toDouble(),
        locationText: m['location_text'] as String?,
        payMin: _num(m['pay_min']),
        payMax: _num(m['pay_max']),
        payPeriod: m['job_pay_period'] as String?,
        payCurrency: (m['pay_currency'] as String?)?.trim(),
        payNegotiable: (m['pay_negotiable'] ?? false) as bool,
        payMonthlyMin: _num(m['pay_monthly_min']),
        workType: m['job_work_type'] as String?,
        workplace: m['job_workplace'] as String?,
        shiftTypes: parseStrList(m['shift_types']),
        acceptsNoExperience: (m['accepts_no_experience'] ?? false) as bool,
        minExperienceMonths: _num(m['min_experience_months'])?.toInt(),
        isImmediateStart: (m['is_immediate_start'] ?? false) as bool,
        quickApplyEnabled: (m['quick_apply_enabled'] ?? true) as bool,
        openings: _num(m['openings'])?.toInt(),
        categorySlug: m['category_slug'] as String?,
        professionName: m['profession_name'] as String?,
        benefits: parseStrList(m['benefits']),
        publishedAt: m['published_at'] == null
            ? null
            : DateTime.tryParse(m['published_at'].toString())?.toLocal(),
      );
}

/// Full job detail, loaded from the `jobs` table with embedded relations.
class JobDetail {
  JobDetail({
    required this.job,
    required this.description,
    required this.responsibilities,
    required this.requiredSkills,
    required this.preferredSkills,
    required this.questions,
    required this.stages,
    required this.hoursPerWeek,
    required this.workingDays,
    required this.applicationMethod,
    required this.walkInDetails,
    required this.contactPhone,
    required this.aboutCompany,
    required this.companyTotalHires,
    required this.companyResponseRate,
    required this.uniformRequired,
    required this.ownVehicleRequired,
    required this.ownToolsRequired,
    required this.visaSponsorship,
  });

  final Job job;
  final String? description;
  final List<String> responsibilities;
  final List<String> requiredSkills;
  final List<String> preferredSkills;
  final List<JobQuestion> questions;
  final List<String> stages;
  final int? hoursPerWeek;
  final int? workingDays;
  final String? applicationMethod;
  final String? walkInDetails;
  final String? contactPhone;
  final String? aboutCompany;
  final int? companyTotalHires;
  final num? companyResponseRate;
  final bool? uniformRequired;
  final bool? ownVehicleRequired;
  final bool? ownToolsRequired;
  final bool? visaSponsorship;
}

class JobQuestion {
  JobQuestion({
    required this.id,
    required this.prompt,
    required this.answerType,
    required this.isRequired,
    required this.isKnockout,
    required this.options,
  });

  final String id;
  final String prompt;
  final String answerType;
  final bool isRequired;
  final bool isKnockout;
  final List<String> options;

  factory JobQuestion.fromRow(Map<String, dynamic> m) => JobQuestion(
        id: m['id'] as String,
        prompt: (m['prompt'] ?? '') as String,
        answerType: (m['answer_type'] ?? 'text') as String,
        isRequired: (m['is_required'] ?? true) as bool,
        isKnockout: (m['is_knockout'] ?? false) as bool,
        options: (m['options'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
      );
}

/// A job category tile on the browse grid.
class JobCategory {
  JobCategory({
    required this.id,
    required this.slug,
    required this.name,
    required this.position,
  });

  final String id;
  final String slug;
  final String name;
  final int position;

  factory JobCategory.fromRow(Map<String, dynamic> m) => JobCategory(
        id: m['id'] as String,
        slug: (m['slug'] ?? '') as String,
        name: (m['name'] ?? '') as String,
        position: (m['position'] ?? 0) as int,
      );
}
