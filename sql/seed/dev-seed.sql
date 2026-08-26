-- ============================================================
-- OMELO — DEVELOPMENT SEED (Delhi NCR)
--
-- Demo employers and jobs so the apps have real data to render.
-- NOT a migration. NOT production data.
--
-- Every row created here is identifiable by companies.slug LIKE 'demo-%'.
-- Teardown: sql/seed/dev-teardown.sql
-- ============================================================

-- ---------- Companies ----------
insert into companies (slug, display_name, legal_name, country_code, size_band,
                       about, is_verified, verified_at, verification_method,
                       hq_location_id, response_rate_pct, median_response_hours, total_hires)
select 'demo-' || v.slug, v.name, v.name || ' Pvt Ltd', 'IN', v.size::company_size_band,
       v.about, true, now(), 'document_review',
       l.id, v.rate, v.hours, v.hires
from (values
 ('zippy-logistics','Zippy Logistics','201-500','Last-mile delivery across Delhi NCR. 6 hubs, 900+ riders.','Okhla',91,72,84),
 ('freshmart-retail','FreshMart Retail','501-1000','Neighbourhood grocery chain with 40 stores in NCR.','Lajpat Nagar',86,96,150),
 ('storehub-logistics','StoreHub Logistics','201-500','Fulfilment and warehousing for e-commerce brands.','Sector 62',88,60,120),
 ('spice-route','Spice Route Restaurants','51-200','Multi-cuisine restaurant group, 7 outlets.','Connaught Place',79,120,64),
 ('secureguard','SecureGuard Services','501-1000','Manned guarding for corporate parks and residential societies.','Cyber City',93,48,210),
 ('buildright','BuildRight Constructions','201-500','Residential and commercial construction contractor.','Sohna Road',71,168,95),
 ('cleanspace','CleanSpace Facility Services','201-500','Housekeeping and facility management.','Vaishali',84,72,130),
 ('apex-motors','Apex Motors Service','51-200','Multi-brand car and two-wheeler service network.','Mayur Vihar',76,96,42),
 ('carewell','CareWell Clinic','51-200','Multi-speciality day clinic and diagnostics.','Saket',89,60,38),
 ('quickcabs','QuickCabs','201-500','City taxi and corporate transport fleet.','Dwarka',82,72,110),
 ('novatech','NovaTech Labs','51-200','Product engineering studio building mobile and web apps.','Sector 63',74,120,26),
 ('urban-grocers','Urban Grocers','51-200','Quick-commerce dark stores across NCR.','Indirapuram',90,36,72)
) as v(slug,name,size,about,area,rate,hours,hires)
join locations l on l.kind='area' and l.name = v.area;

-- Company locations (geo copied from the area)
insert into company_locations (company_id, location_id, name, address, geo, is_hq)
select c.id, l.id, 'Head office', l.name || ', ' || p.name, l.geo, true
from companies c
join locations l on l.id = c.hq_location_id
join locations p on p.id = l.parent_id
where c.slug like 'demo-%';

-- Free-tier entitlements
insert into company_entitlements (company_id, plan, recruiter_seats, active_job_slots)
select id, 'free', 3, 25 from companies where slug like 'demo-%';

-- ---------- Jobs ----------
insert into jobs (
  company_id, title, profession_id, category_id, description,
  workplace_type, location_id, location_text, geo, country_code, company_location_id,
  work_type, shift_types, hours_per_week, working_days, is_immediate_start,
  pay_min, pay_max, pay_period, pay_currency, pay_basis,
  min_experience_months, accepts_no_experience, education_negotiable,
  application_method, quick_apply_enabled, requires_resume,
  status, published_at, expires_at, content_language, source, openings
)
select
  c.id, v.title, p.id, p.category_id, v.descr,
  'onsite'::workplace_type, l.id, l.name || ', ' || par.name, l.geo, 'IN', cl.id,
  v.wtype::work_type, v.shifts::shift_type[], v.hours, v.days, true,
  v.pmin, v.pmax, v.period::pay_period, 'INR', 'gross'::pay_basis,
  v.minexp, v.noexp, true,
  'omelo', true, false,
  'published'::job_status, now() - (v.age_days || ' days')::interval,
  now() + interval '30 days', 'eng', 'employer'::source_type, v.openings
