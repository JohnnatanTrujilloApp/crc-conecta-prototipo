"use client";

/* eslint-disable jsx-a11y/no-autofocus */

import { useMemo, useState } from "react";

type Lesson={id:number;title:string;biblicalText:string;centralVerse:string;duration:number;active:boolean};
type Module={id:number;title:string;description:string;lessons:Lesson[]};
type Program={id:number;title:string;type:"DISCIPLESHIP"|"COURSE"|"SCHOOL";description:string;modules:Module[]};

const seedPrograms:Program[]=[
  {id:1,title:"Discipulado CRC",type:"DISCIPLESHIP",description:"Fundamentos para una nueva vida en Cristo.",modules:[
    {id:1,title:"Fundamentos de la fe",description:"Identidad, salvación y vida cristiana.",lessons:[
      {id:1,title:"Un nuevo nacimiento y una nueva vida",biblicalText:"Juan 3:1–15",centralVerse:"Juan 3:3",duration:45,active:true},
      {id:2,title:"La seguridad de la salvación",biblicalText:"Romanos 8:31–39",centralVerse:"Romanos 8:38–39",duration:40,active:true},
      {id:3,title:"La Palabra de Dios",biblicalText:"2 Timoteo 3:14–17",centralVerse:"Salmo 119:105",duration:50,active:true},
    ]},
    {id:2,title:"Vida con propósito",description:"Hábitos que fortalecen el crecimiento.",lessons:[
      {id:4,title:"Una vida de oración",biblicalText:"Mateo 6:5–13",centralVerse:"Filipenses 4:6",duration:45,active:true},
      {id:5,title:"Comunión y servicio",biblicalText:"Hechos 2:42–47",centralVerse:"Gálatas 5:13",duration:45,active:false},
    ]},
  ]},
  {id:2,title:"Escuela de liderazgo",type:"SCHOOL",description:"Formación práctica para líderes y servidores.",modules:[{id:3,title:"Liderazgo que sirve",description:"Carácter, dones y trabajo en equipo.",lessons:[{id:6,title:"El modelo de Jesús",biblicalText:"Marcos 10:42–45",centralVerse:"Marcos 10:45",duration:60,active:true}]}]},
  {id:3,title:"Preparación para bautismo",type:"COURSE",description:"Verdades esenciales antes del bautismo.",modules:[]},
];

