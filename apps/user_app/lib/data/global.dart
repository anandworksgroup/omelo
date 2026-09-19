/// Release 6 — global employment and mobility, from the worker's side.
///
/// Where I live and could work, my right to work in each country, jobs in
/// other countries (remote, relocation, sponsorship), whether I can apply,
/// and plain information about a country's rules.
///
/// Rules that shape this file:
///  * Money is always shown in the record's own currency. A converted amount
///    is only ever an extra "≈" line, with the rate and where it came from.
///  * Eligibility is a guide, not a verdict: "Potentially eligible" never
///    blocks applying, and every eligibility or country screen says it is not
///    legal advice.
///  * Who sees my work authorization is my choice, said in plain words.
///
/// Everything here is pure (no Supabase, no widgets) so it can be tested.
library;

import 'package:intl/intl.dart';

import 'invitations.dart' show shortDate;
import 'work.dart' show money, payPeriodWords, wireDate;

Map<String, dynamic>? _map(dynamic v) =>
    v is Map ? Map<String, dynamic>.from(v) : null;

List<Map<String, dynamic>> _maps(dynamic v) => v is List
    ? v.map(_map).whereType<Map<String, dynamic>>().toList()
    : const [];

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

num? _num(dynamic v) =>
    v == null ? null : (v is num ? v : num.tryParse(v.toString()));

bool _bool(dynamic v) => v == true || v?.toString() == 'true';

bool? _boolOrNull(dynamic v) => v == null ? null : _bool(v);

/// Dates from the server: "2026-11-01" is a calendar day (kept as is);
/// timestamps are shown in the phone's time.
DateTime? _date(dynamic v) {
  final s = _str(v);
  if (s == null) return null;
  final d = DateTime.tryParse(s);
  if (d == null) return null;
  return s.length <= 10 ? d : d.toLocal();
}

/// Country codes: two capital letters, unique, in order.
List<String> _codes(dynamic v) {
  if (v is! List) return const [];
  final out = <String>[];
  for (final e in v) {
    final c = e?.toString().trim().toUpperCase() ?? '';
    if (RegExp(r'^[A-Z]{2}$').hasMatch(c) && !out.contains(c)) out.add(c);
  }
  return out;
}

List<String> _strings(dynamic v) {
  if (v is! List) return const [];
  return v.map(_str).whereType<String>().toList();
}

// ---------------------------------------------------------------------------
// Countries
// ---------------------------------------------------------------------------

class Country {
  const Country({
    required this.code,
    required this.name,
    this.currency,
    this.language,
    this.timezone,
    this.callingCode,
    this.region,
  });

  final String code;
  final String name;
  final String? currency;
  final String? language;
  final String? timezone;
  final String? callingCode;
  final String? region;

  factory Country.fromRow(Map<String, dynamic> m) => Country(
    code: (_str(m['country_code']) ?? '').toUpperCase(),
    name: _str(m['name']) ?? (_str(m['country_code']) ?? ''),
    currency: _str(m['default_currency']),
    language: _str(m['default_language']),
    timezone: _str(m['default_timezone']),
    callingCode: _str(m['calling_code']),
    region: _str(m['world_region']),
  );
}

List<Country> parseCountries(dynamic v) {
  final list = _maps(v)
      .map(Country.fromRow)
      .where((c) => c.code.length == 2)
      .toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
}

/// "Germany", or the code when the country is not in the list.
String countryName(String? code, Iterable<Country> countries) {
  if (code == null || code.isEmpty) return '';
  for (final c in countries) {
    if (c.code == code) return c.name;
  }
  return code;
}

/// Countries whose name or code matches what the worker typed.
List<Country> searchCountries(Iterable<Country> countries, String q) {
  final s = q.trim().toLowerCase();
  if (s.isEmpty) return countries.toList();
  return countries
      .where((c) =>
          c.name.toLowerCase().contains(s) || c.code.toLowerCase() == s)
      .toList();
}

/// Languages on countries use ISO 639-3 codes.
String languageName(String? code) => switch (code?.toLowerCase()) {
  null || '' => '',
  'eng' => 'English',
  'hin' => 'Hindi',
  'ara' => 'Arabic',
  'deu' => 'German',
  'nld' => 'Dutch',
  'por' => 'Portuguese',
  'spa' => 'Spanish',
  'fra' => 'French',
  'ita' => 'Italian',
  'pol' => 'Polish',
  'swe' => 'Swedish',
  'nor' => 'Norwegian',
  'dan' => 'Danish',
  'tur' => 'Turkish',
  'jpn' => 'Japanese',
  'kor' => 'Korean',
  'zho' => 'Chinese',
  'msa' => 'Malay',
  'tha' => 'Thai',
  'vie' => 'Vietnamese',
  'ind' => 'Indonesian',
  'urd' => 'Urdu',
  'ben' => 'Bengali',
  'sin' => 'Sinhala',
  'nep' => 'Nepali',
  'heb' => 'Hebrew',
  final c => c.toUpperCase(),
};

