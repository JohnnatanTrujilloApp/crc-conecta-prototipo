import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";
import ts from "typescript";

const source=await readFile(new URL("../features/kids/kidsReport.ts",import.meta.url),"utf8");
const compiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
const {buildKidsReport,attendanceStatusLabel,kidsReportFileName,kidsParticipants,kidsHistoryParticipants,kidsSessionProgress}=await import(`data:text/javascript;base64,${Buffer.from(compiled).toString("base64")}`);
const kidsView=await readFile(new URL("../features/kids/KidsView.tsx",import.meta.url),"utf8");
const attendanceMigration=await readFile(new URL("../supabase/migrations/20260827020000_sprint_4_events_attendance_dashboard.sql",import.meta.url),"utf8");
const kidsMigration=await readFile(new URL("../supabase/migrations/20260917060000_kids_ministry_management.sql",import.meta.url),"utf8");

const child=(id,name,age,absentCount=0)=>({id,membershipId:id,name,birthDate:"2015-01-01",age,sex:null,groupName:"Semillas",guardianName:"María Pérez",guardianPhone:"3101234567",lastAttendance:"2026-09-20",status:"Activo",presentCount:2,absentCount});
const context={site:{id:"site-a",name:"CRC Nemocón Demo"},ministry:{id:"kids-a",name:"Kids"},canManage:true,children:[child("minor","Ana",11,3),child("leader","Líder de Kids",36)],sessions:[{id:"event-a",title:"Escuela Dominical",startAt:"2026-09-20T14:30:00Z",status:"PUBLISHED"}],attendance:[{eventId:"event-a",personId:"minor",status:"PRESENT"},{eventId:"event-a",personId:"leader",status:"LATE"}]};

test("Historial y Resumen Excel derivan los mismos totales de las sesiones visibles",()=>{
 const {summary}=buildKidsReport(context);
 assert.equal(summary.length,1);
 assert.deepEqual(summary[0],{name:"Ana",age:11,group:"Semillas",guardian:"María Pérez",guardianPhone:"3101234567",presentCount:1,absentCount:0,lastAttendance:"20/09/2026",followUp:"Al día"});
 assert.equal(kidsHistoryParticipants(context)[0].presentCount,summary[0].presentCount);
 const absentSessions=[1,2,3].map(day=>({id:`absent-${day}`,title:"Escuela Dominical",startAt:`2026-09-${day+20}T14:30:00Z`,status:"PUBLISHED"}));
 const absentContext={...context,sessions:absentSessions,attendance:absentSessions.map(session=>({eventId:session.id,personId:"minor",status:"ABSENT"}))};
 assert.equal(buildKidsReport(absentContext).summary[0].followUp,"Revisar inasistencias");
});

test("el detalle traduce estados y excluye registros de líderes adultos",()=>{
 const {detail}=buildKidsReport(context);
 assert.deepEqual(detail,[{date:"20/09/2026",time:"09:30 a. m.",session:"Escuela Dominical",child:"Ana",status:"Presente"}]);
 for(const [code,label] of [["PRESENT","Presente"],["ABSENT","Ausente"],["LATE","Tarde"],["EXCUSED","Excusado"]])assert.equal(attendanceStatusLabel(code),label);
});

test("sin menores autorizados no hay filas exportables",()=>{
 assert.deepEqual(buildKidsReport({...context,children:[]}),{summary:[],detail:[]});
 assert.deepEqual(buildKidsReport({...context,children:[child("leader","Líder de Kids",36)]}),{summary:[],detail:[]});
});

test("el nombre del archivo es seguro y usa fecha de Colombia",()=>{
 assert.equal(kidsReportFileName("CRC Nemocón Demo / Kids",new Date("2026-09-25T03:00:00Z")),"CRC_Kids_Historial_Asistencia_CRC_Nemocon_Demo_Kids_2026-09-24.xlsx");
 assert.equal(kidsReportFileName("///",new Date("2026-09-24T12:00:00Z")),"CRC_Kids_Historial_Asistencia_Sede_2026-09-24.xlsx");
});

