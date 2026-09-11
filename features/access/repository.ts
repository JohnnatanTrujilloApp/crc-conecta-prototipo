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
type AccessRequestRow={id:string;status:string;created_at:string;possible_duplicate:boolean;observations:string;person:AccessRequest["person"];site:AccessRequest["site"]};
export async function loadAccessRequests(){const{data,error}=await getSupabaseBrowserClient().rpc("list_authorized_access_requests");if(error)throw error;const rows=(Array.isArray(data)?data:[]) as AccessRequestRow[];return rows.map(row=>({id:row.id,status:row.status,createdAt:row.created_at,possibleDuplicate:row.possible_duplicate,observations:row.observations??"",person:row.person,site:row.site}))}
export async function reviewAccessRequest(id:string,decision:"APPROVE"|"REJECT"|"PENDING"|"SUSPEND",observations:string){const{error}=await getSupabaseBrowserClient().rpc("review_access_request",{target_request_id:id,decision,given_observations:observations||null});if(error)throw error}