// ---------------------------------------------------------------------------
// Mobility profile
// ---------------------------------------------------------------------------

enum RemotePreference {
  onsiteOnly('onsite_only', 'At the workplace', 'I want to go to work in person'),
  hybrid('hybrid', 'Some days from home', 'A mix of the workplace and home'),
  remoteOnly('remote_only', 'From home only', 'I only want remote work'),
  any('any', 'Any of these', 'Show me every kind of job');

  const RemotePreference(this.wire, this.label, this.help);
  final String wire;
  final String label;
  final String help;

  static RemotePreference fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? any;
}

/// Who may see my work-authorization records (never shown without my say).
enum AuthorizationVisibility {
  private(
    'private',
    'Only me',
    'Employers never see your work permission records. An employer you '
        'apply to still sees only "Eligible" or "Potentially eligible". '
        'Employers searching for people allowed to work in their country will '
        'not find you through it.',
  ),
  eligibilityOnly(
    'eligibility_only',
    'Employers see only whether I\'m eligible',
    'Employers see "Eligible" or "Potentially eligible" for their job, and '
        'can find you when they search for people allowed to work in their '
        'country. They never see your visa type, dates or limits.',
  ),
  detailsWithApplications(
    'details_with_applications',
    'Show details to employers I apply to',
    'When you apply to a job, that employer can also see the country, type '
        'of permission and dates. Nobody else can.',
  ),
  detailsWithVisible(
    'details_with_visible',
    'Show details to employers who can find me',
    'Employers who can see your profile in searches, and employers you '
        'apply to, can see the country, type of permission and dates.',
  );

  const AuthorizationVisibility(this.wire, this.title, this.explanation);
  final String wire;
  final String title;
  final String explanation;

  static const standard = eligibilityOnly;

  static AuthorizationVisibility fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? standard;
}

class MobilityProfile {
  const MobilityProfile({
    this.currentCountry,
    this.citizenships = const [],
    this.timezone,
    this.openToRelocation = false,
    this.preferredCountries = const [],
    this.preferredCityIds = const [],
    this.countriesWillingToWork = const [],
    this.relocationAssistanceRequired = false,
    this.earliestRelocationDate,
    this.remotePreference = RemotePreference.any,
    this.requiresSponsorship,
    this.visibility = AuthorizationVisibility.standard,
  });

  final String? currentCountry;
  final List<String> citizenships;
  final String? timezone;
  final bool openToRelocation;
  final List<String> preferredCountries;
  final List<String> preferredCityIds;
  final List<String> countriesWillingToWork;
  final bool relocationAssistanceRequired;
  final DateTime? earliestRelocationDate;
  final RemotePreference remotePreference;

  /// Null: not said.
  final bool? requiresSponsorship;
  final AuthorizationVisibility visibility;

  static const maxCitizenships = 5;
  static const maxPreferredCountries = 30;
  static const maxPreferredCities = 30;
  static const maxWillingCountries = 60;

  /// [defaultVisibility] comes from the server's `defaults` when the worker
  /// has not saved anything yet.
  factory MobilityProfile.fromJson(dynamic v, {String? defaultVisibility}) {
    final m = _map(v);
    if (m == null) {
      return MobilityProfile(
        visibility: AuthorizationVisibility.fromWire(defaultVisibility),
      );
    }
    return MobilityProfile(
      currentCountry: _str(m['current_country'])?.toUpperCase(),
      citizenships: _codes(m['citizenships']),
      timezone: _str(m['timezone']),
      openToRelocation: _bool(m['open_to_relocation']),
      preferredCountries: _codes(m['preferred_countries']),
      preferredCityIds: _strings(m['preferred_city_ids']),
      countriesWillingToWork: _codes(m['countries_willing_to_work']),
      relocationAssistanceRequired: _bool(m['relocation_assistance_required']),
      earliestRelocationDate: _date(m['earliest_relocation_date']),
      remotePreference: RemotePreference.fromWire(_str(m['remote_preference'])),
      requiresSponsorship: _boolOrNull(m['requires_sponsorship']),
      visibility: AuthorizationVisibility.fromWire(
        _str(m['authorization_visibility']) ?? defaultVisibility,
      ),
    );
  }

