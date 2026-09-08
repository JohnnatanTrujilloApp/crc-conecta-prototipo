-- Personas ficticias para pruebas funcionales en CRC Nemocón.
-- No crea usuarios de Auth, roles, permisos ni cuentas de acceso.
do $$
declare target_site record;
begin
 select s.id,s.organization_id into target_site
 from public.sites s
 where s.active and(lower(s.name) like '%nemocón%' or lower(s.slug) like '%nemocon%')
 order by s.created_at limit 1;
 if target_site.id is null then raise exception 'No se encontró una sede activa CRC Nemocón'; end if;

 insert into public.people(
  organization_id,site_id,document_type,document_number,first_name,middle_name,last_name,second_last_name,
  preferred_name,birth_date,sex,marital_status,email,phone,address,city,department,country,
  first_visit_date,membership_date,person_status,baptized,baptism_date,discipleship_status
 ) values
 (target_site.organization_id,target_site.id,'CC','99000001','Andrés',null,'Prueba','Alvarez','Andrés','1984-02-14','M','MARRIED','crc.pruebas+andres@gmail.com','3109002001','Dirección de prueba 1','Nemocón','Cundinamarca','Colombia','2025-01-12','2025-06-01','MEMBER',true,'2025-05-18','COMPLETED'),
 (target_site.organization_id,target_site.id,'CC','99000002','Beatriz','Elena','Prueba','Alvarez','Beatriz','1987-07-22','F','MARRIED','crc.pruebas+beatriz@gmail.com','3109002002','Dirección de prueba 1','Nemocón','Cundinamarca','Colombia','2025-01-12','2025-06-01','MEMBER',true,'2025-05-18','IN_PROGRESS'),
 (target_site.organization_id,target_site.id,'TI','99000003','Samuel',null,'Prueba','Alvarez','Samuel','2011-11-03','M','SINGLE',null,'3109002003','Dirección de prueba 1','Nemocón','Cundinamarca','Colombia','2025-01-12',null,'CONGREGANT',false,null,'NOT_STARTED'),
 (target_site.organization_id,target_site.id,'BIRTH_CERTIFICATE','99000004','Sara',null,'Prueba','Alvarez','Sara','2018-04-09','F','SINGLE',null,'3109002004','Dirección de prueba 1','Nemocón','Cundinamarca','Colombia','2025-01-12',null,'CONGREGANT',false,null,'NOT_STARTED'),
 (target_site.organization_id,target_site.id,'CC','99000005','Carlos','Eduardo','Prueba','Benítez','Carlos','1971-09-30','M','MARRIED','crc.pruebas+carlos@gmail.com','3109002005','Dirección de prueba 2','Nemocón','Cundinamarca','Colombia','2024-08-04','2024-12-15','SERVER',true,'2024-11-10','COMPLETED'),
 (target_site.organization_id,target_site.id,'CC','99000006','Diana','Marcela','Prueba','Benítez','Diana','1974-12-12','F','MARRIED','crc.pruebas+diana@gmail.com','3109002006','Dirección de prueba 2','Nemocón','Cundinamarca','Colombia','2024-08-04','2024-12-15','MEMBER',true,'2024-11-10','COMPLETED'),
 (target_site.organization_id,target_site.id,'CC','99000007','Esteban',null,'Prueba','Castro','Esteban','1998-06-17','M','SINGLE','crc.pruebas+esteban@gmail.com','3109002007','Dirección de prueba 3','Nemocón','Cundinamarca','Colombia','2026-01-18',null,'CONGREGANT',false,null,'IN_PROGRESS'),
 (target_site.organization_id,target_site.id,'CC','99000008','Fernanda','Lucía','Prueba','Castro','Fer','2000-03-25','F','SINGLE','crc.pruebas+fernanda@gmail.com','3109002008','Dirección de prueba 3','Nemocón','Cundinamarca','Colombia','2026-02-08',null,'VISITOR',false,null,'NOT_STARTED'),
 (target_site.organization_id,target_site.id,'CC','99000009','Gabriel',null,'Prueba','Díaz','Gabriel','1992-08-05','M','MARRIED','crc.pruebas+gabriel@gmail.com','3109002009','Dirección de prueba 4','Nemocón','Cundinamarca','Colombia','2025-03-16','2025-10-05','LEADER',true,'2025-08-24','COMPLETED'),
 (target_site.organization_id,target_site.id,'CC','99000010','Helena','María','Prueba','Díaz','Helena','1994-01-19','F','MARRIED','crc.pruebas+helena@gmail.com','3109002010','Dirección de prueba 4','Nemocón','Cundinamarca','Colombia','2025-03-16','2025-10-05','SERVER',true,'2025-08-24','COMPLETED'),
 (target_site.organization_id,target_site.id,'TI','99000011','Isaac',null,'Prueba','Díaz','Isaac','2009-05-28','M','SINGLE',null,'3109002011','Dirección de prueba 4','Nemocón','Cundinamarca','Colombia','2025-03-16',null,'CONGREGANT',false,null,'IN_PROGRESS'),
 (target_site.organization_id,target_site.id,'CC','99000012','Juliana','Andrea','Prueba','Espitia','Juliana','2003-10-07','F','SINGLE','crc.pruebas+juliana@gmail.com','3109002012','Dirección de prueba 5','Nemocón','Cundinamarca','Colombia','2026-04-05',null,'VISITOR',false,null,'NOT_STARTED'),
 (target_site.organization_id,target_site.id,'CC','99000013','Kevin',null,'Prueba','Fonseca','Kevin','2005-02-11','M','SINGLE','crc.pruebas+kevin@gmail.com','3109002013','Dirección de prueba 6','Nemocón','Cundinamarca','Colombia','2026-05-03',null,'CONGREGANT',false,null,'IN_PROGRESS'),
 (target_site.organization_id,target_site.id,'CC','99000014','Laura','Sofía','Prueba','Gómez','Laura','1989-11-21','F','DIVORCED','crc.pruebas+laura@gmail.com','3109002014','Dirección de prueba 7','Nemocón','Cundinamarca','Colombia','2025-09-07','2026-02-15','MEMBER',true,'2026-01-25','COMPLETED'),
 (target_site.organization_id,target_site.id,'CC','99000015','Mateo',null,'Prueba','Hernández','Mateo','1960-04-16','M','WIDOWED','crc.pruebas+mateo@gmail.com','3109002015','Dirección de prueba 8','Nemocón','Cundinamarca','Colombia','2023-06-11','2023-12-03','MEMBER',true,'2023-11-19','COMPLETED'),
 (target_site.organization_id,target_site.id,'CC','99000016','Natalia','Paola','Prueba','Ibañez','Naty','1996-07-02','F','SINGLE','crc.pruebas+natalia@gmail.com','3109002016','Dirección de prueba 9','Nemocón','Cundinamarca','Colombia','2026-03-22',null,'VISITOR',false,null,'NOT_STARTED'),
 (target_site.organization_id,target_site.id,'TI','99000017','Óscar',null,'Prueba','Jiménez','Óscar','2013-09-14','M','SINGLE',null,'3109002017','Dirección de prueba 10','Nemocón','Cundinamarca','Colombia','2026-01-25',null,'CONGREGANT',false,null,'NOT_STARTED'),
 (target_site.organization_id,target_site.id,'BIRTH_CERTIFICATE','99000018','Paula','Isabel','Prueba','Jiménez','Paula','2020-12-01','F','SINGLE',null,'3109002018','Dirección de prueba 10','Nemocón','Cundinamarca','Colombia','2026-01-25',null,'VISITOR',false,null,'NOT_STARTED')
 on conflict(organization_id,document_type,document_number)
 where document_type is not null and document_number is not null
 do update set
  site_id=excluded.site_id,first_name=excluded.first_name,middle_name=excluded.middle_name,last_name=excluded.last_name,
  second_last_name=excluded.second_last_name,preferred_name=excluded.preferred_name,birth_date=excluded.birth_date,
  sex=excluded.sex,marital_status=excluded.marital_status,email=excluded.email,phone=excluded.phone,
  address=excluded.address,city=excluded.city,department=excluded.department,country=excluded.country,
  first_visit_date=excluded.first_visit_date,membership_date=excluded.membership_date,person_status=excluded.person_status,
  baptized=excluded.baptized,baptism_date=excluded.baptism_date,discipleship_status=excluded.discipleship_status,archived_at=null;
end $$;

notify pgrst,'reload schema';
