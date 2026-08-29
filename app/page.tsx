"use client";

import { useMemo, useState } from "react";
import { PeopleView } from "@/features/people/PeopleView";
import { AccessView } from "@/features/access/AccessView";
import { FamiliesView } from "@/features/families/FamiliesView";
import { MinistriesView } from "@/features/ministries/MinistriesView";
import { GlobalSearch } from "@/features/search/GlobalSearch";
import { AttendanceView } from "@/features/attendance/AttendanceView";
import { TrainingView } from "@/features/training/TrainingView";
import { GroupsView } from "@/features/groups/GroupsView";
import { FollowupsView } from "@/features/followups/FollowupsView";

type View = "dashboard" | "people" | "families" | "ministries" | "attendance" | "discipleship" | "classroom" | "training" | "followups" | "access" | "public";
type Attendance = "present" | "absent";
type Student = { id:number; initials:string; name:string; subtitle:string; color:string; attendance:Attendance; call:boolean; visit:boolean; followup:boolean; notes:string };

const seedStudents:Student[]=[
  {id:1,initials:"MR",name:"María Rodríguez",subtitle:"Progreso 80% · 8 de 10 lecciones",color:"#e9c6a7",attendance:"present",call:false,visit:false,followup:false,notes:""},
  {id:2,initials:"PG",name:"Pedro Gómez",subtitle:"Progreso 60% · 6 de 10 lecciones",color:"#b9d8cf",attendance:"present",call:false,visit:false,followup:false,notes:""},
  {id:3,initials:"CM",name:"Carlos Martínez",subtitle:"Progreso 50% · 5 de 10 lecciones",color:"#c9c2dd",attendance:"absent",call:false,visit:false,followup:true,notes:"Llamar para conocer cómo se encuentra."},
  {id:4,initials:"AP",name:"Ana Pérez",subtitle:"Progreso 70% · 7 de 10 lecciones",color:"#e7c8ce",attendance:"present",call:false,visit:false,followup:false,notes:""},
];
const nav=["Inicio","Personas","Familias","Asistencia","Discipulado","Formación","Seguimiento","Ministerios","Reportes","Accesos"];