  MobilityProfile copyWith({
    String? Function()? currentCountry,
    List<String>? citizenships,
    String? Function()? timezone,
    bool? openToRelocation,
    List<String>? preferredCountries,
    List<String>? preferredCityIds,
    List<String>? countriesWillingToWork,
    bool? relocationAssistanceRequired,
    DateTime? Function()? earliestRelocationDate,
    RemotePreference? remotePreference,
    bool? Function()? requiresSponsorship,
    AuthorizationVisibility? visibility,
  }) => MobilityProfile(
    currentCountry: currentCountry != null ? currentCountry() : this.currentCountry,
    citizenships: citizenships ?? this.citizenships,
    timezone: timezone != null ? timezone() : this.timezone,
    openToRelocation: openToRelocation ?? this.openToRelocation,
    preferredCountries: preferredCountries ?? this.preferredCountries,
    preferredCityIds: preferredCityIds ?? this.preferredCityIds,
    countriesWillingToWork: countriesWillingToWork ?? this.countriesWillingToWork,
    relocationAssistanceRequired:
        relocationAssistanceRequired ?? this.relocationAssistanceRequired,
    earliestRelocationDate: earliestRelocationDate != null
        ? earliestRelocationDate()
        : this.earliestRelocationDate,
    remotePreference: remotePreference ?? this.remotePreference,
    requiresSponsorship: requiresSponsorship != null
        ? requiresSponsorship()
        : this.requiresSponsorship,
    visibility: visibility ?? this.visibility,
  );

  /// The `p` argument of `omelo_save_mobility`. Every key is sent: the
  /// server replaces the whole profile.
  Map<String, Object?> toPayload() => {
    'current_country': currentCountry,
    'citizenships': citizenships,
    'timezone': timezone,
    'open_to_relocation': openToRelocation,
    'preferred_countries': preferredCountries,
    'preferred_city_ids': preferredCityIds,
    'countries_willing_to_work': countriesWillingToWork,
    'relocation_assistance_required': relocationAssistanceRequired,
    'earliest_relocation_date': earliestRelocationDate == null
        ? null
        : wireDate(earliestRelocationDate!),
    'remote_preference': remotePreference.wire,
    'requires_sponsorship': requiresSponsorship,
    'authorization_visibility': visibility.wire,
  };

  @override
  bool operator ==(Object other) =>
      other is MobilityProfile &&
      _deepEq(toPayload(), other.toPayload());

  @override
  int get hashCode => toPayload().toString().hashCode;
}

bool _deepEq(Map<String, Object?> a, Map<String, Object?> b) {
  if (a.length != b.length) return false;
  for (final k in a.keys) {
    final x = a[k], y = b[k];
    if (x is List && y is List) {
      if (x.length != y.length) return false;
      for (var i = 0; i < x.length; i++) {
        if (x[i] != y[i]) return false;
      }
    } else if (x != y) {
      return false;
    }
  }
  return true;
}

/// A reason the profile cannot be saved, in the worker's words, or null.
String? validateMobility(MobilityProfile p) {
  if (p.citizenships.length > MobilityProfile.maxCitizenships) {
    return 'Add up to ${MobilityProfile.maxCitizenships} citizenships.';
  }
  if (p.preferredCountries.length > MobilityProfile.maxPreferredCountries) {
    return 'Pick up to ${MobilityProfile.maxPreferredCountries} countries to move to.';
  }
  if (p.preferredCityIds.length > MobilityProfile.maxPreferredCities) {
    return 'Pick up to ${MobilityProfile.maxPreferredCities} cities.';
  }
  if (p.countriesWillingToWork.length > MobilityProfile.maxWillingCountries) {
    return 'Pick up to ${MobilityProfile.maxWillingCountries} countries you could work in.';
  }
  return null;
}

/// "Yes" / "No" / "Not sure" for "Do you need visa sponsorship?"
String sponsorshipNeedLabel(bool? v) => switch (v) {
  true => 'Yes, I need sponsorship',
  false => 'No, I don\'t',
  null => 'Not sure',
};

// ---------------------------------------------------------------------------
// Work authorizations
// ---------------------------------------------------------------------------

enum WorkAuthStatus {
  citizen('citizen', 'Citizen', 'I am a citizen of this country'),
  permanentResident(
    'permanent_resident',
    'Permanent resident',
    'I can live and work here without a time limit',
  ),
  workPermit('work_permit', 'Work permit or work visa', 'I have a permit to work here'),
  employerSponsored(
    'employer_sponsored',
    'Visa tied to one employer',
    'My permit lets me work only for the employer who sponsors me',
  ),
  dependentVisaWorkRights(
    'dependent_visa_work_rights',
    'Family visa that allows work',
    'I am here with a family member and my visa lets me work',
  ),
  studentVisaLimited(
    'student_visa_limited',
    'Student visa (limited hours)',
    'I can work only some hours a week',
  ),
  requiresSponsorship(
    'requires_sponsorship',
    'I need an employer to sponsor a visa',
    'I cannot work here yet without sponsorship',
  ),
  noRightToWork(
    'no_right_to_work',
    'No right to work here',
    'I am not allowed to work in this country right now',
  ),
  otherAuthorization(
    'other_authorization',
    'Other permission to work',
    'Something else lets me work here',
  ),
  unknown('unknown', 'I\'m not sure', 'I don\'t know my status yet');

