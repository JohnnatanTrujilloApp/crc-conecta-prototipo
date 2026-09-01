import {getSupabaseBrowserClient} from "@/lib/supabase/client";

export type Site={id:string;organizationId:string;name:string};
export type PersonOption={id:string;siteId:string;name:string;crcCode:string};
export type Program={id:string;organizationId:string;title:string;lessonCount:number;lessons:Lesson[]};
export type Lesson={id:string;programId:string;title:string;sortOrder:number};
export type Group={id:string;organizationId:string;siteId:string;name:string;programId:string;program:string;teacherId:string;teacher:string;assistantId:string|null;assistant:string;startDate:string;endDate:string|null;status:string};
export type Enrollment={id:string;groupId:string;personId:string;name:string;crcCode:string;status:string;progress:number;completed:number;total:number};
export type Session={id:string;groupId:string;lessonId:string;lesson:string;teacherId:string;teacher:string;date:string;time:string;status:string;presentIds:string[]};

const one=<T>(value:T|T[]|null|undefined)=>Array.isArray(value)?value[0]:value;
export async function loadDiscipleshipData(siteId?:string){
 const client=getSupabaseBrowserClient();const sitesResult=await client.from("sites").select("id,organization_id,name").eq("active",true).order("name");if(sitesResult.error)throw sitesResult.error;
 const sites:Site[]=(sitesResult.data??[]).map(row=>({id:row.id,organizationId:row.organization_id,name:row.name}));const selected=siteId&&sites.some(item=>item.id===siteId)?siteId:sites[0]?.id;if(!selected)return{sites,people:[],programs:[],groups:[],enrollments:[],sessions:[]};
 const [peopleResult,programsResult,modulesResult,lessonsResult,groupsResult]=await Promise.all([
  client.from("people").select("id,site_id,first_name,last_name,crc_code").eq("site_id",selected).is("archived_at",null).order("first_name"),
  client.from("training_programs").select("id,organization_id,title").eq("program_type","DISCIPLESHIP").eq("active",true).order("title"),
  client.from("training_modules").select("id,program_id").eq("active",true),
  client.from("lessons").select("id,module_id,title,sort_order").eq("active",true).order("sort_order"),
  client.from("training_groups").select("id,organization_id,site_id,program_id,name,teacher_person_id,assistant_person_id,start_date,end_date,status").eq("site_id",selected).neq("status","CANCELLED").order("start_date",{ascending:false}),
 ]);for(const result of [peopleResult,programsResult,modulesResult,lessonsResult,groupsResult])if(result.error)throw result.error;
 const moduleProgram=new Map((modulesResult.data??[]).map(row=>[row.id,row.program_id]));const lessons:Lesson[]=(lessonsResult.data??[]).map(row=>({id:row.id,programId:moduleProgram.get(row.module_id)??"",title:row.title,sortOrder:row.sort_order}));
 const programs:Program[]=(programsResult.data??[]).map(row=>{const own=lessons.filter(item=>item.programId===row.id);return{id:row.id,organizationId:row.organization_id,title:row.title,lessonCount:own.length,lessons:own}});
 const people:PersonOption[]=(peopleResult.data??[]).map(row=>({id:row.id,siteId:row.site_id,name:`${row.first_name} ${row.last_name}`,crcCode:row.crc_code}));
 const personName=(id:string|null)=>people.find(item=>item.id===id)?.name??"Sin asignar";
 const groups:Group[]=(groupsResult.data??[]).map(row=>({id:row.id,organizationId:row.organization_id,siteId:row.site_id,name:row.name,programId:row.program_id,program:programs.find(item=>item.id===row.program_id)?.title??"Programa",teacherId:row.teacher_person_id,teacher:personName(row.teacher_person_id),assistantId:row.assistant_person_id,assistant:personName(row.assistant_person_id),startDate:row.start_date,endDate:row.end_date,status:row.status}));
 if(!groups.length)return{sites,people,programs,groups,enrollments:[],sessions:[]};
 const ids=groups.map(group=>group.id);const [enrollmentResult,sessionResult]=await Promise.all([
  client.from("enrollments").select("id,group_id,person_id,status,people(first_name,last_name,crc_code)").in("group_id",ids),
  client.from("class_sessions").select("id,group_id,lesson_id,teacher_person_id,session_date,start_time,status").in("group_id",ids).order("session_date",{ascending:false}),
 ]);if(enrollmentResult.error)throw enrollmentResult.error;if(sessionResult.error)throw sessionResult.error;
 const sessionIds=(sessionResult.data??[]).map(row=>row.id);let attendanceRows:{session_id:string;person_id:string;attendance_status:string}[]=[];if(sessionIds.length){const result=await client.from("class_attendance").select("session_id,person_id,attendance_status").in("session_id",sessionIds);if(result.error)throw result.error;attendanceRows=result.data??[]}
 const sessions:Session[]=(sessionResult.data??[]).map(row=>({id:row.id,groupId:row.group_id,lessonId:row.lesson_id,lesson:lessons.find(item=>item.id===row.lesson_id)?.title??"Lección",teacherId:row.teacher_person_id,teacher:personName(row.teacher_person_id),date:row.session_date,time:row.start_time,status:row.status,presentIds:attendanceRows.filter(item=>item.session_id===row.id&&(item.attendance_status==="PRESENT"||item.attendance_status==="LATE")).map(item=>item.person_id)}));
 const enrollments:Enrollment[]=(enrollmentResult.data??[]).map(row=>{const person=one(row.people as {first_name:string;last_name:string;crc_code:string}|{first_name:string;last_name:string;crc_code:string}[]|null);const group=groups.find(item=>item.id===row.group_id);const total=programs.find(item=>item.id===group?.programId)?.lessonCount??0;const completed=new Set(sessions.filter(item=>item.groupId===row.group_id&&item.status==="COMPLETED"&&item.presentIds.includes(row.person_id)).map(item=>item.lessonId)).size;return{id:row.id,groupId:row.group_id,personId:row.person_id,name:person?`${person.first_name} ${person.last_name}`:"Persona",crcCode:person?.crc_code??"",status:row.status,completed,total,progress:total?Math.round(completed/total*100):0}});
 return{sites,people,programs,groups,enrollments,sessions};
}

