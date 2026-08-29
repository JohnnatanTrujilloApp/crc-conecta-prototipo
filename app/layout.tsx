import type { Metadata } from "next";
import { Geist, Geist_Mono } from "next/font/google";
import "./globals.css";
const geistSans=Geist({variable:"--font-geist-sans",subsets:["latin"]});
const geistMono=Geist_Mono({variable:"--font-geist-mono",subsets:["latin"]});
const siteUrl=new URL("https://crc-conecta-prototipo.johnnatan-trujillo.chatgpt.site");
export const metadata:Metadata={metadataBase:siteUrl,title:{default:"CRC Conecta · Una comunidad para renovar vidas",template:"%s · CRC Conecta"},description:"Conoce la Comunidad de Renovación Cristiana, nuestras sedes, eventos y espacios de formación.",keywords:["CRC","Comunidad de Renovación Cristiana","iglesia cristiana","Nemocón"],alternates:{canonical:"/"},icons:{icon:"/favicon.svg",shortcut:"/favicon.svg"},robots:{index:true,follow:true},openGraph:{type:"website",locale:"es_CO",siteName:"CRC Conecta",title:"CRC Conecta · Una comunidad para renovar vidas",description:"Una iglesia, una familia y una misión.",url:"/",images:[{url:"/og.png",width:1200,height:630,alt:"CRC Conecta"}]},twitter:{card:"summary_large_image",title:"CRC Conecta",description:"Una comunidad para renovar vidas.",images:["/og.png"]}};
export default function RootLayout({children}:Readonly<{children:React.ReactNode}>){return <html lang="es"><body className={`${geistSans.variable} ${geistMono.variable}`}>{children}</body></html>}
