"use client";

import { useMemo, useState } from "react";
import { personStatuses, type Person, type PersonDraft } from "./types";
import { validatePersonDraft, type PersonDraftErrors } from "./validation";

const sites = [
  { id: "nemocon-demo", name: "CRC Nemocón Demo" },
  { id: "central-demo", name: "CRC Central Demo" },
];

const statusLabels: Record<Person["status"], string> = {
  VISITOR: "Visitante",
  CONGREGANT: "Congregante",
  MEMBER: "Miembro",
  SERVER: "Servidor",
  LEADER: "Líder",
  PASTOR: "Pastor",
  INACTIVE: "Inactivo",
  TRANSFERRED: "Trasladado",
};

const seedPeople: Person[] = [
  { id: "demo-1", firstName: "María", lastName: "Rodríguez", phone: "300 555 0101", email: "maria@example.com", siteId: "nemocon-demo", siteName: "CRC Nemocón Demo", status: "MEMBER", firstVisitDate: "2026-02-08" },
  { id: "demo-2", firstName: "Pedro", lastName: "Gómez", phone: "301 555 0102", siteId: "nemocon-demo", siteName: "CRC Nemocón Demo", status: "CONGREGANT", firstVisitDate: "2026-04-19" },
  { id: "demo-3", firstName: "Ana", lastName: "Martínez", phone: "302 555 0103", email: "ana@example.com", siteId: "central-demo", siteName: "CRC Central Demo", status: "VISITOR", firstVisitDate: "2026-08-16" },
  { id: "demo-4", firstName: "Carlos", lastName: "Pérez", phone: "303 555 0104", siteId: "nemocon-demo", siteName: "CRC Nemocón Demo", status: "LEADER", firstVisitDate: "2025-11-02" },
];

const emptyDraft: PersonDraft = {
  firstName: "",
  lastName: "",
  email: "",
  phone: "",
  siteId: "nemocon-demo",
  status: "VISITOR",
};

