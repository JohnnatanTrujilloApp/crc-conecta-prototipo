"use client";

import {AuthProvider} from "@/features/auth/AuthProvider";
import {PasswordRecoveryView} from "@/features/auth/PasswordRecoveryView";

export default function PasswordRecoveryPage(){
 return <AuthProvider><PasswordRecoveryView/></AuthProvider>;
}
