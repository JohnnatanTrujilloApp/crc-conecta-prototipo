"use client";

import {AuthProvider} from "@/features/auth/AuthProvider";
import {RegistrationView} from "@/features/registration/RegistrationView";

export default function RegistrationPage(){
 return <AuthProvider><RegistrationView onPublic={()=>window.location.assign("/?public=1")} onCampus={()=>window.location.assign("/")}/></AuthProvider>;
}
