create or replace function omelo_private.omelo_seed_questions(
  p_profession_slugs text[], p_category_slug text, p_round_kind text, p_questions text[][]
) returns void
language plpgsql
set search_path = public, omelo_private
as $$
declare v_prof uuid; v_cat uuid; n int;
begin
  if p_category_slug is not null then
    select id into v_cat from job_categories where slug = p_category_slug;
    if v_cat is null then return; end if;
  end if;
  if p_profession_slugs is not null then
    for v_prof in select id from professions where slug = any(p_profession_slugs) loop
      for n in 1 .. array_length(p_questions, 1) loop
        insert into interview_question_templates (profession_id, round_kind, question, category, position)
        select v_prof, p_round_kind, p_questions[n][1], p_questions[n][2], n
         where not exists (select 1 from interview_question_templates
                            where profession_id = v_prof and question = p_questions[n][1]);
      end loop;
    end loop;
  elsif v_cat is not null then
    for n in 1 .. array_length(p_questions, 1) loop
      insert into interview_question_templates (category_id, round_kind, question, category, position)
      select v_cat, p_round_kind, p_questions[n][1], p_questions[n][2], n
       where not exists (select 1 from interview_question_templates
                          where category_id = v_cat and profession_id is null and question = p_questions[n][1]);
    end loop;
  else
    for n in 1 .. array_length(p_questions, 1) loop
      insert into interview_question_templates (round_kind, question, category, position)
      select p_round_kind, p_questions[n][1], p_questions[n][2], n
       where not exists (select 1 from interview_question_templates
                          where profession_id is null and category_id is null and question = p_questions[n][1]);
    end loop;
  end if;
end;
$$;
revoke execute on function omelo_private.omelo_seed_questions(text[], text, text, text[][]) from public, anon, authenticated;

select omelo_private.omelo_seed_questions(null, null, null, array[
  ['Tell us about the work you have done before.', 'experience'],
  ['Why are you interested in this job?', 'motivation'],
  ['Which days and hours are you available to work?', 'availability'],
  ['How would you get to work each day?', 'logistics'],
  ['Tell us about a difficult situation at work and how you handled it.', 'behaviour'],
  ['When could you start?', 'availability']
]);

select omelo_private.omelo_seed_questions(array['software-engineer','mobile-developer'], null, null, array[
  ['Explain your experience with distributed systems.', 'technical'],
  ['Describe a production problem you solved. How did you find the cause?', 'problem_solving'],
  ['How would you design a service that sends millions of notifications a day?', 'system_design'],
  ['What is your experience with Kubernetes or other container platforms?', 'technical'],
  ['How do you make sure your code is correct before it reaches users?', 'quality'],
  ['Tell us about a technical decision you disagreed with and what you did.', 'collaboration']
]);

select omelo_private.omelo_seed_questions(array['driver','delivery-executive','taxi-driver','truck-driver','bus-driver'], null, null, array[
  ['How long have you been driving?', 'experience'],
  ['What vehicle do you use, and do you own it?', 'equipment'],
  ['Do you have a valid driving licence? Which class?', 'licence'],
  ['How do you handle a difficult or angry customer?', 'customer'],
  ['Are you available for night shifts or weekends?', 'availability'],
  ['How well do you know the roads in this area?', 'local_knowledge']
]);

select omelo_private.omelo_seed_questions(array['nurse'], null, null, array[
  ['What is your specialisation?', 'specialisation'],
  ['Which hospitals or clinics have you worked in?', 'experience'],
  ['Tell us about your emergency or critical care experience.', 'clinical'],
  ['Is your nursing registration current? When does it expire?', 'certification'],
  ['Which shifts can you work, including nights?', 'availability'],
  ['How do you handle a patient or family member who is upset?', 'patient_care']
]);

select omelo_private.omelo_seed_questions(array['cook','chef','cook-domestic','kitchen-helper'], null, null, array[
  ['Which cuisines can you cook well?', 'skills'],
  ['How many people have you cooked for at one time?', 'experience'],
  ['How do you keep the kitchen clean and food safe?', 'hygiene'],
  ['What would you do if you ran out of an ingredient during service?', 'problem_solving'],
  ['Are you comfortable working early mornings, late nights or weekends?', 'availability']
]);

select omelo_private.omelo_seed_questions(array['security-guard','security-supervisor'], null, null, array[
  ['Where have you worked as a security guard before?', 'experience'],
  ['Do you have a security licence or training certificate?', 'licence'],
  ['What would you do if someone tried to enter without permission?', 'situational'],
  ['Are you comfortable standing for long hours and working night shifts?', 'availability'],
  ['How do you keep records of visitors and incidents?', 'procedures']
]);

