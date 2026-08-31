import { getSupabaseBrowserClient } from "@/lib/supabase/client";

export const familyRelationships = ["FATHER","MOTHER","HUSBAND","WIFE","SON","DAUGHTER","GUARDIAN","CAREGIVER","OTHER"] as const;
export type FamilyRelationship=(typeof familyRelationships)[number];
export type FamilyMember={id:string;personId:string;name:string;crcCode:string;relationship:FamilyRelationship;primary:boolean};
export type Family={id:string;organizationId:string;siteId:string;siteName:string;name:string;address:string;notes:string;members:FamilyMember[]};
export type FamilyDraft={name:string;address:string;notes:string;siteId:string};
export type FamilyPersonOption={id:string;siteId:string;name:string;crcCode:string};
export type FamilySiteOption={id:string;organizationId:string;name:string};

type FamilyRow={id:string;organization_id:string;site_id:string;name:string;address:string|null;notes:string|null;sites:{name:string}|{name:string}[]|null};
type MemberRow={id:string;family_id:string;person_id:string;relationship:FamilyRelationship;is_primary_contact:boolean};
type PersonRow={id:string;site_id:string;first_name:string;last_name:string;crc_code:string};
const relatedName=(value:FamilyRow["sites"])=>Array.isArray(value)?value[0]?.name:value?.name;

export async function loadFamiliesData(){
 const client=getSupabaseBrowserClient();
 const [familiesResult,membersResult,peopleResult,sitesResult]=await Promise.all([
  client.from("families").select("id,organization_id,site_id,name,address,notes,sites(name)").eq("active",true).order("name"),
  client.from("family_members").select("id,family_id,person_id,relationship,is_primary_contact"),
  client.from("people").select("id,site_id,first_name,last_name,crc_code").is("archived_at",null).order("first_name"),
  client.from("sites").select("id,organization_id,name").eq("active",true).order("name"),
 ]);
 if(familiesResult.error)throw familiesResult.error;if(membersResult.error)throw membersResult.error;if(peopleResult.error)throw peopleResult.error;if(sitesResult.error)throw sitesResult.error;
 const peopleRows=(peopleResult.data??[]) as PersonRow[];const peopleById=new Map(peopleRows.map(row=>[row.id,row]));
 const membersByFamily=new Map<string,FamilyMember[]>();
 for(const row of (membersResult.data??[]) as MemberRow[]){const person=peopleById.get(row.person_id);if(!person)continue;const member={id:row.id,personId:row.person_id,name:`${person.first_name} ${person.last_name}`,crcCode:person.crc_code,relationship:row.relationship,primary:row.is_primary_contact};membersByFamily.set(row.family_id,[...(membersByFamily.get(row.family_id)??[]),member]);}
 const families=((familiesResult.data??[]) as unknown as FamilyRow[]).map(row=>({id:row.id,organizationId:row.organization_id,siteId:row.site_id,siteName:relatedName(row.sites)??"Sede autorizada",name:row.name,address:row.address??"",notes:row.notes??"",members:membersByFamily.get(row.id)??[]}));
 const people:FamilyPersonOption[]=peopleRows.map(row=>({id:row.id,siteId:row.site_id,name:`${row.first_name} ${row.last_name}`,crcCode:row.crc_code}));
 const sites:FamilySiteOption[]=(sitesResult.data??[]).map(row=>({id:row.id,organizationId:row.organization_id,name:row.name}));
 return {families,people,sites};
}

export async function createFamily(draft:FamilyDraft,site:FamilySiteOption):Promise<Family>{const {data,error}=await getSupabaseBrowserClient().from("families").insert({organization_id:site.organizationId,site_id:site.id,name:draft.name.trim(),address:draft.address.trim()||null,notes:draft.notes.trim()||null}).select("id,organization_id,site_id,name,address,notes").single();if(error)throw error;return{id:data.id,organizationId:data.organization_id,siteId:data.site_id,siteName:site.name,name:data.name,address:data.address??"",notes:data.notes??"",members:[]};}
export async function updateFamily(family:Family,draft:FamilyDraft,site:FamilySiteOption):Promise<Family>{const {data,error}=await getSupabaseBrowserClient().from("families").update({organization_id:site.organizationId,site_id:site.id,name:draft.name.trim(),address:draft.address.trim()||null,notes:draft.notes.trim()||null}).eq("id",family.id).select("id,organization_id,site_id,name,address,notes").single();if(error)throw error;return{...family,organizationId:data.organization_id,siteId:data.site_id,siteName:site.name,name:data.name,address:data.address??"",notes:data.notes??""};}
export async function archiveFamily(id:string){const {error}=await getSupabaseBrowserClient().from("families").update({active:false}).eq("id",id);if(error)throw error;}
export async function linkFamilyMember(family:Family,person:FamilyPersonOption,relationship:FamilyRelationship,primary:boolean):Promise<FamilyMember>{const {data,error}=await getSupabaseBrowserClient().from("family_members").insert({organization_id:family.organizationId,site_id:family.siteId,family_id:family.id,person_id:person.id,relationship,is_primary_contact:primary}).select("id,person_id,relationship,is_primary_contact").single();if(error)throw error;return{id:data.id,personId:data.person_id,name:person.name,crcCode:person.crcCode,relationship:data.relationship,primary:data.is_primary_contact};}
export async function unlinkFamilyMember(id:string){const {error}=await getSupabaseBrowserClient().from("family_members").delete().eq("id",id);if(error)throw error;}
