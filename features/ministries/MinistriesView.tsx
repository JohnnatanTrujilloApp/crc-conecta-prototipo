"use client";

import { useState } from "react";

const ministries = [
  { name: "Alabanza", leader: "Laura Moreno", members: 14, color: "gold", roles: ["Director musical", "Vocalista", "Instrumentista"] },
  { name: "Ujieres", leader: "Carlos Pérez", members: 18, color: "green", roles: ["Líder", "Coordinador", "Servidor"] },
  { name: "CRC Kids", leader: "Diana Rojas", members: 22, color: "rose", roles: ["Coordinador", "Maestro", "Auxiliar"] },
  { name: "Intercesión", leader: "Marta Díaz", members: 11, color: "blue", roles: ["Líder", "Intercesor"] },
  { name: "Evangelismo", leader: "Pedro Gómez", members: 9, color: "forest", roles: ["Líder", "Servidor"] },
  { name: "Audiovisuales", leader: "Andrés Ruiz", members: 7, color: "slate", roles: ["Director", "Cámara", "Sonido"] },
];

export function MinistriesView() {
  const [selected, setSelected] = useState(ministries[0]);
  return <div className="content ministry-content"><div className="module-heading"><div><span className="eyebrow">SERVICIO Y DONES</span><h1>Ministerios</h1><p>Equipos de servicio organizados por sede, posición y periodo de participación.</p></div><button className="primary-button">＋ Crear ministerio</button></div><section className="ministry-grid">{ministries.map((ministry)=><button key={ministry.name} className={`ministry-card ${ministry.color} ${selected.name===ministry.name?"selected":""}`} onClick={()=>setSelected(ministry)}><span>{ministry.name[0]}</span><div><strong>{ministry.name}</strong><small>{ministry.members} integrantes</small></div><b>→</b></button>)}</section><section className="ministry-detail panel"><div className="ministry-detail-head"><div><span className="panel-kicker">CRC NEMOCÓN DEMO</span><h2>{selected.name}</h2><p>Liderado por {selected.leader}</p></div><button className="secondary-button">Editar ministerio</button></div><div className="ministry-stats"><div><strong>{selected.members}</strong><span>integrantes activos</span></div><div><strong>{selected.roles.length}</strong><span>posiciones definidas</span></div><div><strong>100%</strong><span>registro actualizado</span></div></div><div className="ministry-roles"><h3>Posiciones del equipo</h3>{selected.roles.map((role,index)=><div key={role}><span>{index+1}</span><strong>{role}</strong><small>{Math.max(1,Math.round(selected.members/selected.roles.length))} personas</small></div>)}</div></section></div>;
}
