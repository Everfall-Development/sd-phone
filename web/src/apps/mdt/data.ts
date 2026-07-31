export type MdtSection =
    | 'home'
    | 'dispatch'
    | 'profiles'
    | 'vehicles'
    | 'reports'
    | 'cases'
    | 'warrants'
    | 'offences'
    | 'employees'
    | 'chat'
    | 'jail'
    | 'logs'
    | 'patients'
    | 'protocols';

export type DepartmentType = 'leo' | 'ems' | 'doj';

export const LEO_SECTIONS: readonly MdtSection[] = [
    'home', 'dispatch', 'profiles', 'vehicles', 'reports', 'cases',
    'warrants', 'offences', 'employees', 'chat', 'jail', 'logs',
] as const;

export const EMS_SECTIONS: readonly MdtSection[] = [
    'home', 'dispatch', 'patients', 'reports', 'cases',
    'protocols', 'employees', 'chat', 'logs',
] as const;

export function sectionsFor(type: DepartmentType | undefined): readonly MdtSection[] {
    return type === 'ems' ? EMS_SECTIONS : LEO_SECTIONS;
}

export type MdtPermission =
    | 'home.view'
    | 'persons.view'
    | 'persons.edit'
    | 'profiles.view'
    | 'vehicles.view'
    | 'vehicles.edit'
    | 'reports.view'
    | 'reports.create'
    | 'reports.edit.own'
    | 'reports.edit.any'
    | 'reports.delete'
    | 'cases.view'
    | 'cases.create'
    | 'cases.edit'
    | 'cases.delete'
    | 'warrants.view'
    | 'warrants.issue'
    | 'warrants.close'
    | 'offences.view'
    | 'offences.manage'
    | 'offences.delete'
    | 'roster.view'
    | 'employees.view'
    | 'roster.callsign'
    | 'roster.radio'
    | 'roster.grade'
    | 'roster.dismiss'
    | 'dispatch.view'
    | 'dispatch.attach'
    | 'dispatch.status'
    | 'chat.view'
    | 'chat.send'
    | 'bulletins.view'
    | 'bulletins.manage'
    | 'jail.view'
    | 'jail.book'
    | 'logs.view'
    | 'me.update'
    | 'patients.view'
    | 'patients.edit'
    | 'protocols.view'
    | 'protocols.manage';

export const SECTION_PERMISSION: Record<MdtSection, MdtPermission> = {
    home:      'home.view',
    dispatch:  'dispatch.view',
    profiles:  'persons.view',
    vehicles:  'vehicles.view',
    reports:   'reports.view',
    cases:     'cases.view',
    warrants:  'warrants.view',
    offences:  'offences.view',
    employees: 'roster.view',
    chat:      'chat.view',
    jail:      'jail.view',
    logs:      'logs.view',
    patients:  'patients.view',
    protocols: 'protocols.view',
};

export type ChargeClass = 'felony' | 'misdemeanor' | 'infraction';
export type ReportType = 'Incident' | 'Traffic' | 'Arrest' | 'Investigation' | 'Warrant';
export type InvolvedRole = 'suspect' | 'victim' | 'witness';

export type EmsReportType = 'Patient Care' | 'Trauma' | 'Cardiac' | 'Overdose' | 'Transport' | 'Death';
export type EmsInvolvedRole = 'patient' | 'witness' | 'responder' | 'other';

export type AnyReportType = ReportType | EmsReportType;
export type AnyInvolvedRole = InvolvedRole | EmsInvolvedRole;
export type ProtocolCategory = 'assessment' | 'airway' | 'cardiac' | 'trauma' | 'medical' | 'admin';
export type ProtocolPriority = 'immediate' | 'urgent' | 'routine';

export const EMS_REPORT_TYPES: readonly EmsReportType[] =
    ['Patient Care', 'Trauma', 'Cardiac', 'Overdose', 'Transport', 'Death'] as const;
export const EMS_INVOLVED_ROLES: readonly EmsInvolvedRole[] =
    ['patient', 'witness', 'responder', 'other'] as const;
export const BLOOD_TYPES: readonly string[] =
    ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'] as const;

export interface Protocol {
    code:        string;
    label:       string;
    category:    ProtocolCategory;
    priority:    ProtocolPriority;
    description: string;
    body:        string;
}

export interface MedicalFile {
    bloodType:   string;
    allergies:   string;
    conditions:  string;
    medications: string;
    notes:       string;
    dnr:         boolean;
    updatedBy:   string;
    updatedAt:   number;
}

