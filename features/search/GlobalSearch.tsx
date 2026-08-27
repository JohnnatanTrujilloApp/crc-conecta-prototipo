"use client";

import { useMemo, useState } from "react";

const records = [
  { name: "María Rodríguez", meta: "CC 1012345678 · 300 555 0101", site: "CRC Nemocón Demo", status: "Miembro", progress: "Discipulado 80%" },
  { name: "Pedro Gómez", meta: "301 555 0102 · pedro@example.com", site: "CRC Nemocón Demo", status: "Congregante", progress: "Discipulado 60%" },
  { name: "Ana Martínez", meta: "CRC-000103 · ana@example.com", site: "CRC Central Demo", status: "Visitante", progress: "Primera visita" },
  { name: "Carlos Pérez", meta: "CC 80765432 · 303 555 0104", site: "CRC Nemocón Demo", status: "Líder", progress: "Ujieres" },
];

export function GlobalSearch({onClose,onOpenPerson}:{onClose:()=>void;onOpenPerson:()=>void}){
  const [query,setQuery]=useState("");
  const matches=useMemo(()=>{const value=query.trim().toLocaleLowerCase("es");return value?records.filter(record=>Object.values(record).join(" ").toLocaleLowerCase("es").includes(value)):records.slice(0,3)},[query]);
  return <div className="global-search-layer"><button className="global-search-scrim" onClick={onClose} aria-label="Cerrar búsqueda"/><section className="global-search" role="dialog" aria-modal="true" aria-labelledby="global-search-title"><div className="global-search-input"><span>⌕</span><input value={query} onChange={(event)=>setQuery(event.target.value)} placeholder="Nombre, documento, celular, correo o código CRC" aria-label="Búsqueda global"/><button onClick={onClose}>Esc</button></div><div className="global-search-head"><strong id="global-search-title">{query?`${matches.length} resultados`:`Búsquedas recientes`}</strong><span>Resultados limitados a CRC Nemocón Demo</span></div><div className="global-results">{matches.map(record=><button key={record.name} onClick={onOpenPerson}><span className="global-avatar">{record.name.split(" ").map(part=>part[0]).slice(0,2).join("")}</span><div><strong>{record.name}</strong><small>{record.meta}</small><em>{record.site} · {record.status}</em></div><b>{record.progress}<i>→</i></b></button>)}{!matches.length&&<div className="global-empty"><strong>Sin resultados</strong><span>Verifique el término o el alcance de sede.</span></div>}</div><footer><span>La búsqueda aplica RLS y sólo muestra datos autorizados.</span><button onClick={onOpenPerson}>Abrir directorio de personas →</button></footer></section></div>;
}
