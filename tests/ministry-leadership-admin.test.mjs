import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";

const migration=await readFile(new URL("../supabase/migrations/20260925010000_manage_multi_ministry_leadership.sql",import.meta.url),"utf8");
const people=await readFile(new URL("../features/people/PeopleView.tsx",import.meta.url),"utf8");
const repository=await readFile(new URL("../features/people/repository.ts",import.meta.url),"utf8");
const kids=await readFile(new URL("../features/kids/KidsView.tsx",import.meta.url),"utf8");
const agenda=await readFile(new URL("../supabase/migrations/20260924010000_multi_ministry_leadership.sql",import.meta.url),"utf8");
const checks=[
 ["SITE_PASTOR de la sede puede nombrar",/r\.code in\('SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR'\)[\s\S]*ur\.site_id=target\.site_id/],
 ["pastor de otra sede no puede",/current_user_has_permission\('ministries\.manage_leadership',target\.organization_id,target\.site_id\)/],
 ["líder ordinario no puede autodesignarse",/r\.code in\('SUPER_ADMIN','NATIONAL_PASTOR','SITE_PASTOR'\)/],
 ["líder ordinario no puede nombrar a terceros",/MINISTRY_LEADERSHIP_DENIED/],
 ["primer liderazgo crea rol de sede",/insert into public\.user_roles\([\s\S]*'SITE',target\.site_id/],
 ["liderazgos posteriores reutilizan rol vigente",/if existing_role\.id is null then/],
 ["un retiro conserva otros liderazgos",/if not other_leadership then/],
 ["retirar no borra membresía",/update public\.person_ministries pm set is_leader=given_is_leader/],
 ["último liderazgo cierra solo rol gestionado",/ur\.ministry_leadership_managed/],
 ["position no autoriza",/pm\.is_leader or m\.leader_person_id=ua\.person_id/],
 ["membresía obligatoria",/MINISTRY_MEMBERSHIP_REQUIRED/],
 ["nombramiento deja auditoría",/MINISTRY_LEADERSHIP_GRANTED'[\s\S]*MINISTRY_LEADERSHIP_REVOKED/],
 ["auditoría y rol están en la misma RPC transaccional",/insert into public\.user_roles[\s\S]*update public\.person_ministries[\s\S]*insert into public\.audit_logs/],
 ["Kids conserva filtro de menores",/kidsParticipants\(data\)/],
 ["Agenda conserva función de liderazgo",/public\.current_user_leads_ministry\(m\.id\)/],
 ["RPC no se concede a anónimo",/grant execute on function public\.set_ministry_leadership\(uuid,uuid,boolean\) to authenticated/],
 ["organización y sede se validan",/p\.organization_id=target\.organization_id and p\.site_id=target\.site_id/],
];
for(const [name,pattern] of checks)test(`liderazgo: ${name}`,()=>assert.match(name.includes("Kids")?kids:name.includes("Agenda")||name.includes("position")?agenda:migration,pattern));
test("la UI muestra acciones explícitas y confirmación",()=>{for(const label of ["Otorgar liderazgo","Retirar liderazgo","Cancelar"])assert.match(people,new RegExp(label));assert.match(repository,/rpc\("set_ministry_leadership"/)});
test("insert y update directos no permiten is_leader",()=>{assert.match(migration,/revoke insert on public\.person_ministries/);assert.match(migration,/revoke update on public\.person_ministries/);assert.doesNotMatch(migration,/grant (?:insert|update)\([^)]*is_leader/i)});

// Modelo de las invariantes; estas pruebas no sustituyen ejecución PostgreSQL.
const date="2026-09-25";
const row=(id,isLeader,startDate="2026-09-01",endDate=null)=>({id,personId:"p",ministryId:"kids",siteId:"nemocon",active:true,startDate,endDate,isLeader});
const valid=member=>member.active&&member.startDate<=date&&(!member.endDate||member.endDate>=date);
function designate(rows,grant,{primary=false,otherLeadership=false,role=null}={}){
 const memberships=rows.filter(member=>member.personId==="p"&&member.ministryId==="kids"&&member.siteId==="nemocon"&&valid(member));
 if(!memberships.length)throw Error("MINISTRY_MEMBERSHIP_REQUIRED");
 if(!grant&&primary)throw Error("MINISTRY_PRIMARY_LEADER_CHANGE_REQUIRED");
 const previous=memberships.some(member=>member.isLeader);
 const next=rows.map(member=>memberships.includes(member)?{...member,isLeader:grant}:member);
 const nextRole=grant?(role??{scope:"SITE",siteId:"nemocon",managed:true,active:true}):(!otherLeadership&&role?.managed&&role.scope==="SITE"&&role.siteId==="nemocon"?{...role,active:false}:role);
 return {rows:next,role:nextRole,audit:[{previous,next:grant,membershipCount:memberships.length}]};
}
const leads=(rows,primary=false)=>primary||rows.some(member=>valid(member)&&member.isLeader);

for(const [label,values] of [["A: true + true",[true,true]],["B: true + false",[true,false]],["C: false + true",[false,true]]]){
 test(`${label}: retirar limpia todos los vínculos y D: ya no autoriza`,()=>{
  const result=designate(values.map((value,index)=>row(String(index),value)),false);
  assert.deepEqual(result.rows.map(member=>member.isLeader),[false,false]);
  assert.equal(leads(result.rows),false);
 });
}
test("E: líder principal no puede retirarse aunque todas las filas sean false",()=>assert.throws(()=>designate([row("1",false),row("2",false)],false,{primary:true}),/MINISTRY_PRIMARY_LEADER_CHANGE_REQUIRED/));
test("F: true sin rol vuelve a crear el rol de sede",()=>{const result=designate([row("1",true)],true);assert.equal(result.role.managed,true);assert.equal(result.role.active,true)});
test("G: otorgar actualiza todos los vínculos vigentes",()=>assert.deepEqual(designate([row("1",false),row("2",false)],true).rows.map(member=>member.isLeader),[true,true]));
test("H e I: vínculos vencidos y futuros no cambian",()=>{const result=designate([row("actual",false),row("vencido",false,"2026-01-01","2026-08-31"),row("futuro",false,"2026-10-01")],true);assert.deepEqual(result.rows.map(member=>member.isLeader),[true,false,false])});
test("J: retirar uno de varios ministerios conserva el rol",()=>assert.equal(designate([row("1",true)],false,{otherLeadership:true,role:{scope:"SITE",siteId:"nemocon",managed:true,active:true}}).role.active,true));
test("K: retirar el último cierra solo el rol SITE gestionado",()=>assert.equal(designate([row("1",true)],false,{role:{scope:"SITE",siteId:"nemocon",managed:true,active:true}}).role.active,false));
test("L: rol preexistente y rol de organización permanecen",()=>{for(const role of[{scope:"SITE",siteId:"nemocon",managed:false,active:true},{scope:"ORGANIZATION",siteId:null,managed:true,active:true},{scope:"SITE",siteId:"central",managed:true,active:true}])assert.equal(designate([row("1",true)],false,{role}).role.active,true)});
test("M: una sola auditoría describe la designación lógica",()=>{const result=designate([row("1",true),row("2",false)],false);assert.equal(result.audit.length,1);assert.deepEqual(result.audit[0],{previous:true,next:false,membershipCount:2})});
test("N: la RPC conserva atomicidad y no captura un error de auditoría",()=>{assert.match(migration,/update public\.person_ministries pm set is_leader=given_is_leader[\s\S]*insert into public\.audit_logs/);assert.doesNotMatch(migration,/exception when others then/)});
test("SQL bloquea y actualiza todo el conjunto vigente, sin LIMIT 1 en membresías",()=>{assert.match(migration,/for member in[\s\S]*order by pm\.id for update[\s\S]*end loop/);assert.match(migration,/update public\.person_ministries pm set is_leader=given_is_leader[\s\S]*pm\.start_date<=current_date[\s\S]*pm\.end_date>=current_date/);assert.doesNotMatch(migration.slice(migration.indexOf("for member in"),migration.indexOf("end loop;")),/limit 1 for update/)});
test("SQL valida al principal antes de cambiar filas y repara el rol aunque ya sea líder",()=>{const principal=migration.indexOf("MINISTRY_PRIMARY_LEADER_CHANGE_REQUIRED"),role=migration.indexOf("if given_is_leader then"),update=migration.indexOf("update public.person_ministries pm set is_leader");assert.ok(principal>0&&principal<role&&role<update);assert.doesNotMatch(migration,/if member\.is_leader=given_is_leader then return/)});
test("diálogo sin carácter accidental",()=>assert.doesNotMatch(people,/^n\s+\{selectedPerson&&leadershipTarget/m));
