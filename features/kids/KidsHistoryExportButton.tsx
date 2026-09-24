"use client";

import {useState} from "react";
import ExcelJS from "exceljs";
import type {KidsContext} from "./repository";
import {buildKidsReport,kidsReportFileName} from "./kidsReport";

export function KidsHistoryExportButton({context}:{context:KidsContext|null}){
 const[busy,setBusy]=useState(false),[error,setError]=useState("");
 const report=context?buildKidsReport(context):null;
 const download=async()=>{
  if(!context||!report?.summary.length||busy)return;
  setBusy(true);setError("");
  try{
   const workbook=new ExcelJS.Workbook();workbook.creator="CRC Conecta";
   const summary=workbook.addWorksheet("Resumen",{views:[{state:"frozen",ySplit:1}]});
   summary.columns=[{header:"Niño/adolescente",key:"name",width:30},{header:"Edad",key:"age",width:10},{header:"Grupo",key:"group",width:22},{header:"Acudiente",key:"guardian",width:30},{header:"Teléfono acudiente",key:"guardianPhone",width:22},{header:"Total asistencias",key:"presentCount",width:20},{header:"Total ausencias",key:"absentCount",width:18},{header:"Última asistencia",key:"lastAttendance",width:20},{header:"Seguimiento",key:"followUp",width:28}];
   report.summary.forEach(row=>summary.addRow(row));
   const detail=workbook.addWorksheet("Detalle asistencia",{views:[{state:"frozen",ySplit:1}]});
   detail.columns=[{header:"Fecha",key:"date",width:17},{header:"Hora",key:"time",width:16},{header:"Sesión / evento",key:"session",width:34},{header:"Niño/adolescente",key:"child",width:30},{header:"Estado de asistencia",key:"status",width:24}];
   report.detail.forEach(row=>detail.addRow(row));
   for(const sheet of [summary,detail]){sheet.autoFilter={from:"A1",to:sheet.getRow(1).getCell(sheet.columnCount).address};sheet.getRow(1).eachCell(cell=>{cell.font={bold:true,color:{argb:"FFFFFFFF"}};cell.fill={type:"pattern",pattern:"solid",fgColor:{argb:"FF1F705B"}}});sheet.getRow(1).height=24;sheet.eachRow((row,index)=>{row.alignment={vertical:"middle",wrapText:true};if(index>1&&index%2===0)row.eachCell(cell=>{cell.fill={type:"pattern",pattern:"solid",fgColor:{argb:"FFF2F7F5"}}})})}
   const buffer=await workbook.xlsx.writeBuffer();const url=URL.createObjectURL(new Blob([buffer],{type:"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"}));
   try{const link=document.createElement("a");link.href=url;link.download=kidsReportFileName(context.site.name);document.body.appendChild(link);link.click();link.remove()}finally{setTimeout(()=>URL.revokeObjectURL(url),0)}
  }catch{setError("No fue posible generar el Excel. Intenta nuevamente.")}finally{setBusy(false)}
 };
 return <div className="kids-export-action"><button type="button" className="secondary-button" disabled={!report?.summary.length||busy} onClick={()=>void download()}>{busy?"Generando…":"↓ Descargar Excel"}</button>{error&&<span role="alert" className="kids-export-error">{error}</span>}</div>;
}
