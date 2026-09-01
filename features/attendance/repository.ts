import { getSupabaseBrowserClient } from "@/lib/supabase/client";

export type AttendanceSite={id:string;organizationId:string;name:string};
export type AttendancePerson={id:string;siteId:string;name:string;crcCode:string;status:string;birthDate:string|null};
export type AttendanceEvent={id:string;organizationId:string;siteId:string;title:string;type:string;startAt:string;endAt:string|null;location:string|null;status:string};
export type AttendanceEntry={id:string;eventId:string;personId:string;status:"PRESENT"|"ABSENT"|"EXCUSED"|"LATE";method:string;checkInAt:string|null};
export type EventDraft={title:string;type:string;startAt:string;endAt:string;location:string;status:string};

export async function loadAttendanceData(siteId?:string){
 const client=getSupabaseBrowserClient();
 const sitesResult=await client.from("sites").select("id,organization_id,name").eq("active",true).order("name");
 if(sitesResult.error)throw sitesResult.error;
 const sites:AttendanceSite[]=(sitesResult.data??[]).map(row=>({id:row.id,organizationId:row.organization_id,name:row.name}));
 const selectedSiteId=siteId&&sites.some(site=>site.id===siteId)?siteId:sites[0]?.id;
 if(!selectedSiteId)return{sites,people:[],events:[],entries:[]};
 const [peopleResult,eventsResult]=await Promise.all([
  client.from("people").select("id,site_id,first_name,last_name,crc_code,person_status,birth_date").eq("site_id",selectedSiteId).is("archived_at",null).order("first_name"),
  client.from("events").select("id,organization_id,site_id,title,event_type,start_at,end_at,location,status").eq("site_id",selectedSiteId).neq("status","CANCELLED").order("start_at",{ascending:false}),
 ]);
 if(peopleResult.error)throw peopleResult.error;if(eventsResult.error)throw eventsResult.error;
 const events:AttendanceEvent[]=(eventsResult.data??[]).map(row=>({id:row.id,organizationId:row.organization_id,siteId:row.site_id,title:row.title,type:row.event_type,startAt:row.start_at,endAt:row.end_at,location:row.location,status:row.status}));
 let entries:AttendanceEntry[]=[];
 if(events.length){const result=await client.from("attendance").select("id,event_id,person_id,status,check_in_method,check_in_at").eq("site_id",selectedSiteId).in("event_id",events.map(event=>event.id));if(result.error)throw result.error;entries=(result.data??[]).map(row=>({id:row.id,eventId:row.event_id,personId:row.person_id,status:row.status,method:row.check_in_method,checkInAt:row.check_in_at}))}
 const people:AttendancePerson[]=(peopleResult.data??[]).map(row=>({id:row.id,siteId:row.site_id,name:`${row.first_name} ${row.last_name}`.trim(),crcCode:row.crc_code,status:row.person_status,birthDate:row.birth_date}));
 return{sites,people,events,entries};
}

export async function createAttendanceEvent(site:AttendanceSite,draft:EventDraft){
 const payload={organization_id:site.organizationId,site_id:site.id,title:draft.title.trim(),event_type:draft.type,start_at:new Date(draft.startAt).toISOString(),end_at:draft.endAt?new Date(draft.endAt).toISOString():null,location:draft.location.trim()||null,status:draft.status};
 const {data,error}=await getSupabaseBrowserClient().from("events").insert(payload).select("id,organization_id,site_id,title,event_type,start_at,end_at,location,status").single();if(error)throw error;
 return{id:data.id,organizationId:data.organization_id,siteId:data.site_id,title:data.title,type:data.event_type,startAt:data.start_at,endAt:data.end_at,location:data.location,status:data.status} as AttendanceEvent;
}

export async function setPersonAttendance(event:AttendanceEvent,personId:string,current:AttendanceEntry|undefined,present:boolean){
 const client=getSupabaseBrowserClient();const status=present?"PRESENT":"ABSENT";
 if(current){const {data,error}=await client.from("attendance").update({status,check_in_method:"MANUAL",check_in_at:present?new Date().toISOString():null}).eq("id",current.id).select("id,event_id,person_id,status,check_in_method,check_in_at").single();if(error)throw error;return{id:data.id,eventId:data.event_id,personId:data.person_id,status:data.status,method:data.check_in_method,checkInAt:data.check_in_at} as AttendanceEntry}
 const {data,error}=await client.from("attendance").insert({organization_id:event.organizationId,site_id:event.siteId,event_id:event.id,person_id:personId,status,check_in_method:"MANUAL",check_in_at:present?new Date().toISOString():null}).select("id,event_id,person_id,status,check_in_method,check_in_at").single();if(error)throw error;return{id:data.id,eventId:data.event_id,personId:data.person_id,status:data.status,method:data.check_in_method,checkInAt:data.check_in_at} as AttendanceEntry;
}