export default function Home(){
  const [view,setView]=useState<View>("dashboard");
  const [menuOpen,setMenuOpen]=useState(false);
  const [lessonOpen,setLessonOpen]=useState(false);
  const [students,setStudents]=useState(seedStudents);
  const [activeStudent,setActiveStudent]=useState<number|null>(null);
  const [saved,setSaved]=useState(false);
  const [searchOpen,setSearchOpen]=useState(false);
  const [attendanceCount,setAttendanceCount]=useState(32);
  const present=useMemo(()=>students.filter(s=>s.attendance==="present").length,[students]);
  const updateStudent=(id:number,patch:Partial<Student>)=>{setSaved(false);setStudents(current=>current.map(s=>s.id===id?{...s,...patch}:s))};
  const choose=(item:string)=>{if(item==="Inicio")setView("dashboard");if(item==="Personas")setView("people");if(item==="Familias")setView("families");if(item==="Ministerios")setView("ministries");if(item==="Asistencia")setView("attendance");if(item==="Discipulado")setView("discipleship");if(item==="Formación")setView("training");if(item==="Seguimiento")setView("followups");if(item==="Accesos")setView("access");setMenuOpen(false)};

  if(view==="public")return <PublicPortal onCampus={()=>setView("dashboard")}/>;
  return <div className="app-shell">
    <aside className={`sidebar ${menuOpen?"sidebar-open":""}`}>
      <button className="brand brand-button" onClick={()=>setView("dashboard")}><div className="brand-mark">CRC</div><div><strong>CRC Conecta</strong><span>Acompañar · Formar · Crecer</span></div></button>
      <nav aria-label="Navegación principal">{nav.map(item=><button key={item} className={(view==="dashboard"&&item==="Inicio")||(view==="people"&&item==="Personas")||(view==="families"&&item==="Familias")||(view==="ministries"&&item==="Ministerios")||(view==="attendance"&&item==="Asistencia")||((view==="discipleship"||view==="classroom")&&item==="Discipulado")||(view==="training"&&item==="Formación")||(view==="followups"&&item==="Seguimiento")||(view==="access"&&item==="Accesos")?"nav-active":""} onClick={()=>choose(item)}><span className="nav-dot"/>{item}</button>)}</nav>
      <button className="public-link" onClick={()=>setView("public")}><span>↗</span> Ver portal público</button>
      <div className="sidebar-help"><span>?</span><div><strong>Centro de ayuda</strong><small>Guías y soporte</small></div></div>
      <div className="profile-mini"><div className="avatar avatar-dark">JP</div><div><strong>Juan Pérez</strong><span>Líder de discipulado</span></div><button aria-label="Más opciones">•••</button></div>
    </aside>
    <main>
      <header className="topbar"><button className="menu-button" aria-label="Abrir menú" onClick={()=>setMenuOpen(!menuOpen)}>☰</button><div className="site-picker"><span className="pin">●</span><div><small>Sede activa</small><strong>CRC Nemocón</strong></div><span>⌄</span></div><div className="top-actions"><button aria-label="Buscar" onClick={()=>setSearchOpen(true)}>⌕</button><button className="bell" aria-label="Notificaciones">♢<i>3</i></button><div className="avatar avatar-dark">JP</div></div></header>
      {view==="dashboard"
        ? <Dashboard attendanceCount={attendanceCount} onClass={()=>setView("classroom")} onPeople={()=>setView("people")} onAttendance={()=>setView("attendance")} onFollowups={()=>setView("followups")}/>
        : view==="people"
          ? <PeopleView/>
          : view==="families"
            ? <FamiliesView onPerson={()=>setView("people")}/>
            : view==="ministries"
              ? <MinistriesView/>
              : view==="attendance"
                ? <AttendanceView attendanceCount={attendanceCount} adjustAttendance={(delta)=>setAttendanceCount(current=>current+delta)}/>
                : view==="training"
                  ? <TrainingView/>
                : view==="discipleship"
                  ? <GroupsView onOpenClass={()=>setView("classroom")}/>
                : view==="followups"
                  ? <FollowupsView/>
                : view==="access"
                  ? <AccessView/>
                  : <Discipleship students={students} present={present} activeStudent={activeStudent} saved={saved} setActiveStudent={setActiveStudent} updateStudent={updateStudent} save={()=>setSaved(true)} openLesson={()=>setLessonOpen(true)}/>}
    </main>
    {menuOpen&&<button className="scrim" aria-label="Cerrar menú" onClick={()=>setMenuOpen(false)}/>} 
    {lessonOpen&&<LessonDrawer onClose={()=>setLessonOpen(false)}/>} 
    {searchOpen&&<GlobalSearch onClose={()=>setSearchOpen(false)} onOpenPerson={()=>{setSearchOpen(false);setView("people")}}/>}
  </div>;
}

