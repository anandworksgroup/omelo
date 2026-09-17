import 'package:flutter_test/flutter_test.dart';
import 'package:omelo_user_app/core/env.dart';

void main() {
  test('default dev config is sane', () {
    expect(Env.isConfigured, isTrue);
    expect(Env.usesDevProject, isTrue);
  });

  test('config problems are reported, not thrown', () {
    expect(Env.configProblems('https://abc.supabase.co', 'sb_publishable_x'),
        isEmpty);
    expect(Env.configProblems('', 'sb_publishable_x'), isNotEmpty);
    expect(Env.configProblems('http://abc.supabase.co', 'sb_publishable_x'),
        contains('SUPABASE_URL must use https'));
    expect(Env.configProblems('http://10.0.2.2:54321', 'sb_publishable_x'),
        isEmpty);
    expect(Env.configProblems('https://abc.supabase.co', ''),
        contains('SUPABASE_KEY is missing'));
    expect(Env.configProblems('https://abc.supabase.co', 'sb_secret_abc'),
        hasLength(1));
    // A JWT whose payload says service_role: {"role":"service_role"}
    const jwt = 'eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.sig';
    expect(Env.configProblems('https://abc.supabase.co', jwt), hasLength(1));
  });
}