  const WorkAuthStatus(this.wire, this.label, this.help);
  final String wire;
  final String label;
  final String help;

  static WorkAuthStatus fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? unknown;

  /// Statuses the server treats as "needs sponsorship" (the column is
  /// computed by the database, never written by the app).
  bool get needsSponsorship =>
      this == requiresSponsorship ||
      this == noRightToWork ||
      this == studentVisaLimited;

  /// Citizens and permanent residents have no dates to add.
  bool get hasDates => this != citizen && this != permanentResident;
}

class WorkAuthorization {
  const WorkAuthorization({
    required this.id,
    required this.country,
    this.countryName,
    required this.status,
    this.validFrom,
    this.expiresOn,
    this.restrictions,
    this.requiresSponsorship = false,
    this.isVerified = false,
    this.hasDocument = false,
  });

  final String id;
  final String country;
  final String? countryName;
  final WorkAuthStatus status;
  final DateTime? validFrom;
  final DateTime? expiresOn;
  final String? restrictions;
  final bool requiresSponsorship;
  final bool isVerified;
  final bool hasDocument;

  static const maxRestrictions = 500;

  factory WorkAuthorization.fromJson(Map<String, dynamic> m) => WorkAuthorization(
    id: _str(m['id']) ?? '',
    country: (_str(m['country']) ?? _str(m['country_code']) ?? '').toUpperCase(),
    countryName: _str(m['country_name']),
    status: WorkAuthStatus.fromWire(_str(m['status'])),
    validFrom: _date(m['valid_from']),
    expiresOn: _date(m['expires_on']),
    restrictions: _str(m['restrictions']) ?? _str(m['work_restrictions']),
    requiresSponsorship: _bool(m['requires_sponsorship']),
    isVerified: _bool(m['is_verified']),
    hasDocument: _bool(m['has_document']),
  );

  String get displayCountry => countryName ?? country;

  bool isExpiredAt(DateTime now) =>
      expiresOn != null &&
      DateTime(expiresOn!.year, expiresOn!.month, expiresOn!.day)
          .isBefore(DateTime(now.year, now.month, now.day));
}

List<WorkAuthorization> parseAuthorizations(dynamic v) => _maps(v)
    .map(WorkAuthorization.fromJson)
    .where((a) => a.id.isNotEmpty)
    .toList();

/// "Valid 1 Jan 2025 – 31 Jan 2029" · "Expired 31 Jan 2026" · "From 1 Mar"
String? authorizationDatesLine(WorkAuthorization a, DateTime now) {
  String d(DateTime x) => shortDate(x, now);
  final from = a.validFrom, to = a.expiresOn;
  if (to != null && a.isExpiredAt(now)) return 'Expired ${d(to)}';
  if (from != null && to != null) return 'Valid ${d(from)} – ${d(to)}';
  if (to != null) return 'Valid until ${d(to)}';
  if (from != null) {
    return from.isAfter(now) ? 'Starts ${d(from)}' : 'Valid from ${d(from)}';
  }
  return null;
}

/// Why this authorization cannot be saved, or null.
String? validateAuthorization({
  required String? country,
  required WorkAuthStatus? status,
  DateTime? validFrom,
  DateTime? expiresOn,
  String? restrictions,
}) {
  if (country == null || country.isEmpty) return 'Choose the country.';
  if (status == null) return 'Choose what lets you work there.';
  if (validFrom != null && expiresOn != null && expiresOn.isBefore(validFrom)) {
    return 'The end date is before the start date.';
  }
  if ((restrictions ?? '').trim().length > WorkAuthorization.maxRestrictions) {
    return 'Keep the limits under ${WorkAuthorization.maxRestrictions} characters.';
  }
  return null;
}

/// The row written to `work_authorizations`. `requires_sponsorship` is
/// computed by the database and `is_verified` is Omelo's to set, so neither
/// is ever sent.
Map<String, Object?> authorizationRow({
  String? personId,
  required String country,
  required WorkAuthStatus status,
  DateTime? validFrom,
  DateTime? expiresOn,
  String? restrictions,
}) {
  final r = restrictions?.trim();
  return {
    'person_id': ?personId,
    'country_code': country.toUpperCase(),
    'status': status.wire,
    'valid_from': validFrom == null ? null : wireDate(validFrom),
    'expires_on': expiresOn == null ? null : wireDate(expiresOn),
    'work_restrictions': (r == null || r.isEmpty) ? null : r,
  };
}

