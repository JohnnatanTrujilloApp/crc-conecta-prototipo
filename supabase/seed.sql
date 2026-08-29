-- Datos exclusivamente ficticios para Supabase de desarrollo.
insert into public.organizations(id,name,slug) values('10000000-0000-0000-0000-000000000001','CRC Demo','crc-demo') on conflict(id) do update set name=excluded.name;
insert into public.sites(id,organization_id,name,slug,department,city) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','CRC Nemocón Demo','nemocon-demo','Cundinamarca','Nemocón'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','CRC Central Demo','central-demo','Cundinamarca','Bogotá')
on conflict(id) do update set name=excluded.name,city=excluded.city;
insert into public.people(id,organization_id,site_id,first_name,last_name,phone,email,person_status,first_visit_date) values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','María','Rodríguez','3005550101','maria@example.com','MEMBER','2026-02-08'),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001','Pedro','Gómez','3015550102',null,'CONGREGANT','2026-04-19'),
 ('30000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002','Ana','Martínez','3025550103','ana@example.com','VISITOR','2026-08-16')
on conflict(id) do update set phone=excluded.phone,email=excluded.email,person_status=excluded.person_status;
