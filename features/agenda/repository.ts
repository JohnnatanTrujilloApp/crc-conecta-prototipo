import {getSupabaseBrowserClient} from "@/lib/supabase/client";

export type AgendaEvent={
 id:string;title:string;description:string|null;start_at:string;end_at:string|null;timezone:string;
 banner_url:string|null;modality:"IN_PERSON"|"ONLINE"|"HYBRID";location:string|null;event_type:string;
 is_featured:boolean;site_id:string;site_name:string;ministry_name:string|null;organizer_name:string|null;
};

export async function loadUpcomingEvents(limit=12){
 const{data,error}=await getSupabaseBrowserClient().rpc("get_my_upcoming_events",{result_limit:limit});
 if(error)throw error;
 return(data??[])as AgendaEvent[];
}

export async function loadVisibleEvent(eventId:string){
 const{data,error}=await getSupabaseBrowserClient().rpc("get_visible_event",{target_event_id:eventId});
 if(error)throw error;
 return(data??null)as AgendaEvent|null;
}
