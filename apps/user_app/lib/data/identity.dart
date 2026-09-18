/// Release 2 — Universal Professional Identity.
///
/// A person holds up to five work identities (Delivery Driver, Electrician,
/// Cook, Software Engineer...). Each one is its own lens: profession,
/// headline, skills, experience, preferences, adaptive profile answers,
/// visibility and evidence. Employers only ever see the identity a person
/// applied with — the database enforces that, this file only describes it.
///
/// Everything here is pure (no Supabase, no widgets) so it can be tested.
library;

const kMaxWorkIdentities = 5;

// ---------------------------------------------------------------------------
// Visibility
// ---------------------------------------------------------------------------

/// Who can see one work identity. Mirrors the `discoverability` enum.
enum IdentityVisibility {
  private('private', 'Only me',
      'Only you can see it, and an employer sees it only when you apply with it.'),
  matchedOnly('matched_only', 'Only when I am a strong match',
      'Employers see it only when you are a strong match for one of their open jobs.'),
  discoverable('discoverable', 'Verified employers',
      'Verified employers can find it when they search for workers.'),
  recruiters('recruiters', 'Employers and agencies',
      'Verified employers and recruitment agencies can find it.'),
  public('public', 'Anyone with the link',
      'Anyone who has the link can see it, even people who are not employers.');

  const IdentityVisibility(this.wire, this.title, this.description);

  /// Value stored in the database.
  final String wire;

  /// Short name shown on chips and radio options.
  final String title;

  /// One plain sentence explaining the level.
  final String description;

  /// The default for every new identity.
  static const fallback = IdentityVisibility.private;

  static IdentityVisibility fromWire(String? v) {
    for (final l in values) {
      if (l.wire == v) return l;
    }
    return fallback;
  }

  /// Shown before a person switches to [public].
  String? get warning => this == IdentityVisibility.public
      ? 'Anyone with the link can see this profile, including people who are '
          'not employers. Only choose this if you are happy for it to be '
          'shared.'
      : null;
}

/// Employers can only invite an identity they can find, so "Let employers
/// invite me to apply" means nothing while it is [IdentityVisibility.private].
bool invitationsPossible(IdentityVisibility v) =>
    v != IdentityVisibility.private;

/// Recruitment agencies only ever find an identity that is
/// [IdentityVisibility.recruiters] or [IdentityVisibility.public].
bool agenciesCanFind(IdentityVisibility v) =>
    v == IdentityVisibility.recruiters || v == IdentityVisibility.public;

/// Said next to "Let recruiters and agencies ask to represent me".
String agencyFindabilityNote(IdentityVisibility v) => agenciesCanFind(v)
    ? 'Agencies can find this profile because it is set to "${v.title}".'
    : 'Agencies cannot find this profile while it is "${v.title}". Only '
        '"${IdentityVisibility.recruiters.title}" or '
        '"${IdentityVisibility.public.title}" lets agencies find you.';

/// Shown under the visibility choices.
const kVisibilitySearchNote =
    'Employers can only search for workers after Omelo has verified them and '
    'turned on search for their account.';

// ---------------------------------------------------------------------------
// Identities
// ---------------------------------------------------------------------------

class WorkIdentity {
  const WorkIdentity({
    required this.id,
    required this.label,
    this.professionId,
    this.professionName,
    this.categoryId,
    this.headline,
    this.about,
    this.isPrimary = false,
    this.status = 'active',
    this.visibility = IdentityVisibility.private,
    this.totalExperienceMonths,
    this.completenessScore = 0,
    this.updatedAt,
  });

  final String id;
  final String label;
  final String? professionId;
  final String? professionName;
  final String? categoryId;
  final String? headline;
  final String? about;
  final bool isPrimary;

  /// active | paused | archived
  final String status;
  final IdentityVisibility visibility;
  final int? totalExperienceMonths;
  final int completenessScore;
  final DateTime? updatedAt;

  bool get isActive => status == 'active';
  bool get isArchived => status == 'archived';

