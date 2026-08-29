import type { MetadataRoute } from "next";
const base="https://crc-conecta-prototipo.johnnatan-trujillo.chatgpt.site";
export default function sitemap():MetadataRoute.Sitemap{return ["","/conocenos","/conoce-a-jesus","/sedes","/ministerios","/eventos","/predicaciones","/formacion","/contacto"].map((path,index)=>({url:`${base}${path}`,lastModified:new Date("2026-08-28"),changeFrequency:index===0?"weekly":"monthly",priority:index===0?1:0.7}));}
