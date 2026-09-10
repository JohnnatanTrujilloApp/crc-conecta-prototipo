-- Completa el cambio de candidatos: asignar o reasignar no exige que la persona
-- tenga cuenta. Registrar lecciones continúa protegido por permisos en su RPC.
create or replace function public.create_individual_discipleship(target_site_id uuid,target_program_id uuid,target_disciple_person_id uuid,target_discipler_person_id uuid,given_notes text default null)
returns uuid language plpgsql security definer set search_path='' as $$
declare s record; created_id uuid;
begin
 select * into s from public.sites where id=target_site_id;
 if s.id is null or not public.current_user_has_permission('discipleship.assign',s.organization_id,s.id) then raise exception 'DISCIPLESHIP_ASSIGN_DENIED'; end if;
 if target_disciple_person_id=target_discipler_person_id then raise exception 'SELF_DISCIPLESHIP_NOT_ALLOWED'; end if;
 if not exists(select 1 from public.training_programs p where p.id=target_program_id and p.organization_id=s.organization_id and p.program_type='DISCIPLESHIP' and p.active) then raise exception 'INVALID_DISCIPLESHIP_PROGRAM'; end if;
 if not exists(select 1 from public.people p where p.id=target_disciple_person_id and p.organization_id=s.organization_id and p.person_status not in('INACTIVE','TRANSFERRED')) then raise exception 'DISCIPLE_NOT_AVAILABLE'; end if;
 if not exists(select 1 from public.people p where p.id=target_discipler_person_id and p.organization_id=s.organization_id and p.person_status not in('INACTIVE','TRANSFERRED')) then raise exception 'DISCIPLER_NOT_AVAILABLE'; end if;
 insert into public.discipleship_assignments(organization_id,site_id,program_id,disciple_person_id,discipler_person_id,notes,created_by)
 values(s.organization_id,s.id,target_program_id,target_disciple_person_id,target_discipler_person_id,nullif(trim(given_notes),''),auth.uid()) returning id into created_id;
 return created_id;
exception when unique_violation then raise exception 'DISCIPLESHIP_ALREADY_ASSIGNED'; end; $$;

create or replace function public.reassign_individual_discipler(target_assignment_id uuid,new_discipler_person_id uuid,given_reason text default null)
returns void language plpgsql security definer set search_path='' as $$
declare a record; old_teacher uuid;
begin
 select * into a from public.discipleship_assignments where id=target_assignment_id for update;
 if a.id is null or not public.current_user_has_permission('discipleship.reassign',a.organization_id,a.site_id) then raise exception 'DISCIPLESHIP_REASSIGN_DENIED'; end if;
 if new_discipler_person_id=a.disciple_person_id then raise exception 'SELF_DISCIPLESHIP_NOT_ALLOWED'; end if;
 if not exists(select 1 from public.people p where p.id=new_discipler_person_id and p.organization_id=a.organization_id and p.person_status not in('INACTIVE','TRANSFERRED')) then raise exception 'DISCIPLER_NOT_AVAILABLE'; end if;
 old_teacher:=a.discipler_person_id;
 update public.discipleship_assignments set discipler_person_id=new_discipler_person_id where id=a.id;
 insert into public.audit_logs(organization_id,site_id,user_id,action,entity_type,entity_id,old_values,new_values)
 values(a.organization_id,a.site_id,auth.uid(),'DISCIPLESHIP_DISCIPLER_REASSIGNED','DISCIPLESHIP_ASSIGNMENT',a.id,jsonb_build_object('disciplerPersonId',old_teacher),jsonb_build_object('disciplerPersonId',new_discipler_person_id,'reason',given_reason));
end; $$;

revoke all on function public.create_individual_discipleship(uuid,uuid,uuid,uuid,text) from public;
revoke all on function public.reassign_individual_discipler(uuid,uuid,text) from public;
grant execute on function public.create_individual_discipleship(uuid,uuid,uuid,uuid,text) to authenticated;
grant execute on function public.reassign_individual_discipler(uuid,uuid,text) to authenticated;
notify pgrst,'reload schema';