from (values
 -- company slug        title                              profession            area              wtype        shifts            hrs days pmin   pmax   period  minexp noexp openings age
 ('zippy-logistics','Delivery Executive - Okhla','delivery-executive','Okhla',            'full_time','{day}',            48,6, 18000, 28000,'month', 0,  true, 25, 2,'Deliver parcels across South Delhi on your own two-wheeler. Fuel allowance and daily incentives on top of base pay.'),
 ('zippy-logistics','Delivery Executive - Dwarka','delivery-executive','Dwarka',          'full_time','{day,evening}',    48,6, 19000, 29000,'month', 0,  true, 18, 1,'Morning and evening delivery shifts in the Dwarka sector cluster. Weekly payouts.'),
 ('zippy-logistics','Night Courier','courier','Okhla',                                    'part_time','{night}',          30,6, 14000, 19000,'month', 0,  true, 10, 4,'Overnight parcel movement between hubs. Suits anyone looking for night-only work.'),
 ('zippy-logistics','Fleet Supervisor','warehouse-supervisor','Okhla',                    'full_time','{day}',            48,6, 28000, 38000,'month',24, false, 2, 6,'Manage a rider roster of 60+, daily dispatch planning and route allocation.'),

 ('storehub-logistics','Warehouse Worker','warehouse-worker','Sector 62',                 'full_time','{day}',            48,6, 15000, 22000,'month', 0,  true, 40, 1,'Picking, packing and dispatch in a modern fulfilment centre. Full training provided.'),
 ('storehub-logistics','Warehouse Worker - Night Shift','warehouse-worker','Sector 62',   'full_time','{night}',          48,6, 18000, 25000,'month', 0,  true, 30, 3,'Night shift picking and packing with a 20% shift premium included in the range.'),
 ('storehub-logistics','Packer','packer','Sector 63',                                     'full_time','{day,evening}',    48,6, 13000, 18000,'month', 0,  true, 35, 2,'Pack customer orders to spec. No experience needed, we train on the floor.'),
 ('storehub-logistics','Forklift Operator','forklift-operator','Sector 62',               'full_time','{day}',            48,6, 18000, 26000,'month',12, false, 6, 5,'Operate counterbalance forklifts. Valid forklift licence required.'),
 ('storehub-logistics','Warehouse Supervisor','warehouse-supervisor','Sector 62',         'full_time','{rotating}',       48,6, 26000, 36000,'month',36, false, 3, 7,'Run a shift of 40 associates. Inventory accuracy and dispatch SLAs.'),

 ('freshmart-retail','Cashier','cashier','Lajpat Nagar',                                  'full_time','{day,evening}',    48,6, 14000, 20000,'month', 0,  true, 12, 1,'Billing, cash handling and customer service at the front of store.'),
 ('freshmart-retail','Sales Assistant','sales-assistant','Saket',                         'full_time','{day}',            48,6, 15000, 22000,'month', 0,  true, 15, 3,'Help customers on the floor, keep shelves full and displays tidy.'),
 ('freshmart-retail','Stock Clerk','stock-clerk','Karol Bagh',                            'full_time','{early_morning}',  42,6, 14000, 19000,'month', 0,  true, 8, 4,'Early morning replenishment before the store opens.'),
 ('freshmart-retail','Store Manager','store-manager','Rajouri Garden',                    'full_time','{day}',            48,6, 32000, 48000,'month',48, false, 2, 9,'Own the P&L of a neighbourhood store: team, stock, service and shrinkage.'),

 ('urban-grocers','Picker - Dark Store','packer','Indirapuram',                           'part_time','{day,evening}',    30,6, 12000, 17000,'month', 0,  true, 20, 1,'10-minute grocery picking. Flexible 6-hour shifts, choose your slot.'),
 ('urban-grocers','Delivery Executive','delivery-executive','Indirapuram',                'gig',      '{flexible}',       0, 0,  700,   1100,'day',    0,  true, 40, 1,'Per-day earnings with peak-hour bonuses. Work the hours you want.'),
 ('urban-grocers','Store Assistant','sales-assistant','Vaishali',                         'full_time','{rotating}',       48,6, 14000, 19000,'month', 0,  true, 10, 2,'Inventory, packing and handover to riders in a dark store.'),

 ('spice-route','Cook - North Indian','cook','Connaught Place',                           'full_time','{split}',          54,6, 20000, 32000,'month',24, false, 3, 3,'Main kitchen, North Indian section. Tandoor experience is a plus.'),
 ('spice-route','Kitchen Helper','kitchen-helper','Connaught Place',                      'full_time','{split}',          54,6, 11000, 15000,'month', 0,  true, 6, 1,'Prep, washing and kitchen hygiene. No experience needed.'),
 ('spice-route','Waiter','waiter','Hauz Khas',                                            'full_time','{evening}',        48,6, 12000, 18000,'month', 0,  true, 8, 2,'Evening service. Tips shared across the floor team.'),
 ('spice-route','Head Chef','chef','Connaught Place',                                     'full_time','{split}',          54,6, 45000, 70000,'month',60, false, 1, 8,'Lead a brigade of 14. Menu development and food cost ownership.'),
 ('spice-route','Barista','barista','Saket',                                              'part_time','{day}',            30,6, 15000, 20000,'month', 0,  true, 4, 5,'Espresso bar in our cafe format. Training provided.'),

 ('secureguard','Security Guard - Corporate Park','security-guard','Cyber City',          'full_time','{rotating}',       48,6, 15000, 20000,'month', 0,  true, 30, 1,'Access control and patrolling at a Grade-A office park. PSARA licence required.'),
 ('secureguard','Security Guard - Night','security-guard','Udyog Vihar',                  'full_time','{night}',          48,6, 17000, 22000,'month', 0,  true, 25, 2,'Night shift guarding for an industrial estate.'),
 ('secureguard','Security Supervisor','security-supervisor','Cyber City',                 'full_time','{rotating}',       48,6, 24000, 32000,'month',36, false, 4, 6,'Supervise a 20-guard deployment across three gates.'),

 ('buildright','Mason','mason','Sohna Road',                                              'contract', '{day}',            48,6,  800,  1100,'day',   24, false, 12, 2,'Brickwork and plastering on a residential tower project. Daily wage, paid weekly.'),
 ('buildright','General Labourer','general-laborer','Manesar',                            'daily_wage','{day}',           48,6,  550,   750,'day',    0,  true, 30, 1,'Site support work. Daily wage paid same day. No experience needed.'),
 ('buildright','Electrician','electrician','Sohna Road',                                  'full_time','{day}',            48,6, 22000, 34000,'month',24, false, 5, 4,'Conduit, wiring and panel work. Valid electrical licence required.'),
 ('buildright','Site Supervisor','site-supervisor','Manesar',                             'full_time','{day}',            54,6, 32000, 45000,'month',48, false, 2, 7,'Daily site progress, labour coordination and safety compliance.'),
 ('buildright','Welder','welder','Manesar',                                               'contract', '{day}',            48,6,  900,  1300,'day',   12, false, 6, 3,'Structural welding. Own safety gear preferred, PPE provided.'),

 ('cleanspace','Cleaner','cleaner','Vaishali',                                            'full_time','{early_morning}',  42,6, 12000, 16000,'month', 0,  true, 22, 1,'Office cleaning, early morning shift before staff arrive.'),
 ('cleanspace','Housekeeper','housekeeper','Indirapuram',                                  'full_time','{day}',            48,6, 13000, 18000,'month', 0,  true, 16, 2,'Housekeeping in a serviced apartment block.'),
 ('cleanspace','Janitor - Mall','janitor','Sahibabad',                                     'full_time','{rotating}',       48,6, 13000, 17000,'month', 0,  true, 12, 4,'Rotating shifts covering mall public areas.'),

 ('apex-motors','Auto Mechanic','auto-mechanic','Mayur Vihar',                            'full_time','{day}',            48,6, 18000, 30000,'month',24, false, 5, 3,'Engine, brakes and general service on multi-brand cars.'),
 ('apex-motors','Two-Wheeler Technician','auto-mechanic','Preet Vihar',                   'full_time','{day}',            48,6, 15000, 24000,'month',12, false, 4, 5,'Servicing and repair for scooters and motorcycles.'),
 ('apex-motors','Auto Electrician','auto-electrician','Mayur Vihar',                      'full_time','{day}',            48,6, 20000, 32000,'month',24, false, 2, 6,'Wiring, diagnostics and electrical fault finding.'),

 ('carewell','Staff Nurse','nurse','Saket',                                               'full_time','{rotating}',       48,6, 26000, 42000,'month',24, false, 4, 3,'Day clinic nursing. Valid nursing registration required.'),
 ('carewell','Ward Attendant','ward-attendant','Saket',                                   'full_time','{rotating}',       48,6, 14000, 19000,'month', 0,  true, 6, 2,'Patient support and ward hygiene. Training provided.'),
 ('carewell','Receptionist','receptionist','Nehru Place',                                 'full_time','{day}',            48,6, 16000, 22000,'month',12, false, 2, 5,'Front desk, appointments and patient records.'),

 ('quickcabs','Taxi Driver','taxi-driver','Dwarka',                                       'full_time','{rotating}',       48,6, 18000, 30000,'month',12, false, 20, 1,'City driving with a company-provided vehicle. Commercial licence required.'),
 ('quickcabs','Corporate Chauffeur','driver','Janakpuri',                                 'full_time','{day}',            48,6, 20000, 28000,'month',24, false, 8, 4,'Executive transport for a corporate account.'),
 ('quickcabs','Truck Driver','truck-driver','Najafgarh',                                  'full_time','{night}',          48,6, 24000, 38000,'month',36, false, 6, 3,'Inter-city night runs. HMV licence required.'),

 ('novatech','Mobile Developer (Flutter)','mobile-developer','Sector 63',                 'full_time','{day}',            40,5, 700000,1400000,'year',24, false, 2, 6,'Build cross-platform apps in Flutter. Product studio, small teams.'),
 ('novatech','Software Engineer','software-engineer','Sector 63',                         'full_time','{day}',            40,5, 600000,1200000,'year',12, false, 3, 4,'Backend and API work across client products.'),
 ('novatech','Data Entry Operator','data-entry-operator','Sector 63',                     'part_time','{day}',            24,5, 14000, 19000,'month', 0,  true, 2, 2,'Structured data entry and validation. Part-time, flexible hours.')
) as v(cslug,title,prof,area,wtype,shifts,hours,days,pmin,pmax,period,minexp,noexp,openings,age_days,descr)
join companies c on c.slug = 'demo-' || v.cslug
join professions p on p.slug = v.prof
join locations l on l.kind='area' and l.name = v.area
join locations par on par.id = l.parent_id
join company_locations cl on cl.company_id = c.id;

