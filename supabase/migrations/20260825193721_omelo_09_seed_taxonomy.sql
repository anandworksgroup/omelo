-- =====================================================================
-- OMELO 09 — Taxonomy Seed
-- =====================================================================

insert into languages (code, name, native_name, rtl) values
  ('eng','English','English',false),
  ('hin','Hindi','हिन्दी',false),
  ('spa','Spanish','Español',false),
  ('ara','Arabic','العربية',true),
  ('por','Portuguese','Português',false),
  ('fra','French','Français',false),
  ('deu','German','Deutsch',false),
  ('nld','Dutch','Nederlands',false),
  ('ben','Bengali','বাংলা',false),
  ('tam','Tamil','தமிழ்',false),
  ('tel','Telugu','తెలుగు',false),
  ('mar','Marathi','मराठी',false),
  ('urd','Urdu','اردو',true),
  ('zho','Chinese','中文',false),
  ('rus','Russian','Русский',false),
  ('ind','Indonesian','Bahasa Indonesia',false),
  ('tgl','Filipino','Filipino',false),
  ('nep','Nepali','नेपाली',false),
  ('mal','Malayalam','മലയാളം',false),
  ('pan','Punjabi','ਪੰਜਾਬੀ',false)
on conflict (code) do nothing;

insert into country_policies
  (country_code, name, default_currency, default_pay_period,
   salary_disclosure_required, phone_auth_preferred, supported) values
  ('IN','India','INR','month', false, true,  true),
  ('AE','United Arab Emirates','AED','month', false, true,  true),
  ('SA','Saudi Arabia','SAR','month', false, true,  false),
  ('DE','Germany','EUR','year',  true,  false, true),
  ('NL','Netherlands','EUR','month', true, false, true),
  ('GB','United Kingdom','GBP','year', false, false, true),
  ('US','United States','USD','year', false, false, true),
  ('CA','Canada','CAD','year',  false, false, true),
  ('AU','Australia','AUD','year', true,  false, true),
  ('SG','Singapore','SGD','month', false, false, true),
  ('PH','Philippines','PHP','month', false, true, false),
  ('BR','Brazil','BRL','month', false, true, false),
  ('MX','Mexico','MXN','month', false, true, false),
  ('ZA','South Africa','ZAR','month', false, true, false)
on conflict (country_code) do nothing;

insert into job_categories (slug, name, position) values
  ('technology','Technology',1),
  ('healthcare','Healthcare',2),
  ('construction','Construction',3),
  ('education','Education',4),
  ('hospitality','Hospitality',5),
  ('food-restaurant','Food & Restaurant',6),
  ('retail','Retail',7),
  ('sales','Sales',8),
  ('transportation','Transportation',9),
  ('logistics','Logistics',10),
  ('manufacturing','Manufacturing',11),
  ('agriculture','Agriculture',12),
  ('security','Security',13),
  ('cleaning','Cleaning',14),
  ('domestic-services','Domestic Services',15),
  ('beauty-wellness','Beauty & Wellness',16),
  ('automotive','Automotive',17),
  ('banking-finance','Banking & Finance',18),
  ('government','Government',19),
  ('legal','Legal',20),
  ('media','Media',21),
  ('design','Design',22),
  ('sports-fitness','Sports & Fitness',23),
  ('skilled-trades','Skilled Trades',24),
  ('administrative','Administrative',25),
  ('customer-service','Customer Service',26),
  ('engineering','Engineering',27),
  ('science','Science',28),
  ('real-estate','Real Estate',29),
  ('travel-tourism','Travel & Tourism',30),
  ('delivery','Delivery',31),
  ('warehousing','Warehousing',32),
  ('energy-utilities','Energy & Utilities',33),
  ('other','Other',99)
on conflict (slug) do nothing;

insert into professions
  (category_id, slug, name, typical_education_level, requires_license, is_entry_level_friendly, typical_work_types)
