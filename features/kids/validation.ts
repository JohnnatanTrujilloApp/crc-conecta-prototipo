export type KidsBirthDateError="KIDS_BIRTH_DATE_REQUIRED"|"KIDS_BIRTH_DATE_FUTURE"|"KIDS_AGE_NOT_ALLOWED";

const civilDate=(value:string)=>{
 const match=/^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
 if(!match)return null;
 const year=Number(match[1]),month=Number(match[2]),day=Number(match[3]);
 const date=new Date(year,month-1,day);
 return date.getFullYear()===year&&date.getMonth()===month-1&&date.getDate()===day?{year,month,day}:null;
};

export function validateKidsBirthDate(value:string|null|undefined,today=new Date()):KidsBirthDateError|null{
 if(!value)return "KIDS_BIRTH_DATE_REQUIRED";
 const birth=civilDate(value);
 if(!birth)return "KIDS_BIRTH_DATE_REQUIRED";
 const current={year:today.getFullYear(),month:today.getMonth()+1,day:today.getDate()};
 if(birth.year>current.year||birth.year===current.year&&(birth.month>current.month||birth.month===current.month&&birth.day>current.day))return "KIDS_BIRTH_DATE_FUTURE";
 const age=current.year-birth.year-(current.month<birth.month||current.month===birth.month&&current.day<birth.day?1:0);
 return age>=18?"KIDS_AGE_NOT_ALLOWED":null;
}

export const kidsErrorMessage:Record<KidsBirthDateError|"KIDS_FAMILY_AMBIGUOUS"|"KIDS_GUARDIAN_RELATIONSHIP_REQUIRED",string>={
 KIDS_BIRTH_DATE_REQUIRED:"La persona necesita una fecha de nacimiento para vincularse a Kids.",
 KIDS_BIRTH_DATE_FUTURE:"La fecha de nacimiento no puede ser posterior a hoy.",
 KIDS_AGE_NOT_ALLOWED:"CRC Kids está configurado para menores de 18 años.",
 KIDS_FAMILY_AMBIGUOUS:"La persona tiene más de una relación familiar posible. Revisa su familia antes de continuar.",
 KIDS_GUARDIAN_RELATIONSHIP_REQUIRED:"Selecciona el parentesco del responsable."
};

export function explainKidsError(error:unknown){
 const detail=error instanceof Error?error.message:String(error);
 const code=Object.keys(kidsErrorMessage).find(item=>detail.includes(item)) as keyof typeof kidsErrorMessage|undefined;
 return code?kidsErrorMessage[code]:"No fue posible guardar el registro Kids. Revisa los datos e inténtalo de nuevo.";
}
