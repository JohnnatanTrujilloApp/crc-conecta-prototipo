"use client";

import { useState } from "react";

const families = [
  { id: 1, name: "Familia Pérez Gómez", site: "CRC Nemocón Demo", address: "Barrio Centro", members: ["Carlos Pérez · Padre", "María Gómez · Madre", "Samuel Pérez · Hijo", "Sara Pérez · Hija"] },
  { id: 2, name: "Familia Rodríguez Díaz", site: "CRC Nemocón Demo", address: "Vereda Susatá", members: ["María Rodríguez · Madre", "Elena Díaz · Hija"] },
  { id: 3, name: "Familia Martínez Rojas", site: "CRC Central Demo", address: "Bogotá", members: ["Ana Martínez · Hija", "Lucía Rojas · Madre", "Jorge Martínez · Padre"] },
];

export function FamiliesView({ onPerson }: { onPerson: () => void }) {
  const [active, setActive] = useState(families[0]);
  return <div className="content family-content"><div className="module-heading"><div><span className="eyebrow">NÚCLEOS FAMILIARES</span><h1>Familias</h1><p>Navega desde una familia hacia sus integrantes y desde cada persona hacia su hogar.</p></div><button className="primary-button">＋ Crear familia</button></div><div className="demo-notice"><strong>Datos ficticios</strong><span>Los vínculos familiares respetarán el mismo alcance de sede de cada persona.</span></div><section className="family-layout"><div className="family-list"><div className="module-search">⌕ <input placeholder="Buscar familia" aria-label="Buscar familia"/></div>{families.map((family)=><button className={active.id===family.id?"active":""} key={family.id} onClick={()=>setActive(family)}><span className="family-mark">⌂</span><div><strong>{family.name}</strong><small>{family.members.length} integrantes · {family.site}</small></div><b>→</b></button>)}</div><article className="family-detail"><div className="family-title"><div><span className="eyebrow">PERFIL FAMILIAR</span><h2>{active.name}</h2><p>{active.address} · {active.site}</p></div><span className="family-count">{active.members.length}<small>personas</small></span></div><div className="family-members"><h3>Integrantes</h3>{active.members.map((member)=>{const [name,relationship]=member.split(" · ");return <button key={member} onClick={onPerson}><span>{name.split(" ").map(part=>part[0]).slice(0,2).join("")}</span><div><strong>{name}</strong><small>{relationship}</small></div><b>Ver perfil →</b></button>})}</div><div className="family-actions"><button className="secondary-button">Editar familia</button><button className="primary-button">＋ Vincular persona</button></div></article></section></div>;
}
