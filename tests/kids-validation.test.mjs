import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";
import ts from "typescript";

const source=await readFile(new URL("../features/kids/validation.ts",import.meta.url),"utf8");
const compiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
const {validateKidsBirthDate}=await import(`data:text/javascript;base64,${Buffer.from(compiled).toString("base64")}`);
const migration=await readFile(new URL("../supabase/migrations/20260922160000_validate_kids_age_guardians.sql",import.meta.url),"utf8");
const incrementalMigration=await readFile(new URL("../supabase/migrations/20260923010000_validate_new_kids_birth_before_insert.sql",import.meta.url),"utf8");
const modal=await readFile(new URL("../features/kids/KidsChildModal.tsx",import.meta.url),"utf8");

test("Kids compara fechas civiles, incluyendo el límite exacto de 18 años",()=>{
 const today=new Date(2026,8,22,23,30);
 assert.equal(validateKidsBirthDate("2008-09-22",today),"KIDS_AGE_NOT_ALLOWED");
 assert.equal(validateKidsBirthDate("2007-09-22",today),"KIDS_AGE_NOT_ALLOWED");
 assert.equal(validateKidsBirthDate("2008-09-23",today),null);
 assert.equal(validateKidsBirthDate("2010-01-01",today),null);
 assert.equal(validateKidsBirthDate(null,today),"KIDS_BIRTH_DATE_REQUIRED");
 assert.equal(validateKidsBirthDate("2026-09-23",today),"KIDS_BIRTH_DATE_FUTURE");
});

test("la función SQL valida la identidad definitiva antes de vincular o relacionar",()=>{
 const resolved=migration.indexOf("-- La identidad definitiva gobierna edad y sede");
 const ministry=migration.indexOf("insert into public.person_ministries");
 const family=migration.indexOf("insert into public.family_members");
 assert.ok(resolved>migration.indexOf("if duplicate_id is not null")&&resolved<ministry&&ministry<family);
 assert.match(migration,/if birth_date is null then raise exception 'KIDS_BIRTH_DATE_REQUIRED'/);
 assert.match(migration,/if birth_date>current_date then raise exception 'KIDS_BIRTH_DATE_FUTURE'/);
 assert.match(migration,/birth_date<=\(current_date-interval '18 years'\)::date/);
 assert.match(migration,/if not found then raise exception 'KIDS_PERSON_OUT_OF_SCOPE'/);
});

test("familias ambiguas se rechazan y los parentescos existentes se preservan",()=>{
 assert.match(migration,/if matches>1 then raise exception 'KIDS_FAMILY_AMBIGUOUS'/);
 assert.match(migration,/f\.organization_id=target_organization_id and f\.site_id=target_site_id and f\.active/);
 assert.match(migration,/requested_rel not in\('FATHER','MOTHER','GUARDIAN','CAREGIVER','OTHER'\)/);
 assert.match(migration,/on conflict\(family_id,person_id\) do update set is_primary_contact=excluded\.is_primary_contact/);
 assert.doesNotMatch(migration,/set relationship=excluded\.relationship/);
 assert.match(migration,/when 'M' then 'SON'::public\.family_relationship else 'OTHER'::public\.family_relationship/);
 assert.match(migration,/revoke all on function public\.resolve_kids_family/);
 assert.match(migration,/public\.save_kids_child\(jsonb\) from anon,authenticated/);
 assert.match(migration,/grant execute on function public\.get_kids_guardian_link\(uuid,uuid\).*to authenticated/);
});

test("el formulario muestra adultos hallados pero bloquea el guardado y protege relaciones",()=>{
 assert.match(modal,/results\.map\(row=>/);
 assert.match(modal,/const birthError=validateKidsBirthDate/);
 assert.match(modal,/disabled=\{busy\|\|linkLoading\|\|linkPending\|\|linkError\|\|Boolean\(birthError\)/);
 assert.match(modal,/Esta relación ya está registrada en la familia y no será modificada desde Kids/);
 assert.match(modal,/needsRelationship&&<label/);
 assert.match(modal,/<option value="">Selecciona el parentesco<\/option>/);
});

test("Kids valida la fecha de una persona nueva antes de insertarla y conserva la segunda validación",()=>{
 const insert=incrementalMigration.indexOf("insert into public.people");
 assert.ok(incrementalMigration.indexOf("new_birth_date:=trim(payload->>'birthDate')::date")<insert);
 assert.ok(incrementalMigration.indexOf("if new_birth_date>current_date")<insert);
 assert.ok(incrementalMigration.indexOf("if new_birth_date<=(current_date-interval '18 years')::date")<insert);
 assert.ok(incrementalMigration.indexOf("if birth_date is null then raise exception 'KIDS_BIRTH_DATE_REQUIRED'")>insert);
 assert.match(incrementalMigration,/exception when invalid_datetime_format or datetime_field_overflow/);
 assert.equal((incrementalMigration.match(/create or replace function/g)??[]).length,1);
});

test("Kids no muestra el selector antes de conocer el parentesco existente",()=>{
 assert.match(modal,/const linkPending=Boolean\(selectedChild&&selectedGuardian&&!guardianLink\)/);
 assert.match(modal,/const needsRelationship=hasGuardian&&!existingRelationship&&!linkLoading&&!linkPending/);
 assert.match(modal,/linkPending&&!linkError&&<p className="kids-search-status">Consultando relación familiar/);
 assert.match(modal,/disabled=\{busy\|\|linkLoading\|\|linkPending\|\|linkError/);
});