/// Everything the mobility screen loads in one call.
class MyMobility {
  const MyMobility({
    required this.profile,
    required this.saved,
    this.authorizations = const [],
  });

  final MobilityProfile profile;

  /// False until the worker saves the profile for the first time.
  final bool saved;
  final List<WorkAuthorization> authorizations;

  factory MyMobility.fromJson(dynamic v) {
    final m = _map(v) ?? const <String, dynamic>{};
    final defaults = _map(m['defaults']);
    return MyMobility(
      profile: MobilityProfile.fromJson(
        m['mobility'],
        defaultVisibility: _str(defaults?['authorization_visibility']),
      ),
      saved: _map(m['mobility']) != null,
      authorizations: parseAuthorizations(m['authorizations']),
    );
  }
}

// ---------------------------------------------------------------------------
// Pay and currency
// ---------------------------------------------------------------------------

/// "1 EUR = 91.23 INR"
String rateLine(num rate, String from, String to) {
  final digits = rate >= 100 ? 2 : (rate >= 1 ? 4 : 6);
  final text = NumberFormat.decimalPatternDigits(locale: 'en', decimalDigits: digits)
      .format(rate)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
  return '1 $from = $text $to';
}

/// Pay converted into the worker's currency, with the rate that was used.
class ConvertedPay {
  const ConvertedPay({
    required this.currency,
    this.hourly,
    this.monthly,
    this.yearly,
    this.rate,
    this.source,
    this.effectiveAt,
  });

  final String currency;
  final num? hourly;
  final num? monthly;
  final num? yearly;
  final num? rate;
  final String? source;
  final DateTime? effectiveAt;

  static ConvertedPay? fromJson(dynamic v) {
    final m = _map(v);
    final cur = _str(m?['currency'])?.toUpperCase();
    if (m == null || cur == null) return null;
    return ConvertedPay(
      currency: cur,
      hourly: _num(m['hourly']),
      monthly: _num(m['monthly']),
      yearly: _num(m['yearly']),
      rate: _num(m['rate']),
      source: _str(m['source']),
      effectiveAt: _date(m['effective_at']),
    );
  }
}

/// The server's hourly / monthly / yearly view of one pay amount, in the
/// job's currency, and (when different) in the worker's.
class NormalizedPay {
  const NormalizedPay({
    this.amount,
    this.period,
    required this.currency,
    this.hourly,
    this.monthly,
    this.yearly,
    this.target,
    this.note,
  });

  final num? amount;
  final String? period;
  final String currency;
  final num? hourly;
  final num? monthly;
  final num? yearly;
  final ConvertedPay? target;
  final String? note;

  static NormalizedPay? fromJson(dynamic v) {
    final m = _map(v);
    final cur = _str(m?['currency'])?.toUpperCase();
    if (m == null || cur == null) return null;
    return NormalizedPay(
      amount: _num(m['amount']),
      period: _str(m['period']),
      currency: cur,
      hourly: _num(m['hourly']),
      monthly: _num(m['monthly']),
      yearly: _num(m['yearly']),
      target: ConvertedPay.fromJson(m['target']),
      note: _str(m['note']),
    );
  }
}

/// Pay on a job card: the job's own amounts and currency.
class JobPay {
  const JobPay({
    this.min,
    this.max,
    this.period,
    required this.currency,
    this.normalized,
  });

  final num? min;
  final num? max;
  final String? period;
  final String currency;
  final NormalizedPay? normalized;

  static JobPay? fromJson(dynamic v) {
    final m = _map(v);
    final cur = _str(m?['currency'])?.toUpperCase();
    if (m == null || cur == null) return null;
    final min = _num(m['min']), max = _num(m['max']);
    if (min == null && max == null) return null;
    return JobPay(
      min: min,
      max: max,
      period: _str(m['period']),
      currency: cur,
      normalized: NormalizedPay.fromJson(m['normalized']),
    );
  }
}

/// "€2,800 – €3,400 per month", always in [currency].
String payRangeLine(num? min, num? max, String currency, String? period) {
  if (min == null && max == null) return 'Pay not shown';
  final body = (min != null && max != null && min != max)
      ? '${money(min, currency)} – ${money(max, currency)}'
      : money((max ?? min)!, currency);
  final per = payPeriodWords(period);
  return per.isEmpty ? body : '$body $per';
}

String payLineOf(JobPay p) => payRangeLine(p.min, p.max, p.currency, p.period);

/// The converted amount in the unit closest to how the job pays.
({num amount, String per})? _converted(ConvertedPay t, String? period) {
  final (num? v, String per) = switch (period) {
    'hour' => (t.hourly, 'an hour'),
    'year' => (t.yearly, 'a year'),
    _ => (t.monthly, 'a month'),
  };
  if (v == null) return null;
  return (amount: v, per: per);
}

