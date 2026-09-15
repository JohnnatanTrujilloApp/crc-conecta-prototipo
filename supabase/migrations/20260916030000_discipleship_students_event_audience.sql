-- La audiencia del ministerio Discipulado también incluye a los alumnos con
-- una asignación individual vigente en la misma organización y sede.
-- Esto solo amplía la lectura de actividades publicadas; no concede gestión.

create or replace function public.can_user_view_event(target_event_id uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
 select exists(
  select 1
  from public.events e
  where e.id=target_event_id
    and e.published_at is not null
    and e.archived_at is null
    and e.status in('SCHEDULED','IN_PROGRESS')
    and coalesce(e.end_at,e.start_at)>=now()
    and(
      exists(
        select 1 from public.event_audiences ea
        where ea.event_id=e.id and ea.audience_type='PUBLIC'
      )
      or(
        auth.uid() is not null
        and exists(
          select 1 from public.user_accounts ua
          where ua.id=auth.uid() and ua.access_status='ACTIVE'
        )
        and(
          exists(
            select 1
            from public.user_roles ur
            join public.roles r on r.id=ur.role_id
            where ur.user_account_id=auth.uid()
              and ur.active
              and ur.starts_at<=now()
              and(ur.ends_at is null or ur.ends_at>now())
              and ur.organization_id=e.organization_id
              and r.code='SUPER_ADMIN'
          )
          or exists(
            select 1
            from public.event_audiences ea
            where ea.event_id=e.id
              and(
                ea.audience_type in('ALL_CRC','NATIONAL')
                or(
                  ea.audience_type='ALL_MEMBERS'
                  and exists(
                    select 1
                    from public.user_accounts ua
                    join public.people p on p.id=ua.person_id
                    where ua.id=auth.uid() and p.person_status<>'VISITOR'
                  )
                )
                or(
                  ea.audience_type='SITE'
                  and exists(
                    select 1
                    from public.user_accounts ua
                    join public.people p on p.id=ua.person_id
                    where ua.id=auth.uid() and p.site_id=ea.site_id
                  )
                )
                or(
                  ea.audience_type='MINISTRY'
                  and(
                    exists(
                      select 1
                      from public.user_accounts ua
                      join public.person_ministries pm on pm.person_id=ua.person_id
                      where ua.id=auth.uid()
                        and pm.ministry_id=ea.ministry_id
                        and pm.active
                        and(pm.end_date is null or pm.end_date>=current_date)
                    )
                    or exists(
                      select 1
                      from public.user_accounts ua
                      join public.discipleship_assignments da on da.disciple_person_id=ua.person_id
                      join public.ministries ministry on ministry.id=ea.ministry_id
                      where ua.id=auth.uid()
                        and da.organization_id=e.organization_id
                        and da.site_id=e.site_id
                        and da.status in('ASSIGNED','ACTIVE','PAUSED')
                        and ministry.organization_id=e.organization_id
                        and ministry.site_id=e.site_id
                        and ministry.active
                        and lower(trim(ministry.name)) in('discipulado','ministerio de discipulado')
                    )
                  )
                )
                or(
                  ea.audience_type='ROLE'
                  and exists(
                    select 1
                    from public.user_roles ur
                    where ur.user_account_id=auth.uid()
                      and ur.role_id=ea.role_id
                      and ur.active
                      and ur.starts_at<=now()
                      and(ur.ends_at is null or ur.ends_at>now())
                      and(ea.role_scope_site_id is null or ur.scope_type='ORGANIZATION' or ur.site_id=ea.role_scope_site_id)
                  )
                )
                or(ea.audience_type='SPECIFIC_USERS' and ea.user_account_id=auth.uid())
              )
          )
        )
      )
    )
 );
$$;

revoke all on function public.can_user_view_event(uuid) from public;
grant execute on function public.can_user_view_event(uuid) to authenticated;

comment on function public.can_user_view_event(uuid)
is 'Autoriza actividades publicadas por audiencia; Discipulado incluye alumnos con asignación individual vigente en la misma sede.';

notify pgrst,'reload schema';