export interface PatientRow {
    citizenid:  string;
    name:       string;
    dob:        string;
    sex:        string;
    phone:      string;
    bloodType:  string;
    hasAllergy: boolean;
    dnr:        boolean;
}

export interface PatientPaperwork {
    ref:       string;
    title:     string;
    type:      string;
    role:      string;
    createdAt: number;
}

export interface PatientDetail {
    citizenid: string;
    name:      string;
    dob:       string;
    sex:       string;
    phone:     string;
    file:      MedicalFile;
    reports:   PatientPaperwork[];
}
export type CaseStatus = 'open' | 'in_progress' | 'closed';
export type CasePriority = 'low' | 'medium' | 'high';
export type CaseRole = 'primary' | 'assisting' | 'supervisor';
export type VehicleStatus = 'valid' | 'suspended' | 'expired' | 'impounded';
export type UnitCode = '10-8' | '10-6' | '10-7' | '10-90';
export type CallPriority = 1 | 2 | 3 | 4;
export type PersonFlag = 'wanted' | 'armed' | 'gang' | 'mental_health' | 'flight_risk' | 'informant';

export const CHARGE_CLASSES: readonly ChargeClass[] = ['felony', 'misdemeanor', 'infraction'] as const;
export const VEHICLE_STATUSES: readonly VehicleStatus[] = ['valid', 'suspended', 'expired', 'impounded'] as const;
export const UNIT_CODES: readonly UnitCode[] = ['10-8', '10-6', '10-7', '10-90'] as const;
export const PERSON_FLAGS: readonly PersonFlag[] = [
    'wanted', 'armed', 'gang', 'mental_health', 'flight_risk', 'informant',
] as const;

export interface Page<T> {
    rows:     T[];
    total:    number;
    page:     number;
    pageSize: number;
}

export interface Officer {
    citizenid:  string;
    name:       string;
    callsign?:  string;
    badge?:     string;
    radio?:     string;
    rank:       string;
    gradeLevel: number;
    avatar?:    string;
    duty:       boolean;
}

export interface Department {
    job:    string;
    label:  string;
    short:  string;
    type:   'leo' | 'ems' | 'doj';
    seal:   string;
    accent: string;
}

export interface Offence {
    code:        string;
    label:       string;
    class:       ChargeClass;
    months:      number;
    fine:        number;
    description: string;
}

export interface MdtBootstrap {
    me:         Officer;
    department: Department;
    grants:     MdtPermission[];
    offences:   Offence[];
    protocols:  Protocol[];
}

export interface PersonRow {
    citizenid: string;
    name:      string;
    dob:       string;
    sex:       string;
    phone:     string;
    wanted:    boolean;
    bolo:      boolean;
    mugshot?:  string;
}

export interface Prior {
    reportRef:   string;
    reportTitle: string;
    code:        string;
    label:       string;
    class:       ChargeClass;
    count:       number;
    date:        number;
}

export interface PersonDetail extends PersonRow {
    firstname:   string;
    lastname:    string;
    nationality: string;
    job:         string;
    jobGrade:    number;
    licences:    string[];
    fingerprint: string;
    bloodtype:   string;
    notes:       string;
    flags:       PersonFlag[];
    vehicles:    VehicleRow[];
    warrants:    Warrant[];
    priors:      Prior[];
    arrests:     number;
}

export interface VehicleRow {
    plate:      string;
    model:      string;
    owner:      string;
    ownerName:  string;
    status:     VehicleStatus;
    stolen:     boolean;
    bolo:       boolean;
}

export interface VehicleDetail extends VehicleRow {
    garage:     string;
    stored:     boolean;
    notes:      string;
    points:     number;
    image?:     string;
    updatedBy?: string;
    updatedAt?: number;
}

export interface Charge {
    code:      string;
    label:     string;
    class:     ChargeClass;
    citizenid: string;
    name:      string;
    count:     number;
    months:    number;
    fine:      number;
}

export interface ChargeInput {
    code:       string;
    citizenid?: string;
    count:      number;
}

export interface Involved {
    citizenid: string;
    name:      string;
    role:      AnyInvolvedRole;
    notes?:    string;
}

export interface ReportSummary {
    ref:         string;
    title:       string;
    type:        AnyReportType;
    author:      string;
    authorCid:   string;
    callsign?:   string;
    chargeCount: number;
    createdAt:   number;
    updatedAt:   number;
}

export interface ReportDetail extends ReportSummary {
    body:        string;
    involved:    Involved[];
    charges:     Charge[];
    totalMonths: number;
    totalFine:   number;
    caseRef?:    string;
    canEdit:     boolean;
    canDelete:   boolean;
}

