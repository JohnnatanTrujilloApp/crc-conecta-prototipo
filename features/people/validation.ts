import type { PersonDraft } from "./types";

export type PersonDraftErrors = Partial<Record<keyof PersonDraft, string>>;

export function validatePersonDraft(draft: PersonDraft): PersonDraftErrors {
  const errors: PersonDraftErrors = {};

  if (draft.firstName.trim().length < 2) errors.firstName = "Ingrese el nombre.";
  if (draft.lastName.trim().length < 2) errors.lastName = "Ingrese el apellido.";
  if (!/^\+?[0-9\s-]{7,18}$/.test(draft.phone.trim())) {
    errors.phone = "Ingrese un celular válido.";
  }
  if (draft.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(draft.email)) {
    errors.email = "Ingrese un correo válido.";
  }
  if (!draft.siteId) errors.siteId = "Seleccione una sede.";

  return errors;
}
