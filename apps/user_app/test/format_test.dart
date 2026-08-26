import 'package:flutter_test/flutter_test.dart';
import 'package:omelo_user_app/core/format.dart';

void main() {
  group('pay formatting — money is never a bare number', () {
    test('monthly salary uses Indian digit grouping', () {
      expect(
        Fmt.pay(min: 18000, max: 28000, currency: 'INR', period: 'month'),
        '₹18,000 – ₹28,000/month',
      );
    });

    test('lakh-scale grouping is Indian, not Western', () {
      expect(
        Fmt.pay(min: 700000, max: 1400000, currency: 'INR', period: 'year'),
        '₹7,00,000 – ₹14,00,000/year',
      );
    });

    test('daily wage keeps its period — never silently monthly', () {
      expect(
        Fmt.pay(min: 550, max: 750, currency: 'INR', period: 'day'),
        '₹550 – ₹750/day',
      );
    });

    test('single value does not render a fake range', () {
      expect(Fmt.pay(min: 25000, currency: 'INR', period: 'month'),
          '₹25,000/month');
    });

    test('missing pay is stated, never guessed', () {
      expect(Fmt.pay(currency: 'INR', period: 'month'), 'Pay not shown');
    });

    test('per_task has no slash prefix', () {
      expect(Fmt.pay(min: 300, currency: 'INR', period: 'per_task'),
          '₹300 per task');
    });

    test('negotiable is surfaced', () {
      expect(
        Fmt.pay(min: 20000, currency: 'INR', period: 'month', negotiable: true),
        '₹20,000/month · negotiable',
      );
    });
  });

  group('distance', () {
    test('under a kilometre shows metres', () {
      expect(Fmt.distance(0.45), '450 m');
    });
    test('short distances keep one decimal', () {
      expect(Fmt.distance(4.14), '4.1 km');
    });
    test('long distances round', () {
      expect(Fmt.distance(23.7), '24 km');
    });
    test('null distance renders empty, not "null"', () {
      expect(Fmt.distance(null), '');
    });
  });

  group('experience — never framed as a deficiency', () {
    test('accepts_no_experience wins over any minimum', () {
      expect(Fmt.experience(24, true), 'No experience needed');
    });
    test('zero months is not "0 years"', () {
      expect(Fmt.experience(0, false), 'No experience needed');
    });
    test('sub-year experience shows months', () {
      expect(Fmt.experience(6, false), '6 months experience');
    });
    test('years are pluralised correctly', () {
      expect(Fmt.experience(12, false), '1+ year experience');
      expect(Fmt.experience(48, false), '4+ years experience');
    });
  });

  group('employer response signal', () {
    test('under a day is phrased in days, not hours', () {
      expect(Fmt.responseTime(12), 'usually replies within a day');
    });
    test('multi-day rounds and pluralises', () {
      expect(Fmt.responseTime(72), 'usually replies in 3 days');
      expect(Fmt.responseTime(24), 'usually replies in 1 day');
    });
    test('unknown response time returns null so the UI can omit it', () {
      expect(Fmt.responseTime(null), isNull);
    });
  });

  group('labels cover the full universal-work enum surface', () {
    test('daily_wage and gig are not left as raw enum values', () {
      expect(Fmt.workType('daily_wage'), 'Daily wage');
      expect(Fmt.workType('gig'), 'Gig work');
    });
    test('blue-collar benefits have real labels', () {
      expect(Fmt.benefit('accommodation'), 'Accommodation');
      expect(Fmt.benefit('transport'), 'Transport');
      expect(Fmt.benefit('meals'), 'Meals');
    });
    test('shift labels are human', () {
      expect(Fmt.shift('early_morning'), 'Early morning');
      expect(Fmt.shift('split'), 'Split shift');
    });
  });
}
