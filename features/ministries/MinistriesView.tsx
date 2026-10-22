"use client";
/* eslint-disable react-hooks/set-state-in-effect */
import {useEffect,useState} from "react";
import {useAuth} from "@/features/auth/AuthProvider";
import {createMinistry,loadMinistries,type Ministry,type MinistrySite} from "./repository";

export function MinistriesView({selectedId,activeSiteId,canManage,onSelect}:{selectedId:string|null;activeSiteId:string;canManage:boolean;onSelect:(id:string|null)=>void}){
 const{configured,session}=useAuth();
 const[ministries,setMinistries]=useState<Ministry[]>([]);
 const[sites,setSites]=useState<MinistrySite[]>([]);
 const[selected,setSelected]=useState<Ministry|null>(null);
 const[modal,setModal]=useState(false);
 const[siteId,setSiteId]=useState("");
 const[name,setName]=useState("");
 const[description,setDescription]=useState("");
 const[error,setError]=useState("");
 const[loading,setLoading]=useState(true);
 const refresh=async()=>{
  setLoading(true);
  try{
   const data=await loadMinistries();
   setMinistries(data.ministries);setSites(data.sites);
   setSiteId(current=>current||activeSiteId||data.sites[0]?.id||"");
   setSelected(current=>data.ministries.find(x=>x.id===current?.id)??data.ministries[0]??null);
   setError("");window.dispatchEvent(new Event("ministries-changed"));
  }catch{setError("No fue posible cargar los ministerios autorizados.")}
  finally{setLoading(false)}
 };
 useEffect(()=>{if(configured&&session)void refresh()},[configured,session]);
 const save=async(e:React.FormEvent)=>{e.preventDefault();const site=sites.find(x=>x.id===siteId);if(!site)return;try{await createMinistry(site,name,description);setModal(false);setName("");setDescription("");await refresh()}catch{setError("No fue posible crear el ministerio. Verifica nombre, sede y permisos.")}};
 const visible=ministries.filter(m=>m.active&&(!activeSiteId||m.siteId===activeSiteId));
 const current=selectedId?visible.find(m=>m.id===selectedId)??null:visible.find(m=>m.id===selected?.id)??visible[0]??null;
 const inaccessible=Boolean(selectedId&&!current);
 const siteName=sites.find(x=>x.id===current?.siteId)?.name??"Sede";
 return <div className="content ministry-content">
  <div className="module-heading"><div><span className="eyebrow">SERVICIO Y DONES</span><h1>Ministerios</h1><p>Equipos reales organizados por sede, posición y periodo.</p></div>{canManage&&<button className="primary-button" onClick={()=>setModal(true)}>＋ Crear ministerio</button>}</div>
  {error&&<div className="form-error">{error}</div>}
  {loading?<div className="dashboard-loading">Cargando ministerios…</div>:inaccessible?<div className="dashboard-empty"><strong>Ministerio no disponible</strong><span>No pertenece a la sede activa o está fuera de tu alcance autorizado.</span><button onClick={()=>onSelect(null)}>Ver ministerios</button></div>:<><section className="ministry-grid">{visible.map((m,i)=><button key={m.id} className={`ministry-card ${["gold","green","rose","blue","forest","slate"][i%6]} ${current?.id===m.id?"selected":""}`} onClick={()=>onSelect(m.id)}><span>{m.name[0]}</span><div><strong>{m.name}</strong><small>{m.members} integrante{m.members===1?"":"s"}</small></div><b>→</b></button>)}</section>{current?<section className="ministry-detail panel"><div className="ministry-detail-head"><div><span className="panel-kicker">{siteName}</span><h2>{current.name}</h2><p>Liderado por {current.leader}</p></div></div><div className="ministry-stats"><div><strong>{current.members}</strong><span>integrantes activos</span></div><div><strong>{current.active?"Activo":"Inactivo"}</strong><span>estado actual</span></div></div><div className="ministry-roles"><h3>Descripción</h3><p>{current.description||"Sin descripción registrada."}</p></div></section>:<div className="dashboard-empty"><strong>Sin ministerios registrados</strong><span>Crea el primero para esta sede.</span></div>}</>}
  {modal&&<div className="modal-layer"><button className="modal-scrim" aria-label="Cerrar" onClick={()=>setModal(false)}/><form className="entity-modal" onSubmit={save}><div className="modal-title"><div><span className="eyebrow">NUEVO MINISTERIO</span><h2>Crear ministerio</h2></div><button type="button" onClick={()=>setModal(false)}>×</button></div><label><span>Sede</span><select required value={siteId} onChange={e=>setSiteId(e.target.value)}>{sites.map(s=><option key={s.id} value={s.id}>{s.name}</option>)}</select></label><label><span>Nombre</span><input required minLength={2} maxLength={120} value={name} onChange={e=>setName(e.target.value)}/></label><label><span>Descripción</span><textarea value={description} onChange={e=>setDescription(e.target.value)}/></label><button className="primary-button" type="submit">Guardar ministerio</button></form></div>}
 </div>;
}
