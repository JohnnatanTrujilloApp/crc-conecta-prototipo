import type { MetadataRoute } from "next";
const base="https://crc-conecta-prototipo.johnnatan-trujillo.chatgpt.site";
export default function robots():MetadataRoute.Robots{return {rules:{userAgent:"*",allow:"/"},sitemap:`${base}/sitemap.xml`};}
