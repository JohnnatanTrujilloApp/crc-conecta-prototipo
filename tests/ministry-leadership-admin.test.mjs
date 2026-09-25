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
 ["retirar no borra membresía",/update public\.person_ministries set is_leader=given_is_leader/],
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
