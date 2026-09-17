-- ============================================================
-- OMELO 17 — Match weight profiles (docs/08 §4, features F1-F17)
--
-- Weights are DATA, not code, so per-category tuning never needs a
-- deploy. Every profile sums to 1.000.
--
-- The shape of these numbers is the product thesis in numeric form:
-- for manual and shift work, distance / pay / shift / availability
-- outweigh granular skill matching. For technology, the reverse.
-- trajectory_fit and company_preference are 0 until Phase 2 ships
-- career goals — present so the vector shape never changes.
-- ============================================================

insert into weight_profiles (name, category_id, weights, is_active)
select v.name,
       (select id from job_categories where slug = v.cat),
       v.w::jsonb,
       true
from (values
('default', null, '{
  "skill_coverage_required":0.18,"skill_coverage_preferred":0.05,"skill_depth":0.07,
  "profession_fit":0.12,"experience_fit":0.10,"distance_fit":0.12,"pay_fit":0.10,
  "shift_fit":0.05,"availability_fit":0.06,"work_type_fit":0.05,"licence_coverage":0.02,
  "attribute_fit":0.03,"education_fit":0.02,"language_fit":0.02,"benefit_fit":0.01,
  "trajectory_fit":0.00,"company_preference":0.00}'),

('delivery', 'delivery', '{
  "skill_coverage_required":0.14,"skill_coverage_preferred":0.03,"skill_depth":0.05,
  "profession_fit":0.10,"experience_fit":0.07,"distance_fit":0.20,"pay_fit":0.12,
  "shift_fit":0.06,"availability_fit":0.07,"work_type_fit":0.04,"licence_coverage":0.03,
  "attribute_fit":0.06,"education_fit":0.00,"language_fit":0.01,"benefit_fit":0.02,
  "trajectory_fit":0.00,"company_preference":0.00}'),

('warehousing', 'warehousing', '{
  "skill_coverage_required":0.16,"skill_coverage_preferred":0.04,"skill_depth":0.05,
  "profession_fit":0.10,"experience_fit":0.08,"distance_fit":0.17,"pay_fit":0.12,
  "shift_fit":0.09,"availability_fit":0.07,"work_type_fit":0.04,"licence_coverage":0.02,
  "attribute_fit":0.03,"education_fit":0.00,"language_fit":0.01,"benefit_fit":0.02,
  "trajectory_fit":0.00,"company_preference":0.00}'),

('retail', 'retail', '{
  "skill_coverage_required":0.18,"skill_coverage_preferred":0.05,"skill_depth":0.06,
  "profession_fit":0.11,"experience_fit":0.08,"distance_fit":0.16,"pay_fit":0.11,
  "shift_fit":0.07,"availability_fit":0.06,"work_type_fit":0.04,"licence_coverage":0.01,
  "attribute_fit":0.02,"education_fit":0.01,"language_fit":0.03,"benefit_fit":0.01,
  "trajectory_fit":0.00,"company_preference":0.00}'),

('food-restaurant', 'food-restaurant', '{
  "skill_coverage_required":0.20,"skill_coverage_preferred":0.05,"skill_depth":0.07,
  "profession_fit":0.11,"experience_fit":0.09,"distance_fit":0.14,"pay_fit":0.11,
  "shift_fit":0.08,"availability_fit":0.06,"work_type_fit":0.03,"licence_coverage":0.01,
  "attribute_fit":0.02,"education_fit":0.00,"language_fit":0.02,"benefit_fit":0.01,
  "trajectory_fit":0.00,"company_preference":0.00}'),

('security', 'security', '{
  "skill_coverage_required":0.15,"skill_coverage_preferred":0.04,"skill_depth":0.05,
  "profession_fit":0.11,"experience_fit":0.09,"distance_fit":0.15,"pay_fit":0.11,
  "shift_fit":0.10,"availability_fit":0.06,"work_type_fit":0.03,"licence_coverage":0.06,
  "attribute_fit":0.02,"education_fit":0.00,"language_fit":0.02,"benefit_fit":0.01,
  "trajectory_fit":0.00,"company_preference":0.00}'),

('transportation', 'transportation', '{
  "skill_coverage_required":0.14,"skill_coverage_preferred":0.03,"skill_depth":0.05,
  "profession_fit":0.10,"experience_fit":0.10,"distance_fit":0.16,"pay_fit":0.12,
  "shift_fit":0.07,"availability_fit":0.06,"work_type_fit":0.03,"licence_coverage":0.05,
  "attribute_fit":0.06,"education_fit":0.00,"language_fit":0.01,"benefit_fit":0.02,
  "trajectory_fit":0.00,"company_preference":0.00}'),

('construction', 'construction', '{
  "skill_coverage_required":0.20,"skill_coverage_preferred":0.04,"skill_depth":0.08,
  "profession_fit":0.11,"experience_fit":0.10,"distance_fit":0.14,"pay_fit":0.12,
  "shift_fit":0.04,"availability_fit":0.06,"work_type_fit":0.03,"licence_coverage":0.02,
  "attribute_fit":0.03,"education_fit":0.00,"language_fit":0.01,"benefit_fit":0.02,
  "trajectory_fit":0.00,"company_preference":0.00}'),

('cleaning', 'cleaning', '{
  "skill_coverage_required":0.14,"skill_coverage_preferred":0.03,"skill_depth":0.04,
  "profession_fit":0.10,"experience_fit":0.07,"distance_fit":0.19,"pay_fit":0.12,
  "shift_fit":0.09,"availability_fit":0.08,"work_type_fit":0.04,"licence_coverage":0.01,
  "attribute_fit":0.02,"education_fit":0.00,"language_fit":0.02,"benefit_fit":0.05,
  "trajectory_fit":0.00,"company_preference":0.00}'),

('healthcare', 'healthcare', '{
  "skill_coverage_required":0.18,"skill_coverage_preferred":0.05,"skill_depth":0.08,
  "profession_fit":0.12,"experience_fit":0.10,"distance_fit":0.12,"pay_fit":0.10,
  "shift_fit":0.07,"availability_fit":0.05,"work_type_fit":0.03,"licence_coverage":0.04,
  "attribute_fit":0.02,"education_fit":0.02,"language_fit":0.02,"benefit_fit":0.00,
  "trajectory_fit":0.00,"company_preference":0.00}'),

('technology', 'technology', '{
  "skill_coverage_required":0.28,"skill_coverage_preferred":0.08,"skill_depth":0.12,
  "profession_fit":0.12,"experience_fit":0.12,"distance_fit":0.05,"pay_fit":0.10,
  "shift_fit":0.01,"availability_fit":0.04,"work_type_fit":0.04,"licence_coverage":0.00,
  "attribute_fit":0.01,"education_fit":0.02,"language_fit":0.01,"benefit_fit":0.00,
  "trajectory_fit":0.00,"company_preference":0.00}')
) as v(name, cat, w);

-- Guard: a profile whose weights do not sum to 1.000 silently distorts
-- every score computed with it. Fail loudly instead.
create or replace function omelo_check_weight_profile()
returns trigger language plpgsql set search_path = public as $$
declare v_sum numeric;
begin
  select round(sum(value::numeric), 4) into v_sum
  from jsonb_each_text(new.weights);
  if v_sum <> 1.0000 then
    raise exception 'weight_profile "%" sums to %, must be 1.0000', new.name, v_sum;
  end if;
  return new;
end;
$$;
revoke execute on function omelo_check_weight_profile() from public, anon, authenticated;

create trigger weight_profiles_check_sum
  before insert or update of weights on weight_profiles
  for each row execute function omelo_check_weight_profile();