-- ============================================================
-- OMELO 15 — geo sync trigger + Delhi NCR location gazetteer
-- Launch market: India / Delhi NCR (docs/12 Q1, Q3)
-- ============================================================

create or replace function omelo_sync_geo()
returns trigger language plpgsql set search_path = public, extensions as $$
begin
  if new.latitude is not null and new.longitude is not null then
    new.geo := extensions.ST_SetSRID(
                 extensions.ST_MakePoint(new.longitude, new.latitude), 4326
               )::extensions.geography;
  end if;
  return new;
end;
$$;
revoke execute on function omelo_sync_geo() from public, anon, authenticated;

create trigger locations_sync_geo
  before insert or update of latitude, longitude on locations
  for each row execute function omelo_sync_geo();

insert into locations (kind, name, country_code, timezone, latitude, longitude, population)
values ('country', 'India', 'IN', 'Asia/Kolkata', 20.5937, 78.9629, 1400000000);

insert into locations (parent_id, kind, name, country_code, admin_code, timezone, latitude, longitude)
select id, 'region', v.name, 'IN', v.code, 'Asia/Kolkata', v.lat, v.lng
from locations, (values
  ('Delhi',         'DL', 28.6139, 77.2090),
  ('Haryana',       'HR', 29.0588, 76.0856),
  ('Uttar Pradesh', 'UP', 26.8467, 80.9462)
) as v(name, code, lat, lng)
where kind = 'country' and country_code = 'IN';

insert into locations (parent_id, kind, name, country_code, timezone, latitude, longitude, population)
select r.id, 'city', v.name, 'IN', 'Asia/Kolkata', v.lat, v.lng, v.pop
from (values
  ('Delhi',         'New Delhi',     28.6139, 77.2090, 32900000),
  ('Haryana',       'Gurugram',      28.4595, 77.0266,  1150000),
  ('Haryana',       'Faridabad',     28.4089, 77.3178,  1400000),
  ('Uttar Pradesh', 'Noida',         28.5355, 77.3910,   640000),
  ('Uttar Pradesh', 'Greater Noida', 28.4744, 77.5040,   300000),
  ('Uttar Pradesh', 'Ghaziabad',     28.6692, 77.4538,  1650000)
) as v(region, name, lat, lng, pop)
join locations r on r.kind = 'region' and r.name = v.region and r.country_code = 'IN';

insert into locations (parent_id, kind, name, country_code, timezone, latitude, longitude)
select c.id, 'area', v.name, 'IN', 'Asia/Kolkata', v.lat, v.lng
from (values
  ('New Delhi', 'Connaught Place',  28.6315, 77.2167),
  ('New Delhi', 'Karol Bagh',       28.6519, 77.1909),
  ('New Delhi', 'Dwarka',           28.5921, 77.0460),
  ('New Delhi', 'Rohini',           28.7495, 77.0565),
  ('New Delhi', 'Saket',            28.5245, 77.2066),
  ('New Delhi', 'Nehru Place',      28.5494, 77.2519),
  ('New Delhi', 'Lajpat Nagar',     28.5677, 77.2433),
  ('New Delhi', 'Okhla',            28.5355, 77.2730),
  ('New Delhi', 'Janakpuri',        28.6219, 77.0878),
  ('New Delhi', 'Pitampura',        28.6942, 77.1314),
  ('New Delhi', 'Vasant Kunj',      28.5200, 77.1591),
  ('New Delhi', 'Mayur Vihar',      28.6127, 77.2951),
  ('New Delhi', 'Shahdara',         28.6692, 77.2891),
  ('New Delhi', 'Narela',           28.8553, 77.0910),
  ('New Delhi', 'Najafgarh',        28.6090, 76.9795),
  ('New Delhi', 'Paharganj',        28.6450, 77.2120),
  ('New Delhi', 'Chandni Chowk',    28.6562, 77.2301),
  ('New Delhi', 'Hauz Khas',        28.5494, 77.2001),
  ('New Delhi', 'Rajouri Garden',   28.6469, 77.1200),
  ('New Delhi', 'Preet Vihar',      28.6410, 77.2950),
  ('Gurugram',  'Cyber City',       28.4949, 77.0880),
  ('Gurugram',  'Udyog Vihar',      28.5023, 77.0864),
  ('Gurugram',  'Sohna Road',       28.4089, 77.0378),
  ('Gurugram',  'Sector 56',        28.4211, 77.1000),
  ('Gurugram',  'Manesar',          28.3549, 76.9366),
  ('Gurugram',  'MG Road',          28.4796, 77.0800),
  ('Gurugram',  'Golf Course Road', 28.4420, 77.0980),
  ('Noida',     'Sector 18',        28.5700, 77.3210),
  ('Noida',     'Sector 62',        28.6231, 77.3720),
  ('Noida',     'Sector 63',        28.6280, 77.3810),
  ('Noida',     'Sector 16',        28.5790, 77.3160),
  ('Noida',     'Sector 1',         28.5890, 77.3110),
  ('Noida',     'Sector 135',       28.5000, 77.3900),
  ('Noida',     'Noida Extension',  28.6100, 77.4400),
  ('Greater Noida', 'Knowledge Park', 28.4640, 77.5030),
  ('Greater Noida', 'Surajpur',       28.4720, 77.5100),
  ('Ghaziabad', 'Indirapuram',      28.6421, 77.3710),
  ('Ghaziabad', 'Vaishali',         28.6500, 77.3400),
  ('Ghaziabad', 'Raj Nagar',        28.6800, 77.4300),
  ('Ghaziabad', 'Sahibabad',        28.6800, 77.3400),
  ('Faridabad', 'Ballabgarh',       28.3400, 77.3200),
  ('Faridabad', 'Sector 21',        28.4200, 77.3100),
  ('Faridabad', 'NIT Faridabad',    28.3800, 77.3100)
) as v(city, name, lat, lng)
join locations c on c.kind = 'city' and c.name = v.city and c.country_code = 'IN';