import{getSupabaseBrowserClient}from"@/lib/supabase/client";
export type Capability={id:string;name:string;level:string;category?:string};
export type WorshipMember={id:string;personId:string;name:string;status:string;trainingStartedAt:string|null;teamJoinedAt:string|null;notes:string|null;positions:Capability[];instruments:Capability[];history:{from:string|null;to:string;at:string;notes:string|null}[]};
export type WorshipTeam={ministryId:string;siteId:string;siteName:string;positions:Capability[];instruments:Capability[];members:WorshipMember[]};
export type PersonResult={id:string;full_name:string;document_number:string|null;phone:string;email:string|null};
const client=()=>getSupabaseBrowserClient();
export async function loadWorshipTeam(){const{data,error}=await client().rpc("get_my_worship_team");if(error)throw error;return data as WorshipTeam}
export async function searchWorshipPeople(term:string){const{data,error}=await client().rpc("search_worship_people",{search_term:term,result_limit:20});if(error)throw error;return(data??[])as PersonResult[]}
export async function saveWorshipMember(personId:string,status:string,positionIds:string[],instruments:{id:string;level:string}[],notes:string){const{error}=await client().rpc("save_worship_member",{target_person_id:personId,given_status:status,given_position_ids:positionIds,given_instruments:instruments,given_notes:notes||null});if(error)throw error}