export async function createGroup(site:Site,draft:{name:string;programId:string;teacherId:string;assistantId:string;startDate:string;endDate:string}){const {data,error}=await getSupabaseBrowserClient().from("training_groups").insert({organization_id:site.organizationId,site_id:site.id,program_id:draft.programId,name:draft.name.trim(),teacher_person_id:draft.teacherId,assistant_person_id:draft.assistantId||null,start_date:draft.startDate,end_date:draft.endDate||null,status:"ACTIVE"}).select("id").single();if(error)throw error;return data.id as string}
export async function enrollPerson(group:Group,personId:string){const {error}=await getSupabaseBrowserClient().from("enrollments").insert({organization_id:group.organizationId,site_id:group.siteId,program_id:group.programId,group_id:group.id,person_id:personId,status:"ACTIVE"});if(error)throw error}
export async function createExternalStudent(site:Site,draft:{firstName:string;lastName:string;phone:string;email:string}){const {data,error}=await getSupabaseBrowserClient().from("people").insert({organization_id:site.organizationId,site_id:site.id,first_name:draft.firstName.trim(),last_name:draft.lastName.trim(),phone:draft.phone.trim(),email:draft.email.trim()||null,person_status:"VISITOR",first_visit_date:null}).select("id").single();if(error)throw error;return data.id as string}
export async function createClassSession(group:Group,draft:{lessonId:string;teacherId:string;date:string;time:string}){const {data,error}=await getSupabaseBrowserClient().from("class_sessions").insert({organization_id:group.organizationId,site_id:group.siteId,group_id:group.id,lesson_id:draft.lessonId,teacher_person_id:draft.teacherId,session_date:draft.date,start_time:draft.time,status:"SCHEDULED"}).select("id").single();if(error)throw error;return data.id as string}
export async function completeSession(group:Group,session:Session,presentIds:string[]){const client=getSupabaseBrowserClient();const rows=presentIds.map(personId=>({organization_id:group.organizationId,site_id:group.siteId,session_id:session.id,person_id:personId,attendance_status:"PRESENT"}));if(rows.length){const {error}=await client.from("class_attendance").upsert(rows,{onConflict:"session_id,person_id"});if(error)throw error}const {error}=await client.from("class_sessions").update({status:"COMPLETED"}).eq("id",session.id);if(error)throw error}
