import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";

const migration=await readFile(new URL("../supabase/migrations/20260924010000_multi_ministry_leadership.sql",import.meta.url),"utf8");
const agenda=await readFile(new URL("../supabase/migrations/20260916010000_event_agenda_management.sql",import.meta.url),"utf8");
const management=await readFile(new URL("../supabase/migrations/20260917050000_expand_training_event_audience.sql",import.meta.url),"utf8");
const view=await readFile(new URL("../features/agenda/AgendaCarousel.tsx",import.meta.url),"utf8");
const schema=await readFile(new URL("../supabase/migrations/20260827010000_sprint_3_families_ministries_profile_search.sql",import.meta.url),"utf8");
const roles=await readFile(new URL("../supabase/migrations/20260826020000_sprint_2_roles_permissions_scopes_rls.sql",import.meta.url),"utf8");
const kids=await readFile(new URL("../features/kids/kidsReport.ts",import.meta.url),"utf8");
const ministryRepository=await readFile(new URL("../features/ministries/repository.ts",import.meta.url),"utf8");
const discipleship=await readFile(new URL("../supabase/migrations/20260828020000_sprint_7_discipleship_followups_dashboard.sql",import.meta.url),"utf8");
const functionBody=(name)=>{const match=migration.match(new RegExp(`create or replace function public\\.${name}\\([\\s\\S]*?as \\$\\$([\\s\\S]*?)\\$\\$;`));assert.ok(match,`${name} falta en la migración`);return match[1]};

const ministryIds=["ujieres","caballeros","kids","parejas"];
const ministry=(id)=>({id,organizationId:"crc",siteId:"nemocon",active:true,leaderPersonId:null});
const today="2026-09-24";
const memberships=ministryIds.map(id=>({ministryId:id,personId:"juan",position:`Líder de ${id}`,isLeader:true,active:true,startDate:"2026-01-01",endDate:null}));
const role={personId:"juan",code:"MINISTRY_LEADER",organizationId:"crc",siteId:"nemocon",active:true};
function leads(ministryRow,membershipRows=memberships,assignedRole=role,date=today){
 return assignedRole.active&&assignedRole.code==="MINISTRY_LEADER"&&assignedRole.organizationId===ministryRow.organizationId&&assignedRole.siteId===ministryRow.siteId&&ministryRow.active&&membershipRows.some(pm=>pm.ministryId===ministryRow.id&&pm.personId===assignedRole.personId&&pm.active&&pm.startDate<=date&&(!pm.endDate||pm.endDate>=date)&&(ministryRow.leaderPersonId===pm.personId||pm.isLeader));
}
const visible=(audiences,membershipRows=memberships)=>audiences.some(id=>leads(ministry(id),membershipRows));

test("una cuenta y un rol de sede respaldan cuatro vínculos ministeriales independientes",()=>{
 assert.match(roles,/unique index if not exists user_roles_active_assignment_idx[\s\S]*user_account_id, role_id, organization_id, scope_type/);
 assert.match(schema,/unique \(person_id, ministry_id, start_date\)/);
 assert.equal(new Set(memberships.map(pm=>pm.personId)).size,1);
 assert.deepEqual(ministryIds.filter(id=>leads(ministry(id))),ministryIds);
 assert.equal(leads({...ministry("ujieres"),leaderPersonId:"juan"},[{...memberships[0],position:"Integrante",isLeader:false}]),true,"leader_person_id sigue funcionando");
 const body=functionBody("current_user_leads_ministry");
 for(const guard of [/r\.code='MINISTRY_LEADER'/,/ur\.organization_id=m\.organization_id/,/ur\.site_id=m\.site_id/,/pm\.active/,/pm\.start_date<=current_date/,/pm\.end_date>=current_date/,/m\.leader_person_id=ua\.person_id/,/pm\.is_leader/])assert.match(body,guard);
 assert.doesNotMatch(body,/pm\.position|like|ilike|~/i);
});

