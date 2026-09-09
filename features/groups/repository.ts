import {getSupabaseBrowserClient} from "@/lib/supabase/client";

export type Site={id:string;organizationId:string;name:string};
export type PersonOption={id:string;siteId:string;name:string;crcCode:string;phone:string;documentNumber:string};
export type DiscipleshipCandidate={id:string;name:string;crcCode:string;siteId:string;siteName:string;phoneMasked:string|null;documentMasked:string|null};
export type Program={id:string;organizationId:string;title:string;lessonCount:number;lessons:Lesson[]};
export type Lesson={id:string;programId:string;title:string;sortOrder:number};
export type Group={id:string;organizationId:string;siteId:string;name:string;programId:string;program:string;teacherId:string;teacher:string;assistantId:string|null;assistant:string;startDate:string;endDate:string|null;status:string};
export type Enrollment={id:string;groupId:string;personId:string;name:string;crcCode:string;status:string;progress:number;completed:number;total:number};
export type Session={id:string;groupId:string;lessonId:string;lesson:string;teacherId:string;teacher:string;date:string;time:string;status:string;presentIds:string[]};
export type LessonAvailability={lessonId:string;title:string;sortOrder:number;pendingCount:number;completedCount:number;eligiblePersonIds:string[]};

const one=<T>(value:T|T[]|null|undefined)=>Array.isArray(value)?value[0]:value;
export async function loadDiscipleshipData(siteId?:string){
 const client=getSupabaseBrowserClient();const siteResult=await client.rpc("get_my_discipleship_site",{preferred_site_id:siteId||null});if(siteResult.error)throw siteResult.error;
 const authorizedSite=siteResult.data as Site|null;const sites:Site[]=authorizedSite?[authorizedSite]:[];const selected=authorizedSite?.id;if(!selected)return{sites,people:[],programs:[],groups:[],enrollments:[],sessions:[]};
 const [peopleResult,programsResult,groupsResult]=await Promise.all([
  client.rpc("list_authorized_people"),
  client.rpc("get_my_discipleship_programs",{target_site_id:selected}),
  client.from("training_groups").select("id,organization_id,site_id,program_id,name,teacher_person_id,assistant_person_id,start_date,end_date,status").eq("site_id",selected).neq("status","CANCELLED").order("start_date",{ascending:false}),
 ]);for(const result of [peopleResult,programsResult,groupsResult])if(result.error)throw result.error;
 const programs=(programsResult.data??[]) as Program[];const lessons=programs.flatMap(program=>program.lessons);
 const peopleRows=(peopleResult.data??[]) as {id:string;site_id:string;first_name:string;last_name:string;crc_code:string;phone:string|null;document_number:string|null}[];
 const people:PersonOption[]=peopleRows.filter(row=>row.site_id===selected).map(row=>({id:row.id,siteId:row.site_id,name:`${row.first_name} ${row.last_name}`,crcCode:row.crc_code,phone:row.phone??"",documentNumber:row.document_number??""}));
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
export async function searchDiscipleshipCandidates(groupId:string,term:string){const{data,error}=await getSupabaseBrowserClient().rpc("search_discipleship_candidates",{target_group_id:groupId,search_term:term,result_limit:20});if(error)throw error;return(data??[])as DiscipleshipCandidate[]}
export async function registerExternalStudent(group:Group,draft:{firstName:string;lastName:string;phone:string;email:string;documentType:string;documentNumber:string}){const{data,error}=await getSupabaseBrowserClient().rpc("register_external_discipleship_student",{target_group_id:group.id,given_first_name:draft.firstName,given_last_name:draft.lastName,given_phone:draft.phone,given_email:draft.email||null,given_document_type:draft.documentType||null,given_document_number:draft.documentNumber||null});if(error)throw error;return data as{personId:string;created:boolean;crossSite:boolean;personSiteId:string;name:string}}
export async function loadLessonAvailability(groupId:string){const{data,error}=await getSupabaseBrowserClient().rpc("get_discipleship_lesson_availability",{target_group_id:groupId});if(error)throw error;return(data??[])as LessonAvailability[]}
export async function createClassSession(group:Group,draft:{lessonId:string;teacherId:string;date:string;time:string}){const {data,error}=await getSupabaseBrowserClient().rpc("schedule_discipleship_session",{target_group_id:group.id,given_lesson_id:draft.lessonId,given_teacher_person_id:draft.teacherId,given_date:draft.date,given_time:draft.time});if(error)throw error;return data as string}
export async function reassignGroupTeacher(groupId:string,teacherId:string,reason:string){const{error}=await getSupabaseBrowserClient().rpc("reassign_discipleship_teacher",{target_group_id:groupId,new_teacher_person_id:teacherId,given_reason:reason||null});if(error)throw error}
export async function completeSession(group:Group,session:Session,presentIds:string[]){const client=getSupabaseBrowserClient();const rows=presentIds.map(personId=>({organization_id:group.organizationId,site_id:group.siteId,session_id:session.id,person_id:personId,attendance_status:"PRESENT"}));if(rows.length){const {error}=await client.from("class_attendance").upsert(rows,{onConflict:"session_id,person_id"});if(error)throw error}const {error}=await client.from("class_sessions").update({status:"COMPLETED"}).eq("id",session.id);if(error)throw error}