test("asistencia muestra menores y excluye líderes adultos del listado y búsqueda",()=>{
 assert.deepEqual(kidsParticipants(context).map(person=>person.name),["Ana"]);
 assert.match(kidsView,/const participants=useMemo\(\(\)=>data\?kidsParticipants\(data\):\[\],\[data\]\)/);
 assert.match(kidsView,/const children=useMemo\(\(\)=>participants\.filter\(/);
 assert.match(kidsView,/kids-checkin-list">\{children\.map\(child=>/);
 assert.match(kidsView,/section==="children"[\s\S]*?<tbody>\{children\.map\(child=>/);
 assert.match(kidsView,/section==="home"[\s\S]*?<strong>\{participants\.length\}<\/strong>/);
 assert.doesNotMatch(kidsView,/data\??\.children/);
});

test("Todos presentes, contadores y guardado utilizan únicamente participantes menores",()=>{
 const participants=kidsParticipants(context);
 const marks=Object.fromEntries(participants.map(person=>[person.id,"PRESENT"]));
 assert.deepEqual(marks,{minor:"PRESENT"});
 assert.equal(participants.length,1);
 assert.match(kidsView,/setAttendanceDraft\(\{sessionId,overrides:Object\.fromEntries\(participants\.map\(/);
 assert.match(kidsView,/saveKidsAttendance\(sessionId,sessionProgress\.rowsToSave\)/);
 assert.match(kidsView,/\{present\} presentes · \{participants\.length\} registrados/);
 assert.match(kidsView,/const present=participants\.filter\(/);
 assert.match(kidsView,/const absences=participants\.filter\(/);
 assert.match(kidsView,/kidsSessionProgress\(data,sessionId/);
});

test("dos sesiones PRESENT cuentan como dos aunque una preceda la vinculación Kids",()=>{
 const earlier={id:"event-before-membership",title:"Escuela Dominical",startAt:"2026-09-18T14:00:00Z",status:"PUBLISHED"};
 const later={id:"event-after-membership",title:"Escuela Dominical",startAt:"2026-09-24T14:00:00Z",status:"PUBLISHED"};
 const twoPresent={...context,sessions:[earlier,later],attendance:[earlier,later].map(session=>({eventId:session.id,personId:"minor",status:"PRESENT"}))};
 assert.equal(kidsHistoryParticipants(twoPresent)[0].presentCount,2);
 const report=buildKidsReport(twoPresent);
 assert.equal(report.summary[0].presentCount,2);
 assert.equal(report.detail.length,2);
 assert.deepEqual(report.detail.map(row=>row.status),["Presente","Presente"]);
 assert.match(kidsMigration,/e\.start_at::date>=pm\.start_date/);
 assert.match(kidsView,/history\.map\(child=>/);
});

test("sesión nueva queda pendiente y habilita Guardar asistencia",()=>{
 const fresh={...context,attendance:[]};
 const progress=kidsSessionProgress(fresh,"event-a");
 assert.equal(progress.pendingCount,1);
 assert.equal(progress.isRegistered,false);
 assert.equal(progress.hasRecorded,false);
 assert.deepEqual(progress.rowsToSave,[{eventId:"event-a",personId:"minor",status:"ABSENT"}]);
 assert.match(kidsView,/:"Guardar asistencia"/);
});

test("sesión completa carga estados, muestra registro y deshabilita el botón",()=>{
 const progress=kidsSessionProgress(context,"event-a");
 assert.deepEqual(progress.persistedMarks,{minor:"PRESENT"});
 assert.equal(progress.marks.minor,"PRESENT");
 assert.equal(progress.pendingCount,0);
 assert.equal(progress.isRegistered,true);
 assert.deepEqual(progress.rowsToSave,[]);
 assert.match(kidsView,/✓ Asistencia registrada para esta sesión\./);
 assert.match(kidsView,/disabled=\{busy\|\|!sessionProgress\?\.rowsToSave\.length\}/);
});

test("cambiar una asistencia existente permite Actualizar y al persistir vuelve a registrado",()=>{
 const changed=kidsSessionProgress(context,"event-a",{minor:"ABSENT"});
 assert.equal(changed.hasChangedExisting,true);
 assert.equal(changed.isRegistered,false);
 assert.deepEqual(changed.rowsToSave,[{eventId:"event-a",personId:"minor",status:"ABSENT"}]);
 const persisted={...context,attendance:context.attendance.map(row=>row.personId==="minor"?{...row,status:"ABSENT"}:row)};
 assert.equal(kidsSessionProgress(persisted,"event-a").isRegistered,true);
 assert.match(kidsView,/"Actualizar asistencia"/);
 assert.match(kidsView,/Asistencia actualizada correctamente\./);
});

test("un menor nuevo en sesión ya registrada queda pendiente sin actualizar otros registros",()=>{
 const expanded={...context,children:[...context.children,child("new-minor","Luis",9)]};
 const progress=kidsSessionProgress(expanded,"event-a");
 assert.equal(progress.hasRecorded,true);
 assert.equal(progress.pendingCount,1);
 assert.equal(progress.isRegistered,false);
 assert.deepEqual(progress.rowsToSave,[{eventId:"event-a",personId:"new-minor",status:"ABSENT"}]);
 assert.match(kidsView,/asistencia pendiente/);
});

test("adultos y sesiones fuera del contexto no afectan totales ni registros",()=>{
 const extra={...context,attendance:[...context.attendance,{eventId:"unknown",personId:"minor",status:"PRESENT"}]};
 assert.equal(kidsHistoryParticipants(extra)[0].presentCount,1);
 assert.deepEqual(kidsSessionProgress(extra,"event-a").persistedMarks,{minor:"PRESENT"});
 assert.equal(buildKidsReport(extra).detail.length,1);
});

test("la persistencia conserva UNIQUE y upsert por evento y persona",()=>{
 assert.match(attendanceMigration,/unique \(event_id,person_id\)/);
 assert.match(kidsMigration,/on conflict\(event_id,person_id\) do update/);
 const duplicated={...context,attendance:[...context.attendance,context.attendance[0]]};
 assert.equal(kidsHistoryParticipants(duplicated)[0].presentCount,1);
 assert.equal(buildKidsReport(duplicated).detail.length,1);
});
