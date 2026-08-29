import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

async function render(){const workerUrl=new URL("../dist/server/index.js",import.meta.url);workerUrl.searchParams.set("test",`${process.pid}-${Date.now()}`);const {default:worker}=await import(workerUrl.href);return worker.fetch(new Request("http://localhost/",{headers:{accept:"text/html"}}),{ASSETS:{fetch:async()=>new Response("Not found",{status:404})}},{waitUntil(){},passThroughOnException(){}})}

test("renderiza CRC Conecta y sus metadatos",async()=>{const response=await render();assert.equal(response.status,200);assert.match(response.headers.get("content-type")??"",/^text\/html\b/i);const html=await response.text();assert.match(html,/<title>CRC Conecta/);assert.match(html,/Comunidad de Renovación Cristiana/);assert.match(html,/Modo demostración/);assert.match(html,/Ver portal público/)});

test("mantiene contratos de sesión y persistencia Supabase",async()=>{const [auth,repository,migration]=await Promise.all([readFile(new URL("../features/auth/AuthProvider.tsx",import.meta.url),"utf8"),readFile(new URL("../features/people/repository.ts",import.meta.url),"utf8"),readFile(new URL("../supabase/migrations/20260829010000_sprint_10_supabase_sessions_crud.sql",import.meta.url),"utf8")]);assert.match(auth,/onAuthStateChange/);assert.match(auth,/signInWithPassword/);assert.match(repository,/from\("people"\)\.insert/);assert.match(repository,/from\("people"\)\.update/);assert.match(repository,/archived_at/);assert.match(migration,/get_my_access_context/);assert.match(migration,/people_document_present_unique/)});
