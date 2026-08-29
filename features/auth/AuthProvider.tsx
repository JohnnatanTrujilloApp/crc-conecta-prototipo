"use client";

import { createContext,useContext,useEffect,useMemo,useState } from "react";
import type { Session } from "@supabase/supabase-js";
import { getSupabaseBrowserClient } from "@/lib/supabase/client";
import { isSupabaseConfigured } from "@/lib/supabase/config";

type AuthState={configured:boolean;loading:boolean;session:Session|null;signIn:(email:string,password:string)=>Promise<string|null>;signOut:()=>Promise<void>};
const AuthContext=createContext<AuthState|null>(null);

export function AuthProvider({children}:{children:React.ReactNode}){
 const configured=isSupabaseConfigured();const [loading,setLoading]=useState(configured);const [session,setSession]=useState<Session|null>(null);
 useEffect(()=>{if(!configured)return;const client=getSupabaseBrowserClient();client.auth.getSession().then(({data})=>{setSession(data.session);setLoading(false)});const {data}=client.auth.onAuthStateChange((_event,next)=>{setSession(next);setLoading(false)});return()=>data.subscription.unsubscribe()},[configured]);
 const value=useMemo<AuthState>(()=>({configured,loading,session,signIn:async(email,password)=>{const {error}=await getSupabaseBrowserClient().auth.signInWithPassword({email,password});return error?.message??null},signOut:async()=>{await getSupabaseBrowserClient().auth.signOut()}}),[configured,loading,session]);
 return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}
export function useAuth(){const value=useContext(AuthContext);if(!value)throw new Error("useAuth debe usarse dentro de AuthProvider");return value;}