select c.id, v.slug, v.name, v.edu::education_level, v.lic, v.entry, v.wt::work_type[]
from (values
  ('technology','software-engineer','Software Engineer','bachelor',false,false,'{full_time,contract,freelance}'),
  ('technology','mobile-developer','Mobile Developer','bachelor',false,false,'{full_time,contract,freelance}'),
  ('technology','data-analyst','Data Analyst','bachelor',false,false,'{full_time,contract}'),
  ('technology','it-support','IT Support Technician','diploma',false,true,'{full_time,part_time}'),
  ('technology','network-engineer','Network Engineer','diploma',false,false,'{full_time,contract}'),
  ('healthcare','doctor','Doctor','professional',true,false,'{full_time,contract}'),
  ('healthcare','nurse','Nurse','diploma',true,false,'{full_time,part_time,contract}'),
  ('healthcare','caregiver','Caregiver','certificate',false,true,'{full_time,part_time,temporary}'),
  ('healthcare','pharmacist','Pharmacist','bachelor',true,false,'{full_time,part_time}'),
  ('healthcare','lab-technician','Lab Technician','diploma',false,false,'{full_time}'),
  ('healthcare','ward-attendant','Ward Attendant','secondary',false,true,'{full_time,part_time}'),
  ('construction','general-laborer','General Labourer','none',false,true,'{full_time,daily_wage,temporary}'),
  ('construction','mason','Mason','vocational',false,true,'{full_time,daily_wage,contract}'),
  ('construction','carpenter','Carpenter','vocational',false,true,'{full_time,contract,daily_wage}'),
  ('construction','electrician','Electrician','vocational',true,false,'{full_time,contract}'),
  ('construction','plumber','Plumber','vocational',true,false,'{full_time,contract}'),
  ('construction','welder','Welder','vocational',true,false,'{full_time,contract}'),
  ('construction','painter','Painter','none',false,true,'{full_time,daily_wage,contract}'),
  ('construction','site-supervisor','Site Supervisor','diploma',false,false,'{full_time}'),
  ('construction','civil-engineer','Civil Engineer','bachelor',true,false,'{full_time,contract}'),
  ('construction','heavy-equipment-operator','Heavy Equipment Operator','vocational',true,false,'{full_time,contract}'),
  ('education','teacher','Teacher','bachelor',true,false,'{full_time,part_time}'),
  ('education','tutor','Tutor','secondary',false,true,'{part_time,freelance,gig}'),
  ('education','teaching-assistant','Teaching Assistant','secondary',false,true,'{full_time,part_time}'),
  ('hospitality','hotel-receptionist','Hotel Receptionist','secondary',false,true,'{full_time,part_time}'),
  ('hospitality','housekeeper','Housekeeper','none',false,true,'{full_time,part_time,temporary}'),
  ('hospitality','concierge','Concierge','secondary',false,true,'{full_time}'),
  ('hospitality','hotel-manager','Hotel Manager','bachelor',false,false,'{full_time}'),
  ('food-restaurant','chef','Chef','vocational',false,false,'{full_time,contract}'),
  ('food-restaurant','cook','Cook','none',false,true,'{full_time,part_time}'),
  ('food-restaurant','waiter','Waiter / Server','none',false,true,'{full_time,part_time,gig}'),
  ('food-restaurant','kitchen-helper','Kitchen Helper','none',false,true,'{full_time,part_time,daily_wage}'),
  ('food-restaurant','barista','Barista','none',false,true,'{full_time,part_time}'),
  ('food-restaurant','dishwasher','Dishwasher','none',false,true,'{part_time,full_time,daily_wage}'),
  ('retail','sales-assistant','Sales Assistant','secondary',false,true,'{full_time,part_time,seasonal}'),
  ('retail','cashier','Cashier','secondary',false,true,'{full_time,part_time,seasonal}'),
  ('retail','store-manager','Store Manager','diploma',false,false,'{full_time}'),
  ('retail','stock-clerk','Stock Clerk','none',false,true,'{full_time,part_time}'),
  ('sales','sales-executive','Sales Executive','diploma',false,true,'{full_time,part_time}'),
  ('sales','field-sales-rep','Field Sales Representative','secondary',false,true,'{full_time}'),
  ('sales','account-manager','Account Manager','bachelor',false,false,'{full_time}'),
  ('transportation','driver','Driver','none',true,true,'{full_time,part_time,gig,contract}'),
  ('transportation','truck-driver','Truck Driver','none',true,false,'{full_time,contract}'),
  ('transportation','bus-driver','Bus Driver','secondary',true,false,'{full_time}'),
  ('transportation','taxi-driver','Taxi Driver','none',true,true,'{full_time,part_time,gig}'),
  ('transportation','forklift-operator','Forklift Operator','vocational',true,false,'{full_time,temporary}'),
  ('logistics','logistics-coordinator','Logistics Coordinator','diploma',false,false,'{full_time}'),
  ('warehousing','warehouse-worker','Warehouse Worker','none',false,true,'{full_time,part_time,temporary}'),
  ('warehousing','warehouse-supervisor','Warehouse Supervisor','secondary',false,false,'{full_time}'),
  ('warehousing','packer','Packer','none',false,true,'{full_time,part_time,daily_wage}'),
  ('delivery','delivery-executive','Delivery Executive','none',true,true,'{full_time,part_time,gig}'),
  ('delivery','courier','Courier','none',true,true,'{full_time,gig}'),
  ('manufacturing','machine-operator','Machine Operator','vocational',false,true,'{full_time,contract}'),
  ('manufacturing','production-worker','Production Worker','none',false,true,'{full_time,temporary,daily_wage}'),
  ('manufacturing','quality-inspector','Quality Inspector','diploma',false,false,'{full_time}'),
  ('manufacturing','maintenance-technician','Maintenance Technician','vocational',false,false,'{full_time}'),
  ('agriculture','farm-worker','Farm Worker','none',false,true,'{full_time,seasonal,daily_wage}'),
  ('agriculture','tractor-operator','Tractor Operator','none',true,true,'{seasonal,full_time}'),
  ('security','security-guard','Security Guard','secondary',true,true,'{full_time,part_time}'),
  ('security','security-supervisor','Security Supervisor','secondary',true,false,'{full_time}'),
  ('cleaning','cleaner','Cleaner','none',false,true,'{full_time,part_time,gig}'),
  ('cleaning','janitor','Janitor','none',false,true,'{full_time,part_time}'),
  ('domestic-services','domestic-helper','Domestic Helper','none',false,true,'{full_time,part_time}'),
  ('domestic-services','nanny','Nanny','none',false,true,'{full_time,part_time}'),
  ('domestic-services','cook-domestic','Domestic Cook','none',false,true,'{full_time,part_time}'),
  ('beauty-wellness','hairdresser','Hairdresser','vocational',true,true,'{full_time,part_time,freelance}'),
  ('beauty-wellness','beautician','Beautician','vocational',true,true,'{full_time,part_time,freelance}'),
  ('beauty-wellness','massage-therapist','Massage Therapist','certificate',true,false,'{full_time,part_time}'),
  ('automotive','auto-mechanic','Auto Mechanic','vocational',false,true,'{full_time,contract}'),
  ('automotive','auto-electrician','Auto Electrician','vocational',true,false,'{full_time}'),
  ('banking-finance','accountant','Accountant','bachelor',false,false,'{full_time,contract,freelance}'),
  ('banking-finance','bank-teller','Bank Teller','diploma',false,true,'{full_time}'),
  ('banking-finance','financial-analyst','Financial Analyst','bachelor',false,false,'{full_time}'),
  ('skilled-trades','hvac-technician','HVAC Technician','vocational',true,false,'{full_time,contract}'),
  ('skilled-trades','fitter','Fitter','vocational',false,true,'{full_time,contract}'),
  ('skilled-trades','scaffolder','Scaffolder','vocational',true,false,'{full_time,contract}'),
  ('administrative','office-assistant','Office Assistant','secondary',false,true,'{full_time,part_time}'),
  ('administrative','data-entry-operator','Data Entry Operator','secondary',false,true,'{full_time,part_time,freelance}'),
  ('administrative','receptionist','Receptionist','secondary',false,true,'{full_time,part_time}'),
  ('customer-service','call-centre-agent','Call Centre Agent','secondary',false,true,'{full_time,part_time}'),
  ('customer-service','customer-support-rep','Customer Support Representative','diploma',false,true,'{full_time,part_time}'),
  ('engineering','mechanical-engineer','Mechanical Engineer','bachelor',false,false,'{full_time,contract}'),
  ('engineering','electrical-engineer','Electrical Engineer','bachelor',true,false,'{full_time,contract}'),
  ('energy-utilities','lineman','Lineman','vocational',true,false,'{full_time}'),
  ('science','lab-assistant','Lab Assistant','diploma',false,true,'{full_time}'),
  ('design','graphic-designer','Graphic Designer','diploma',false,true,'{full_time,freelance,contract}'),
  ('media','videographer','Videographer','diploma',false,true,'{freelance,contract,full_time}'),
  ('sports-fitness','fitness-trainer','Fitness Trainer','certificate',true,true,'{full_time,part_time,freelance}'),
  ('real-estate','real-estate-agent','Real Estate Agent','secondary',true,true,'{full_time,freelance}'),
  ('travel-tourism','tour-guide','Tour Guide','secondary',true,true,'{full_time,seasonal,freelance}'),
  ('legal','paralegal','Paralegal','diploma',false,false,'{full_time}'),
  ('government','clerk','Government Clerk','secondary',false,true,'{full_time}')
) as v(cat, slug, name, edu, lic, entry, wt)
join job_categories c on c.slug = v.cat
on conflict (slug) do nothing;

