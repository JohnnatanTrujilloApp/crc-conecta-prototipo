"use client";

import {useRef,useState} from "react";
import {saveKidsChild,searchKidsPeople,type ChildDraft,type PersonOption} from "./repository";

const emptyDraft=():ChildDraft=>({firstName:"",lastName:"",birthDate:"",sex:"",documentType:"",documentNumber:"",phone:"",email:"",guardianName:"",guardianRelationship:"GUARDIAN",guardianPhone:"",guardianEmail:"",primaryContact:true});

export function KidsChildModal({attendanceEventId,close,saved}:{attendanceEventId?:string;close:()=>void;saved:()=>Promise<void>}){
 const[draft,setDraft]=useState<ChildDraft>({...emptyDraft(),attendanceEventId});
 const[mode,setMode]=useState<"new"|"existing">("new");
 const[term,setTerm]=useState("");
 const[results,setResults]=useState<PersonOption[]>([]);
 const[selectedChild,setSelectedChild]=useState<PersonOption|null>(null);
 const[guardianTerm,setGuardianTerm]=useState("");
 const[guardians,setGuardians]=useState<PersonOption[]>([]);
 const[selectedGuardian,setSelectedGuardian]=useState<PersonOption|null>(null);
 const[childLoading,setChildLoading]=useState(false);
 const[guardianLoading,setGuardianLoading]=useState(false);
 const[busy,setBusy]=useState(false);
 const[error,setError]=useState("");
 const childRequest=useRef(0);
 const guardianRequest=useRef(0);

 const search=async(value:string,guardian=false)=>{
  const normalized=value.trim();
  const request=guardian?++guardianRequest.current:++childRequest.current;
  if(normalized.length<2){guardian?setGuardians([]):setResults([]);guardian?setGuardianLoading(false):setChildLoading(false);return}
  guardian?setGuardians([]):setResults([]);
  guardian?setGuardianLoading(true):setChildLoading(true);
  try{
   const rows=await searchKidsPeople(normalized,!guardian);
   if(request!==(guardian?guardianRequest.current:childRequest.current))return;
   guardian?setGuardians(rows):setResults(rows);
   setError("");
  }catch{
   if(request===(guardian?guardianRequest.current:childRequest.current))setError("No fue posible buscar personas autorizadas.");
  }finally{
   if(request===(guardian?guardianRequest.current:childRequest.current))(guardian?setGuardianLoading:setChildLoading)(false);
  }
 };

 const selectChild=(row:PersonOption)=>{setSelectedChild(row);setDraft(current=>({...current,existingPersonId:row.id}));setTerm(row.name);setResults([])};
 const selectGuardian=(row:PersonOption)=>{setSelectedGuardian(row);setDraft(current=>({...current,guardianPersonId:row.id,guardianName:""}));setGuardianTerm(row.name);setGuardians([])};
 const clearChild=()=>{setSelectedChild(null);setDraft(current=>({...current,existingPersonId:undefined}));setTerm("");setResults([])};
 const clearGuardian=()=>{setSelectedGuardian(null);setDraft(current=>({...current,guardianPersonId:undefined}));setGuardianTerm("");setGuardians([])};
 const submit=async(e:React.FormEvent)=>{e.preventDefault();setBusy(true);try{await saveKidsChild(draft);await saved()}catch(err){setError(err instanceof Error?err.message:"No fue posible guardar el registro Kids.")}finally{setBusy(false)}};

 return <div className="modal-layer"><button className="modal-scrim" aria-label="Cerrar registro Kids" onClick={close}/><form className="person-modal kids-modal" onSubmit={submit}>
  <div className="modal-head"><div><span className="eyebrow">REGISTRO PROTEGIDO</span><h2>Registrar niño/adolescente</h2></div><button type="button" onClick={close}>×</button></div>
  <p className="privacy-note">Solicita únicamente información necesaria. El menor no necesita correo, celular ni cuenta de acceso.</p>{error&&<div className="form-error">{error}</div>}
  <div className="kids-choice"><button type="button" className={mode==="existing"?"active":""} onClick={()=>setMode("existing")}>Buscar persona existente</button><button type="button" className={mode==="new"?"active":""} onClick={()=>{setMode("new");clearChild()}}>Registrar nueva persona</button></div>
  {mode==="existing"?<>{selectedChild?<SelectedPerson label="Persona seleccionada" person={selectedChild} clear={clearChild}/>:<><label className="form-field"><span>Nombre, apellido, documento o acudiente</span><input autoFocus value={term} onChange={e=>{setTerm(e.target.value);setDraft(current=>({...current,existingPersonId:undefined}));void search(e.target.value)}} placeholder="Escribe al menos 2 caracteres"/></label><SearchStatus loading={childLoading} term={term} results={results}/><div className="kids-search-results">{results.map(row=><button type="button" key={row.id} onClick={()=>selectChild(row)}><strong>{row.name}</strong><small>{row.documentNumber||row.birthDate||"Sin documento"}</small></button>)}</div></>}</>:<NewPersonFields draft={draft} setDraft={setDraft}/>} 
  <fieldset className="kids-guardian"><legend>Responsable / Acudiente</legend>{selectedGuardian?<SelectedPerson label="Acudiente seleccionado" person={selectedGuardian} clear={clearGuardian}/>:<><label className="form-field"><span>Buscar persona existente</span><input value={guardianTerm} onChange={e=>{setGuardianTerm(e.target.value);void search(e.target.value,true)}} placeholder="Nombre, apellido, documento o teléfono"/></label><SearchStatus loading={guardianLoading} term={guardianTerm} results={guardians}/><div className="kids-search-results compact">{guardians.map(row=><button type="button" key={row.id} onClick={()=>selectGuardian(row)}><strong>{row.name}</strong><small>{row.documentNumber||row.phone||"Sin documento"}</small></button>)}</div></>}{!draft.guardianPersonId&&<GuardianFields draft={draft} setDraft={setDraft}/>}</fieldset>
  <div className="modal-actions kids-modal-actions"><button type="button" className="secondary-button" onClick={close}>Cancelar</button><button className="primary-button" disabled={busy||mode==="existing"&&!draft.existingPersonId}>{busy?"Guardando…":"Guardar en Kids"}</button></div>
 </form></div>;
}

