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

export type Person = {
  id: string;
  firstName: string;
  lastName: string;
  preferredName?: string;
  email?: string;
  phone: string;
  siteId: string;
  siteName: string;
  status: PersonStatus;
  firstVisitDate: string;
};

export type PersonDraft = Pick<
  Person,
  "firstName" | "lastName" | "email" | "phone" | "siteId" | "status"
>;