  /// The profession if chosen, else the name the person gave it.
  String get displayProfession => professionName ?? label;

  /// A row of `work_identities`, optionally with `professions ( name )`.
  factory WorkIdentity.fromRow(Map<String, dynamic> m) {
    final prof = m['professions'];
    return WorkIdentity(
      id: m['id'].toString(),
      label: (m['label'] ?? '').toString(),
      professionId: m['profession_id']?.toString(),
      professionName: prof is Map
          ? prof['name']?.toString()
          : m['profession']?.toString(),
      categoryId: m['category_id']?.toString(),
      headline: m['headline'] as String?,
      about: m['about'] as String?,
      isPrimary: m['is_primary'] == true,
      status: (m['status'] ?? 'active').toString(),
      visibility: IdentityVisibility.fromWire(m['discoverability']?.toString()),
      totalExperienceMonths: _int(m['total_experience_months']),
      completenessScore: _int(m['completeness_score']) ??
          _int(m['completeness']) ??
          0,
      updatedAt: m['updated_at'] == null
          ? null
          : DateTime.tryParse(m['updated_at'].toString()),
    );
  }
}

/// Active identities first (main one on top), archived last.
List<WorkIdentity> sortIdentities(Iterable<WorkIdentity> list) {
  int rank(WorkIdentity i) => i.isPrimary ? 0 : (i.isActive ? 1 : 2);
  final out = list.toList();
  out.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    return a.label.toLowerCase().compareTo(b.label.toLowerCase());
  });
  return out;
}

// ---------------------------------------------------------------------------
// Completeness
// ---------------------------------------------------------------------------

class Completeness {
  const Completeness({required this.score, required this.missing});
  final int score;

  /// profession | headline | about | skills | experience | preferences |
  /// location | profile_questions
  final List<String> missing;

  bool get isComplete => missing.isEmpty;