export interface ReportDraft {
    ref:      string | null;
    title:    string;
    type:     AnyReportType;
    body:     string;
    involved: { citizenid: string; role: AnyInvolvedRole; notes?: string }[];
    charges:  ChargeInput[];
}

export interface CaseSummary {
    ref:       string;
    title:     string;
    status:    CaseStatus;
    priority:  CasePriority;
    officers:  number;
    reports:   number;
    createdBy: string;
    createdAt: number;
    updatedAt: number;
}

export interface CaseOfficer {
    citizenid: string;
    name:      string;
    callsign?: string;
    role:      CaseRole;
}

export interface CaseNote {
    id:        number;
    author:    string;
    callsign?: string;
    body:      string;
    createdAt: number;
}

export interface CaseDetail {
    ref:       string;
    title:     string;
    status:    CaseStatus;
    priority:  CasePriority;
    summary:   string;
    createdBy: string;
    createdAt: number;
    updatedAt: number;
    officers:  CaseOfficer[];
    notes:     CaseNote[];
    reports:   { ref: string; title: string; type: AnyReportType }[];
    canEdit:   boolean;
    canDelete: boolean;
}

export interface WarrantCharge {
    code:   string;
    label:  string;
    class:  ChargeClass;
    count:  number;
    months: number;
    fine:   number;
}

export interface Warrant {
    ref:          string;
    citizenid:    string;
    subject:      string;
    reportRef?:   string;
    charges:      WarrantCharge[];
    felonies:     number;
    misdemeanors: number;
    infractions:  number;
    bond:         number;
    officer:      string;
    callsign?:    string;
    issuedAt:     number;
    expiresAt:    number;
    active:       boolean;
}

export interface ArrestRow {
    ref:        string;
    reportRef?: string;
    citizenid:  string;
    subject:    string;
    officer:    string;
    callsign?:  string;
    charges:    WarrantCharge[];
    months:     number;
    fine:       number;
    jailed:     boolean;
    fined:      boolean;
    createdAt:  number;
}

export interface JailQuote {
    months:        number;
    fine:          number;
    charges:       Charge[];
    jailedAlready: boolean;
    finedAlready:  boolean;
    jailAvailable: boolean;
    maxReduction:  number;
    maxFine:       number;
}

export interface OfficerRow {
    citizenid:  string;
    name:       string;
    callsign?:  string;
    badge?:     string;
    radio?:     string;
    rank:       string;
    gradeLevel: number;
    avatar?:    string;
    online:     boolean;
    duty:       boolean;
    hours:      number;
    reports:    number;
    arrests:    number;
}

export interface GradeOption {
    level:  number;
    label:  string;
    isboss: boolean;
}

export interface RosterPage extends Page<OfficerRow> {
    grades?: GradeOption[];
}

export interface Unit {
    citizenid:  string;
    name:       string;
    callsign:   string;
    rank:       string;
    code:       UnitCode;
    department: string;
    domain:     DepartmentType;
    callId?:    string;
    coords?:    MapPoint;
}

export interface Call {
    id:         string;
    code:       string;
    type:       string;
    priority:   CallPriority;
    location:   string;
    direction?: string;
    suspect?:   string;
    weapon?:    string;
    units:      string[];
    unitCount:  number;
    createdAt:  number;
    expiresAt:  number;
    hasCoords:  boolean;
    coords?:    MapPoint;
}

export interface DispatchState {
    units: Unit[];
    calls: Call[];
}

export interface ChatMsg {
    id:        string;
    citizenid: string;
    name:      string;
    callsign?: string;
    avatar?:   string;
    body:      string;
    createdAt: number;
}

export interface Bulletin {
    id:              number;
    title:           string;
    body:            string;
    author:          string;
    authorCid:       string;
    authorCallsign?: string;
    createdAt:       number;
    updatedAt:       number;
}

export interface AuditRow {
    id:             number;
    actor:          string;
    actorCid:       string;
    actorCallsign?: string;
    action:         string;
    entityType?:    string;
    entityId?:      string;
    details?:       Record<string, unknown>;
    createdAt:      number;
}

export interface MdtHome {
    recentReports: ReportSummary[];
    bulletins:     Bulletin[];
    units:         Unit[];
}

export interface MapPoint {
    x: number;
    y: number;
}

export interface Coords {
    x: number;
    y: number;
    z: number;
}

export function emptyPage<T>(pageSize = 25): Page<T> {
    return { rows: [], total: 0, page: 1, pageSize };
}
