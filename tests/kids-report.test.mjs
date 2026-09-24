import assert from "node:assert/strict";
import {readFile} from "node:fs/promises";
import test from "node:test";
import ts from "typescript";

const source=await readFile(new URL("../features/kids/kidsReport.ts",import.meta.url),"utf8");
const compiled=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ESNext,target:ts.ScriptTarget.ES2022}}).outputText;
const {buildKidsReport,attendanceStatusLabel,kidsReportFileName,kidsParticipants}=await import(`data:text/javascript;base64,${Buffer.from(compiled).toString("base64")}`);
const kidsView=await readFile(new URL("../features/kids/KidsView.tsx",import.meta.url),"utf8");

const child=(id,name,age,absentCount=0)=>({id,membershipId:id,name,birthDate:"2015-01-01",age,sex:null,groupName:"Semillas",guardianName:"María Pérez",guardianPhone:"3101234567",lastAttendance:"2026-09-20",status:"Activo",presentCount:2,absentCount});
const context={site:{id:"site-a",name:"CRC Nemocón Demo"},ministry:{id:"kids-a",name:"Kids"},canManage:true,children:[child("minor","Ana",11,3),child("leader","Líder de Kids",36)],sessions:[{id:"event-a",title:"Escuela Dominical",startAt:"2026-09-20T14:30:00Z",status:"PUBLISHED"}],attendance:[{eventId:"event-a",personId:"minor",status:"PRESENT"},{eventId:"event-a",personId:"leader",status:"LATE"}]};

test("el resumen contiene únicamente menores y mantiene la regla de seguimiento",()=>{
 const {summary}=buildKidsReport(context);
 assert.equal(summary.length,1);
 assert.deepEqual(summary[0],{name:"Ana",age:11,group:"Semillas",guardian:"María Pérez",guardianPhone:"3101234567",presentCount:2,absentCount:3,lastAttendance:"20/09/2026",followUp:"Revisar inasistencias"});
 assert.equal(buildKidsReport({...context,children:[child("minor","Ana",11,2)]}).summary[0].followUp,"Al día");
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
 const rows=participants.map(person=>({eventId:"event-a",personId:person.id,status:marks[person.id]??"ABSENT"}));
 assert.deepEqual(marks,{minor:"PRESENT"});
 assert.deepEqual(rows,[{eventId:"event-a",personId:"minor",status:"PRESENT"}]);
 assert.equal(participants.length,1);
 assert.match(kidsView,/setMarks\(Object\.fromEntries\(participants\.map\(/);
 assert.match(kidsView,/const rows:KidsAttendance\[\]=participants\.map\(/);
 assert.match(kidsView,/\{present\} presentes · \{participants\.length\} registrados/);
 assert.match(kidsView,/const present=participants\.filter\(/);
 assert.match(kidsView,/const absences=participants\.filter\(/);
 assert.match(kidsView,/participantIds\.has\(x\.personId\)/);
});
