import {getSupabaseBrowserClient} from "@/lib/supabase/client";

export type KidsChild={id:string;membershipId:string;name:string;birthDate:string;age:number;sex:string|null;groupName:string;guardianName:string|null;guardianPhone:string|null;lastAttendance:string|null;status:string;presentCount:number;absentCount:number};
export type KidsSession={id:string;title:string;startAt:string;status:string};
export type KidsAttendance={eventId:string;personId:string;status:"PRESENT"|"ABSENT"|"EXCUSED"|"LATE"};
export type KidsContext={site:{id:string;name:string};ministry:{id:string;name:string};children:KidsChild[];sessions:KidsSession[];attendance:KidsAttendance[];canManage:boolean};
export type PersonOption={id:string;name:string;birthDate:string|null;documentNumber:string|null;phone:string|null};
export type GuardianRelationship="FATHER"|"MOTHER"|"GUARDIAN"|"CAREGIVER"|"OTHER";
export type KidsGuardianLink={familyId:string|null;relationship:string|null;isPrimaryContact:boolean|null};
export type ChildDraft={existingPersonId?:string;firstName?:string;lastName?:string;birthDate?:string;sex?:string;documentType?:string;documentNumber?:string;phone?:string;email?:string;guardianPersonId?:string;guardianName?:string;guardianRelationship?:GuardianRelationship|"";guardianPhone?:string;guardianEmail?:string;primaryContact?:boolean;attendanceEventId?:string};

const rpc = async <T>(
  name: string,
  args: Record<string, unknown> = {}
) => {
  const { data, error } = await getSupabaseBrowserClient().rpc(name, args);

  if (error) {
    console.error(`[Supabase RPC: ${name}]`, {
      message: error.message,
      details: error.details,
      hint: error.hint,
      code: error.code,
      error,
    });

    throw new Error(
      [
        error.message,
        error.details,
        error.hint,
        error.code ? `Código: ${error.code}` : null,
      ]
        .filter(Boolean)
        .join(" | ")
    );
  }

  return data as T;
};
export const loadKidsContext=()=>rpc<KidsContext>("get_my_kids_context");
export const searchKidsPeople=(term:string,includeGuardianMatches=true)=>rpc<PersonOption[]>("search_kids_people",{search_term:term,result_limit:20,include_guardian_matches:includeGuardianMatches});
export const getKidsGuardianLink=(childId:string,guardianId:string)=>rpc<KidsGuardianLink>("get_kids_guardian_link",{target_child_id:childId,target_guardian_id:guardianId});
export const saveKidsChild=(draft:ChildDraft)=>rpc<string>("save_kids_child",{payload:draft});
export const inactivateKidsChild=(personId:string)=>rpc<void>("inactivate_kids_child",{target_person_id:personId});
export const createKidsSession=(date:string,time:string)=>rpc<string>("create_kids_sunday_session",{session_date:date,start_time:time});
export const saveKidsAttendance=(eventId:string,rows:KidsAttendance[])=>rpc<void>("save_kids_attendance",{target_event_id:eventId,attendance_rows:rows.map(row=>({personId:row.personId,status:row.status}))});