export function PeopleView() {
  const [people, setPeople] = useState(seedPeople);
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<"ALL" | Person["status"]>("ALL");
  const [formOpen, setFormOpen] = useState(false);
  const [draft, setDraft] = useState<PersonDraft>(emptyDraft);
  const [errors, setErrors] = useState<PersonDraftErrors>({});
  const [notice, setNotice] = useState("");

  const filteredPeople = useMemo(() => {
    const normalized = query.trim().toLocaleLowerCase("es");
    return people.filter((person) => {
      const matchesStatus = status === "ALL" || person.status === status;
      const searchable = `${person.firstName} ${person.lastName} ${person.phone} ${person.email ?? ""}`.toLocaleLowerCase("es");
      return matchesStatus && (!normalized || searchable.includes(normalized));
    });
  }, [people, query, status]);

  const updateDraft = <K extends keyof PersonDraft>(key: K, value: PersonDraft[K]) => {
    setDraft((current) => ({ ...current, [key]: value }));
    setErrors((current) => ({ ...current, [key]: undefined }));
  };

  const savePerson = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const nextErrors = validatePersonDraft(draft);
    if (Object.keys(nextErrors).length) {
      setErrors(nextErrors);
      return;
    }

    const selectedSite = sites.find((site) => site.id === draft.siteId) ?? sites[0];
    setPeople((current) => [
      {
        id: `demo-${Date.now()}`,
        ...draft,
        firstName: draft.firstName.trim(),
        lastName: draft.lastName.trim(),
        email: draft.email?.trim() || undefined,
        phone: draft.phone.trim(),
        siteName: selectedSite.name,
        firstVisitDate: new Date().toISOString().slice(0, 10),
      },
      ...current,
    ]);
    setDraft(emptyDraft);
    setErrors({});
    setFormOpen(false);
    setNotice("Persona agregada a la demostración. La persistencia se activará al conectar Supabase.");
  };

  return <div className="content people-content">
    <div className="people-heading"><div><span className="eyebrow">REGISTRO MAESTRO</span><h1>Personas</h1><p>Un registro único por persona, tenga o no una cuenta de acceso.</p></div><button className="primary-button" onClick={() => { setNotice(""); setFormOpen(true); }}>＋ Registrar persona</button></div>
    <div className="demo-notice"><strong>Datos ficticios</strong><span>Este Sprint 1 prepara el modelo multi-sede. No se está utilizando información real.</span></div>
    <section className="people-summary"><article><span>Total visible</span><strong>{filteredPeople.length}</strong></article><article><span>Visitantes</span><strong>{people.filter((person) => person.status === "VISITOR").length}</strong></article><article><span>Con cuenta</span><strong>0</strong><small>Vinculación opcional</small></article></section>
    <section className="people-panel">
      <div className="people-tools"><label className="people-search"><span>⌕</span><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Buscar por nombre, celular o correo" aria-label="Buscar personas"/></label><select value={status} onChange={(event) => setStatus(event.target.value as "ALL" | Person["status"])} aria-label="Filtrar por estado"><option value="ALL">Todos los estados</option>{personStatuses.map((item) => <option value={item} key={item}>{statusLabels[item]}</option>)}</select></div>
      {notice && <div className="people-success" role="status">✓ {notice}</div>}
      {filteredPeople.length ? <div className="people-table-wrap"><table className="people-table"><thead><tr><th>Persona</th><th>Sede</th><th>Contacto</th><th>Estado</th><th>Primera visita</th><th><span className="sr-only">Acciones</span></th></tr></thead><tbody>{filteredPeople.map((person) => <tr key={person.id}><td><div className="person-cell"><span>{person.firstName[0]}{person.lastName[0]}</span><div><strong>{person.firstName} {person.lastName}</strong><small>Sin cuenta de acceso</small></div></div></td><td>{person.siteName}</td><td><strong className="contact-primary">{person.phone}</strong><small>{person.email ?? "Sin correo"}</small></td><td><span className={`person-status status-${person.status.toLowerCase()}`}>{statusLabels[person.status]}</span></td><td>{new Intl.DateTimeFormat("es-CO", { day: "2-digit", month: "short", year: "numeric" }).format(new Date(`${person.firstVisitDate}T12:00:00`))}</td><td><button className="row-action" aria-label={`Ver perfil de ${person.firstName} ${person.lastName}`}>→</button></td></tr>)}</tbody></table></div>:<div className="people-empty"><strong>No encontramos personas</strong><span>Ajuste la búsqueda o registre una nueva persona.</span></div>}
    </section>
    {formOpen && <div className="modal-layer"><button className="modal-scrim" onClick={() => setFormOpen(false)} aria-label="Cerrar formulario"/><section className="person-modal" role="dialog" aria-modal="true" aria-labelledby="new-person-title"><div className="modal-head"><div><span className="eyebrow">NUEVO REGISTRO</span><h2 id="new-person-title">Registrar persona</h2><p>Solicite sólo la información necesaria para el primer contacto.</p></div><button onClick={() => setFormOpen(false)} aria-label="Cerrar">×</button></div><form onSubmit={savePerson} noValidate><div className="form-grid"><Field label="Nombre" error={errors.firstName}><input value={draft.firstName} onChange={(event) => updateDraft("firstName", event.target.value)} /></Field><Field label="Apellido" error={errors.lastName}><input value={draft.lastName} onChange={(event) => updateDraft("lastName", event.target.value)} /></Field><Field label="Celular" error={errors.phone}><input inputMode="tel" value={draft.phone} onChange={(event) => updateDraft("phone", event.target.value)} /></Field><Field label="Correo opcional" error={errors.email}><input type="email" value={draft.email} onChange={(event) => updateDraft("email", event.target.value)} /></Field><Field label="Sede" error={errors.siteId}><select value={draft.siteId} onChange={(event) => updateDraft("siteId", event.target.value)}>{sites.map((site) => <option key={site.id} value={site.id}>{site.name}</option>)}</select></Field><Field label="Estado inicial"><select value={draft.status} onChange={(event) => updateDraft("status", event.target.value as Person["status"])}>{personStatuses.slice(0, 3).map((item) => <option key={item} value={item}>{statusLabels[item]}</option>)}</select></Field></div><div className="privacy-note"><b>Privacidad</b><span>En producción este registro requerirá autorización de tratamiento de datos y permisos de sede.</span></div><div className="modal-actions"><button type="button" className="secondary-button" onClick={() => setFormOpen(false)}>Cancelar</button><button className="primary-button" type="submit">Guardar persona</button></div></form></section></div>}
  </div>;
}

function Field({ label, error, children }: { label: string; error?: string; children: React.ReactNode }) {
  return <label className={`form-field ${error ? "has-error" : ""}`}><span>{label}</span>{children}{error && <small>{error}</small>}</label>;
}
