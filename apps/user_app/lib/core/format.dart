import 'package:intl/intl.dart';

/// Money, distance and time formatting.
///
/// The pay-period rule from docs/00 PR-6 and A1 §1: money is NEVER a bare
/// number. A daily-wage worker cannot read an annual salary, and an annual
/// salary shown as a monthly figure is a lie. Amount, currency and period
/// always travel together.
class Fmt {
  static const _periodLabels = <String, String>{
    'hour': '/hour',
    'day': '/day',
    'week': '/week',
    'fortnight': '/fortnight',
    'month': '/month',
    'year': '/year',
    'per_task': 'per task',
  };

  /// Indian digit grouping (1,20,000) for INR; Western grouping otherwise.
  static String _amount(num value, String currency) {
    final rounded = value.round();
    if (currency == 'INR') {
      return NumberFormat.decimalPattern('en_IN').format(rounded);
    }
    return NumberFormat.decimalPattern('en_US').format(rounded);
  }

  static String _symbol(String currency) {
    switch (currency) {
      case 'INR':
        return '₹';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      case 'AED':
        return 'AED ';
      default:
        return '$currency ';
    }
  }

  /// "₹18,000 – ₹28,000/month" · "₹700 – ₹1,100/day" · "Pay not shown"
  static String pay({
    num? min,
    num? max,
    String? currency,
    String? period,
    bool negotiable = false,
  }) {
    if (min == null && max == null) return 'Pay not shown';
    final cur = currency ?? 'INR';
    final sym = _symbol(cur);
    final suffix = _periodLabels[period] ?? '';

    final String body;
    if (min != null && max != null && max != min) {
      body = '$sym${_amount(min, cur)} – $sym${_amount(max, cur)}';
    } else {
      body = '$sym${_amount((min ?? max)!, cur)}';
    }
    final sep = suffix.startsWith('/') ? '' : ' ';
    return '$body$sep$suffix${negotiable ? ' · negotiable' : ''}';
  }

  /// "450 m" under a kilometre, "4.1 km" above.
  static String distance(num? km) {
    if (km == null) return '';
    if (km < 1) return '${(km * 1000).round()} m';
    if (km < 10) return '${km.toStringAsFixed(1)} km';
    return '${km.round()} km';
  }

  /// "Today" · "2 days ago" · "3 weeks ago"
  static String posted(DateTime? at) {
    if (at == null) return '';
    final d = DateTime.now().difference(at);
    if (d.inHours < 24) return 'Today';
    if (d.inDays == 1) return 'Yesterday';
    if (d.inDays < 7) return '${d.inDays} days ago';
    if (d.inDays < 14) return 'Last week';
    if (d.inDays < 60) return '${(d.inDays / 7).floor()} weeks ago';
    return '${(d.inDays / 30).floor()} months ago';
  }

  /// "usually replies in 3 days" — the employer honesty signal (FR-334).
  static String? responseTime(int? medianHours) {
    if (medianHours == null) return null;
    if (medianHours < 24) return 'usually replies within a day';
    final days = (medianHours / 24).round();
    return 'usually replies in $days day${days == 1 ? '' : 's'}';
  }

  static String workType(String? t) => switch (t) {
        'full_time' => 'Full-time',
        'part_time' => 'Part-time',
        'contract' => 'Contract',
        'freelance' => 'Freelance',
        'temporary' => 'Temporary',
        'internship' => 'Internship',
        'apprenticeship' => 'Apprenticeship',
        'seasonal' => 'Seasonal',
        'gig' => 'Gig work',
        'volunteer' => 'Volunteer',
        'daily_wage' => 'Daily wage',
        _ => t ?? '',
      };

  static String workplace(String? t) => switch (t) {
        'onsite' => 'On-site',
        'hybrid' => 'Hybrid',
        'remote' => 'Remote',
        'field_based' => 'Field based',
        'client_site' => 'Client site',
        'multiple_sites' => 'Multiple sites',
        _ => t ?? '',
      };

  static String shift(String s) => switch (s) {
        'day' => 'Day shift',
        'evening' => 'Evening shift',
        'night' => 'Night shift',
        'early_morning' => 'Early morning',
        'rotating' => 'Rotating shifts',
        'split' => 'Split shift',
        'flexible' => 'Flexible hours',
        'weekend' => 'Weekends',
        'on_call' => 'On call',
        _ => s,
      };

  static String benefit(String b) => switch (b) {
        'accommodation' => 'Accommodation',
        'transport' => 'Transport',
        'meals' => 'Meals',
        'health_insurance' => 'Health insurance',
        'life_insurance' => 'Life insurance',
        'visa_sponsorship' => 'Visa sponsorship',
        'flight_tickets' => 'Flight tickets',
        'relocation_assistance' => 'Relocation help',
        'bonus' => 'Bonus',
        'overtime_pay' => 'Overtime pay',
        'tips' => 'Tips',
        'commission' => 'Commission',
        'paid_leave' => 'Paid leave',
        'sick_leave' => 'Sick leave',
        'parental_leave' => 'Parental leave',
        'training' => 'Training',
        'equipment_provided' => 'Equipment provided',
        'uniform_provided' => 'Uniform provided',
        'childcare' => 'Childcare',
        'retirement' => 'Retirement',
        'stock_options' => 'Stock options',
        'gym' => 'Gym',
        _ => b,
      };

  /// Experience shown in the units workers use, not raw months.
  static String experience(int? minMonths, bool acceptsNone) {
    if (acceptsNone) return 'No experience needed';
    if (minMonths == null || minMonths == 0) return 'No experience needed';
    if (minMonths < 12) return '$minMonths months experience';
    final years = minMonths ~/ 12;
    return '$years+ year${years == 1 ? '' : 's'} experience';
  }
}