/// "≈ ₹3,10,000 a month in INR" — or null when there is nothing to convert
/// (same currency, per-task pay, or no rate).
String? approxPayLine(NormalizedPay? n, {bool isUpperBound = false}) {
  final t = n?.target;
  if (n == null || t == null || t.currency == n.currency) return null;
  final c = _converted(t, n.period);
  if (c == null) return null;
  final upTo = isUpperBound ? 'up to ' : '';
  return '≈ $upTo${money(c.amount, t.currency)} ${c.per} in ${t.currency}';
}

String? approxPayLineOf(JobPay p) => approxPayLine(
  p.normalized,
  isUpperBound: p.min != null && p.max != null && p.min != p.max,
);

/// Where the conversion came from, for the tooltip.
String? conversionSource(NormalizedPay? n, {DateTime? now}) {
  final t = n?.target;
  if (n == null || t == null) return null;
  final parts = <String>[
    if (t.rate != null) 'Rate: ${rateLine(t.rate!, n.currency, t.currency)}',
    if (t.source != null) 'Source: ${t.source}',
    if (t.effectiveAt != null)
      'Rate date: ${shortDate(t.effectiveAt!, now ?? DateTime.now())}',
    'For comparison only. The job pays in ${n.currency}.',
  ];
  return parts.join('\n');
}

// ---------------------------------------------------------------------------
// Eligibility
// ---------------------------------------------------------------------------

enum EligibilityStatus {
  eligible('eligible', 'Eligible'),
  potentiallyEligible('potentially_eligible', 'Potentially eligible'),
  notEligible('not_eligible', 'Not currently eligible');

  const EligibilityStatus(this.wire, this.label);
  final String wire;
  final String label;

  static EligibilityStatus? fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull;
}

class EligibilityGap {
  const EligibilityGap({required this.kind, required this.text});
  final String kind;
  final String text;
}

class OfficialSource {
  const OfficialSource({
    required this.title,
    this.url,
    this.source,
    this.topic,
    this.summary,
    this.reviewedAt,
  });

  final String title;
  final String? url;
  final String? source;
  final String? topic;
  final String? summary;
  final DateTime? reviewedAt;

  factory OfficialSource.fromJson(Map<String, dynamic> m) => OfficialSource(
    title: _str(m['title']) ?? _str(m['source']) ?? 'Official source',
    url: _str(m['url']),
    source: _str(m['source']),
    topic: _str(m['topic']),
    summary: _str(m['summary']),
    reviewedAt: _date(m['reviewed_at']),
  );

  /// Only secure web links are opened.
  Uri? get link => safeLink(url);
}

/// An https link, or null.
Uri? safeLink(String? url) {
  final u = Uri.tryParse(url?.trim() ?? '');
  if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
  return u;
}

class LicenceRequirement {
  const LicenceRequirement({
    required this.name,
    this.description,
    this.url,
    this.source,
    this.level,
    this.profession,
    this.reviewedAt,
  });

  final String name;
  final String? description;
  final String? url;
  final String? source;

  /// 'required' | 'recommended'
  final String? level;
  final String? profession;
  final DateTime? reviewedAt;

  bool get isRequired => level != 'recommended';
  Uri? get link => safeLink(url);

  factory LicenceRequirement.fromJson(Map<String, dynamic> m) =>
      LicenceRequirement(
        name: _str(m['name']) ?? 'Licence',
        description: _str(m['description']),
        url: _str(m['url']),
        source: _str(m['source']),
        level: _str(m['level']),
        profession: _str(m['profession']),
        reviewedAt: _date(m['reviewed_at']),
      );
}

List<LicenceRequirement> parseLicences(dynamic v) =>
    _maps(v).map(LicenceRequirement.fromJson).toList();

List<OfficialSource> parseSources(dynamic v) =>
    _maps(v).map(OfficialSource.fromJson).toList();

const notLegalAdvice = 'Not legal advice';
const informationOnlyBanner = 'Information only — not legal advice';

class JobEligibility {
  const JobEligibility({
    required this.status,
    this.summary,
    this.missing = const [],
    this.notes = const [],
    this.country,
    this.officialSources = const [],
    this.licences = const [],
    this.pay,
    this.disclaimer,
  });

  /// Null when the server sent a status this app does not know.
  final EligibilityStatus? status;
  final String? summary;
  final List<EligibilityGap> missing;
  final List<String> notes;
  final String? country;
  final List<OfficialSource> officialSources;
  final List<LicenceRequirement> licences;
  final NormalizedPay? pay;
  final String? disclaimer;

