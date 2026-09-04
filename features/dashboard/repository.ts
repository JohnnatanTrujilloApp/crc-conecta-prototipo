import {getSupabaseBrowserClient} from "@/lib/supabase/client";

export type DashboardKind="ADMIN"|"LEADER"|"TEACHER"|"PERSONAL"|"NONE";
export type DashboardData={kind:DashboardKind;roles:string[];personId:string|null;siteId:string;siteName:string;sites:{id:string;name:string}[];permissions:string[];metrics:Record<string,number>;alerts:{tone:string;title:string;detail:string;action:string}[];upcoming:{type:string;title:string;date:string;detail:string}[]};

export async function loadDashboard(siteId?:string){
 const{data,error}=await getSupabaseBrowserClient().rpc("get_my_dashboard",{target_site_id:siteId||null});
 if(error)throw error;
 return data as DashboardData;
}