  factory Completeness.fromJson(dynamic v) {
    final m = v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
    return Completeness(
      score: (_int(m['score']) ?? 0).clamp(0, 100),
      missing: (m['missing'] as List? ?? const [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// Order the "Next:" tip picks from — biggest gain for the least effort first.
const kCompletenessPriority = [
  'profession',
  'skills',
  'experience',
  'profile_questions',
  'headline',
  'preferences',
  'location',
  'about',
];

/// Skills needed before the server stops listing `skills` as missing.
const kMinSkills = 3;

/// The single most useful next step, e.g. "Next: add 2 more skills".
/// Returns null when nothing is missing.
String? completenessTip(List<String> missing, {int? skillCount}) {
  if (missing.isEmpty) return null;
  final ordered = [
    ...kCompletenessPriority.where(missing.contains),
    ...missing.where((m) => !kCompletenessPriority.contains(m)),
  ];
  final key = ordered.first;
  switch (key) {
    case 'profession':
      return 'Next: choose your job type';
    case 'skills':
      final need = skillCount == null
          ? kMinSkills
          : (kMinSkills - skillCount).clamp(1, kMinSkills);
      if (skillCount == null || skillCount == 0) {
        return 'Next: add $need skills';
      }
      return need == 1 ? 'Next: add 1 more skill' : 'Next: add $need more skills';
    case 'experience':
      return 'Next: add your work experience';
    case 'profile_questions':
      return 'Next: answer the questions for your job';
    case 'headline':
      return 'Next: write a short headline';
    case 'preferences':
      return 'Next: say when and how you want to work';
    case 'location':
      return 'Next: add where you want to work';
    case 'about':
      return 'Next: say a little about yourself';
    default:
      return 'Next: finish your profile';
  }
}

/// Which editor section fixes a missing item.
String sectionForMissing(String key) => switch (key) {
      'profession' || 'headline' || 'about' => 'basics',
      'profile_questions' => 'questions',
      'skills' => 'skills',
      'experience' => 'experience',
      'preferences' || 'location' => 'preferences',
      _ => 'basics',
    };

/// Main identity below this score gets a gentle nudge on Home / Discover.
const kNudgeBelowScore = 60;

// ---------------------------------------------------------------------------
// Adaptive profile
// ---------------------------------------------------------------------------

class ProfileField {
  const ProfileField({
    required this.attributeId,
    required this.slug,
    required this.label,
    required this.dataType,
    this.helpText,
    this.options = const [],
    this.unit,
    this.isRequired = false,
    this.scope = 'universal',
    this.value,
  });

  final String attributeId;
  final String slug;
  final String label;
  final String? helpText;

  /// text | long_text | number | boolean | single_select | multi_select |
  /// date | years | file | location
  final String dataType;
  final List<String> options;
  final String? unit;
  final bool isRequired;

  /// profession | category | universal
  final String scope;

  /// Raw server value (see [decodeFieldValue]).
  final Object? value;

  factory ProfileField.fromJson(Map<String, dynamic> m) => ProfileField(
        attributeId: (m['attribute_id'] ?? '').toString(),
        slug: (m['slug'] ?? '').toString(),
        label: (m['label'] ?? '').toString(),
        helpText: (m['help_text'] as String?)?.trim().isEmpty == true
            ? null
            : m['help_text'] as String?,
        dataType: (m['data_type'] ?? 'text').toString(),
        options: _options(m['options']),
        unit: m['unit'] as String?,
        isRequired: m['is_required'] == true,
        scope: (m['scope'] ?? 'universal').toString(),
        value: m['value'],
      );

  static List<String> _options(dynamic v) {
    if (v is! List) return const [];
    return v
        .map((e) => e is Map
            ? (e['label'] ?? e['value'] ?? '').toString()
            : e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
  }
}

class IdentityProfile {
  const IdentityProfile({
    required this.identity,
    required this.completeness,
    required this.fields,
  });

  final WorkIdentity identity;
  final Completeness completeness;
  final List<ProfileField> fields;

  factory IdentityProfile.fromJson(dynamic v) {
    final m = Map<String, dynamic>.from(v as Map);
    final completeness = Completeness.fromJson(m['completeness']);
    final idMap = Map<String, dynamic>.from(m['identity'] as Map? ?? const {});
    idMap['completeness'] ??= completeness.score;
    return IdentityProfile(
      identity: WorkIdentity.fromRow(idMap),
      completeness: completeness,
      fields: (m['fields'] as List? ?? const [])
          .map((e) => ProfileField.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }
}

/// Which widget renders a profile question.
enum FieldInputKind {
  text,
  longText,
  number,
  toggle,

  /// A few short options side by side.
  segmented,

  /// A longer single-choice list.
  radio,

  /// Pick any number of options.
  chips,

  /// A multi-select with no listed options: type your own short items.
  tags,
  date,

  /// Not answerable in the app yet (file upload, or a choice with no options).
  unsupported,
}

/// Segmented buttons only fit a few short options on a phone.
const kSegmentedMaxOptions = 3;
const kSegmentedMaxChars = 14;

FieldInputKind inputKindFor(ProfileField f) {
  switch (f.dataType) {
    case 'long_text':
      return FieldInputKind.longText;
    case 'number':
    case 'years':
      return FieldInputKind.number;
    case 'boolean':
      return FieldInputKind.toggle;
    case 'single_select':
      if (f.options.isEmpty) return FieldInputKind.unsupported;
      final short = f.options.length <= kSegmentedMaxOptions &&
          f.options.every((o) => o.length <= kSegmentedMaxChars);
      return short ? FieldInputKind.segmented : FieldInputKind.radio;
    case 'multi_select':
      // With no listed options the server accepts short free-text items.
      return f.options.isEmpty ? FieldInputKind.tags : FieldInputKind.chips;
    case 'date':
      return FieldInputKind.date;
    case 'file':
      return FieldInputKind.unsupported;
    case 'text':
    case 'location':
    default:
      return FieldInputKind.text;
  }
}

/// Server value → the value a widget edits.
///
/// multi_select → `List<String>`, boolean → `bool?`, number/years → `num?`,
/// date → `DateTime?`, everything else → `String?`.
Object? decodeFieldValue(String dataType, Object? raw) {
  switch (dataType) {
    case 'multi_select':
      if (raw is List) return raw.map((e) => e.toString()).toList();
      return <String>[];
    case 'boolean':
      if (raw is bool) return raw;
      if (raw is String) return raw == 'true' ? true : (raw == 'false' ? false : null);
      return null;
    case 'number':
    case 'years':
      if (raw is num) return raw;
      if (raw is String) return num.tryParse(raw);
      return null;
    case 'date':
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    default:
      if (raw == null) return null;
      if (raw is Map) {
        return (raw['label'] ?? raw['name'] ?? raw['text'] ?? '').toString();
      }
      return raw.toString();
  }
}

/// Result of turning a widget value into what `omelo_save_identity_profile`
/// expects. A null [value] with no [error] removes the answer.
class EncodedValue {
  const EncodedValue(this.value, [this.error]);
  final Object? value;
  final String? error;
  bool get ok => error == null;
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}'
    '-${d.day.toString().padLeft(2, '0')}';

/// Widget value → JSON value for the save call.
///
/// text → string, select → one of the options, multi_select → array of
/// options (in option order), boolean, number/years → number,
/// date → 'YYYY-MM-DD'.
EncodedValue encodeFieldValue(ProfileField f, Object? ui) {
  switch (f.dataType) {
    case 'multi_select':
      if (f.options.isEmpty) {
        // Open list: trimmed, non-empty, no repeats (ignoring case), in order.
        final seen = <String>{};
        final items = <String>[
          if (ui is Iterable)
            for (final e in ui.map((e) => e.toString().trim()))
              if (e.isNotEmpty && seen.add(e.toLowerCase())) e,
        ];
        return EncodedValue(items.isEmpty ? null : items);
      }
      final picked = ui is Iterable ? ui.map((e) => e.toString()).toSet() : <String>{};
      final ordered = f.options.where(picked.contains).toList();
      return EncodedValue(ordered.isEmpty ? null : ordered);
    case 'single_select':
      final s = ui?.toString();
      return EncodedValue(s != null && f.options.contains(s) ? s : null);
    case 'boolean':
      return EncodedValue(ui is bool ? ui : null);
    case 'number':
    case 'years':
      num? n;
      if (ui is num) {
        n = ui;
      } else {
        final s = (ui?.toString() ?? '').trim().replaceAll(',', '.');
        if (s.isEmpty) return const EncodedValue(null);
        n = num.tryParse(s);
        if (n == null) return const EncodedValue(null, 'Enter a number');
      }
      if (n < 0) return const EncodedValue(null, 'Enter 0 or more');
      final max = f.dataType == 'years' ? 70 : 100000;
      if (n > max) {
        return EncodedValue(
            null,
            f.dataType == 'years'
                ? 'Enter between 0 and 70 years'
                : 'That number is too big');
      }
      // Whole numbers go as integers ("3", not "3.0").
      return EncodedValue(n == n.roundToDouble() ? n.round() : n.toDouble());
    case 'date':
      if (ui is DateTime) return EncodedValue(isoDate(ui));
      final s = ui?.toString().trim() ?? '';
      if (s.isEmpty) return const EncodedValue(null);
      final d = DateTime.tryParse(s);
      return d == null
          ? const EncodedValue(null, 'Choose a date')
          : EncodedValue(isoDate(d));
    case 'long_text':
      final s = ui?.toString().trim() ?? '';
      if (s.length > 2000) {
        return const EncodedValue(null, 'Keep it under 2000 characters');
      }
      return EncodedValue(s.isEmpty ? null : s);
    default:
      final s = ui?.toString().trim() ?? '';
      if (s.length > 300) {
        return const EncodedValue(null, 'Keep it under 300 characters');
      }
      return EncodedValue(s.isEmpty ? null : s);
  }
}

/// Is a (decoded) value an answer at all? Used for "required" markers.
bool hasAnswer(Object? v) {
  if (v == null) return false;
  if (v is String) return v.trim().isNotEmpty;
  if (v is Iterable) return v.isNotEmpty;
  return true;
}

// ---------------------------------------------------------------------------
// Skills, experience, preferences
// ---------------------------------------------------------------------------

/// Skill levels, in the words workers use.
const kProficiencyLabels = <String, String>{
  'beginner': 'Just starting',
  'basic': 'Basic',
  'intermediate': 'Good',
  'advanced': 'Very good',
  'expert': 'Expert',
};

/// "How long have you used it?" choices (months).
const kMonthsUsedChoices = <int, String>{
  6: 'About 6 months',
  12: 'About 1 year',
  24: 'About 2 years',
  60: 'About 5 years',
  120: '10 years or more',
};

String monthsLabel(int? months) {
  if (months == null || months <= 0) return '';
  if (months < 12) return months == 1 ? '1 month' : '$months months';
  final years = months / 12;
  final whole = years == years.roundToDouble();
  final text = whole ? years.round().toString() : years.toStringAsFixed(1);
  return text == '1' ? '1 year' : '$text years';
}

class PersonSkill {
  const PersonSkill({
    required this.id,
    required this.skillId,
    required this.name,
    this.workIdentityId,
    this.proficiency,
    this.monthsUsed,
    this.isVerified = false,
    this.evidenceType = 'self_declared',
  });

  final String id;
  final String skillId;
  final String name;

  /// Null means shared by every identity.
  final String? workIdentityId;
  final String? proficiency;
  final int? monthsUsed;
  final bool isVerified;
  final String evidenceType;

  bool get isShared => workIdentityId == null;

  factory PersonSkill.fromRow(Map<String, dynamic> m) {
    final s = m['skills'];
    return PersonSkill(
      id: m['id'].toString(),
      skillId: m['skill_id'].toString(),
      name: s is Map ? (s['name'] ?? '').toString() : '',
      workIdentityId: m['work_identity_id']?.toString(),
      proficiency: m['proficiency']?.toString(),
      monthsUsed: _int(m['months_used']),
      isVerified: m['is_verified'] == true,
      evidenceType: (m['evidence_type'] ?? 'self_declared').toString(),
    );
  }
}

/// Skills counted for one identity: its own plus the shared ones.
int skillCountFor(String identityId, Iterable<String?> skillIdentityIds) =>
    skillIdentityIds.where((w) => w == null || w == identityId).length;

class Experience {
  const Experience({
    required this.id,
    required this.employerName,
    required this.title,
    this.workIdentityId,
    this.startedOn,
    this.endedOn,
    this.isCurrent = false,
    this.description,
    this.isVerified = false,
  });

  final String id;
  final String employerName;
  final String title;
  final String? workIdentityId;
  final DateTime? startedOn;
  final DateTime? endedOn;
  final bool isCurrent;
  final String? description;
  final bool isVerified;

  factory Experience.fromRow(Map<String, dynamic> m) => Experience(
        id: m['id'].toString(),
        employerName: (m['employer_name'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        workIdentityId: m['work_identity_id']?.toString(),
        startedOn: _date(m['started_on']),
        endedOn: _date(m['ended_on']),
        isCurrent: m['is_current'] == true,
        description: m['description'] as String?,
        isVerified: m['is_verified'] == true,
      );
}

const kAvailabilityLabels = <String, String>{
  'immediate': 'Right away',
  'within_7_days': 'Within a week',
  'within_15_days': 'Within 2 weeks',
  'within_30_days': 'Within a month',
  'within_60_days': 'Within 2 months',
  'within_90_days': 'Within 3 months',
  'flexible': 'Flexible',
  'not_available': 'Not looking right now',
};

const kWorkTypeLabels = <String, String>{
  'full_time': 'Full time',
  'part_time': 'Part time',
  'daily_wage': 'Daily wage',
  'contract': 'Contract',
  'temporary': 'Temporary',
  'gig': 'Gig',
  'freelance': 'Freelance',
  'seasonal': 'Seasonal',
  'internship': 'Internship',
  'apprenticeship': 'Apprenticeship',
};

const kShiftLabels = <String, String>{
  'day': 'Day',
  'evening': 'Evening',
  'night': 'Night',
  'early_morning': 'Early morning',
  'rotating': 'Rotating',
  'weekend': 'Weekends',
  'flexible': 'Flexible',
};

const kPayPeriodLabels = <String, String>{
  'hour': 'per hour',
  'day': 'per day',
  'week': 'per week',
  'month': 'per month',
  'year': 'per year',
};

class WorkPreferences {
  const WorkPreferences({
    this.availability = 'immediate',
    this.workTypes = const [],
    this.shiftTypes = const [],
    this.expectedPayAmount,
    this.expectedPayPeriod,
    this.payCurrency,
  });

  final String availability;
  final List<String> workTypes;
  final List<String> shiftTypes;
  final num? expectedPayAmount;
  final String? expectedPayPeriod;
  final String? payCurrency;

  factory WorkPreferences.fromRow(Map<String, dynamic>? m) {
    if (m == null) return const WorkPreferences();
    List<String> list(dynamic v) =>
        v is List ? v.map((e) => e.toString()).toList() : const [];
    return WorkPreferences(
      availability: (m['availability'] ?? 'immediate').toString(),
      workTypes: list(m['work_types']),
      shiftTypes: list(m['shift_types']),
      expectedPayAmount: m['expected_pay_amount'] is num
          ? m['expected_pay_amount'] as num
          : num.tryParse('${m['expected_pay_amount']}'),
      expectedPayPeriod: m['expected_pay_period']?.toString(),
      payCurrency: m['pay_currency']?.toString().trim(),
    );
  }
}

class LocationPreference {
  const LocationPreference({
    required this.id,
    required this.name,
    this.locationId,
    this.radiusKm,
    this.kind = 'city',
  });

  final String id;
  final String name;
  final String? locationId;
  final int? radiusKm;
  final String kind;

  factory LocationPreference.fromRow(Map<String, dynamic> m) {
    final loc = m['locations'];
    final kind = (m['kind'] ?? 'city').toString();
    return LocationPreference(
      id: m['id'].toString(),
      locationId: m['location_id']?.toString(),
      radiusKm: _int(m['radius_km']),
      kind: kind,
      name: loc is Map
          ? (loc['name'] ?? '').toString()
          : switch (kind) {
              'remote' => 'Remote work',
              'anywhere' => 'Anywhere',
              'nearby' => 'Near me',
              _ => 'A place',
            },
    );
  }
}

// ---------------------------------------------------------------------------
// Evidence
// ---------------------------------------------------------------------------

class EvidenceItem {
  const EvidenceItem({
    required this.type,
    required this.label,
    this.verified = false,
  });

  /// verified_employment | employer_verified | assessment | experience |
  /// project | self_declared
  final String type;
  final String label;
  final bool verified;

  factory EvidenceItem.fromJson(Map<String, dynamic> m) => EvidenceItem(
        type: (m['type'] ?? 'self_declared').toString(),
        label: (m['label'] ?? '').toString(),
        verified: m['verified'] == true,
      );
}

/// Short badge text for each kind of evidence.
String evidenceBadge(String type) => switch (type) {
      'verified_employment' => 'Verified job',
      'employer_verified' => 'Employer confirmed',
      'assessment' => 'Passed a test',
      'experience' => 'Experience',
      'project' => 'Projects',
      'self_declared' => 'Self-declared',
      _ => 'Other',
    };

class SkillEvidence {
  const SkillEvidence({
    required this.skillId,
    required this.name,
    this.proficiency,
    this.monthsUsed,
    this.verified = false,
    this.evidence = const [],
  });

  final String skillId;
  final String name;
  final String? proficiency;
  final int? monthsUsed;
  final bool verified;
  final List<EvidenceItem> evidence;

  factory SkillEvidence.fromJson(Map<String, dynamic> m) => SkillEvidence(
        skillId: (m['skill_id'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        proficiency: m['proficiency']?.toString(),
        monthsUsed: _int(m['months_used']),
        verified: m['verified'] == true,
        evidence: (m['evidence'] as List? ?? const [])
            .map((e) => EvidenceItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );
}

class IdentityEvidence {
  const IdentityEvidence({
    this.skills = const [],
    this.verifiedEmployment = const [],
    this.licences = const [],
    this.credentials = const [],
    this.emailVerified = false,
    this.phoneVerified = false,
    this.identityVerified = false,
  });

  final List<SkillEvidence> skills;
  final List<Map<String, dynamic>> verifiedEmployment;
  final List<Map<String, dynamic>> licences;
  final List<Map<String, dynamic>> credentials;
  final bool emailVerified;
  final bool phoneVerified;
  final bool identityVerified;

  factory IdentityEvidence.fromJson(dynamic v) {
    final m = v is Map ? Map<String, dynamic>.from(v) : const <String, dynamic>{};
    List<Map<String, dynamic>> maps(dynamic x) => (x as List? ?? const [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final trust = m['trust'] is Map
        ? Map<String, dynamic>.from(m['trust'] as Map)
        : const <String, dynamic>{};
    return IdentityEvidence(
      skills: maps(m['skills']).map(SkillEvidence.fromJson).toList(),
      verifiedEmployment: maps(m['verified_employment']),
      licences: maps(m['licences']),
      credentials: maps(m['credentials']),
      emailVerified: trust['email_verified'] == true,
      phoneVerified: trust['phone_verified'] == true,
      identityVerified: trust['identity_verified'] == true,
    );
  }
}

// ---------------------------------------------------------------------------
// Apply with an identity
// ---------------------------------------------------------------------------

/// Which identity to apply as by default: the active one whose profession
/// matches the job, else the main one, else any active one.
WorkIdentity? defaultIdentityForJob(
  List<WorkIdentity> identities, {
  String? jobProfessionId,
  String? jobProfessionName,
}) {
  final active = identities.where((i) => i.isActive).toList();
  if (active.isEmpty) return null;
  WorkIdentity? preferPrimary(Iterable<WorkIdentity> l) {
    final list = l.toList();
    if (list.isEmpty) return null;
    return list.firstWhere((i) => i.isPrimary, orElse: () => list.first);
  }

  if (jobProfessionId != null) {
    final m = preferPrimary(active.where((i) => i.professionId == jobProfessionId));
    if (m != null) return m;
  }
  final name = jobProfessionName?.trim().toLowerCase();
  if (name != null && name.isNotEmpty) {
    final m = preferPrimary(active.where((i) =>
        i.professionName?.trim().toLowerCase() == name ||
        i.label.trim().toLowerCase() == name));
    if (m != null) return m;
  }
  return preferPrimary(active);
}

/// The identity the apply screen starts on.
///
/// The one the worker tapped wins; then the one an employer invited (when it
/// is still active); then [defaultIdentityForJob].
WorkIdentity? pickApplyIdentity(
  List<WorkIdentity> identities, {
  String? pickedId,
  String? invitedId,
  String? jobProfessionId,
  String? jobProfessionName,
}) {
  final active = identities.where((i) => i.isActive).toList();
  for (final id in [pickedId, invitedId]) {
    if (id == null) continue;
    for (final i in active) {
      if (i.id == id) return i;
    }
  }
  return defaultIdentityForJob(active,
      jobProfessionId: jobProfessionId, jobProfessionName: jobProfessionName);
}

/// One line under the identity chooser.
String applyPreviewLine(WorkIdentity i) =>
    'Employers will see your ${i.label} profile only';

/// "Complete your Cook profile to get better matches".
String nudgeTitle(WorkIdentity i) =>
    'Complete your ${i.label} profile to get better matches';

// ---------------------------------------------------------------------------

int? _int(dynamic v) =>
    v == null ? null : (v is num ? v.toInt() : num.tryParse(v.toString())?.toInt());

DateTime? _date(dynamic v) => v == null ? null : DateTime.tryParse(v.toString());