function Dashboard({attendanceCount,onClass,onPeople,onAttendance,onFollowups}:{attendanceCount:number;onClass:()=>void;onPeople:()=>void;onAttendance:()=>void;onFollowups:()=>void}){
  const points=[36,32,29,34,37,35,39];
  return <div className="content dashboard-content">
    <div className="dashboard-welcome"><div><span className="eyebrow">SÁBADO, 22 DE AGOSTO</span><h1>Buenos días, Juan.</h1><p>Esta es la actividad reciente de CRC Nemocón.</p></div><button className="primary-button" onClick={onClass}>Abrir clase de hoy <span>→</span></button></div>
    <section className="metric-grid">
      <Metric label="Personas registradas" value="53" detail="41 recurrentes" trend="Base consolidada" tone="green"/>
      <Metric label="Última asistencia" value={String(attendanceCount)} detail={`${Math.round(attendanceCount/53*100)}% del registro`} trend="Actualizado al registrar" tone="gold"/>
      <Metric label="Nuevos asistentes" value="12" detail="23% del total" trend="Por acompañar" tone="rose"/>
      <Metric label="En discipulado" value="4" detail="Grupo demostración" trend="Clase mañana" tone="blue"/>
    </section>
    <section className="dashboard-grid">
      <article className="panel attendance-chart"><div className="panel-head"><div><span className="panel-kicker">ASISTENCIA</span><h2>Tendencia semanal</h2></div><button>Últimas 7 semanas⌄</button></div><div className="chart-wrap"><div className="chart-y"><span>40</span><span>30</span><span>20</span><span>10</span><span>0</span></div><div className="bars">{points.map((p,i)=><div className="bar-col" key={i}><span className="bar-value">{p}</span><i style={{height:`${p*2.6}px`}}/><small>{["24 M","31 M","7 J","14 J","21 J","28 J","5 J"][i]}</small></div>)}</div></div><div className="chart-note"><span className="status-dot"/> Datos de referencia agregados del control de asistencia</div></article>
      <article className="panel next-class"><span className="panel-kicker">PRÓXIMA ACTIVIDAD</span><div className="class-date"><strong>23</strong><span>AGO<br/>DOM</span></div><h2>Un nuevo nacimiento<br/>y una nueva vida</h2><p>Discipulado CRC · Lección 01</p><div className="class-meta"><span>◷ 9:00 a. m.</span><span>4 estudiantes</span></div><button className="primary-button wide" onClick={onClass}>Registrar asistencia</button></article>
      <article className="panel quick-panel"><div className="panel-head"><div><span className="panel-kicker">ACCESOS RÁPIDOS</span><h2>¿Qué deseas hacer?</h2></div></div><div className="quick-actions"><button onClick={onPeople}><b>＋</b><span><strong>Registrar persona</strong><small>Primera visita o nuevo miembro</small></span></button><button onClick={onAttendance}><b>✓</b><span><strong>Tomar asistencia</strong><small>Culto, evento o discipulado</small></span></button><button onClick={onPeople}><b>⌕</b><span><strong>Buscar persona</strong><small>Perfil, familia y progreso</small></span></button></div></article>
      <article className="panel alerts-panel"><div className="panel-head"><div><span className="panel-kicker">ACOMPAÑAMIENTO</span><h2>Pendientes</h2></div><button onClick={onFollowups}>Ver todos</button></div><button className="alert-item" onClick={onFollowups}><i className="alert-icon rose">!</i><div><strong>3 personas requieren seguimiento</strong><span>Ausencia o solicitud registrada</span></div><b>→</b></button><button className="alert-item" onClick={onFollowups}><i className="alert-icon gold">◷</i><div><strong>2 llamadas por completar</strong><span>Asignadas para esta semana</span></div><b>→</b></button><button className="alert-item" onClick={onClass}><i className="alert-icon green">✓</i><div><strong>Clase preparada</strong><span>Lección y grupo confirmados</span></div><b>→</b></button></article>
    </section>
  </div>;
}

function Metric({label,value,detail,trend,tone}:{label:string;value:string;detail:string;trend:string;tone:string}){return <article className={`metric-card ${tone}`}><span>{label}</span><div><strong>{value}</strong><i/></div><p>{detail}</p><small>{trend}</small></article>}

