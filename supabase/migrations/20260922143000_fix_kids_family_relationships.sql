CREATE OR REPLACE FUNCTION public.save_kids_child(payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
    scope record;
    child_id uuid;
    duplicate_id uuid;
    guardian_id uuid;
    v_family_id uuid;
    rel public.family_relationship;
    attendance_event uuid;
begin

    select *
    into scope
    from public.get_my_kids_scope();

    if scope.ministry_id is null then
        raise exception 'KIDS_SCOPE_DENIED';
    end if;


    -- =========================================================
    -- 1. PERSONA EXISTENTE O NUEVA
    -- =========================================================

    child_id := nullif(payload->>'existingPersonId', '')::uuid;

    if child_id is not null then

        if not exists (
            select 1
            from public.people p
            where p.id = child_id
              and p.organization_id = scope.organization_id
              and p.site_id = scope.site_id
              and p.archived_at is null
        ) then
            raise exception 'KIDS_PERSON_OUT_OF_SCOPE';
        end if;

    else

        if nullif(trim(payload->>'firstName'), '') is null
           or nullif(trim(payload->>'lastName'), '') is null
           or nullif(payload->>'birthDate', '') is null
        then
            raise exception 'KIDS_REQUIRED_FIELDS';
        end if;


        if nullif(payload->>'documentNumber', '') is not null then

            select p.id
            into duplicate_id
            from public.people p
            where p.organization_id = scope.organization_id
              and p.document_number = trim(payload->>'documentNumber')
              and p.archived_at is null
            limit 1;

        end if;


        if duplicate_id is null then

            select p.id
            into duplicate_id
            from public.people p
            where p.organization_id = scope.organization_id
              and lower(trim(p.first_name)) =
                  lower(trim(payload->>'firstName'))
              and lower(trim(p.last_name)) =
                  lower(trim(payload->>'lastName'))
              and p.birth_date = (payload->>'birthDate')::date
              and p.archived_at is null
            limit 1;

        end if;


        if duplicate_id is not null then

            child_id := duplicate_id;

        else

            insert into public.people (
                organization_id,
                site_id,
                document_type,
                document_number,
                first_name,
                last_name,
                birth_date,
                sex,
                email,
                phone,
                person_status,
                first_visit_date
            )
            values (
                scope.organization_id,
                scope.site_id,
                nullif(payload->>'documentType', '')::public.document_type,
                nullif(trim(payload->>'documentNumber'), ''),
                trim(payload->>'firstName'),
                trim(payload->>'lastName'),
                (payload->>'birthDate')::date,
                nullif(payload->>'sex', ''),
                nullif(lower(trim(payload->>'email')), ''),
                nullif(trim(payload->>'phone'), ''),
                'VISITOR',
                current_date
            )
            returning id into child_id;

        end if;

    end if;


    -- =========================================================
    -- 2. VINCULAR A KIDS
    -- =========================================================

    insert into public.person_ministries (
        organization_id,
        site_id,
        person_id,
        ministry_id,
        position,
        active
    )
    values (
        scope.organization_id,
        scope.site_id,
        child_id,
        scope.ministry_id,
        'Participante Kids',
        true
    )
    on conflict (person_id, ministry_id, start_date)
    do update
    set
        active = true,
        end_date = null,
        position = excluded.position;


    -- =========================================================
    -- 3. RESPONSABLE / ACUDIENTE
    -- =========================================================

    guardian_id :=
        nullif(payload->>'guardianPersonId', '')::uuid;


    if guardian_id is null
       and nullif(trim(payload->>'guardianName'), '') is not null
    then

        select p.id
        into guardian_id
        from public.people p
        where p.organization_id = scope.organization_id
          and p.site_id = scope.site_id
          and (
                (
                    nullif(payload->>'guardianPhone', '') is not null
                    and p.phone = trim(payload->>'guardianPhone')
                )
                or
                (
                    nullif(payload->>'guardianEmail', '') is not null
                    and lower(p.email) =
                        lower(trim(payload->>'guardianEmail'))
                )
          )
          and p.archived_at is null
        limit 1;


        if guardian_id is null then

            insert into public.people (
                organization_id,
                site_id,
                first_name,
                last_name,
                email,
                phone,
                person_status,
                first_visit_date
            )
            values (
                scope.organization_id,
                scope.site_id,

                split_part(
                    trim(payload->>'guardianName'),
                    ' ',
                    1
                ),

                coalesce(
                    nullif(
                        trim(
                            substr(
                                trim(payload->>'guardianName'),
                                length(
                                    split_part(
                                        trim(payload->>'guardianName'),
                                        ' ',
                                        1
                                    )
                                ) + 1
                            )
                        ),
                        ''
                    ),
                    'Acudiente'
                ),

                nullif(
                    lower(trim(payload->>'guardianEmail')),
                    ''
                ),

                nullif(
                    trim(payload->>'guardianPhone'),
                    ''
                ),

                'VISITOR',
                current_date
            )
            returning id into guardian_id;

        end if;

    end if;


    -- =========================================================
    -- 4. FAMILIA / PARENTESCO
    -- =========================================================

    if guardian_id is not null then

        if not exists (
            select 1
            from public.people p
            where p.id = guardian_id
              and p.organization_id = scope.organization_id
              and p.site_id = scope.site_id
              and p.archived_at is null
        ) then
            raise exception 'KIDS_GUARDIAN_OUT_OF_SCOPE';
        end if;


        -- -----------------------------------------------------
        -- PRIORIDAD 1:
        -- Buscar una familia que YA compartan menor y acudiente.
        -- -----------------------------------------------------

        select child_fm.family_id
        into v_family_id
        from public.family_members child_fm
        join public.family_members guardian_fm
          on guardian_fm.family_id = child_fm.family_id
         and guardian_fm.person_id = guardian_id
        join public.families f
          on f.id = child_fm.family_id
         and f.organization_id = scope.organization_id
         and f.site_id = scope.site_id
        where child_fm.person_id = child_id
        order by
            guardian_fm.is_primary_contact desc,
            child_fm.family_id
        limit 1;


        -- -----------------------------------------------------
        -- PRIORIDAD 2:
        -- Si no comparten familia, utilizar una familia existente
        -- del menor dentro de la misma organización y sede.
        -- -----------------------------------------------------

        if v_family_id is null then

            select fm.family_id
            into v_family_id
            from public.family_members fm
            join public.families f
              on f.id = fm.family_id
             and f.organization_id = scope.organization_id
             and f.site_id = scope.site_id
            where fm.person_id = child_id
            order by fm.family_id
            limit 1;

        end if;


        -- -----------------------------------------------------
        -- PRIORIDAD 3:
        -- Si el menor todavía no tiene familia, comprobar si el
        -- acudiente tiene una familia apropiada en la misma sede.
        -- -----------------------------------------------------

        if v_family_id is null then

            select fm.family_id
            into v_family_id
            from public.family_members fm
            join public.families f
              on f.id = fm.family_id
             and f.organization_id = scope.organization_id
             and f.site_id = scope.site_id
            where fm.person_id = guardian_id
            order by
                fm.is_primary_contact desc,
                fm.family_id
            limit 1;

        end if;


        -- -----------------------------------------------------
        -- PRIORIDAD 4:
        -- Si ninguno tiene familia, crear una nueva.
        -- -----------------------------------------------------

        if v_family_id is null then

            insert into public.families (
                organization_id,
                site_id,
                name,
                active
            )
            values (
                scope.organization_id,
                scope.site_id,
                'Familia ' || (
                    select p.last_name
                    from public.people p
                    where p.id = child_id
                ),
                true
            )
            returning id into v_family_id;

        end if;


        -- =====================================================
        -- ASEGURAR QUE EL MENOR PERTENEZCA A LA FAMILIA
        -- =====================================================

        insert into public.family_members (
            organization_id,
            site_id,
            family_id,
            person_id,
            relationship,
            is_primary_contact
        )
        values (
            scope.organization_id,
            scope.site_id,
            v_family_id,
            child_id,

            case
                when (
                    select p.sex
                    from public.people p
                    where p.id = child_id
                ) = 'F'
                then 'DAUGHTER'::public.family_relationship
                else 'SON'::public.family_relationship
            end,

            false
        )
        on conflict (family_id, person_id)
        do nothing;


        rel := coalesce(
            nullif(
                payload->>'guardianRelationship',
                ''
            )::public.family_relationship,
            'GUARDIAN'::public.family_relationship
        );


        -- =====================================================
        -- ACUDIENTE
        --
        -- IMPORTANTE:
        -- Si ya existe una relación familiar, NO modificarla.
        --
        -- Ejemplo:
        -- FATHER seguirá siendo FATHER.
        -- MOTHER seguirá siendo MOTHER.
        --
        -- Kids no debe convertir esos parentescos a GUARDIAN.
        -- =====================================================

        insert into public.family_members (
            organization_id,
            site_id,
            family_id,
            person_id,
            relationship,
            is_primary_contact
        )
        values (
            scope.organization_id,
            scope.site_id,
            v_family_id,
            guardian_id,
            rel,
            coalesce(
                (payload->>'primaryContact')::boolean,
                true
            )
        )
        on conflict (family_id, person_id)
        do update
        set
            -- Preservar parentesco existente.
            relationship = public.family_members.relationship,

            -- Sí permitimos actualizar que sea contacto principal.
            is_primary_contact =
                excluded.is_primary_contact;


        -- =====================================================
        -- AUDITORÍA
        -- =====================================================

        insert into public.audit_logs (
            organization_id,
            site_id,
            user_id,
            action,
            entity_type,
            entity_id,
            new_values
        )
        values (
            scope.organization_id,
            scope.site_id,
            auth.uid(),
            'KIDS_GUARDIAN_LINKED',
            'PERSON',
            child_id,
            jsonb_build_object(
                'guardianId',
                guardian_id,
                'requestedRelationship',
                rel,
                'familyId',
                v_family_id
            )
        );

    end if;


    -- =========================================================
    -- 5. ASISTENCIA OPCIONAL
    -- =========================================================

    attendance_event :=
        nullif(payload->>'attendanceEventId', '')::uuid;


    if attendance_event is not null then

        if not exists (
            select 1
            from public.events e
            where e.id = attendance_event
              and e.ministry_id = scope.ministry_id
              and e.site_id = scope.site_id
        ) then
            raise exception 'KIDS_EVENT_OUT_OF_SCOPE';
        end if;


        insert into public.attendance (
            organization_id,
            site_id,
            event_id,
            person_id,
            status,
            check_in_method,
            check_in_at,
            registered_by
        )
        values (
            scope.organization_id,
            scope.site_id,
            attendance_event,
            child_id,
            'PRESENT',
            'MANUAL',
            now(),
            auth.uid()
        )
        on conflict (event_id, person_id)
        do update
        set
            status = 'PRESENT',
            check_in_at = now();

    end if;


    -- =========================================================
    -- 6. AUDITORÍA FINAL
    -- =========================================================

    insert into public.audit_logs (
        organization_id,
        site_id,
        user_id,
        action,
        entity_type,
        entity_id,
        new_values
    )
    values (
        scope.organization_id,
        scope.site_id,
        auth.uid(),
        'KIDS_PERSON_ADDED',
        'PERSON',
        child_id,
        jsonb_build_object(
            'ministryId',
            scope.ministry_id,
            'existing',
            payload ? 'existingPersonId'
        )
    );


    return child_id;

end;
$function$

-- Mantener la RPC fuera del rol public y disponible únicamente
-- para usuarios autenticados.
revoke all on function public.save_kids_child(jsonb) from public;
grant execute on function public.save_kids_child(jsonb) to authenticated;

-- Actualizar el esquema expuesto por PostgREST.
notify pgrst, 'reload schema';