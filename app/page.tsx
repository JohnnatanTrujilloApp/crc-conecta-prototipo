"use client";

import { useMemo, useState } from "react";

type Attendance = "present" | "absent";
type Student = { id:number; initials:string; name:string; subtitle:string; color:string; attendance:Attendance; call:boolean; visit:boolean; followup:boolean; notes:string };

const seedStudents: Student[] = [
  { id:1, initials:"MR", name:"María Rodríguez", subtitle:"Progreso 80% · 8 de 10 lecciones", color:"#e9c6a7", attendance:"present", call:false, visit:false, followup:false, notes:"" },
  { id:2, initials:"PG", name:"Pedro Gómez", subtitle:"Progreso 60% · 6 de 10 lecciones", color:"#b9d8cf", attendance:"present", call:false, visit:false, followup:false, notes:"" },
  { id:3, initials:"CM", name:"Carlos Martínez", subtitle:"Progreso 50% · 5 de 10 lecciones", color:"#c9c2dd", attendance:"absent", call:false, visit:false, followup:true, notes:"Llamar para conocer cómo se encuentra." },
  { id:4, initials:"AP", name:"Ana Pérez", subtitle:"Progreso 70% · 7 de 10 lecciones", color:"#e7c8ce", attendance:"present", call:false, visit:false, followup:false, notes:"" },
];
const nav = ["Inicio","Personas","Familias","Asistencia","Discipulado","Formación","Ministerios","Reportes"];

export default function Home() {
  const [students,setStudents] = useState(seedStudents);
  const [activeStudent,setActiveStudent] = useState<number|null>(null);
  const [saved,setSaved] = useState(false);
  const [menuOpen,setMenuOpen] = useState(false);
  const present = useMemo(()=>students.filter((s)=>s.attendance==="present").length,[students]);
  function updateStudent(id:number, patch:Partial<Student>) { setSaved(false); setStudents((current)=>current.map((s)=>s.id===id?{...s,...patch}:s)); }

  return <div className="app-shell">
    <aside className={`sidebar ${menuOpen?"sidebar-open":""}`}>
      <div className="brand"><div className="brand-mark">CRC</div><div><strong>CRC Conecta</strong><span>Acompañar · Formar · Crecer</span></div></div>
      <nav aria-label="Navegación principal">{nav.map((item)=><button key={item} className={item==="Discipulado"?"nav-active":""} onClick={()=>setMenuOpen(false)}><span className="nav-dot"/>{item}</button>)}</nav>
      <div className="sidebar-help"><span>?</span><div><strong>Centro de ayuda</strong><small>Guías y soporte</small></div></div>
      <div className="profile-mini"><div className="avatar avatar-dark">JP</div><div><strong>Juan Pérez</strong><span>Líder de discipulado</span></div><button aria-label="Más opciones">•••</button></div>
    </aside>
    <main>
      <header className="topbar">
        <button className="menu-button" aria-label="Abrir menú" onClick={()=>setMenuOpen(!menuOpen)}>☰</button>
        <div className="site-picker"><span className="pin">●</span><div><small>Sede activa</small><strong>CRC Nemocón</strong></div><span>⌄</span></div>
        <div className="top-actions"><button aria-label="Buscar">⌕</button><button className="bell" aria-label="Notificaciones">♢<i>3</i></button><div className="avatar avatar-dark">JP</div></div>
      </header>
      <div className="content">
        <div className="breadcrumbs"><span>Discipulado</span><b>›</b><span>Mi grupo</span><b>›</b><strong>Clase de hoy</strong></div>
        <section className="page-heading"><div><span className="eyebrow">CLASE DE HOY</span><h1>Un nuevo nacimiento<br/>y una nueva vida</h1><p>Registra la asistencia y el seguimiento de tu grupo.</p></div><div className="date-card"><span>DOM</span><strong>23</strong><small>AGO · 2026</small></div></section>
        <section className="lesson-card"><div className="lesson-number"><span>LECCIÓN</span><strong>01</strong></div><div className="lesson-details"><div><span>Texto base</span><strong>Juan 3:1–15</strong></div><div><span>Versículo central</span><strong>Juan 3:3</strong></div><div><span>Maestro</span><strong>Juan Pérez</strong></div></div><button className="outline-button">Ver contenido <span>→</span></button></section>
        <section className="attendance-section">
          <div className="section-title"><div><h2>Asistencia</h2><p>Marca el estado de cada estudiante.</p></div><div className="counter"><strong>{present}</strong><span>de {students.length} presentes</span></div></div>
          <div className="progress"><span style={{width:`${(present/students.length)*100}%`}}/></div>
          <div className="student-list">{students.map((student)=>{ const expanded=activeStudent===student.id; return <article className={`student-card ${expanded?"expanded":""}`} key={student.id}>
            <div className="student-row"><div className="avatar" style={{background:student.color}}>{student.initials}</div><div className="student-info"><strong>{student.name}</strong><span>{student.subtitle}</span></div>
              <div className="attendance-toggle" role="group" aria-label={`Asistencia de ${student.name}`}><button className={student.attendance==="present"?"selected present":""} onClick={()=>updateStudent(student.id,{attendance:"present"})}><i>✓</i><span>Asistió</span></button><button className={student.attendance==="absent"?"selected absent":""} onClick={()=>updateStudent(student.id,{attendance:"absent"})}><i>×</i><span>No asistió</span></button></div>
              <button className={`details-button ${student.followup?"has-alert":""}`} onClick={()=>setActiveStudent(expanded?null:student.id)} aria-label={`Seguimiento de ${student.name}`}>{student.followup&&<i>!</i>}⌄</button>
            </div>
            {expanded&&<div className="followup-panel"><div className="followup-label"><strong>Seguimiento</strong><span>Información posterior a la clase</span></div><label className="check-option"><input type="checkbox" checked={student.call} onChange={(e)=>updateStudent(student.id,{call:e.target.checked})}/><span>Llamada realizada</span></label><label className="check-option"><input type="checkbox" checked={student.visit} onChange={(e)=>updateStudent(student.id,{visit:e.target.checked})}/><span>Visita realizada</span></label><label className="check-option follow"><input type="checkbox" checked={student.followup} onChange={(e)=>updateStudent(student.id,{followup:e.target.checked})}/><span>Requiere seguimiento</span></label><label className="notes"><span>Observaciones</span><textarea value={student.notes} onChange={(e)=>updateStudent(student.id,{notes:e.target.value})} placeholder="Añade una nota breve..."/></label></div>}
          </article>})}</div>
        </section>
        <div className="save-bar"><div><span className="status-dot"/><p><strong>{saved?"Asistencia guardada":"Cambios listos para guardar"}</strong><small>{saved?"Los perfiles y reportes fueron actualizados.":"La última sincronización fue hoy a las 9:41 a. m."}</small></p></div><button onClick={()=>setSaved(true)}>{saved?"Guardado ✓":"Guardar asistencia"}</button></div>
      </div>
    </main>
    {menuOpen&&<button className="scrim" aria-label="Cerrar menú" onClick={()=>setMenuOpen(false)}/>} 
  </div>;
}