-- ---------------------------------------------------------------
-- ADAPTIVE PROFILE ATTRIBUTES
-- ---------------------------------------------------------------
insert into profile_attributes (slug, label, help_text, data_type, category_id, options, is_required, position)
select v.slug, v.label, v.help, v.dt::attribute_data_type, c.id, v.opts::jsonb, v.req, v.pos
from (values
  ('vehicle-classes','Vehicle types you can drive','Select every type you are licensed and confident to drive','multi_select','transportation',
   '["Two-wheeler","Three-wheeler","Car (LMV)","Van","Light truck","Heavy truck (HMV)","Trailer","Bus","Forklift","Crane","Tractor"]',true,1),
  ('own-vehicle','Do you have your own vehicle?','','boolean','transportation','[]',false,2),
  ('driving-experience-years','Years of driving experience','','years','transportation','[]',true,3),
  ('routes-known','Routes / areas you know well','','multi_select','transportation','[]',false,4),
  ('night-driving','Willing to drive at night','','boolean','transportation','[]',false,5),
  ('delivery-vehicle','Vehicle you deliver with','','single_select','delivery',
   '["Bicycle","Two-wheeler","Three-wheeler","Car","Van","On foot"]',true,1),
  ('smartphone-available','Do you have a smartphone?','Most delivery work requires one','boolean','delivery','[]',true,2),
  ('clinical-specialisation','Specialisation','','multi_select','healthcare',
   '["General","ICU / Critical care","Emergency","Paediatrics","Surgery / OT","Maternity","Oncology","Cardiology","Orthopaedics","Psychiatry","Geriatric care","Home care","Dialysis"]',false,1),
  ('patient-settings','Where have you worked?','','multi_select','healthcare',
   '["Hospital","Clinic","Nursing home","Home care","Community health","Laboratory"]',false,2),
  ('night-shift-ok','Available for night shifts','','boolean','healthcare','[]',false,3),
  ('trade-level','Your level','','single_select','construction',
   '["Helper","Apprentice","Semi-skilled","Skilled","Master / Foreman","Supervisor"]',true,1),
  ('own-tools','Do you have your own tools?','','boolean','construction','[]',false,2),
  ('site-types','Types of sites worked on','','multi_select','construction',
   '["Residential","Commercial","Industrial","Infrastructure / Roads","Oil & Gas","High-rise"]',false,3),
  ('safety-training','Safety training completed','','multi_select','construction',
   '["None","Basic site safety","Working at height","Confined space","First aid","Scaffolding","Electrical safety"]',false,4),
  ('heights-comfortable','Comfortable working at height','','boolean','construction','[]',false,5),
  ('cuisines','Cuisines you can cook','','multi_select','food-restaurant',
   '["North Indian","South Indian","Chinese","Continental","Italian","Arabic / Lebanese","Fast food","Bakery / Pastry","Grill / BBQ","Seafood","Vegan"]',false,1),
  ('food-safety-cert','Food safety certification','','boolean','food-restaurant','[]',false,2),
  ('service-style','Service experience','','multi_select','food-restaurant',
   '["Fine dining","Casual dining","Quick service","Cafe","Catering","Banquet","Room service"]',false,3),
  ('security-settings','Security experience','','multi_select','security',
   '["Residential","Commercial / Office","Retail / Mall","Industrial","Event","Hospital","Bank / ATM","VIP / Personal"]',false,1),
  ('security-clearance','Police verification / clearance held','','boolean','security','[]',false,2),
  ('domestic-tasks','Tasks you can do','','multi_select','domestic-services',
   '["Cooking","Cleaning","Laundry","Childcare","Elderly care","Pet care","Driving","Gardening"]',true,1),
  ('live-in','Open to live-in arrangement','','boolean','domestic-services','[]',false,2),
  ('portfolio-url','Portfolio / GitHub','','text','technology','[]',false,1),
  ('work-setup','Do you have a laptop and reliable internet?','Required for most remote technology roles','boolean','technology','[]',false,2)
) as v(slug,label,help,dt,cat,opts,req,pos)
join job_categories c on c.slug = v.cat
on conflict (slug) do nothing;