export function TrainingView(){
  const [programs,setPrograms]=useState(seedPrograms);
  const [activeId,setActiveId]=useState(1);
  const [query,setQuery]=useState("");
  const [expanded,setExpanded]=useState<number|null>(1);
  const [selectedLesson,setSelectedLesson]=useState<Lesson|null>(seedPrograms[0].modules[0].lessons[0]);
  const [creating,setCreating]=useState(false);
  const [title,setTitle]=useState("");
  const [error,setError]=useState("");
  const active=programs.find(program=>program.id===activeId)??programs[0];
  const filtered=useMemo(()=>programs.filter(program=>program.title.toLocaleLowerCase("es").includes(query.toLocaleLowerCase("es"))),[programs,query]);
  const createProgram=()=>{const clean=title.trim();if(clean.length<3){setError("Escribe un nombre de al menos 3 caracteres.");return;}const next:Program={id:Date.now(),title:clean,type:"COURSE",description:"Nuevo programa listo para organizar.",modules:[]};setPrograms(current=>[...current,next]);setActiveId(next.id);setTitle("");setError("");setCreating(false);setSelectedLesson(null)};
  return <div className="content training-content"><div className="module-heading"><div><span className="eyebrow">FORMACIÓN CRC</span><h1>Programas y lecciones</h1><p>Organiza contenidos reutilizables antes de crear grupos y matrículas.</p></div><button className="primary-button" onClick={()=>setCreating(true)}>＋ Nuevo programa</button></div><div className="training-summary"><article><strong>{programs.length}</strong><span>programas</span></article><article><strong>{programs.reduce((n,p)=>n+p.modules.length,0)}</strong><span>módulos</span></article><article><strong>{programs.reduce((n,p)=>n+p.modules.reduce((m,x)=>m+x.lessons.length,0),0)}</strong><span>lecciones</span></article><div><b>Biblioteca protegida</b><span>Permisos y RLS por organización</span></div></div><section className="training-layout"><aside className="program-list"><label className="module-search"><span>⌕</span><input value={query} onChange={event=>setQuery(event.target.value)} placeholder="Buscar programa" aria-label="Buscar programa de formación"/></label>{filtered.length?filtered.map(program=><button key={program.id} className={program.id===active.id?"active":""} onClick={()=>{setActiveId(program.id);setExpanded(program.modules[0]?.id??null);setSelectedLesson(program.modules[0]?.lessons[0]??null)}}><span>{program.type==="DISCIPLESHIP"?"D":program.type==="SCHOOL"?"E":"C"}</span><div><strong>{program.title}</strong><small>{program.type} · {program.modules.length} módulos</small></div><b>›</b></button>):<div className="training-empty"><strong>Sin resultados</strong><span>Prueba con otro nombre.</span></div>}</aside><section className="curriculum-panel"><header><div><span className="panel-kicker">{active.type}</span><h2>{active.title}</h2><p>{active.description}</p></div><button className="secondary-button">Editar programa</button></header>{active.modules.length?<div className="module-stack">{active.modules.map((module,index)=><article key={module.id} className={expanded===module.id?"open":""}><button className="module-row" onClick={()=>setExpanded(expanded===module.id?null:module.id)}><span>{String(index+1).padStart(2,"0")}</span><div><strong>{module.title}</strong><small>{module.description} · {module.lessons.length} lecciones</small></div><b>{expanded===module.id?"−":"＋"}</b></button>{expanded===module.id&&<div className="lesson-list">{module.lessons.map((lesson,lessonIndex)=><button key={lesson.id} className={selectedLesson?.id===lesson.id?"selected":""} onClick={()=>setSelectedLesson(lesson)}><i>{lessonIndex+1}</i><div><strong>{lesson.title}</strong><small>{lesson.biblicalText} · {lesson.duration} min</small></div><span className={lesson.active?"lesson-active":"lesson-draft"}>{lesson.active?"Activa":"Borrador"}</span></button>)}<button className="add-lesson">＋ Agregar lección</button></div>}</article>)}</div>:<div className="curriculum-empty"><span>◇</span><strong>Aún no hay módulos</strong><p>Crea el primer módulo para comenzar el plan de formación.</p><button className="primary-button">Crear módulo</button></div>}</section><aside className="lesson-preview">{selectedLesson?<><span className="panel-kicker">VISTA DE LECCIÓN</span><h2>{selectedLesson.title}</h2><div className="lesson-facts"><p><span>Texto bíblico</span><strong>{selectedLesson.biblicalText}</strong></p><p><span>Versículo central</span><strong>{selectedLesson.centralVerse}</strong></p><p><span>Duración</span><strong>{selectedLesson.duration} minutos</strong></p></div><div className="resource-list"><strong>Contenido y recursos</strong><span>▤ Guía de enseñanza</span><span>▷ Video complementario</span><span>♫ Audio de la lección</span></div><button className="primary-button wide">Abrir contenido</button></>:<div className="training-empty"><strong>Selecciona una lección</strong><span>Aquí verás su contenido y recursos.</span></div>}</aside></section>{creating&&<div className="modal-layer"><button className="modal-scrim" aria-label="Cerrar" onClick={()=>setCreating(false)}/><section className="program-modal"><div className="modal-head"><div><span className="eyebrow">NUEVO PROGRAMA</span><h2>Crear programa</h2><p>Podrás agregar módulos y lecciones después.</p></div><button onClick={()=>setCreating(false)}>×</button></div><label className={`form-field ${error?"has-error":""}`}><span>Nombre del programa</span><input value={title} onChange={event=>{setTitle(event.target.value);setError("")}} placeholder="Ej. Fundamentos para matrimonios" autoFocus/>{error&&<small>{error}</small>}</label><label className="form-field"><span>Tipo</span><select><option>Curso</option><option>Discipulado</option><option>Escuela</option><option>Seminario</option><option>Diplomado</option><option>Taller</option></select></label><div className="modal-actions"><button className="secondary-button" onClick={()=>setCreating(false)}>Cancelar</button><button className="primary-button" onClick={createProgram}>Crear programa</button></div></section></div>}</div>;
}
