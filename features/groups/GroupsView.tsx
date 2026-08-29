"use client";

import { useMemo, useState } from "react";

type Group={id:number;name:string;program:string;teacher:string;assistant:string;status:"ACTIVE"|"PLANNED";start:string;end:string;students:number;progress:number};
type Student={id:number;name:string;code:string;status:"ACTIVE"|"PAUSED";progress:number};
type Session={id:number;lesson:string;date:string;time:string;teacher:string;status:"SCHEDULED"|"COMPLETED";attendance:number};

const groups:Group[]=[
  {id:1,name:"Discipulado Grupo 2026-04",program:"Discipulado CRC",teacher:"Juan Pérez",assistant:"Laura Moreno",status:"ACTIVE",start:"05 ABR 2026",end:"28 JUN 2026",students:4,progress:68},
  {id:2,name:"Discipulado Jóvenes 2026-02",program:"Discipulado CRC",teacher:"Diana Rojas",assistant:"Carlos Pérez",status:"ACTIVE",start:"12 JUL 2026",end:"04 OCT 2026",students:7,progress:31},
  {id:3,name:"Liderazgo servidores",program:"Escuela de liderazgo",teacher:"Pedro Gómez",assistant:"Ana Martínez",status:"PLANNED",start:"06 SEP 2026",end:"29 NOV 2026",students:0,progress:0},
];
const students:Student[]=[
  {id:1,name:"María Rodríguez",code:"CRC-00001001",status:"ACTIVE",progress:80},
  {id:2,name:"Pedro Gómez",code:"CRC-00001002",status:"ACTIVE",progress:60},
  {id:3,name:"Carlos Martínez",code:"CRC-00001007",status:"PAUSED",progress:50},
  {id:4,name:"Ana Pérez",code:"CRC-00001008",status:"ACTIVE",progress:70},
];
const sessions:Session[]=[
  {id:1,lesson:"Un nuevo nacimiento y una nueva vida",date:"23 AGO 2026",time:"9:00 a. m.",teacher:"Juan Pérez",status:"SCHEDULED",attendance:0},
  {id:2,lesson:"La seguridad de la salvación",date:"16 AGO 2026",time:"9:00 a. m.",teacher:"Juan Pérez",status:"COMPLETED",attendance:4},
  {id:3,lesson:"La Palabra de Dios",date:"09 AGO 2026",time:"9:00 a. m.",teacher:"Laura Moreno",status:"COMPLETED",attendance:3},
];

export function GroupsView({onOpenClass}:{onOpenClass:()=>void}){
  const [activeGroup,setActiveGroup]=useState(groups[0]);
  const [tab,setTab]=useState<"students"|"sessions">("students");
  const [query,setQuery]=useState("");
  const [enrolled,setEnrolled]=useState(students);
  const [notice,setNotice]=useState("");
  const visible=useMemo(()=>enrolled.filter(person=>person.name.toLocaleLowerCase("es").includes(query.toLocaleLowerCase("es"))||person.code.toLowerCase().includes(query.toLowerCase())),[enrolled,query]);
  const toggleStatus=(id:number)=>{setEnrolled(current=>current.map(person=>person.id===id?{...person,status:person.status==="ACTIVE"?"PAUSED":"ACTIVE"}:person));setNotice("Matrícula actualizada en la demostración.")};
  return <div className="content groups-content"><div className="module-heading"><div><span className="eyebrow">DISCIPULADO Y FORMACIÓN</span><h1>Grupos y clases</h1><p>Gestiona matrículas, agenda sesiones y registra quién impartió cada clase.</p></div><button className="primary-button">＋ Crear grupo</button></div><div className="group-summary"><article><strong>2</strong><span>grupos activos</span></article><article><strong>{enrolled.filter(person=>person.status==="ACTIVE").length}</strong><span>matrículas activas</span></article><article><strong>3</strong><span>sesiones registradas</span></article><div><b>CRC Nemocón</b><span>Información aislada por sede</span></div></div><section className="group-layout"><aside className="group-list"><div className="group-list-head"><strong>Grupos de la sede</strong><span>{groups.length}</span></div>{groups.map(group=><button key={group.id} className={group.id===activeGroup.id?"active":""} onClick={()=>{setActiveGroup(group);setNotice("")}}><span>{group.name.split(" ").slice(0,2).map(word=>word[0]).join("")}</span><div><strong>{group.name}</strong><small>{group.teacher} · {group.students} estudiantes</small></div><i className={group.status.toLowerCase()}>{group.status==="ACTIVE"?"Activo":"Planeado"}</i></button>)}</aside><section className="group-detail"><header><div><span className="panel-kicker">{activeGroup.program}</span><h2>{activeGroup.name}</h2><p>{activeGroup.start} — {activeGroup.end}</p></div><button className="secondary-button">Editar grupo</button></header><div className="group-facts"><p><span>Maestro</span><strong>{activeGroup.teacher}</strong></p><p><span>Asistente</span><strong>{activeGroup.assistant}</strong></p><p><span>Progreso promedio</span><strong>{activeGroup.progress}%</strong></p></div><nav className="group-tabs" aria-label="Contenido del grupo"><button className={tab==="students"?"active":""} onClick={()=>setTab("students")}>Matrículas <span>{enrolled.length}</span></button><button className={tab==="sessions"?"active":""} onClick={()=>setTab("sessions")}>Sesiones <span>{sessions.length}</span></button></nav>{notice&&<div className="group-notice">✓ {notice}</div>}{tab==="students"?<div className="enrollment-panel"><div className="group-tools"><label><span>⌕</span><input value={query} onChange={event=>setQuery(event.target.value)} placeholder="Buscar estudiante o código CRC" aria-label="Buscar matrícula"/></label><button>＋ Matricular persona</button></div>{visible.length?<div className="enrollment-list">{visible.map(person=><article key={person.id}><span className="enrollment-avatar">{person.name.split(" ").map(word=>word[0]).slice(0,2).join("")}</span><div><strong>{person.name}</strong><small>{person.code} · Progreso {person.progress}%</small><i><b style={{width:`${person.progress}%`}}/></i></div><button className={person.status==="ACTIVE"?"active":"paused"} onClick={()=>toggleStatus(person.id)}>{person.status==="ACTIVE"?"Activa":"Pausada"}</button></article>)}</div>:<div className="group-empty"><strong>Sin matrículas encontradas</strong><span>Prueba con otro nombre o código.</span></div>}</div>:<div className="session-panel"><div className="session-head"><div><strong>Historial de clases</strong><span>Una sesión registra cuándo y quién impartió una lección.</span></div><button>＋ Programar sesión</button></div><div className="session-list">{sessions.map(session=><article key={session.id}><time><strong>{session.date.split(" ")[0]}</strong><span>{session.date.split(" ")[1]}</span></time><div><strong>{session.lesson}</strong><small>{session.time} · Maestro: {session.teacher}</small></div><span className={session.status.toLowerCase()}>{session.status==="SCHEDULED"?"Programada":`${session.attendance} presentes`}</span>{session.status==="SCHEDULED"?<button onClick={onOpenClass}>Abrir clase →</button>:<button>Ver registro →</button>}</article>)}</div></div>}</section></section></div>;
}