-- ---------- Pipeline stages (every job needs them) ----------
insert into job_stages (job_id, name, position, maps_to_state, is_terminal)
select j.id, s.name, s.pos, s.state::application_state, s.terminal
from jobs j
join companies c on c.id = j.company_id and c.slug like 'demo-%'
cross join (values
 ('New',                1,'applied',   false),
 ('Shortlisted',        2,'shortlisted',false),
 ('Phone call',         3,'screening', false),
 ('Interview',          4,'interview', false),
 ('Hired',              5,'hired',     true),
 ('Not moving forward', 6,'rejected',  true)
) as s(name,pos,state,terminal);

-- ---------- Requirements derived from the profession taxonomy ----------
insert into job_skills (job_id, skill_id, requirement_level, weight)
select j.id, ps.skill_id,
       case when ps.importance >= 0.85 then 'required' else 'preferred' end::requirement_level,
       round(ps.importance, 3)
from jobs j
join companies c on c.id = j.company_id and c.slug like 'demo-%'
join profession_skills ps on ps.profession_id = j.profession_id
where ps.importance >= 0.65
on conflict do nothing;

-- ---------- Benefits by category ----------
insert into job_benefits (job_id, benefit_type, detail)
select j.id, b.bt::benefit_type, b.detail
from jobs j
join companies c on c.id = j.company_id and c.slug like 'demo-%'
join job_categories cat on cat.id = j.category_id
join (values
 ('delivery',       'transport',       'Fuel allowance'),
 ('delivery',       'overtime_pay',    'Peak-hour incentives'),
 ('delivery',       'health_insurance','Accident cover'),
 ('warehousing',    'transport',       'Shuttle from metro station'),
 ('warehousing',    'meals',           'Subsidised canteen'),
 ('warehousing',    'health_insurance','ESI covered'),
 ('retail',         'meals',           'Staff meal'),
 ('retail',         'uniform_provided','Uniform provided'),
 ('food-restaurant','meals',           'Two meals per shift'),
 ('food-restaurant','tips',            'Shared tip pool'),
 ('food-restaurant','uniform_provided','Uniform provided'),
 ('security',       'uniform_provided','Uniform and shoes provided'),
 ('security',       'overtime_pay',    'Overtime at 1.5x'),
 ('construction',   'accommodation',   'On-site accommodation available'),
 ('construction',   'equipment_provided','PPE provided'),
 ('cleaning',       'transport',       'Transport allowance'),
 ('cleaning',       'uniform_provided','Uniform provided'),
 ('healthcare',     'health_insurance','Family health cover'),
 ('healthcare',     'training',        'Continuing education support'),
 ('transportation', 'health_insurance','Accident cover'),
 ('transportation', 'overtime_pay',    'Trip incentives'),
 ('automotive',     'training',        'Manufacturer training'),
 ('technology',     'health_insurance','Family health cover'),
 ('technology',     'training',        'Learning budget'),
 ('administrative', 'health_insurance','ESI covered')
) as b(cat,bt,detail) on b.cat = cat.slug
on conflict do nothing;

-- ---------- One employer screening question per job ----------
insert into job_questions (job_id, position, prompt, answer_type, is_required, is_knockout)
select j.id, 1,
       case cat.slug
         when 'delivery'      then 'Do you have your own two-wheeler?'
         when 'transportation' then 'Do you hold a valid commercial driving licence?'
         when 'security'      then 'Do you hold a valid PSARA security licence?'
         when 'construction'  then 'Can you start on site within 7 days?'
         else 'Can you start within 15 days?'
       end,
       'boolean', true, false
from jobs j
join companies c on c.id = j.company_id and c.slug like 'demo-%'
join job_categories cat on cat.id = j.category_id;