insert into profile_attributes (slug, label, help_text, data_type, options, is_required, position) values
  ('has-smartphone','Do you have a smartphone?','','boolean','[]'::jsonb,false,90),
  ('can-travel-daily-km','How far can you travel to work each day?','','number','[]'::jsonb,false,91),
  ('first-job','Is this your first job?','We will show you roles that welcome first-time workers','boolean','[]'::jsonb,false,92)
on conflict (slug) do nothing;

-- ---------------------------------------------------------------
-- Licence types
-- ---------------------------------------------------------------
insert into license_types (slug, name, country_code, issuing_body, category_id, class_options, renewable)
select v.slug, v.name, v.cc, v.body, c.id, v.classes::text[], true
from (values
  ('in-driving-licence','Driving Licence (India)','IN','RTO','transportation',
   '{"MCWG","MCWOG","LMV","LMV-TR","HMV","HGMV","HPMV","Trailer","Bus"}'),
  ('ae-driving-licence','Driving Licence (UAE)','AE','RTA','transportation',
   '{"Motorcycle","Light Vehicle","Heavy Truck","Heavy Bus","Forklift","Crane"}'),
  ('uk-driving-licence','Driving Licence (UK)','GB','DVLA','transportation',
   '{"AM","A1","A2","A","B","BE","C1","C","CE","D1","D","DE"}'),
  ('in-electrician-licence','Electrician Licence (India)','IN','State Electrical Licensing Board','construction',
   '{"Wireman","Supervisor","Contractor"}'),
  ('in-nursing-registration','Nursing Registration (India)','IN','State Nursing Council','healthcare',
   '{"GNM","ANM","BSc Nursing","Post Basic"}'),
  ('in-medical-registration','Medical Registration (India)','IN','National Medical Commission','healthcare','{}'),
  ('in-psara-security','Security Guard Licence (PSARA)','IN','PSARA','security','{}'),
  ('food-handler-cert','Food Handler Certificate',null,'Various','food-restaurant','{}'),
  ('forklift-licence','Forklift Operator Licence',null,'Various','transportation','{}'),
  ('first-aid-cert','First Aid Certificate',null,'Various','healthcare','{}')
) as v(slug,name,cc,body,cat,classes)
join job_categories c on c.slug = v.cat
on conflict (slug) do nothing;
