export const personStatuses = [
  "VISITOR",
  "CONGREGANT",
  "MEMBER",
  "SERVER",
  "LEADER",
  "PASTOR",
  "INACTIVE",
  "TRANSFERRED",
] as const;

export type PersonStatus = (typeof personStatuses)[number];
export type DocumentType = "CC" | "TI" | "BIRTH_CERTIFICATE";

export type Person = {
  id: string;
  crcCode?: string;
  documentType?: DocumentType;
  documentNumber?: string;
  firstName: string;
  lastName: string;
  preferredName?: string;
  email?: string;
  phone: string;
  siteId: string;
  siteName: string;
  status: PersonStatus;
  firstVisitDate: string;
  birthDate: string;
  baptized?: boolean;
};

export type PersonProfileDetails = {
  family?: { id: string; name: string; memberCount: number };
  enrollments: Array<{ id: string; program: string; group: string; progress: number; status: string }>;
  ministries: Array<{ id: string; name: string; position: string }>;
};

export type PersonDraft = Pick<
  Person,
  "firstName" | "lastName" | "email" | "phone" | "siteId" | "status" | "birthDate" | "documentType" | "documentNumber"
>;
