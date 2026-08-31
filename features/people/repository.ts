import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import type { Person,PersonDraft,PersonProfileDetails } from "./types";

export type SiteOption={id:string;name:string;organizationId:string};
type PersonRow={id:string;crc_code?:string;first_name:string;last_name:string;preferred_name:string|null;email:string|null;phone:string;site_id:string;person_status:Person["status"];first_visit_date:string|null;baptized?:boolean;sites:{name:string}|{name:string}[]|null};
const siteName=(value:PersonRow["sites"])=>Array.isArray(value)?value[0]?.name:value?.name;
const mapPerson=(row:PersonRow,site?:SiteOption):Person=>({id:row.id,crcCode:row.crc_code,firstName:row.first_name,lastName:row.last_name,preferredName:row.preferred_name??undefined,email:row.email??undefined,phone:row.phone,siteId:row.site_id,siteName:site?.name??siteName(row.sites)??"Sede autorizada",status:row.person_status,firstVisitDate:row.first_visit_date??new Date().toISOString().slice(0,10),baptized:row.baptized??false});

export async function loadPeopleData(){
 const client=getSupabaseBrowserClient();
 const [sitesResult,peopleResult]=await Promise.all([
  client.from("sites").select("id,name,organization_id").eq("active",true).order("name"),
  client.from("people").select("id,crc_code,first_name,last_name,preferred_name,email,phone,site_id,person_status,first_visit_date,baptized,sites(name)").is("archived_at",null).order("created_at",{ascending:false}),
 ]);
 if(sitesResult.error)throw sitesResult.error;if(peopleResult.error)throw peopleResult.error;
 return {sites:(sitesResult.data??[]).map(row=>({id:row.id,name:row.name,organizationId:row.organization_id})) as SiteOption[],people:((peopleResult.data??[]) as unknown as PersonRow[]).map(row=>mapPerson(row))};
}

export async function createPerson(draft:PersonDraft,site:SiteOption):Promise<Person>{
 const {data,error}=await getSupabaseBrowserClient().from("people").insert({organization_id:site.organizationId,site_id:site.id,first_name:draft.firstName.trim(),last_name:draft.lastName.trim(),email:draft.email?.trim()||null,phone:draft.phone.trim(),person_status:draft.status,first_visit_date:new Date().toISOString().slice(0,10)}).select("id,crc_code,first_name,last_name,preferred_name,email,phone,site_id,person_status,first_visit_date,baptized").single();
 if(error)throw error;return mapPerson(data as PersonRow,site);
}
export async function updatePerson(id:string,draft:PersonDraft,site:SiteOption):Promise<Person>{
 const {data,error}=await getSupabaseBrowserClient().from("people").update({organization_id:site.organizationId,site_id:site.id,first_name:draft.firstName.trim(),last_name:draft.lastName.trim(),email:draft.email?.trim()||null,phone:draft.phone.trim(),person_status:draft.status}).eq("id",id).select("id,crc_code,first_name,last_name,preferred_name,email,phone,site_id,person_status,first_visit_date,baptized").single();
 if(error)throw error;return mapPerson(data as PersonRow,site);
}
export async function archivePerson(id:string){const {error}=await getSupabaseBrowserClient().from("people").update({archived_at:new Date().toISOString()}).eq("id",id);if(error)throw error;}

const relatedName=(value:unknown,key:string)=>{const record=Array.isArray(value)?value[0]:value;return record&&typeof record==="object"&&key in record?String((record as Record<string,unknown>)[key]):""};

export async function loadPersonProfile(personId:string):Promise<PersonProfileDetails>{
 const client=getSupabaseBrowserClient();
 const [familyResult,enrollmentsResult,ministriesResult]=await Promise.all([
  client.from("family_members").select("family_id,families(id,name)").eq("person_id",personId).limit(1).maybeSingle(),
  client.from("enrollments").select("id,progress_percentage,status,training_programs(title),training_groups(name)").eq("person_id",personId).order("created_at",{ascending:false}),
  client.from("person_ministries").select("id,position,ministries(name)").eq("person_id",personId).eq("active",true).order("created_at",{ascending:false}),
 ]);
 if(familyResult.error)throw familyResult.error;if(enrollmentsResult.error)throw enrollmentsResult.error;if(ministriesResult.error)throw ministriesResult.error;
 let family:PersonProfileDetails["family"];
 if(familyResult.data?.family_id){const {count,error}=await client.from("family_members").select("id",{count:"exact",head:true}).eq("family_id",familyResult.data.family_id);if(error)throw error;family={id:familyResult.data.family_id,name:relatedName(familyResult.data.families,"name")||"Familia sin nombre",memberCount:count??0};}
 return {family,enrollments:(enrollmentsResult.data??[]).map(row=>({id:row.id,program:relatedName(row.training_programs,"title")||"Programa",group:relatedName(row.training_groups,"name")||"Grupo",progress:Number(row.progress_percentage),status:row.status})),ministries:(ministriesResult.data??[]).map(row=>({id:row.id,name:relatedName(row.ministries,"name")||"Ministerio",position:row.position}))};
}
