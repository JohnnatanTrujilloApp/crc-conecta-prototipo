"use client";

import { useEffect, useMemo, useState } from "react";
import { personStatuses, type Person, type PersonDraft, type PersonProfileDetails } from "./types";
import { validatePersonDraft, type PersonDraftErrors } from "./validation";
import { useAuth } from "@/features/auth/AuthProvider";
import { createPerson,loadPeopleData,loadPersonProfile,updatePerson,type SiteOption } from "./repository";

const demoSites:SiteOption[] = [
  { id: "nemocon-demo", name: "CRC Nemocón Demo",organizationId:"demo" },
  { id: "central-demo", name: "CRC Central Demo",organizationId:"demo" },
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
  const {configured,session}=useAuth();
  const [people, setPeople] = useState(seedPeople);
  const [sites,setSites]=useState<SiteOption[]>(demoSites);
  const [loading,setLoading]=useState(configured);
  const [loadError,setLoadError]=useState("");
  const [query, setQuery] = useState("");
  const [status, setStatus] = useState<"ALL" | Person["status"]>("ALL");
  const [formOpen, setFormOpen] = useState(false);
  const [draft, setDraft] = useState<PersonDraft>(emptyDraft);
  const [errors, setErrors] = useState<PersonDraftErrors>({});
  const [notice, setNotice] = useState("");
  const [selectedPerson, setSelectedPerson] = useState<Person | null>(null);
  const [editingId,setEditingId]=useState<string|null>(null);
  const [profileDetails,setProfileDetails]=useState<PersonProfileDetails|null>(null);
  const [profileLoading,setProfileLoading]=useState(false);
  const [profileError,setProfileError]=useState("");

  useEffect(()=>{if(!configured||!session)return;let active=true;loadPeopleData().then(data=>{if(!active)return;setPeople(data.people);setSites(data.sites);setDraft(current=>({...current,siteId:data.sites[0]?.id??""}));setLoadError("")}).catch(()=>active&&setLoadError("No fue posible cargar las personas autorizadas. Verifica permisos y migraciones.")).finally(()=>active&&setLoading(false));return()=>{active=false}},[configured,session]);

  useEffect(()=>{if(!configured||!session||!selectedPerson){setProfileDetails(null);setProfileError("");return}let active=true;setProfileLoading(true);setProfileDetails(null);setProfileError("");loadPersonProfile(selectedPerson.id).then(details=>active&&setProfileDetails(details)).catch(()=>active&&setProfileError("No fue posible consultar los vínculos reales de esta persona.")).finally(()=>active&&setProfileLoading(false));return()=>{active=false}},[configured,session,selectedPerson]);

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

  const savePerson = async (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault();
    const nextErrors = validatePersonDraft(draft);
    if (Object.keys(nextErrors).length) {
      setErrors(nextErrors);
      return;
    }

    const selectedSite = sites.find((site) => site.id === draft.siteId) ?? sites[0];
    if(!selectedSite){setErrors(current=>({...current,siteId:"No hay una sede autorizada."}));return}
    try{const person=configured&&session?(editingId?await updatePerson(editingId,draft,selectedSite):await createPerson(draft,selectedSite)):{
        id: `demo-${Date.now()}`,
        ...draft,
        firstName: draft.firstName.trim(),
        lastName: draft.lastName.trim(),
        email: draft.email?.trim() || undefined,
        phone: draft.phone.trim(),
        siteName: selectedSite.name,
        firstVisitDate: new Date().toISOString().slice(0, 10),
      };setPeople((current) => editingId?current.map(item=>item.id===editingId?person:item):[person,...current]);
    setDraft(emptyDraft);
    setErrors({});
    setFormOpen(false);
    setNotice(configured&&session?`Persona ${editingId?"actualizada":"guardada"} en Supabase con el alcance de la sede.`:`Persona ${editingId?"actualizada":"agregada"} en el modo demostración.`);setEditingId(null);}catch{setLoadError("No fue posible guardar. Confirma que tu rol tenga permisos sobre esta sede.")}
  };

  const editPerson=(person:Person)=>{setEditingId(person.id);setDraft({firstName:person.firstName,lastName:person.lastName,email:person.email??"",phone:person.phone,siteId:person.siteId,status:person.status});setErrors({});setNotice("");setSelectedPerson(null);setFormOpen(true)};

  return <div className="content people-content">
    <div className="people-heading"><div><span className="eyebrow">REGISTRO MAESTRO</span><h1>Personas</h1><p>Un registro único por persona, tenga o no una cuenta de acceso.</p></div><button className="primary-button" onClick={() => { setNotice(""); setFormOpen(true); }}>＋ Registrar persona</button></div>
    <div className="demo-notice"><strong>{configured&&session?"Supabase conectado":"Modo demostración"}</strong><span>{configured&&session?"Lectura y creación protegidas por la sesión y las políticas RLS.":"Configure las variables Supabase para activar persistencia real."}</span></div>
    <section className="people-summary"><article><span>Total visible</span><strong>{filteredPeople.length}</strong></article><article><span>Visitantes</span><strong>{people.filter((person) => person.status === "VISITOR").length}</strong></article><article><span>Con cuenta</span><strong>0</strong><small>Vinculación opcional</small></article></section>
    <section className="people-panel">
      <div className="people-tools"><label className="people-search"><span>⌕</span><input value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Buscar por nombre, celular o correo" aria-label="Buscar personas"/></label><select value={status} onChange={(event) => setStatus(event.target.value as "ALL" | Person["status"])} aria-label="Filtrar por estado"><option value="ALL">Todos los estados</option>{personStatuses.map((item) => <option value={item} key={item}>{statusLabels[item]}</option>)}</select></div>
      {loading&&<div className="people-success" role="status">Cargando registros autorizados…</div>}{loadError&&<div className="auth-error" role="alert">{loadError}</div>}{notice && <div className="people-success" role="status">✓ {notice}</div>}
      {filteredPeople.length ? <div className="people-table-wrap"><table className="people-table"><thead><tr><th>Persona</th><th>Sede</th><th>Contacto</th><th>Estado</th><th>Primera visita</th><th><span className="sr-only">Acciones</span></th></tr></thead><tbody>{filteredPeople.map((person) => <tr key={person.id}><td><div className="person-cell"><span>{person.firstName[0]}{person.lastName[0]}</span><div><strong>{person.firstName} {person.lastName}</strong><small>Sin cuenta de acceso</small></div></div></td><td>{person.siteName}</td><td><strong className="contact-primary">{person.phone}</strong><small>{person.email ?? "Sin correo"}</small></td><td><span className={`person-status status-${person.status.toLowerCase()}`}>{statusLabels[person.status]}</span></td><td>{new Intl.DateTimeFormat("es-CO", { day: "2-digit", month: "short", year: "numeric" }).format(new Date(`${person.firstVisitDate}T12:00:00`))}</td><td><button className="row-action" onClick={()=>setSelectedPerson(person)} aria-label={`Ver perfil de ${person.firstName} ${person.lastName}`}>→</button></td></tr>)}</tbody></table></div>:<div className="people-empty"><strong>No encontramos personas</strong><span>Ajuste la búsqueda o registre una nueva persona.</span></div>}
    </section>
    {formOpen && <div className="modal-layer"><button className="modal-scrim" onClick={() => {setFormOpen(false);setEditingId(null)}} aria-label="Cerrar formulario"/><section className="person-modal" role="dialog" aria-modal="true" aria-labelledby="new-person-title"><div className="modal-head"><div><span className="eyebrow">{editingId?"ACTUALIZAR REGISTRO":"NUEVO REGISTRO"}</span><h2 id="new-person-title">{editingId?"Editar persona":"Registrar persona"}</h2><p>{editingId?"Los cambios se guardarán en Supabase.":"Solicite sólo la información necesaria para el primer contacto."}</p></div><button onClick={() => {setFormOpen(false);setEditingId(null)}} aria-label="Cerrar">×</button></div><form onSubmit={savePerson} noValidate><div className="form-grid"><Field label="Nombre" error={errors.firstName}><input value={draft.firstName} onChange={(event) => updateDraft("firstName", event.target.value)} /></Field><Field label="Apellido" error={errors.lastName}><input value={draft.lastName} onChange={(event) => updateDraft("lastName", event.target.value)} /></Field><Field label="Celular" error={errors.phone}><input inputMode="tel" value={draft.phone} onChange={(event) => updateDraft("phone", event.target.value)} /></Field><Field label="Correo opcional" error={errors.email}><input type="email" value={draft.email} onChange={(event) => updateDraft("email", event.target.value)} /></Field><Field label="Sede" error={errors.siteId}><select value={draft.siteId} onChange={(event) => updateDraft("siteId", event.target.value)}>{sites.map((site) => <option key={site.id} value={site.id}>{site.name}</option>)}</select></Field><Field label="Estado"><select value={draft.status} onChange={(event) => updateDraft("status", event.target.value as Person["status"])}>{personStatuses.map((item) => <option key={item} value={item}>{statusLabels[item]}</option>)}</select></Field></div><div className="privacy-note"><b>Privacidad</b><span>Este registro está protegido por los permisos y políticas RLS de la sede.</span></div><div className="modal-actions"><button type="button" className="secondary-button" onClick={() => {setFormOpen(false);setEditingId(null)}}>Cancelar</button><button className="primary-button" type="submit">{editingId?"Guardar cambios":"Guardar persona"}</button></div></form></section></div>}
    {selectedPerson&&<div className="profile-layer"><button className="profile-scrim" onClick={()=>setSelectedPerson(null)} aria-label="Cerrar perfil"/><aside className="person-profile"><div className="profile-head"><div className="profile-avatar">{selectedPerson.firstName[0]}{selectedPerson.lastName[0]}</div><div><span className="eyebrow">PERFIL DE PERSONA</span><h2>{selectedPerson.firstName} {selectedPerson.lastName}</h2><p>{selectedPerson.siteName} · {statusLabels[selectedPerson.status]}</p></div><button onClick={()=>setSelectedPerson(null)} aria-label="Cerrar">×</button></div><div className="profile-code"><span>Código CRC</span><strong>{selectedPerson.crcCode??"Pendiente de asignación"}</strong><small>{selectedPerson.crcCode?"Identificador real":"Sin código"}</small></div><section className="profile-section"><h3>Información de contacto</h3><div className="profile-facts"><p><span>Celular</span><strong>{selectedPerson.phone}</strong></p><p><span>Correo</span><strong>{selectedPerson.email??"Sin correo"}</strong></p><p><span>Primera visita</span><strong>{selectedPerson.firstVisitDate}</strong></p><p><span>Bautismo</span><strong>{selectedPerson.baptized?"Sí":"No registrado"}</strong></p></div></section>{profileLoading?<section className="profile-section profile-empty"><strong>Consultando vínculos reales…</strong></section>:profileError?<section className="profile-section profile-empty"><strong>{profileError}</strong></section>:<><section className="profile-section"><h3>Familia</h3>{profileDetails?.family?<div className="profile-link"><span>⌂</span><div><strong>{profileDetails.family.name}</strong><small>{profileDetails.family.memberCount} integrante{profileDetails.family.memberCount===1?"":"s"} vinculado{profileDetails.family.memberCount===1?"":"s"}</small></div></div>:<div className="profile-empty"><strong>Sin familia vinculada</strong><span>No existen relaciones familiares registradas para esta persona.</span></div>}</section><section className="profile-section"><h3>Proceso y servicio</h3>{profileDetails?.enrollments.length||profileDetails?.ministries.length?<>{profileDetails.enrollments.map(item=><div className="profile-progress" key={item.id}><div><span>{item.program} · {item.group}</span><strong>{item.progress}%</strong></div><i><b style={{width:`${item.progress}%`}}/></i></div>)}{profileDetails.ministries.length>0&&<div className="profile-tags">{profileDetails.ministries.map(item=><span key={item.id}>{item.name} · {item.position}</span>)}</div>}</>:<div className="profile-empty"><strong>Sin proceso ni servicio registrado</strong><span>No existen matrículas o ministerios vinculados.</span></div>}</section></>}<div className="profile-actions"><button className="secondary-button" onClick={()=>editPerson(selectedPerson)}>Editar perfil</button></div></aside></div>}
  </div>;
}

function Field({ label, error, children }: { label: string; error?: string; children: React.ReactNode }) {
  return <label className={`form-field ${error ? "has-error" : ""}`}><span>{label}</span>{children}{error && <small>{error}</small>}</label>;
}