  static JobEligibility? fromJson(dynamic v) {
    final m = _map(v);
    if (m == null) return null;
    return JobEligibility(
      status: EligibilityStatus.fromWire(_str(m['status'])),
      summary: _str(m['summary']),
      missing: _maps(m['missing'])
          .map((g) => EligibilityGap(
                kind: _str(g['kind']) ?? '',
                text: _str(g['text']) ?? '',
              ))
          .where((g) => g.text.isNotEmpty)
          .toList(),
      notes: _strings(m['notes']),
      country: _str(m['country'])?.toUpperCase(),
      officialSources: parseSources(m['official_sources']),
      licences: parseLicences(m['licence_requirements']),
      pay: NormalizedPay.fromJson(m['pay']),
      disclaimer: _str(m['disclaimer']),
    );
  }

  /// "Eligible" · "Potentially eligible" · "Not currently eligible"
  String get label => status?.label ?? summary ?? 'Eligibility unknown';

  /// "Potentially eligible — Missing: Work authorization for Germany"
  String get headline {
    if (status == EligibilityStatus.eligible || missing.isEmpty) return label;
    return '$label — Missing: ${missing.map((g) => g.text).join('; ')}';
  }
}

// ---------------------------------------------------------------------------
// Global job discovery
// ---------------------------------------------------------------------------

enum GlobalTab {
  nearMe('near_me', 'Near me', 'No jobs near you match. Try a wider search.'),
  remote('remote', 'Remote', 'No remote jobs you can do from where you live yet.'),
  relocation(
    'relocation',
    'Relocation',
    'No jobs with help to move right now.',
  ),
  visaSponsorship(
    'visa_sponsorship',
    'Visa sponsorship',
    'No jobs offering visa sponsorship right now.',
  ),
  international(
    'international',
    'International',
    'No jobs in other countries match yet.',
  ),
  workAbroad(
    'work_abroad',
    'Work abroad',
    'No jobs abroad that fit your plans yet. Add the countries you would '
        'move to in Global mobility.',
  );

  const GlobalTab(this.wire, this.label, this.emptyText);
  final String wire;
  final String label;
  final String emptyText;

  static GlobalTab fromWire(String? v) =>
      values.where((e) => e.wire == v).firstOrNull ?? international;
}

class GlobalJobFilters {
  const GlobalJobFilters({this.country, this.query, this.lat, this.lng});

  final String? country;
  final String? query;

  /// Only for "Near me"; without them the server uses the profile location.
  final double? lat;
  final double? lng;

  Map<String, Object?> toJson(GlobalTab tab) {
    final q = query?.trim();
    return {
      if (country != null && country!.isNotEmpty) 'country': country,
      if (q != null && q.isNotEmpty) 'query': q,
      if (tab == GlobalTab.nearMe && lat != null && lng != null) ...{
        'lat': lat,
        'lng': lng,
      },
    };
  }
}

class GlobalJob {
  const GlobalJob({
    required this.id,
    required this.title,
    this.companyName = '',
    this.companyVerified = false,
    this.country,
    this.countryName,
    this.locationText,
    this.distanceKm,
    this.workplace,
    this.workType,
    this.remoteScope,
    this.remoteCountries = const [],
    this.sponsorship,
    this.relocationSupport = false,
    this.support = const {},
    this.pay,
    this.publishedAt,
    this.eligibility,
  });

  final String id;
  final String title;
  final String companyName;
  final bool companyVerified;
  final String? country;
  final String? countryName;
  final String? locationText;
  final double? distanceKm;
  final String? workplace;
  final String? workType;
  final String? remoteScope;
  final List<String> remoteCountries;

  /// 'yes' | 'no' | 'case_by_case'
  final String? sponsorship;
  final bool relocationSupport;

  /// immigration, legal, visa_fees, travel, accommodation → offered?
  final Map<String, bool> support;
  final JobPay? pay;
  final DateTime? publishedAt;
  final JobEligibility? eligibility;

  factory GlobalJob.fromJson(Map<String, dynamic> m) {
    final s = _map(m['support']) ?? const {};
    return GlobalJob(
      id: _str(m['job_id']) ?? _str(m['id']) ?? '',
      title: _str(m['title']) ?? '',
      companyName: _str(m['company_name']) ?? '',
      companyVerified: _bool(m['company_verified']),
      country: _str(m['country'])?.toUpperCase(),
      countryName: _str(m['country_name']),
      locationText: _str(m['location_text']),
      distanceKm: _num(m['distance_km'])?.toDouble(),
      workplace: _str(m['workplace_type']),
      workType: _str(m['work_type']),
      remoteScope: _str(m['remote_scope']),
      remoteCountries: _codes(m['remote_countries']),
      sponsorship: _str(m['sponsorship']),
      relocationSupport: _bool(m['relocation_support']),
      support: {for (final e in s.entries) e.key: _bool(e.value)},
      pay: JobPay.fromJson(m['pay']),
      publishedAt: _date(m['published_at']),
      eligibility: JobEligibility.fromJson(m['eligibility']),
    );
  }

