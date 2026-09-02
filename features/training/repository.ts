import {getSupabaseBrowserClient} from "@/lib/supabase/client";

export type ResourceType="FILE"|"PDF"|"PRESENTATION"|"IMAGE"|"AUDIO"|"LINK"|"YOUTUBE";
export type LessonResource={id:string;lessonId:string;organizationId:string;title:string;type:ResourceType;sourceUrl:string;storagePath:string;mimeType:string;fileSize:number|null;sortOrder:number};
export type Lesson={id:string;moduleId:string;organizationId:string;title:string;description:string;biblicalText:string;centralVerse:string;content:string;duration:number|null;sortOrder:number;active:boolean;resources:LessonResource[]};
export type Module={id:string;programId:string;title:string;description:string;sortOrder:number;lessons:Lesson[]};
export type Program={id:string;organizationId:string;title:string;type:string;description:string;modules:Module[]};
const bucket="training-materials";

export async function loadTraining(){
 const client=getSupabaseBrowserClient();
 const [siteResult,programResult,moduleResult,lessonResult,resourceResult]=await Promise.all([
  client.from("sites").select("organization_id").eq("active",true).limit(1),
  client.from("training_programs").select("id,organization_id,title,program_type,description").eq("active",true).order("title"),
  client.from("training_modules").select("id,program_id,title,description,sort_order").eq("active",true).order("sort_order"),
  client.from("lessons").select("id,organization_id,module_id,title,description,biblical_text,central_verse,content,duration_minutes,sort_order,active").order("sort_order"),
  client.from("lesson_resources").select("id,lesson_id,organization_id,title,resource_type,source_url,storage_path,mime_type,file_size_bytes,sort_order").eq("active",true).order("sort_order")
 ]);
 for(const result of [siteResult,programResult,moduleResult,lessonResult,resourceResult])if(result.error)throw result.error;
 const resources:LessonResource[]=(resourceResult.data??[]).map(row=>({id:row.id,lessonId:row.lesson_id,organizationId:row.organization_id,title:row.title,type:row.resource_type,sourceUrl:row.source_url??"",storagePath:row.storage_path??"",mimeType:row.mime_type??"",fileSize:row.file_size_bytes,sortOrder:row.sort_order}));
 const lessons:Lesson[]=(lessonResult.data??[]).map(row=>({id:row.id,moduleId:row.module_id,organizationId:row.organization_id,title:row.title,description:row.description??"",biblicalText:row.biblical_text??"",centralVerse:row.central_verse??"",content:row.content??"",duration:row.duration_minutes,sortOrder:row.sort_order,active:row.active,resources:resources.filter(item=>item.lessonId===row.id)}));
 const modules:Module[]=(moduleResult.data??[]).map(row=>({id:row.id,programId:row.program_id,title:row.title,description:row.description??"",sortOrder:row.sort_order,lessons:lessons.filter(item=>item.moduleId===row.id)}));
 const programs=(programResult.data??[]).map(row=>({id:row.id,organizationId:row.organization_id,title:row.title,type:row.program_type,description:row.description??"",modules:modules.filter(item=>item.programId===row.id)})) as Program[];
 return{organizationId:siteResult.data?.[0]?.organization_id??programs[0]?.organizationId??"",programs};
}

export async function createProgram(organizationId:string,draft:{title:string;type:string;description:string}){const{error}=await getSupabaseBrowserClient().from("training_programs").insert({organization_id:organizationId,title:draft.title.trim(),program_type:draft.type,description:draft.description.trim()||null});if(error)throw error}
export async function createModule(program:Program,draft:{title:string;description:string}){const next=program.modules.reduce((max,item)=>Math.max(max,item.sortOrder),0)+1;const{error}=await getSupabaseBrowserClient().from("training_modules").insert({organization_id:program.organizationId,program_id:program.id,title:draft.title.trim(),description:draft.description.trim()||null,sort_order:next});if(error)throw error}
export async function createLesson(program:Program,module:Module,draft:{title:string;description:string;biblicalText:string;centralVerse:string;content:string;duration:string}){const next=module.lessons.reduce((max,item)=>Math.max(max,item.sortOrder),0)+1;const{error}=await getSupabaseBrowserClient().from("lessons").insert({organization_id:program.organizationId,module_id:module.id,title:draft.title.trim(),description:draft.description.trim()||null,biblical_text:draft.biblicalText.trim()||null,central_verse:draft.centralVerse.trim()||null,content:draft.content.trim()||null,duration_minutes:draft.duration?Number(draft.duration):null,sort_order:next,active:true});if(error)throw error}

function fileType(file:File):ResourceType{if(file.type==="application/pdf")return"PDF";if(file.type.startsWith("image/"))return"IMAGE";if(file.type.startsWith("audio/"))return"AUDIO";if(/presentation|powerpoint|officedocument\.presentation/.test(file.type)||/\.(ppt|pptx)$/i.test(file.name))return"PRESENTATION";return"FILE"}
function safeName(name:string){return name.normalize("NFD").replace(/[\u0300-\u036f]/g,"").replace(/[^a-zA-Z0-9._-]+/g,"-").replace(/^-+|-+$/g,"")||"archivo"}
export async function uploadLessonResource(lesson:Lesson,file:File){if(file.size>25*1024*1024)throw new Error("El archivo supera el límite de 25 MB.");const client=getSupabaseBrowserClient();const path=`${lesson.organizationId}/${lesson.id}/${crypto.randomUUID()}-${safeName(file.name)}`;const uploaded=await client.storage.from(bucket).upload(path,file,{contentType:file.type||"application/octet-stream",upsert:false});if(uploaded.error)throw uploaded.error;const next=lesson.resources.reduce((max,item)=>Math.max(max,item.sortOrder),0)+1;const inserted=await client.from("lesson_resources").insert({organization_id:lesson.organizationId,lesson_id:lesson.id,title:file.name,resource_type:fileType(file),storage_path:path,mime_type:file.type||null,file_size_bytes:file.size,sort_order:next}).select("id").single();if(inserted.error){await client.storage.from(bucket).remove([path]);throw inserted.error}}
export async function addLinkedResource(lesson:Lesson,draft:{title:string;url:string;type:"LINK"|"YOUTUBE"}){const next=lesson.resources.reduce((max,item)=>Math.max(max,item.sortOrder),0)+1;const{error}=await getSupabaseBrowserClient().from("lesson_resources").insert({organization_id:lesson.organizationId,lesson_id:lesson.id,title:draft.title.trim(),resource_type:draft.type,source_url:draft.url.trim(),sort_order:next});if(error)throw error}
export async function deleteLessonResource(resource:LessonResource){const client=getSupabaseBrowserClient();const{error}=await client.from("lesson_resources").delete().eq("id",resource.id);if(error)throw error;if(resource.storagePath){const removed=await client.storage.from(bucket).remove([resource.storagePath]);if(removed.error)throw removed.error}}
export async function getLessonResourceUrl(resource:LessonResource){if(resource.sourceUrl)return resource.sourceUrl;const{data,error}=await getSupabaseBrowserClient().storage.from(bucket).createSignedUrl(resource.storagePath,900);if(error)throw error;return data.signedUrl}