function Discipleship({students,present,activeStudent,saved,setActiveStudent,updateStudent,save,openLesson}:{students:Student[];present:number;activeStudent:number|null;saved:boolean;setActiveStudent:(id:number|null)=>void;updateStudent:(id:number,p:Partial<Student>)=>void;save:()=>void;openLesson:()=>void}){
  return <div className="content"><div className="breadcrumbs"><span>Discipulado</span><b>›</b><span>Mi grupo</span><b>›</b><strong>Clase de hoy</strong></div><section className="page-heading"><div><span className="eyebrow">CLASE DE HOY</span><h1>Un nuevo nacimiento<br/>y una nueva vida</h1><p>Registra la asistencia y el seguimiento de tu grupo.</p></div><div className="date-card"><span>DOM</span><strong>23</strong><small>AGO · 2026</small></div></section>
    <section className="lesson-card"><div className="lesson-number"><span>LECCIÓN</span><strong>01</strong></div><div className="lesson-details"><div><span>Texto base</span><strong>Juan 3:1–15</strong></div><div><span>Versículo central</span><strong>Juan 3:3</strong></div><div><span>Maestro</span><strong>Juan Pérez</strong></div></div><button className="outline-button" onClick={openLesson}>Ver contenido <span>→</span></button></section>
    <section className="attendance-section"><div className="section-title"><div><h2>Asistencia y seguimiento</h2><p>La hoja física ahora se registra en cada perfil.</p></div><div className="counter"><strong>{present}</strong><span>de {students.length} presentes</span></div></div><div className="progress"><span style={{width:`${present/students.length*100}%`}}/></div><div className="student-list">{students.map(student=>{const expanded=activeStudent===student.id;return <article className={`student-card ${expanded?"expanded":""}`} key={student.id}><div className="student-row"><div className="avatar" style={{background:student.color}}>{student.initials}</div><div className="student-info"><strong>{student.name}</strong><span>{student.subtitle}</span></div><div className="attendance-toggle" role="group" aria-label={`Asistencia de ${student.name}`}><button className={student.attendance==="present"?"selected present":""} onClick={()=>updateStudent(student.id,{attendance:"present"})}><i>✓</i><span>Asistió</span></button><button className={student.attendance==="absent"?"selected absent":""} onClick={()=>updateStudent(student.id,{attendance:"absent"})}><i>×</i><span>No asistió</span></button></div><button className="details-button" onClick={()=>setActiveStudent(expanded?null:student.id)}>{student.followup&&<i>!</i>}⌄</button></div>{expanded&&<div className="followup-panel"><div className="followup-label"><strong>Hoja de seguimiento</strong><span>Registro asociado a fecha y estudiante</span></div><label className="check-option"><input type="checkbox" checked={student.call} onChange={e=>updateStudent(student.id,{call:e.target.checked})}/><span>Llamada realizada</span></label><label className="check-option"><input type="checkbox" checked={student.visit} onChange={e=>updateStudent(student.id,{visit:e.target.checked})}/><span>Visita realizada</span></label><label className="check-option follow"><input type="checkbox" checked={student.followup} onChange={e=>updateStudent(student.id,{followup:e.target.checked})}/><span>Requiere seguimiento</span></label><label className="notes"><span>Observaciones</span><textarea value={student.notes} onChange={e=>updateStudent(student.id,{notes:e.target.value})} placeholder="Escribe las observaciones del acompañamiento..."/></label></div>}</article>})}</div></section>
    <div className="save-bar"><div><span className="status-dot"/><p><strong>{saved?"Asistencia guardada":"Cambios listos para guardar"}</strong><small>{saved?"Los perfiles y reportes fueron actualizados.":"Se guardarán asistencia, llamada, visita y observaciones."}</small></p></div><button onClick={save}>{saved?"Guardado ✓":"Guardar asistencia"}</button></div>
  </div>;
}

function LessonDrawer({onClose}:{onClose:()=>void}){const blocks=[{n:"1",title:"¿Qué es el nuevo nacimiento?",text:"Es un acto de transformación operado por el Espíritu Santo en el corazón del creyente, dando comienzo a una nueva vida conforme a la voluntad de Dios.",refs:"2 Corintios 5:17 · Efesios 4:22–24"},{n:"2",title:"¿Para qué necesitamos nacer de nuevo?",items:["Ver el Reino de Dios — Juan 3:3","Entrar en el Reino de Dios — Juan 3:5","Entender a Dios — 1 Corintios 2:14–15","Ser guiados por Dios — Romanos 8:14"]},{n:"3",title:"¿Cómo nacer de nuevo?",items:["Aceptando a Jesucristo como Salvador y Señor — Juan 1:12","Por el Espíritu y la Palabra — Juan 3:5–6","Por fe — Romanos 10:9"]},{n:"4",title:"Resultados",items:["Salvación y vida nueva","Entramos en el Reino de Dios","Somos sellados con el Espíritu Santo","Participamos de las bendiciones de Dios"]}];return <div className="drawer-layer"><button className="drawer-scrim" onClick={onClose} aria-label="Cerrar contenido"/><aside className="lesson-drawer"><div className="drawer-head"><div><span className="eyebrow">DISCIPULADO CRC · LECCIÓN 01</span><h2>Un nuevo nacimiento<br/>y una nueva vida</h2><p>Juan 3:1–15 · Versículo central: Juan 3:3</p></div><button onClick={onClose}>×</button></div><div className="lesson-quote">“El que no naciere de nuevo, no puede ver el reino de Dios.” <span>Juan 3:3</span></div><div className="lesson-blocks">{blocks.map(b=><section key={b.n}><strong>{b.n}</strong><div><h3>{b.title}</h3>{b.text&&<p>{b.text}</p>}{b.items&&<ol>{b.items.map(i=><li key={i}>{i}</li>)}</ol>}{b.refs&&<small>{b.refs}</small>}</div></section>)}</div><button className="primary-button wide" onClick={onClose}>Volver a la asistencia</button></aside></div>}

