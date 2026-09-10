import {getSupabaseBrowserClient} from "@/lib/supabase/client";
import {getPublicSupabaseConfig} from "@/lib/supabase/config";
export type PortalContext={status:"PENDING_APPROVAL"|"ACTIVE"|"SUSPENDED"|"REJECTED"|"ARCHIVED";personId?:string;firstName?:string;lastName?:string;siteId?:string;siteName?:string;permissions:string[];roles:string[]};
export type AccessRequest={id:string;status:string;createdAt:string;possibleDuplicate:boolean;observations:string;person:{first_name:string;last_name:string;email:string;phone:string;document_type:string;document_number:string};site:{name:string}};
export async function loadPortalContext(accessToken:string,timeoutMs=12000){
 const {url,anonKey}=getPublicSupabaseConfig();
 const controller=new AbortController();
 let timeout=0;
 try{
  const request=fetch(`${url}/rest/v1/rpc/get_my_portal_context`,{method:"POST",headers:{apikey:anonKey,Authorization:`Bearer ${accessToken}`,"Content-Type":"application/json"},body:"{}",signal:controller.signal,cache:"no-store"});
  const deadline=new Promise<never>((_,reject)=>{timeout=window.setTimeout(()=>{controller.abort();reject(new Error("PORTAL_CONTEXT_TIMEOUT"))},timeoutMs)});
  const response=await Promise.race([request,deadline]);
  if(!response.ok)throw new Error(`PORTAL_CONTEXT_HTTP_${response.status}`);
  const data=await response.json() as PortalContext|null;
  if(!data)throw new Error("PORTAL_CONTEXT_EMPTY");
  return data;
 }catch(error){
  if(controller.signal.aborted||error instanceof Error&&error.message==="PORTAL_CONTEXT_TIMEOUT")throw new Error("PORTAL_CONTEXT_TIMEOUT");
  throw error;
 }finally{window.clearTimeout(timeout)}
}
// Supabase infers embedded relations as a generated shape unavailable in this prototype.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export async function loadAccessRequests(){const{data,error}=await getSupabaseBrowserClient().from("access_requests").select("id,status,created_at,possible_duplicate,observations,person:people!person_id(first_name,last_name,email,phone,document_type,document_number),site:sites!site_id(name)").order("created_at",{ascending:false});if(error)throw error;return(data??[]).map((row:any)=>({id:row.id,status:row.status,createdAt:row.created_at,possibleDuplicate:row.possible_duplicate,observations:row.observations??"",person:Array.isArray(row.person)?row.person[0]:row.person,site:Array.isArray(row.site)?row.site[0]:row.site})) as AccessRequest[]}
export async function reviewAccessRequest(id:string,decision:"APPROVE"|"REJECT"|"PENDING"|"SUSPEND",observations:string){const{error}=await getSupabaseBrowserClient().rpc("review_access_request",{target_request_id:id,decision,given_observations:observations||null});if(error)throw error}