function SearchStatus({loading,term,results}:{loading:boolean;term:string;results:PersonOption[]}){if(term.trim().length<2)return null;return <p className="kids-search-status" aria-live="polite">{loading?"Buscando…":results.length?`${results.length} resultado${results.length===1?"":"s"}`:"No encontramos coincidencias. Puedes registrar una persona nueva."}</p>}
function SelectedPerson({label,person,clear}:{label:string;person:PersonOption;clear:()=>void}){return <div className="kids-selected"><span><small>{label}</small><strong>✓ {person.name}</strong><em>{person.documentNumber||person.phone||person.birthDate||"Sin documento"}</em></span><button type="button" onClick={clear}>Cambiar</button></div>}

function NewPersonFields({draft,setDraft}:{draft:ChildDraft;setDraft:React.Dispatch<React.SetStateAction<ChildDraft>>}){return <div className="form-grid"><label className="form-field"><span>Nombres *</span><input required value={draft.firstName} onChange={e=>setDraft({...draft,firstName:e.target.value})}/></label><label className="form-field"><span>Apellidos *</span><input required value={draft.lastName} onChange={e=>setDraft({...draft,lastName:e.target.value})}/></label><label className="form-field"><span>Fecha de nacimiento *</span><input required type="date" value={draft.birthDate} onChange={e=>setDraft({...draft,birthDate:e.target.value})}/></label><label className="form-field"><span>Sexo</span><select value={draft.sex} onChange={e=>setDraft({...draft,sex:e.target.value})}><option value="">Sin indicar</option><option value="F">Femenino</option><option value="M">Masculino</option></select></label><label className="form-field"><span>Tipo de documento</span><select value={draft.documentType} onChange={e=>setDraft({...draft,documentType:e.target.value})}><option value="">Sin documento</option><option value="BIRTH_CERTIFICATE">Registro civil</option><option value="TI">Tarjeta de identidad</option><option value="PASSPORT">Pasaporte</option><option value="OTHER">Otro</option></select></label><label className="form-field"><span>Número de documento</span><input value={draft.documentNumber} onChange={e=>setDraft({...draft,documentNumber:e.target.value})}/></label><label className="form-field"><span>Teléfono opcional</span><input value={draft.phone} onChange={e=>setDraft({...draft,phone:e.target.value})}/></label><label className="form-field"><span>Correo opcional</span><input type="email" value={draft.email} onChange={e=>setDraft({...draft,email:e.target.value})}/></label></div>}
function GuardianFields({draft,setDraft}:{draft:ChildDraft;setDraft:React.Dispatch<React.SetStateAction<ChildDraft>>}){return <div className="form-grid"><label className="form-field"><span>Nombre del acudiente</span><input value={draft.guardianName} onChange={e=>setDraft({...draft,guardianName:e.target.value})}/></label><label className="form-field"><span>Parentesco</span><select value={draft.guardianRelationship} onChange={e=>setDraft({...draft,guardianRelationship:e.target.value})}><option value="MOTHER">Madre</option><option value="FATHER">Padre</option><option value="GUARDIAN">Acudiente</option><option value="CAREGIVER">Tutor/cuidador</option></select></label><label className="form-field"><span>Teléfono</span><input value={draft.guardianPhone} onChange={e=>setDraft({...draft,guardianPhone:e.target.value})}/></label><label className="form-field"><span>Correo opcional</span><input type="email" value={draft.guardianEmail} onChange={e=>setDraft({...draft,guardianEmail:e.target.value})}/></label></div>}