function PublicPortal({onCampus}:{onCampus:()=>void}){return <div className="public-page"><header className="public-nav"><button className="public-brand"><span>CRC</span><div><strong>Comunidad de Renovación Cristiana</strong><small>Romanos 12:2</small></div></button><nav><a href="#conocenos">Conócenos</a><a href="#mision">Nuestra misión</a><a href="#medios">Audiovisuales</a></nav><button className="campus-button" onClick={onCampus}>Entrar a Campus CRC →</button></header><main>
  <section className="public-hero"><div className="hero-copy"><span className="eyebrow light">BIENVENIDO A LA FAMILIA CRC</span><h1>Una comunidad para<br/><em>renovar vidas.</em></h1><p>Predicamos el evangelio de Jesucristo, acompañamos familias y formamos discípulos que sirven con sus dones.</p><div><button className="hero-primary">Conoce a Jesús</button><button className="hero-secondary" onClick={onCampus}>Ir a Campus CRC</button></div></div><div className="hero-symbol"><span>CRC</span><i/><small>Una iglesia · Una familia · Una misión</small></div></section>
  <section className="public-intro" id="conocenos"><span className="eyebrow">QUIÉNES SOMOS</span><h2>Nuestro fundamento es la Palabra,<br/>la oración y la adoración.</h2><p>Creemos en el poder del Espíritu Santo para renovar mentes y corazones. Servimos integralmente a familias, parejas, jóvenes y niños, creciendo juntos en la fe.</p><div className="belief-grid"><article><b>01</b><h3>Ganar</h3><p>Compartimos el mensaje de salvación de Jesucristo.</p></article><article><b>02</b><h3>Consolidar</h3><p>Acompañamos a cada persona en sus primeros pasos.</p></article><article><b>03</b><h3>Discipular</h3><p>Formamos creyentes en la Palabra y la vida cristiana.</p></article><article><b>04</b><h3>Enviar</h3><p>Desarrollamos líderes, dones y ministerios para servir.</p></article></div></section>
  <section className="mission-section" id="mision"><div><span className="eyebrow light">NUESTRA MISIÓN</span><h2>Crecer juntos para extender el Reino de Dios.</h2></div><blockquote>“Transformaos por medio de la renovación de vuestro entendimiento.”<small>Romanos 12:2</small></blockquote></section>
  <section className="media-section" id="medios"><div className="media-heading"><div><span className="eyebrow">AUDIOVISUALES</span><h2>Un mensaje para cada momento</h2></div><p>Predicaciones, enseñanzas y transmisiones que fortalecen la fe durante la semana.</p></div><div className="media-grid"><article className="media-feature"><div className="play">▶</div><span>MENSAJE DESTACADO</span><h3>Renovados para transformar</h3><p>Una enseñanza basada en Romanos 12:2.</p></article><article><span>ENSEÑANZA</span><h3>Crecer en la Palabra</h3><p>Recursos para tu formación y discipulado.</p><button>Ver recursos →</button></article><article><span>EN VIVO</span><h3>Conéctate con CRC</h3><p>Acompáñanos en nuestras reuniones y eventos.</p><button>Ver transmisiones →</button></article></div></section>
 </main><footer><div className="public-brand"><span>CRC</span><div><strong>Comunidad de Renovación Cristiana</strong><small>Acompañar · Formar · Crecer</small></div></div><p>La tecnología al servicio de la misión.</p><button onClick={onCampus}>Campus CRC →</button></footer></div>}
