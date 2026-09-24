import type {KidsAttendance,KidsChild,KidsContext,KidsSession} from "./repository";

const attendanceLabels={PRESENT:"Presente",ABSENT:"Ausente",LATE:"Tarde",EXCUSED:"Excusado"} as const;
const dateFormatter=new Intl.DateTimeFormat("es-CO",{timeZone:"America/Bogota",day:"2-digit",month:"2-digit",year:"numeric"});
const timeFormatter=new Intl.DateTimeFormat("es-CO",{timeZone:"America/Bogota",hour:"2-digit",minute:"2-digit",hour12:true});

export const isKidsParticipant=(child:KidsChild)=>Number.isInteger(child.age)&&child.age>=0&&child.age<18;
export const kidsParticipants=(context:KidsContext)=>context.children.filter(isKidsParticipant);
export const attendanceStatusLabel=(status:KidsContext["attendance"][number]["status"])=>attendanceLabels[status];

function kidsAttendanceRecords(context:KidsContext){
 const participants=new Map(kidsParticipants(context).map(child=>[child.id,child]));
 const sessions=new Map(context.sessions.map(session=>[session.id,session]));
 const records=new Map<string,{child:KidsChild;session:KidsSession;status:KidsAttendance["status"]}>();
 for(const row of context.attendance){const child=participants.get(row.personId),session=sessions.get(row.eventId);if(child&&session)records.set(`${row.eventId}:${row.personId}`,{child,session,status:row.status})}
 return [...records.values()];
}

export function kidsHistoryParticipants(context:KidsContext){
 const totals=new Map(kidsParticipants(context).map(child=>[child.id,{presentCount:0,absentCount:0,lastAttendance:null as string|null,lastTime:-Infinity}]));
 const colombiaDate=new Intl.DateTimeFormat("en-CA",{timeZone:"America/Bogota",year:"numeric",month:"2-digit",day:"2-digit"});
 for(const record of kidsAttendanceRecords(context)){
  const total=totals.get(record.child.id);if(!total)continue;
  if(record.status==="PRESENT"||record.status==="LATE"){
   total.presentCount++;
   const start=new Date(record.session.startAt);if(!Number.isNaN(start.getTime())&&start.getTime()>total.lastTime){total.lastTime=start.getTime();total.lastAttendance=colombiaDate.format(start)}
  }else if(record.status==="ABSENT"||record.status==="EXCUSED")total.absentCount++;
 }
 return kidsParticipants(context).map(child=>{const total=totals.get(child.id);return {...child,presentCount:total?.presentCount??0,absentCount:total?.absentCount??0,lastAttendance:total?.lastAttendance??null}});
}

export function kidsSessionProgress(context:KidsContext,eventId:string,overrides:Record<string,KidsAttendance["status"]>={}){
 const participants=kidsParticipants(context);
 const participantIds=new Set(participants.map(child=>child.id));
 const persistedMarks:Record<string,KidsAttendance["status"]>={};
 for(const row of context.attendance)if(row.eventId===eventId&&participantIds.has(row.personId))persistedMarks[row.personId]=row.status;
 const marks={...persistedMarks,...overrides};
 const pendingCount=participants.filter(child=>!Object.hasOwn(persistedMarks,child.id)).length;
 const hasChangedExisting=participants.some(child=>Object.hasOwn(persistedMarks,child.id)&&marks[child.id]!==persistedMarks[child.id]);
 const rowsToSave=participants.filter(child=>!Object.hasOwn(persistedMarks,child.id)||marks[child.id]!==persistedMarks[child.id]).map(child=>({eventId,personId:child.id,status:marks[child.id]??"ABSENT"}));
 return {marks,persistedMarks,pendingCount,rowsToSave,hasChangedExisting,hasRecorded:Object.keys(persistedMarks).length>0,isRegistered:participants.length>0&&pendingCount===0&&rowsToSave.length===0};
}

export function buildKidsReport(context:KidsContext){
 const participants=kidsHistoryParticipants(context);
 const summary=participants.map(child=>({name:child.name,age:child.age,group:child.groupName,guardian:child.guardianName??"",guardianPhone:child.guardianPhone??"",presentCount:child.presentCount,absentCount:child.absentCount,lastAttendance:child.lastAttendance?dateFormatter.format(new Date(`${child.lastAttendance.slice(0,10)}T12:00:00Z`)):"Sin registro",followUp:child.absentCount>=3?"Revisar inasistencias":"Al día"}));
 const detail=kidsAttendanceRecords(context).flatMap(record=>{const start=new Date(record.session.startAt);if(Number.isNaN(start.getTime()))return [];return [{date:dateFormatter.format(start),time:timeFormatter.format(start).replace(/\u00a0/g," "),session:record.session.title,child:record.child.name,status:attendanceStatusLabel(record.status),sortTime:start.getTime()}]}).sort((a,b)=>b.sortTime-a.sortTime).map(row=>({date:row.date,time:row.time,session:row.session,child:row.child,status:row.status}));
 return {summary,detail};
}

export function kidsReportFileName(siteName:string,date=new Date()){
 const safeSite=siteName.normalize("NFD").replace(/[\u0300-\u036f]/g,"").replace(/[^A-Za-z0-9]+/g,"_").replace(/^_+|_+$/g,"").slice(0,60)||"Sede";
 const day=new Intl.DateTimeFormat("en-CA",{timeZone:"America/Bogota",year:"numeric",month:"2-digit",day:"2-digit"}).format(date);
 return `CRC_Kids_Historial_Asistencia_${safeSite}_${day}.xlsx`;
}
