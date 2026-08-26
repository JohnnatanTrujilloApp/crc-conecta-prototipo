"use client";

import { useState } from "react";

type Scope = "ORGANIZATION" | "SITE";

const roles = [
  { code: "SUPER_ADMIN", name: "Superadministrador", detail: "Control completo de la organización", tone: "forest" },
  { code: "NATIONAL_PASTOR", name: "Pastor nacional", detail: "Visión consolidada de todas las sedes", tone: "gold" },
  { code: "SITE_PASTOR", name: "Pastor de sede", detail: "Administración pastoral de una sede", tone: "blue" },
  { code: "DISCIPLESHIP_TEACHER", name: "Maestro de discipulado", detail: "Clases y estudiantes asignados", tone: "rose" },
];

const matrix = [
  { action: "Ver personas", superAdmin: "Todas", national: "Todas", sitePastor: "Su sede", teacher: "Asignadas" },
  { action: "Crear personas", superAdmin: "Sí", national: "Sí", sitePastor: "Su sede", teacher: "No" },
  { action: "Registrar asistencia", superAdmin: "Sí", national: "Sí", sitePastor: "Su sede", teacher: "Su grupo" },
  { action: "Gestionar accesos", superAdmin: "Sí", national: "Limitado", sitePastor: "Limitado", teacher: "No" },
];

export function AccessView() {
  const [scope, setScope] = useState<Scope>("SITE");
  const [site, setSite] = useState("CRC Nemocón Demo");
  const [saved, setSaved] = useState(false);

  return <div className="content access-content">
    <div className="access-heading"><div><span className="eyebrow">SEGURIDAD Y AUTORIZACIÓN</span><h1>Roles y accesos</h1><p>Cada permiso se concede dentro de una organización o una sede específica.</p></div><span className="rls-badge"><i/> RLS activo</span></div>
    <section className="access-overview"><div><strong>4</strong><span>roles destacados</span></div><div><strong>14</strong><span>permisos base</span></div><div><strong>2</strong><span>tipos de alcance</span></div><div className="access-lock"><b>Datos protegidos</b><span>Sin rol asignado, no hay acceso.</span></div></section>
    <section className="role-grid">{roles.map((role) => <article className={`role-card ${role.tone}`} key={role.code}><span className="role-icon">{role.name.slice(0, 1)}</span><div><strong>{role.name}</strong><p>{role.detail}</p><small>{role.code}</small></div></article>)}</section>
    <section className="access-layout">
      <article className="panel assignment-panel"><div className="panel-head"><div><span className="panel-kicker">ASIGNACIÓN DEMO</span><h2>Acceso de Juan Pérez</h2></div><span className="access-state">Activo</span></div><div className="assignment-person"><span className="avatar avatar-dark">JP</span><div><strong>Juan Pérez</strong><small>juan.perez@example.com</small></div></div><div className="assignment-form"><label><span>Rol</span><select defaultValue="SITE_PASTOR"><option value="SITE_PASTOR">Pastor de sede</option><option value="DISCIPLESHIP_COORDINATOR">Coordinador de discipulado</option><option value="DISCIPLESHIP_TEACHER">Maestro de discipulado</option></select></label><fieldset><legend>Alcance</legend><button className={scope === "ORGANIZATION" ? "selected" : ""} onClick={() => { setScope("ORGANIZATION"); setSaved(false); }}>Organización</button><button className={scope === "SITE" ? "selected" : ""} onClick={() => { setScope("SITE"); setSaved(false); }}>Sede</button></fieldset>{scope === "SITE" && <label><span>Sede autorizada</span><select value={site} onChange={(event) => { setSite(event.target.value); setSaved(false); }}><option>CRC Nemocón Demo</option><option>CRC Central Demo</option></select></label>}<div className="scope-preview"><span>Puede operar en</span><strong>{scope === "ORGANIZATION" ? "CRC Demo · Todas las sedes" : site}</strong><small>Las consultas de otras sedes serán rechazadas por la base de datos.</small></div><button className="primary-button wide" onClick={() => setSaved(true)}>{saved ? "Asignación guardada ✓" : "Guardar asignación"}</button></div></article>
      <article className="panel permission-panel"><div className="panel-head"><div><span className="panel-kicker">MATRIZ INICIAL</span><h2>Permisos por rol</h2></div><button>14 permisos</button></div><div className="permission-table-wrap"><table><thead><tr><th>Acción</th><th>Superadmin</th><th>Pastor nacional</th><th>Pastor sede</th><th>Maestro</th></tr></thead><tbody>{matrix.map((row) => <tr key={row.action}><td>{row.action}</td><td>{row.superAdmin}</td><td>{row.national}</td><td>{row.sitePastor}</td><td>{row.teacher}</td></tr>)}</tbody></table></div><div className="security-note"><b>Defensa en profundidad</b><span>La interfaz orienta al usuario, pero PostgreSQL valida nuevamente permiso y alcance en cada operación.</span></div></article>
    </section>
  </div>;
}