test("la ficha ministerial muestra todos los líderes vigentes sin duplicar integrantes",()=>{
 assert.match(ministryRepository,/is_leader,start_date,end_date/);
 assert.match(ministryRepository,/m\.person_id===x\.leader_person_id\|\|m\.is_leader/);
 assert.doesNotMatch(ministryRepository,/\/\^\(líder\|lider\)/);
 assert.match(ministryRepository,/new Map\(linked\.filter/);
 assert.match(ministryRepository,/new Set\(linked\.map\(m=>m\.person_id\)\)\.size/);
});

test("la migración agrega is_leader con valor conservador y solo backfill del líder principal vigente",()=>{
 assert.match(migration,/add column if not exists is_leader boolean not null default false/);
 assert.match(migration,/update public\.person_ministries pm[\s\S]*pm\.person_id=m\.leader_person_id/);
 assert.match(migration,/update public\.person_ministries pm[\s\S]*pm\.start_date<=current_date/);
 assert.doesNotMatch(migration,/update public\.person_ministries pm[\s\S]*where[\s\S]*pm\.position/i);
});

test("position no concede ni retira liderazgo estructurado",()=>{
 assert.equal(leads(ministry("kids"),[{...memberships[2],position:"Líder de Kids",isLeader:false}]),false);
 assert.equal(leads(ministry("kids"),[{...memberships[2],position:"Participante Kids",isLeader:true}]),true);
 assert.equal(leads(ministry("kids"),[{...memberships[2],position:"Participante Kids",isLeader:false}]),false);
 assert.equal(leads(ministry("kids"),[{...memberships[2],position:"Coordinador",isLeader:false}]),false);
});

test("Agenda devuelve los cuatro ministerios y permite organizador y audiencias múltiples",()=>{
 assert.match(management,/jsonb_agg\(jsonb_build_object\('id',m\.id,'siteId',m\.site_id,'name',m\.name,'mine',public\.current_user_leads_ministry\(m\.id\)\)/);
 assert.match(agenda,/can_ministry:=given_ministry_id is not null[\s\S]*current_user_leads_ministry\(given_ministry_id\)/);
 assert.match(management,/for target in select value from jsonb_array_elements\(given_audiences\) loop/);
 assert.match(view,/ministries\.map\(m=><option/);
 assert.match(view,/ministries\.map\(m=><label/);
 for(const id of ministryIds)assert.equal(leads(ministry(id)),true);
 assert.equal(leads(ministry("alabanza")),false);
 assert.equal(visible(["ujieres","caballeros"]),true);
});

test("lectura de Agenda es acumulativa y no duplica un evento con dos audiencias",()=>{
 assert.match(functionBody("can_user_view_event"),/ea\.audience_type='MINISTRY'[\s\S]*pm\.ministry_id=ea\.ministry_id/);
 assert.match(agenda,/from public\.events e join public\.sites s[\s\S]*where public\.can_user_view_event\(e\.id\)/);
 assert.doesNotMatch(agenda,/from public\.events e join public\.event_audiences ea[\s\S]*where public\.can_user_view_event\(e\.id\)/);
 assert.equal(visible(["ujieres"]),true);
 assert.equal(visible(["caballeros"]),true);
 assert.equal(visible(["kids"]),true);
 assert.equal(visible(["parejas"]),true);
 assert.equal(visible(["alabanza"]),false);
 assert.equal([{"id":"evento","audiences":["ujieres","caballeros"]}].filter(event=>visible(event.audiences)).length,1);
});

test("publicar para sede o nación no surge del rol MINISTRY_LEADER",()=>{
 assert.match(management,/can_national:=public\.current_user_has_permission\('events\.manage_national'/);
 assert.match(management,/can_site:=public\.current_user_has_permission\('events\.manage_site'/);
 assert.match(management,/target_type='SITE'[\s\S]*EVENT_SITE_AUDIENCE_DENIED/);
 assert.match(management,/target_type in\('ALL_CRC','PUBLIC','NATIONAL'\)[\s\S]*EVENT_NATIONAL_AUDIENCE_DENIED/);
 assert.match(management,/target_type='MINISTRY'[\s\S]*current_user_leads_ministry\(target_id\)/);
 assert.doesNotMatch(agenda,/\('MINISTRY_LEADER','events\.manage_site'\)/);
 assert.doesNotMatch(agenda,/\('MINISTRY_LEADER','events\.manage_national'\)/);
});

test("retirar un liderazgo y respetar sus fechas no toca los otros tres",()=>{
 const remaining=memberships.map(pm=>pm.ministryId==="kids"?{...pm,isLeader:false}:pm);
 assert.deepEqual(ministryIds.filter(id=>leads(ministry(id),remaining)),["ujieres","caballeros","parejas"]);
 assert.equal(leads(ministry("kids"),[{...memberships[2],startDate:"2026-09-25"}]),false);
 assert.equal(leads(ministry("kids"),[{...memberships[2],endDate:"2026-09-23"}]),false);
 assert.equal(leads(ministry("kids"),[{...memberships[2],endDate:today}]),true);
 assert.equal(leads(ministry("kids"),memberships,{...role,siteId:"otra-sede"}),false);
 assert.equal(leads(ministry("kids"),memberships,{...role,organizationId:"otra-organización"}),false);
});

test("Kids, Worship y Formación reutilizan liderazgo scoped sin convertir adultos en menores",()=>{
 for(const name of ["current_user_can_manage_kids","current_user_can_manage_worship","current_user_leads_training_ministry","current_user_is_training_ministry_leader","current_user_is_restricted_worship_leader","current_user_is_restricted_specialized_ministry_leader"])assert.match(functionBody(name),/public\.current_user_leads_(?:training_)?ministry\(m\.id\)/);
 assert.match(kids,/child\.age<18/);
 assert.match(discipleship,/create table.*discipleship_assignments|create table.*discipleship_followups/s);
 assert.doesNotMatch(migration,/insert into public\.(?:person_ministries|discipleship_assignments|user_roles)/);
});