select omelo_private.omelo_seed_questions(array['electrician','auto-electrician','plumber'], null, null, array[
  ['What kind of jobs have you done: homes, shops, factories, vehicles?', 'experience'],
  ['Do you have a licence or trade certificate?', 'licence'],
  ['Which tools do you own?', 'equipment'],
  ['What safety steps do you always follow before starting work?', 'safety'],
  ['Tell us about a fault that was hard to find and how you fixed it.', 'problem_solving']
]);

select omelo_private.omelo_seed_questions(array['cashier','sales-assistant','sales-executive','field-sales-rep'], null, null, array[
  ['Have you handled cash or card payments before?', 'experience'],
  ['How would you help a customer who cannot find what they need?', 'customer'],
  ['Tell us about a sale you are proud of.', 'sales'],
  ['What would you do if the cash did not match at the end of the day?', 'integrity'],
  ['Which shifts and days can you work?', 'availability']
]);

select omelo_private.omelo_seed_questions(array['warehouse-worker','warehouse-supervisor'], null, null, array[
  ['Have you worked in a warehouse before? What did you do?', 'experience'],
  ['Can you lift and move heavy items safely?', 'physical'],
  ['Have you used a scanner, forklift or stock system?', 'equipment'],
  ['How do you make sure orders are picked correctly?', 'accuracy'],
  ['Are you available for rotating or night shifts?', 'availability']
]);

select omelo_private.omelo_seed_questions(array['receptionist','hotel-receptionist'], null, null, array[
  ['Which languages can you speak with guests?', 'language'],
  ['How would you handle a guest complaint at a busy front desk?', 'customer'],
  ['Have you used a booking or front-desk system?', 'tools'],
  ['How do you manage phone calls and visitors at the same time?', 'multitasking'],
  ['Which shifts can you work?', 'availability']
]);

select omelo_private.omelo_seed_questions(array['teacher'], null, null, array[
  ['Which subjects and age groups have you taught?', 'experience'],
  ['How do you help a student who is falling behind?', 'pedagogy'],
  ['How do you manage a noisy or distracted class?', 'classroom'],
  ['Which teaching qualifications do you have?', 'certification'],
  ['How do you communicate with parents?', 'communication']
]);

select omelo_private.omelo_seed_questions(array['domestic-helper'], null, null, array[
  ['Which household work have you done before: cleaning, cooking, childcare, elder care?', 'experience'],
  ['Are you looking for live-in or daily work?', 'arrangement'],
  ['Which hours and days can you work?', 'availability'],
  ['Can you share a reference from a previous household?', 'references']
]);

select omelo_private.omelo_seed_questions(array['accountant'], null, null, array[
  ['Which accounting software have you used?', 'tools'],
  ['Describe how you close the books at month end.', 'process'],
  ['Tell us about an error you found and how you corrected it.', 'accuracy'],
  ['What is your experience with GST or tax filings?', 'compliance']
]);

select omelo_private.omelo_seed_questions(array['civil-engineer','mechanical-engineer','electrical-engineer','network-engineer'], null, null, array[
  ['Describe the largest project you have worked on and your role in it.', 'experience'],
  ['Which design or analysis tools do you use?', 'tools'],
  ['Tell us about a technical problem on site or in production and how you solved it.', 'problem_solving'],
  ['How do you make sure work meets safety and quality standards?', 'quality'],
  ['Which certifications do you hold?', 'certification']
]);

select omelo_private.omelo_seed_questions(null, 'healthcare', null, array[
  ['What healthcare experience do you have?', 'experience'],
  ['Which certifications or registrations do you hold?', 'certification'],
  ['How do you keep patients safe and comfortable?', 'patient_care'],
  ['Which shifts can you work?', 'availability']
]);
select omelo_private.omelo_seed_questions(null, 'transportation', null, array[
  ['How long have you been driving professionally?', 'experience'],
  ['Which licence do you hold?', 'licence'],
  ['Have you had any accidents or traffic fines in the last three years?', 'safety'],
  ['Are you available for long routes or night driving?', 'availability']
]);
select omelo_private.omelo_seed_questions(null, 'technology', null, array[
  ['Walk us through a project you built and the decisions you made.', 'technical'],
  ['How do you debug a problem you have never seen before?', 'problem_solving'],
  ['How do you keep your technical skills up to date?', 'learning'],
  ['Tell us about working with a team to deliver on a deadline.', 'collaboration']
]);
select omelo_private.omelo_seed_questions(null, 'construction', null, array[
  ['What construction work have you done?', 'experience'],
  ['Which safety equipment do you always use on site?', 'safety'],
  ['Which tools and machines can you operate?', 'equipment'],
  ['Are you able to work outdoors and at height?', 'physical']
]);