  /// "Germany · Berlin, Mitte"
  String get placeLine => [
    ?(countryName ?? country),
    if (locationText != null && locationText != (countryName ?? country))
      locationText,
  ].join(' · ');
}

class GlobalJobsPage {
  const GlobalJobsPage({
    required this.tab,
    this.total = 0,
    this.results = const [],
    this.viewerCurrency,
    this.homeCountry,
  });

  final GlobalTab tab;
  final int total;
  final List<GlobalJob> results;
  final String? viewerCurrency;
  final String? homeCountry;

  factory GlobalJobsPage.fromJson(dynamic v) {
    final m = _map(v) ?? const <String, dynamic>{};
    return GlobalJobsPage(
      tab: GlobalTab.fromWire(_str(m['tab'])),
      total: (_num(m['total']) ?? 0).toInt(),
      results: _maps(m['results'])
          .map(GlobalJob.fromJson)
          .where((j) => j.id.isNotEmpty)
          .toList(),
      viewerCurrency: _str(m['viewer_currency'])?.toUpperCase(),
      homeCountry: _str(m['home_country'])?.toUpperCase(),
    );
  }
}

/// "Visa sponsorship" · "Sponsorship case by case" · null
String? sponsorshipLabel(String? s) => switch (s) {
  'yes' => 'Visa sponsorship',
  'case_by_case' => 'Sponsorship case by case',
  _ => null,
};

/// The help an employer offers with moving, in plain words.
List<String> supportLabels(GlobalJob j) {
  const words = {
    'immigration': 'Immigration help',
    'legal': 'Legal help',
    'visa_fees': 'Visa fees paid',
    'travel': 'Travel paid',
    'accommodation': 'Housing help',
  };
  return [
    if (j.relocationSupport) 'Relocation help',
    for (final e in words.entries)
      if (j.support[e.key] == true) e.value,
  ];
}

/// "Remote · anywhere" · "Remote · from India, Nepal" · "Remote · set hours"
String? remoteLine(GlobalJob j, {Iterable<Country> countries = const []}) {
  if (j.workplace != 'remote') return null;
  return switch (j.remoteScope) {
    'worldwide' => 'Remote from anywhere',
    'countries' when j.remoteCountries.isNotEmpty =>
      'Remote from ${j.remoteCountries.map((c) => countryName(c, countries)).join(', ')}',
    'timezone' => 'Remote within set time zones',
    _ => 'Remote from ${j.countryName ?? 'the job\'s country'}',
  };
}

// ---------------------------------------------------------------------------
// Country guide
// ---------------------------------------------------------------------------

String topicLabel(String? topic) => switch (topic) {
  'work_authorization' => 'Permission to work',
  'documents' => 'Documents',
  'licensing' => 'Licences',
  'hiring' => 'Getting hired',
  'worker_rights' => 'Your rights at work',
  'tax_payroll' => 'Tax and pay',
  'official_portal' => 'Official websites',
  null => 'More information',
  final t => t.replaceAll('_', ' '),
};

class CountryGuide {
  const CountryGuide({
    required this.code,
    required this.name,
    this.currency,
    this.currencyName,
    this.language,
    this.timezone,
    this.callingCode,
    this.region,
    this.information = const [],
    this.licences = const [],
    this.disclaimer,
  });

  final String code;
  final String name;
  final String? currency;
  final String? currencyName;
  final String? language;
  final String? timezone;
  final String? callingCode;
  final String? region;
  final List<OfficialSource> information;
  final List<LicenceRequirement> licences;
  final String? disclaimer;

  static CountryGuide? fromJson(dynamic v, {String? code}) {
    final m = _map(v);
    if (m == null) return null;
    final c = (_str(m['country']) ?? code ?? '').toUpperCase();
    return CountryGuide(
      code: c,
      name: _str(m['name']) ?? c,
      currency: _str(m['currency'])?.toUpperCase(),
      currencyName: _str(m['currency_name']),
      language: _str(m['language']),
      timezone: _str(m['timezone']),
      callingCode: _str(m['calling_code']),
      region: _str(m['region']),
      information: parseSources(m['information']),
      licences: parseLicences(m['licence_requirements']),
      disclaimer: _str(m['disclaimer']),
    );
  }

  /// Information grouped by topic, in the order the server sent it.
  Map<String, List<OfficialSource>> get byTopic {
    final out = <String, List<OfficialSource>>{};
    for (final i in information) {
      out.putIfAbsent(topicLabel(i.topic), () => []).add(i);
    }
    return out;
  }

  /// "+49" even when the server leaves out the plus.
  String? get dialCode {
    final c = callingCode;
    if (c == null) return null;
    return c.startsWith('+') ? c : '+$c';
  }
}
