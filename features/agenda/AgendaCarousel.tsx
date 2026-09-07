"use client";
import {useEffect,useRef,useState} from "react";
import {loadUpcomingEvents,type AgendaEvent} from "./repository";

const modality:Record<AgendaEvent["modality"],string>={IN_PERSON:"Presencial",ONLINE:"Virtual",HYBRID:"Híbrido"};
function eventDate(item:AgendaEvent){try{return new Intl.DateTimeFormat("es-CO",{weekday:"short",day:"numeric",month:"short",timeZone:item.timezone||"America/Bogota"}).format(new Date(item.start_at))}catch{return new Intl.DateTimeFormat("es-CO",{weekday:"short",day:"numeric",month:"short",timeZone:"America/Bogota"}).format(new Date(item.start_at))}}
function eventTime(item:AgendaEvent){try{return new Intl.DateTimeFormat("es-CO",{hour:"numeric",minute:"2-digit",timeZone:item.timezone||"America/Bogota"}).format(new Date(item.start_at))}catch{return new Intl.DateTimeFormat("es-CO",{hour:"numeric",minute:"2-digit",timeZone:"America/Bogota"}).format(new Date(item.start_at))}}

export function AgendaCarousel(){
 const[events,setEvents]=useState<AgendaEvent[]>([]);const[selected,setSelected]=useState<AgendaEvent|null>(null);const[loading,setLoading]=useState(true);const[error,setError]=useState("");const rail=useRef<HTMLDivElement>(null);
 useEffect(()=>{let active=true;loadUpcomingEvents(12).then(items=>{if(active)setEvents(items)}).catch(()=>{if(active)setError("No fue posible cargar tu agenda autorizada.")}).finally(()=>{if(active)setLoading(false)});return()=>{active=false}},[]);
 const move=(direction:-1|1)=>rail.current?.scrollBy({left:direction*rail.current.clientWidth*.82,behavior:"smooth"});
 return <section className="agenda-section" aria-labelledby="agenda-title">
  <div className="agenda-heading"><div><span className="panel-kicker">AGENDA</span><h2 id="agenda-title">Próximos eventos</h2><p>Actividades disponibles para tu perfil, sede y ministerios.</p></div>{events.length>1&&<div className="agenda-controls"><button type="button" aria-label="Ver eventos anteriores" onClick={()=>move(-1)}>←</button><button type="button" aria-label="Ver eventos siguientes" onClick={()=>move(1)}>→</button></div>}</div>
  {loading?<div className="agenda-state">Cargando próximos eventos…</div>:error?<div className="agenda-state error">{error}</div>:events.length?<div className="agenda-rail" ref={rail} role="region" aria-label="Carrusel de próximos eventos">{events.map(item=><article className="agenda-card" key={item.id}>
   <div className="agenda-image" style={item.banner_url?{backgroundImage:`linear-gradient(180deg,transparent,#102f28b8),url(${item.banner_url})`}:undefined}>{item.is_featured&&<span>Destacado</span>}<b>{item.event_type.replaceAll("_"," ")}</b></div>
   <div className="agenda-body"><h3>{item.title}</h3><dl><div><dt>Fecha</dt><dd>{eventDate(item)}</dd></div><div><dt>Hora</dt><dd>{eventTime(item)}</dd></div><div><dt>Sede</dt><dd>{item.site_name}</dd></div><div><dt>Modalidad</dt><dd>{modality[item.modality]}</dd></div></dl>{item.ministry_name&&<p className="agenda-ministry">{item.ministry_name}</p>}<p>{item.description||"Consulta los detalles y prepárate para participar."}</p><button type="button" onClick={()=>setSelected(item)}>Ver evento <span>→</span></button></div>
  </article>)}</div>:<div className="agenda-state empty"><strong>No tienes eventos próximos disponibles.</strong><span>Cuando tu sede o tus ministerios publiquen una actividad autorizada, aparecerá aquí.</span></div>}
  {events.length>1&&<div className="agenda-indicators" aria-hidden="true">{events.slice(0,Math.min(events.length,6)).map(item=><i key={item.id}/>)}</div>}
  {selected&&<EventDetail event={selected} close={()=>setSelected(null)}/>} 
 </section>;
}

function EventDetail({event,close}:{event:AgendaEvent;close:()=>void}){
 useEffect(()=>{const key=(e:KeyboardEvent)=>{if(e.key==="Escape")close()};document.addEventListener("keydown",key);return()=>document.removeEventListener("keydown",key)},[close]);
 return <div className="event-modal" role="dialog" aria-modal="true" aria-labelledby="event-detail-title"><article><button className="event-close" type="button" aria-label="Cerrar detalle del evento" onClick={close}>×</button>{event.banner_url&&<img src={event.banner_url} alt=""/>}<span className="panel-kicker">{event.event_type.replaceAll("_"," ")}</span><h2 id="event-detail-title">{event.title}</h2><p>{event.description||"Información del evento autorizado."}</p><dl><div><dt>Fecha y hora</dt><dd>{eventDate(event)} · {eventTime(event)}</dd></div><div><dt>Sede</dt><dd>{event.site_name}</dd></div><div><dt>Modalidad</dt><dd>{modality[event.modality]}</dd></div>{event.location&&<div><dt>Ubicación</dt><dd>{event.location}</dd></div>}{event.ministry_name&&<div><dt>Ministerio</dt><dd>{event.ministry_name}</dd></div>}{event.organizer_name&&<div><dt>Organiza</dt><dd>{event.organizer_name}</dd></div>}</dl></article></div>;
}
