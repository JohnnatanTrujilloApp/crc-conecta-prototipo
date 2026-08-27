"use client";

import { useMemo, useState } from "react";

type EventStatus = "SCHEDULED" | "IN_PROGRESS" | "COMPLETED";
type Attendee = { id:number; name:string; code:string; present:boolean; method:"MANUAL"|"QR" };

const events:{id:number;title:string;type:string;date:string;time:string;status:EventStatus}[]=[
  {id:1,title:"Culto familiar",type:"SERVICE",date:"27 AGO",time:"7:00 p. m.",status:"IN_PROGRESS"},
  {id:2,title:"Discipulado CRC",type:"DISCIPLESHIP",date:"30 AGO",time:"9:00 a. m.",status:"SCHEDULED"},
  {id:3,title:"Reunión de líderes",type:"MINISTRY_MEETING",date:"02 SEP",time:"6:30 p. m.",status:"SCHEDULED"},
];
const initialAttendees:Attendee[]=[
  {id:1,name:"María Rodríguez",code:"CRC-00001001",present:true,method:"MANUAL"},
  {id:2,name:"Pedro Gómez",code:"CRC-00001002",present:true,method:"QR"},
  {id:3,name:"Ana Martínez",code:"CRC-00001003",present:false,method:"MANUAL"},
  {id:4,name:"Carlos Pérez",code:"CRC-00001004",present:true,method:"QR"},
  {id:5,name:"Laura Moreno",code:"CRC-00001005",present:true,method:"MANUAL"},
  {id:6,name:"Diana Rojas",code:"CRC-00001006",present:false,method:"MANUAL"},
];

export function AttendanceView({attendanceCount,adjustAttendance}:{attendanceCount:number;adjustAttendance:(delta:number)=>void}){
  const [activeEvent,setActiveEvent]=useState(events[0]);
  const [attendees,setAttendees]=useState(initialAttendees);
  const [query,setQuery]=useState("");
  const [saved,setSaved]=useState(false);
  const visible=useMemo(()=>attendees.filter(item=>item.name.toLocaleLowerCase("es").includes(query.toLocaleLowerCase("es"))||item.code.toLowerCase().includes(query.toLowerCase())),[attendees,query]);
  const toggle=(id:number)=>{const person=attendees.find(item=>item.id===id);if(!person)return;adjustAttendance(person.present?-1:1);setSaved(false);setAttendees(current=>current.map(item=>item.id===id?{...item,present:!item.present}:item))};
  return <div className="content event-content"><div className="module-heading"><div><span className="eyebrow">EVENTOS Y CHECK-IN</span><h1>Asistencia</h1><p>Selecciona un evento y registra una sola asistencia por persona.</p></div><button className="primary-button">＋ Crear evento</button></div><div className="live-sync"><span/><strong>Dashboard conectado</strong><p>Los cambios de esta demostración se reflejan inmediatamente en Inicio.</p></div><section className="event-layout"><aside className="event-list"><div className="event-list-head"><strong>Próximos eventos</strong><span>{events.length}</span></div>{events.map(event=><button key={event.id} className={activeEvent.id===event.id?"active":""} onClick={()=>{setActiveEvent(event);setSaved(false)}}><time><strong>{event.date.split(" ")[0]}</strong><small>{event.date.split(" ")[1]}</small></time><div><strong>{event.title}</strong><small>{event.time} · {event.type}</small></div><i className={`event-state ${event.status.toLowerCase()}`}>{event.status==="IN_PROGRESS"?"En curso":"Programado"}</i></button>)}</aside><section className="checkin-panel"><div className="checkin-head"><div><span className="panel-kicker">{activeEvent.type}</span><h2>{activeEvent.title}</h2><p>{activeEvent.date} · {activeEvent.time} · CRC Nemocón Demo</p></div><div className="attendance-total"><strong>{attendanceCount}</strong><span>presentes</span></div></div><div className="checkin-tools"><label><span>⌕</span><input value={query} onChange={event=>setQuery(event.target.value)} placeholder="Buscar nombre o código CRC" aria-label="Buscar persona para asistencia"/></label><button>▣ Escanear QR</button></div><div className="duplicate-note"><b>✓ Sin duplicados</b><span>Cada persona sólo puede tener un registro por evento.</span></div><div className="checkin-list">{visible.map(person=><article key={person.id}><span className="checkin-avatar">{person.name.split(" ").map(part=>part[0]).slice(0,2).join("")}</span><div><strong>{person.name}</strong><small>{person.code} · {person.method==="QR"?"Código QR":"Registro manual"}</small></div><button className={person.present?"present":""} onClick={()=>toggle(person.id)}><i>{person.present?"✓":"＋"}</i>{person.present?"Presente":"Registrar"}</button></article>)}</div><div className="checkin-save"><div><strong>{saved?"Asistencia guardada":"Cambios pendientes"}</strong><span>{attendanceCount} registros para {activeEvent.title}</span></div><button className="primary-button" onClick={()=>setSaved(true)}>{saved?"Guardado ✓":"Guardar asistencia"}</button></div></section></section></div>;
}
