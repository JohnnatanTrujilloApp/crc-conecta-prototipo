import type {KidsChild,KidsContext} from "./repository";

const attendanceLabels={PRESENT:"Presente",ABSENT:"Ausente",LATE:"Tarde",EXCUSED:"Excusado"} as const;
const dateFormatter=new Intl.DateTimeFormat("es-CO",{timeZone:"America/Bogota",day:"2-digit",month:"2-digit",year:"numeric"});
const timeFormatter=new Intl.DateTimeFormat("es-CO",{timeZone:"America/Bogota",hour:"2-digit",minute:"2-digit",hour12:true});

export const isKidsParticipant=(child:KidsChild)=>Number.isInteger(child.age)&&child.age>=0&&child.age<18;
export const kidsParticipants=(context:KidsContext)=>context.children.filter(isKidsParticipant);
export const attendanceStatusLabel=(status:KidsContext["attendance"][number]["status"])=>attendanceLabels[status];

export function buildKidsReport(context:KidsContext){
 const participants=kidsParticipants(context);
 const names=new Map(participants.map(child=>[child.id,child.name]));
 const sessions=new Map(context.sessions.map(session=>[session.id,session]));
 const summary=participants.map(child=>({name:child.name,age:child.age,group:child.groupName,guardian:child.guardianName??"",guardianPhone:child.guardianPhone??"",presentCount:child.presentCount,absentCount:child.absentCount,lastAttendance:child.lastAttendance?dateFormatter.format(new Date(`${child.lastAttendance.slice(0,10)}T12:00:00Z`)):"Sin registro",followUp:child.absentCount>=3?"Revisar inasistencias":"Al día"}));
 const detail=context.attendance.flatMap(record=>{const personName=names.get(record.personId),session=sessions.get(record.eventId);if(!personName||!session)return [];const start=new Date(session.startAt);if(Number.isNaN(start.getTime()))return [];return [{date:dateFormatter.format(start),time:timeFormatter.format(start).replace(/\u00a0/g," "),session:session.title,child:personName,status:attendanceStatusLabel(record.status),sortTime:start.getTime()}]}).sort((a,b)=>b.sortTime-a.sortTime).map(row=>({date:row.date,time:row.time,session:row.session,child:row.child,status:row.status}));
 return {summary,detail};
}

export function kidsReportFileName(siteName:string,date=new Date()){
 const safeSite=siteName.normalize("NFD").replace(/[\u0300-\u036f]/g,"").replace(/[^A-Za-z0-9]+/g,"_").replace(/^_+|_+$/g,"").slice(0,60)||"Sede";
 const day=new Intl.DateTimeFormat("en-CA",{timeZone:"America/Bogota",year:"numeric",month:"2-digit",day:"2-digit"}).format(date);
 return `CRC_Kids_Historial_Asistencia_${safeSite}_${day}.xlsx`;
}
