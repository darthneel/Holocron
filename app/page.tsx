"use client";

import {
  ArrowLeft,
  ArrowDown,
  ArrowRight,
  ArrowUp,
  BookOpen,
  BriefcaseBusiness,
  Building2,
  CalendarCheck,
  CalendarDays,
  CheckCircle2,
  CircleHelp,
  Clock3,
  Database,
  Inbox,
  Link2,
  LogOut,
  MessageSquareText,
  MapPin,
  Plus,
  Save,
  Send,
  Sparkles,
  ScrollText,
  ShieldCheck,
  UserPlus,
  UserRound,
  UserRoundPlus,
  UsersRound,
  X,
  XCircle,
} from "lucide-react";
import { FormEvent, useState } from "react";

const API_URL = process.env.NEXT_PUBLIC_API_URL ?? "http://localhost:9292";
const OFFICE_TIME_ZONE = "America/Denver";

type Session = {
  email: string;
  known_member: boolean;
  display_name: string;
  role: string;
};

type WorkspaceMember = {
  id: string;
  display_name: string;
  email: string | null;
  job_title: string | null;
  role: string;
  status: string;
};

type AuditEvent = {
  id: string;
  event_type: string;
  subject_type?: string;
  payload: Record<string, string | number>;
  occurred_at: string;
};

type Foundation = {
  workspace: {
    id: string;
    slug: string;
    name: string;
    timezone: string;
    retention_days: number;
  };
  principal: {
    id: string;
    display_name: string;
    email: string | null;
    title: string;
    status: string;
  } | null;
  members: WorkspaceMember[];
  audit_events: AuditEvent[];
};

type RequestListItem = {
  id: string;
  status: string;
  lock_version: number;
  requester_name: string;
  requester_organization: string | null;
  purpose: string;
  requested_duration_minutes: number;
  source_channel: string;
  assigned_scheduler_name: string;
  candidate_window_count: number;
  created_at: string;
  updated_at: string;
};

type WorkflowReason = {
  code: string;
  label: string;
};

type AvailableTransition = {
  to_status: string;
  label: string;
  reasons: WorkflowReason[];
};

type StateTransition = {
  id: string;
  from_status: string | null;
  to_status: string;
  reason_code: string;
  notes: string | null;
  actor: {
    id: string;
    display_name: string;
  } | null;
  decision: {
    id: string;
    decision: string;
    reason_code: string;
    decided_by_workspace_member_id: string;
    decided_at: string;
  } | null;
  correlation_id: string;
  occurred_at: string;
};

type Participant = {
  id?: string;
  name: string;
  email: string;
  organization: string;
  role: string;
};

type CandidateWindow = {
  id?: string;
  candidate_date: string;
  starts_at: string | null;
  ends_at: string | null;
  notes: string;
};

type RelationshipPerson = {
  id: string;
  display_name: string;
  primary_email: string | null;
  primary_phone: string | null;
  job_title: string | null;
  notes: string | null;
  organization: {id: string; name: string} | null;
  request_count: number;
  interaction_count: number;
  request_role?: string;
  created_at: string;
  updated_at: string;
};

type RelationshipOrganization = {
  id: string;
  name: string;
  website_url: string | null;
  notes: string | null;
  people_count: number;
  request_count: number;
  interaction_count: number;
  request_role?: string;
  created_at: string;
  updated_at: string;
};

type RelationshipInteraction = {
  id: string;
  interaction_type: string;
  summary: string;
  person: {id: string; display_name: string} | null;
  scheduling_request_id: string | null;
  author: {id: string; display_name: string} | null;
  source_type: string;
  source_id: string | null;
  occurred_at: string;
  current_request?: boolean;
};

type RelationshipsOverview = {
  people: RelationshipPerson[];
  organizations: RelationshipOrganization[];
  interactions: RelationshipInteraction[];
  counts: {
    people: number;
    organizations: number;
    linked_people: number;
    interactions: number;
  };
};

type RelationshipContext = {
  people: RelationshipPerson[];
  organizations: RelationshipOrganization[];
  interactions: RelationshipInteraction[];
};

type SchedulingRequest = {
  id: string;
  status: string;
  lock_version: number;
  requester: {
    name: string;
    email: string | null;
    organization: string | null;
  };
  purpose: string;
  requested_duration_minutes: number;
  availability_notes: string | null;
  source_channel: string;
  original_request_text: string | null;
  assigned_scheduler: WorkspaceMember | null;
  participants: Participant[];
  candidate_windows: CandidateWindow[];
  request_extraction: {
    id: string;
    provider: string;
    model: string;
    prompt_version: string;
    accepted_at: string;
  } | null;
  relationship_context: RelationshipContext;
  available_transitions: AvailableTransition[];
  transitions: StateTransition[];
  audit_events: AuditEvent[];
  created_at: string;
  updated_at: string;
};

type MeetingSummary = {
  id: string;
  scheduling_request_id: string;
  title: string;
  starts_at: string;
  ends_at: string;
  location: string | null;
};

type BriefingSource = {
  source_type: string;
  source_id: string;
  source_label: string;
  source_excerpt: string | null;
};

type BriefingSectionData = {
  id: string;
  section_type: string;
  title: string;
  body: string;
  position: number;
  sources: BriefingSource[];
};

type BriefingVersion = {
  id: string;
  version_number: number;
  status: string;
  change_summary: string | null;
  created_by: {id: string; display_name: string};
  review: {
    decision: string;
    notes: string | null;
    reviewed_by: {id: string; display_name: string};
    reviewed_at: string;
  } | null;
  sections: BriefingSectionData[];
  created_at: string;
};

type BriefingListItem = {
  id: string;
  status: string;
  lock_version: number;
  current_version_number: number;
  meeting: MeetingSummary;
  requester_name: string;
  requester_organization: string | null;
  purpose: string;
  section_count: number;
  updated_at: string;
};

type BriefingDetail = {
  id: string;
  status: string;
  lock_version: number;
  current_version_number: number;
  meeting: MeetingSummary;
  request: {
    id: string;
    requester_name: string;
    requester_organization: string | null;
    purpose: string;
    status: string;
  };
  created_by: {id: string; display_name: string};
  versions: BriefingVersion[];
  source_catalog: BriefingSource[];
  created_at: string;
  updated_at: string;
};

type BriefingSectionForm = {
  section_type: string;
  title: string;
  body: string;
  sources: Array<{source_type: string; source_id: string}>;
};

type RequestForm = {
  requester_name: string;
  requester_email: string;
  requester_organization: string;
  purpose: string;
  requested_duration_minutes: string;
  availability_notes: string;
  source_channel: string;
  original_request_text: string;
  assigned_scheduler_member_id: string;
  participants: Participant[];
  candidate_windows: CandidateWindow[];
};

type RequestExtraction = {
  id: string;
  status: "succeeded" | "failed" | "refused";
  provider: string;
  model: string;
  prompt_version: string;
  proposal: {
    requester: {
      name: string | null;
      email: string | null;
      organization: string | null;
    };
    purpose: string | null;
    requested_duration_minutes: number | null;
    availability_notes: string | null;
    participants: Array<{
      name: string | null;
      email: string | null;
      organization: string | null;
      role: string | null;
    }>;
    candidate_windows: Array<{
      candidate_date: string | null;
      starts_at: string | null;
      ends_at: string | null;
      notes: string | null;
    }>;
    warnings: string[];
  } | null;
  warnings: string[];
  validation_errors: Record<string, string>;
  failure_reason: string | null;
  attempt_count: number;
  scheduling_request_id: string | null;
  created_at: string;
  completed_at: string;
  accepted_at: string | null;
};

const roleLabels: Record<string, string> = {
  owner: "Owner",
  chief_of_staff: "Chief of Staff",
  scheduler: "Scheduler",
  advisor: "Advisor",
  principal: "Principal",
  viewer: "Viewer",
};

const sourceLabels: Record<string, string> = {
  email: "Email",
  phone: "Phone",
  web: "Web form",
  staff: "Staff referral",
  other: "Other",
};

const statusLabels: Record<string, string> = {
  submitted: "Submitted",
  needs_information: "Needs information",
  under_review: "Under review",
  approved: "Approved",
  declined: "Declined",
  scheduled: "Scheduled",
};

const briefingStatusLabels: Record<string, string> = {
  draft: "Draft",
  in_review: "In review",
  approved: "Approved",
  changes_requested: "Changes requested",
};

const briefingSectionLabels: Record<string, string> = {
  overview: "Overview",
  attendees: "Attendees",
  relationship_context: "Relationship context",
  prior_history: "Prior history",
  objectives: "Objectives",
  logistics: "Logistics",
  notes: "Notes",
};

function formatRole(role: string) {
  return roleLabels[role] ?? role.replaceAll("_", " ");
}

function formatEvent(eventType: string) {
  return eventType
    .split(".")
    .map((word) => word.replaceAll("_", " "))
    .join(" · ");
}

function formatStatus(status: string) {
  return statusLabels[status] ?? status.replaceAll("_", " ");
}

function formatReason(reasonCode: string) {
  return reasonCode
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}

function formatRelationshipType(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}

function initials(name: string) {
  return name
    .split(" ")
    .map((part) => part[0])
    .join("")
    .slice(0, 2)
    .toUpperCase();
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat("en", {
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
    timeZone: OFFICE_TIME_ZONE,
    timeZoneName: "short",
  }).format(new Date(value));
}

function datetimeLocalValue(value: string | null) {
  if (!value) return "";
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: OFFICE_TIME_ZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(value));
  const part = (type: Intl.DateTimeFormatPartTypes) => parts.find((candidate) => candidate.type === type)?.value ?? "";
  return `${part("year")}-${part("month")}-${part("day")}T${part("hour")}:${part("minute")}`;
}

function officeLocalToIso(value: string) {
  const match = value.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})$/);
  if (!match) return "";
  const [, year, month, day, hour, minute] = match.map(Number);
  const localAsUtc = Date.UTC(year, month - 1, day, hour, minute);

  function offsetAt(timestamp: number) {
    const parts = new Intl.DateTimeFormat("en-CA", {
      timeZone: OFFICE_TIME_ZONE,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hourCycle: "h23",
    }).formatToParts(new Date(timestamp));
    const values = Object.fromEntries(parts.map((candidate) => [candidate.type, candidate.value]));
    return Date.UTC(
      Number(values.year),
      Number(values.month) - 1,
      Number(values.day),
      Number(values.hour),
      Number(values.minute),
      Number(values.second),
    ) - timestamp;
  }

  let offset = offsetAt(localAsUtc);
  let timestamp = localAsUtc - offset;
  offset = offsetAt(timestamp);
  timestamp = localAsUtc - offset;
  return new Date(timestamp).toISOString();
}

function blankRequestForm(members: WorkspaceMember[]): RequestForm {
  const scheduler = members.find(
    (member) => member.status === "active" && ["owner", "chief_of_staff", "scheduler"].includes(member.role),
  );

  return {
    requester_name: "",
    requester_email: "",
    requester_organization: "",
    purpose: "",
    requested_duration_minutes: "30",
    availability_notes: "",
    source_channel: "email",
    original_request_text: "",
    assigned_scheduler_member_id: scheduler?.id ?? "",
    participants: [],
    candidate_windows: [],
  };
}

function requestFormFromDetail(request: SchedulingRequest): RequestForm {
  return {
    requester_name: request.requester.name,
    requester_email: request.requester.email ?? "",
    requester_organization: request.requester.organization ?? "",
    purpose: request.purpose,
    requested_duration_minutes: String(request.requested_duration_minutes),
    availability_notes: request.availability_notes ?? "",
    source_channel: request.source_channel,
    original_request_text: request.original_request_text ?? "",
    assigned_scheduler_member_id: request.assigned_scheduler?.id ?? "",
    participants: request.participants.map((participant) => ({
      name: participant.name,
      email: participant.email ?? "",
      organization: participant.organization ?? "",
      role: participant.role,
    })),
    candidate_windows: request.candidate_windows.map((window) => ({
      candidate_date: window.candidate_date,
      starts_at: datetimeLocalValue(window.starts_at),
      ends_at: datetimeLocalValue(window.ends_at),
      notes: window.notes ?? "",
    })),
  };
}

function requestFormFromExtraction(extraction: RequestExtraction, inputText: string, members: WorkspaceMember[]): RequestForm {
  const proposal = extraction.proposal!;
  return {
    ...blankRequestForm(members),
    requester_name: proposal.requester.name ?? "",
    requester_email: proposal.requester.email ?? "",
    requester_organization: proposal.requester.organization ?? "",
    purpose: proposal.purpose ?? "",
    requested_duration_minutes: proposal.requested_duration_minutes === null ? "" : String(proposal.requested_duration_minutes),
    availability_notes: proposal.availability_notes ?? "",
    source_channel: "email",
    original_request_text: inputText.trim(),
    participants: proposal.participants.map((participant) => ({
      name: participant.name ?? "",
      email: participant.email ?? "",
      organization: participant.organization ?? "",
      role: participant.role ?? "",
    })),
    candidate_windows: proposal.candidate_windows.map((window) => ({
      candidate_date: window.candidate_date ?? "",
      starts_at: datetimeLocalValue(window.starts_at),
      ends_at: datetimeLocalValue(window.ends_at),
      notes: window.notes ?? "",
    })),
  };
}

function briefingSectionsFromVersion(version: BriefingVersion): BriefingSectionForm[] {
  return version.sections.map((section) => ({
    section_type: section.section_type,
    title: section.title,
    body: section.body,
    sources: section.sources.map((source) => ({
      source_type: source.source_type,
      source_id: source.source_id,
    })),
  }));
}

export default function Home() {
  const [email, setEmail] = useState("neelp22@gmail.com");
  const [session, setSession] = useState<Session | null>(null);
  const [foundation, setFoundation] = useState<Foundation | null>(null);
  const [requests, setRequests] = useState<RequestListItem[]>([]);
  const [relationships, setRelationships] = useState<RelationshipsOverview | null>(null);
  const [briefings, setBriefings] = useState<BriefingListItem[]>([]);
  const [selectedRequest, setSelectedRequest] = useState<SchedulingRequest | null>(null);
  const [selectedBriefing, setSelectedBriefing] = useState<BriefingDetail | null>(null);
  const [form, setForm] = useState<RequestForm | null>(null);
  const [mode, setMode] = useState<"inbox" | "extract" | "new" | "edit">("inbox");
  const [extractionText, setExtractionText] = useState("");
  const [requestExtraction, setRequestExtraction] = useState<RequestExtraction | null>(null);
  const [error, setError] = useState("");
  const [formErrors, setFormErrors] = useState<Record<string, string>>({});
  const [isLoading, setIsLoading] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [isExtracting, setIsExtracting] = useState(false);
  const [isTransitioning, setIsTransitioning] = useState(false);
  const [isRelationshipSaving, setIsRelationshipSaving] = useState(false);
  const [isBriefingSaving, setIsBriefingSaving] = useState(false);

  const canMutate = Boolean(session?.known_member);
  const schedulerMembers = foundation?.members.filter(
    (member) => member.status === "active" && ["owner", "chief_of_staff", "scheduler"].includes(member.role),
  ) ?? [];

  async function loadWorkspace() {
    const [foundationResponse, requestsResponse, relationshipsResponse, briefingsResponse] = await Promise.all([
      fetch(`${API_URL}/api/foundation`),
      fetch(`${API_URL}/api/scheduling-requests`),
      fetch(`${API_URL}/api/relationships`),
      fetch(`${API_URL}/api/briefings`),
    ]);
    const [foundationBody, requestsBody, relationshipsBody, briefingsBody] = await Promise.all([
      foundationResponse.json(),
      requestsResponse.json(),
      relationshipsResponse.json(),
      briefingsResponse.json(),
    ]);

    if (!foundationResponse.ok) {
      throw new Error(foundationBody.error ?? "Unable to load the workspace.");
    }
    if (!requestsResponse.ok) {
      throw new Error(requestsBody.error ?? "Unable to load scheduling requests.");
    }
    if (!relationshipsResponse.ok) {
      throw new Error(relationshipsBody.error ?? "Unable to load relationships.");
    }
    if (!briefingsResponse.ok) {
      throw new Error(briefingsBody.error ?? "Unable to load briefings.");
    }

    setFoundation(foundationBody);
    setRequests(requestsBody.requests);
    setRelationships(relationshipsBody);
    setBriefings(briefingsBody.briefings);
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setError("");
    setIsLoading(true);

    try {
      const sessionResponse = await fetch(`${API_URL}/api/fake-session`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email }),
      });
      const sessionBody = await sessionResponse.json();

      if (!sessionResponse.ok) {
        throw new Error(sessionBody.error ?? "Unable to continue.");
      }

      setSession(sessionBody);
      await loadWorkspace();
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "Unable to open the workspace.",
      );
    } finally {
      setIsLoading(false);
    }
  }

  async function selectRequest(id: string) {
    setError("");
    setFormErrors({});
    setRequestExtraction(null);
    setExtractionText("");
    setMode("inbox");
    try {
      const response = await fetch(`${API_URL}/api/scheduling-requests/${id}`);
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? "Unable to load request.");
      setSelectedRequest(body);
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Unable to load request.");
    }
  }

  async function selectBriefing(id: string, scroll = false) {
    setError("");
    try {
      const response = await fetch(`${API_URL}/api/briefings/${id}`);
      const body = await response.json();
      if (!response.ok) throw new Error(body.error ?? "Unable to load briefing.");
      setSelectedBriefing(body);
      if (scroll) {
        window.setTimeout(() => document.getElementById("briefings")?.scrollIntoView({behavior: "smooth"}), 0);
      }
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Unable to load briefing.");
    }
  }

  function beginNewRequest() {
    if (!foundation) return;
    setSelectedRequest(null);
    setRequestExtraction(null);
    setExtractionText("");
    setForm(blankRequestForm(foundation.members));
    setFormErrors({});
    setError("");
    setMode("new");
  }

  function beginRequestExtraction() {
    setSelectedRequest(null);
    setForm(null);
    setRequestExtraction(null);
    setExtractionText("");
    setFormErrors({});
    setError("");
    setMode("extract");
  }

  async function extractRequest(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!session || !foundation) return;

    setIsExtracting(true);
    setRequestExtraction(null);
    setError("");
    try {
      const response = await fetch(`${API_URL}/api/request-extractions`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Holocron-Actor-Email": session.email,
        },
        body: JSON.stringify({input_text: extractionText}),
      });
      const body = await response.json();
      if (!response.ok) {
        const detail = body.fields ? Object.values(body.fields).join(" ") : body.error;
        throw new Error(detail ?? "Unable to extract the request.");
      }

      const extraction = body as RequestExtraction;
      setRequestExtraction(extraction);
      if (extraction.status !== "succeeded" || !extraction.proposal) {
        throw new Error(extraction.failure_reason ?? "The extraction did not produce a reviewable draft.");
      }

      setForm(requestFormFromExtraction(extraction, extractionText, foundation.members));
      setMode("new");
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Unable to extract the request.");
    } finally {
      setIsExtracting(false);
    }
  }

  function beginEditing() {
    if (!selectedRequest) return;
    setRequestExtraction(null);
    setExtractionText("");
    setForm(requestFormFromDetail(selectedRequest));
    setFormErrors({});
    setError("");
    setMode("edit");
  }

  function cancelEditing() {
    setForm(null);
    setRequestExtraction(null);
    setExtractionText("");
    setFormErrors({});
    setMode("inbox");
  }

  function formPayload() {
    if (!form) return null;
    return {
      ...form,
      ...(mode === "edit" && selectedRequest
        ? {expected_lock_version: selectedRequest.lock_version}
        : {}),
      ...(mode === "new" && requestExtraction?.status === "succeeded"
        ? {request_extraction_id: requestExtraction.id}
        : {}),
      requested_duration_minutes: Number(form.requested_duration_minutes),
      participants: form.participants,
      candidate_windows: form.candidate_windows.map((window) => ({
        ...window,
        starts_at: window.starts_at ? officeLocalToIso(window.starts_at) : "",
        ends_at: window.ends_at ? officeLocalToIso(window.ends_at) : "",
      })),
    };
  }

  async function saveRequest(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!form || !session) return;

    setIsSaving(true);
    setFormErrors({});
    setError("");

    try {
      const isEditing = mode === "edit" && selectedRequest;
      const response = await fetch(
        isEditing
          ? `${API_URL}/api/scheduling-requests/${selectedRequest.id}`
          : `${API_URL}/api/scheduling-requests`,
        {
          method: isEditing ? "PATCH" : "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Holocron-Actor-Email": session.email,
          },
          body: JSON.stringify(formPayload()),
        },
      );
      const body = await response.json();

      if (!response.ok) {
        if (body.fields) setFormErrors(body.fields);
        throw new Error(body.error ?? "Unable to save scheduling request.");
      }

      setSelectedRequest(body);
      setMode("inbox");
      setForm(null);
      setRequestExtraction(null);
      setExtractionText("");
      await loadWorkspace();
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Unable to save scheduling request.");
    } finally {
      setIsSaving(false);
    }
  }

  async function transitionRequest(toStatus: string, reasonCode: string, notes: string) {
    if (!selectedRequest || !session) return false;

    setIsTransitioning(true);
    setError("");

    try {
      const response = await fetch(
        `${API_URL}/api/scheduling-requests/${selectedRequest.id}/transitions`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-Holocron-Actor-Email": session.email,
          },
          body: JSON.stringify({
            to_status: toStatus,
            reason_code: reasonCode,
            notes,
            expected_lock_version: selectedRequest.lock_version,
          }),
        },
      );
      const body = await response.json();

      if (!response.ok) {
        if (response.status === 409) {
          await selectRequest(selectedRequest.id);
          await loadWorkspace();
        }
        throw new Error(body.error ?? "Unable to update request status.");
      }

      setSelectedRequest(body);
      await loadWorkspace();
      return true;
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Unable to update request status.");
      return false;
    } finally {
      setIsTransitioning(false);
    }
  }

  async function saveRelationship(resource: string, payload: Record<string, unknown>, method: "POST" | "PATCH" = "POST") {
    if (!session) return false;

    setIsRelationshipSaving(true);
    setError("");
    try {
      const response = await fetch(`${API_URL}/api/relationships/${resource}`, {
        method,
        headers: {
          "Content-Type": "application/json",
          "X-Holocron-Actor-Email": session.email,
        },
        body: JSON.stringify(payload),
      });
      const body = await response.json();
      if (!response.ok) {
        const detail = body.fields ? Object.values(body.fields).join(" ") : body.error;
        throw new Error(detail ?? "Unable to save relationship record.");
      }

      await loadWorkspace();
      if (selectedRequest) await selectRequest(selectedRequest.id);
      return true;
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Unable to save relationship record.");
      return false;
    } finally {
      setIsRelationshipSaving(false);
    }
  }

  async function sendBriefingCommand(path: string, payload: Record<string, unknown>) {
    if (!session) throw new Error("Sign in before updating a briefing.");

    const response = await fetch(`${API_URL}${path}`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Holocron-Actor-Email": session.email,
      },
      body: JSON.stringify(payload),
    });
    const body = await response.json();
    if (!response.ok) {
      if (response.status === 409 && selectedBriefing) await selectBriefing(selectedBriefing.id);
      const detail = body.fields ? Object.values(body.fields).join(" ") : body.error;
      throw new Error(detail ?? "Unable to update briefing.");
    }

    setSelectedBriefing(body);
    await loadWorkspace();
    return body as BriefingDetail;
  }

  async function briefingCommand(path: string, payload: Record<string, unknown>) {
    if (!session) return false;

    setIsBriefingSaving(true);
    setError("");
    try {
      await sendBriefingCommand(path, payload);
      return true;
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Unable to update briefing.");
      return false;
    } finally {
      setIsBriefingSaving(false);
    }
  }

  async function createMeetingAndBriefing(payload: Record<string, unknown>) {
    if (!selectedRequest || !session) return false;

    setIsBriefingSaving(true);
    setError("");
    try {
      const createdBriefing = await sendBriefingCommand(
        `/api/scheduling-requests/${selectedRequest.id}/meeting`,
        payload,
      );
      window.setTimeout(() => document.getElementById("briefings")?.scrollIntoView({behavior: "smooth"}), 0);

      try {
        await sendBriefingCommand(`/api/briefings/${createdBriefing.id}/generate`, {
          expected_lock_version: createdBriefing.lock_version,
        });
      } catch (generationError) {
        const detail = generationError instanceof Error ? generationError.message : "Unable to generate the briefing.";
        setError(`Meeting created with a fallback draft. Automatic briefing generation failed: ${detail}`);
      }

      return true;
    } catch (requestError) {
      setError(requestError instanceof Error ? requestError.message : "Unable to create the meeting.");
      return false;
    } finally {
      setIsBriefingSaving(false);
    }
  }

  async function saveBriefingVersion(payload: Record<string, unknown>) {
    if (!selectedBriefing) return false;
    return briefingCommand(`/api/briefings/${selectedBriefing.id}/versions`, payload);
  }

  async function generateBriefing() {
    if (!selectedBriefing) return false;
    return briefingCommand(`/api/briefings/${selectedBriefing.id}/generate`, {
      expected_lock_version: selectedBriefing.lock_version,
    });
  }

  async function submitBriefingForReview() {
    if (!selectedBriefing) return false;
    return briefingCommand(`/api/briefings/${selectedBriefing.id}/submit-review`, {
      expected_lock_version: selectedBriefing.lock_version,
    });
  }

  async function reviewBriefing(decision: string, notes: string) {
    if (!selectedBriefing) return false;
    return briefingCommand(`/api/briefings/${selectedBriefing.id}/reviews`, {
      expected_lock_version: selectedBriefing.lock_version,
      decision,
      notes,
    });
  }

  function signOut() {
    setSession(null);
    setFoundation(null);
    setRequests([]);
    setRelationships(null);
    setBriefings([]);
    setSelectedRequest(null);
    setSelectedBriefing(null);
    setForm(null);
    setRequestExtraction(null);
    setExtractionText("");
    setError("");
    setFormErrors({});
    setIsTransitioning(false);
    setIsExtracting(false);
    setIsRelationshipSaving(false);
    setIsBriefingSaving(false);
    setMode("inbox");
  }

  function updateForm(field: keyof Omit<RequestForm, "participants" | "candidate_windows">, value: string) {
    setForm((current) => current ? {...current, [field]: value} : current);
  }

  function updateParticipant(index: number, field: keyof Participant, value: string) {
    setForm((current) => {
      if (!current) return current;
      const participants = current.participants.map((participant, participantIndex) =>
        participantIndex === index ? {...participant, [field]: value} : participant,
      );
      return {...current, participants};
    });
  }

  function updateCandidateWindow(index: number, field: keyof CandidateWindow, value: string) {
    setForm((current) => {
      if (!current) return current;
      const candidate_windows = current.candidate_windows.map((window, windowIndex) =>
        windowIndex === index ? {...window, [field]: value} : window,
      );
      return {...current, candidate_windows};
    });
  }

  if (!session || !foundation) {
    return (
      <div className="auth-shell">
        <aside className="auth-brand" aria-label="Holocron">
          <div className="wordmark wordmark-inverse">
            <span className="wordmark-mark" aria-hidden="true">H</span>
            <span>Holocron</span>
          </div>
          <div className="auth-brand-copy">
            <p className="eyebrow eyebrow-inverse">Principal operations</p>
            <h1>One office.<br />Clear context.</h1>
            <p>A focused workspace for the people, decisions, and priorities behind public leadership.</p>
          </div>
          <div className="auth-office-signal">
            <Building2 aria-hidden="true" />
            <div><span>Cedar Grove</span><strong>Mayor&apos;s Office</strong></div>
          </div>
        </aside>
        <main className="auth-main">
          <section className="auth-form-wrap" aria-labelledby="sign-in-title">
            <div className="auth-heading">
              <p className="eyebrow">Workspace access</p>
              <h2 id="sign-in-title">Welcome back</h2>
              <p>Enter your office email to continue.</p>
            </div>
            <form className="auth-form" onSubmit={handleSubmit} noValidate={false}>
              <label htmlFor="email">Work email</label>
              <input id="email" name="email" type="email" autoComplete="email" value={email} onChange={(event) => setEmail(event.target.value)} placeholder="name@office.gov" required />
              {error ? <p className="form-error" role="alert">{error}</p> : null}
              <button className="primary-button" type="submit" disabled={isLoading}>
                <span>{isLoading ? "Opening workspace" : "Continue"}</span><ArrowRight aria-hidden="true" />
              </button>
            </form>
            <div className="auth-footnote"><ShieldCheck aria-hidden="true" /><span>Local development workspace</span></div>
          </section>
        </main>
      </div>
    );
  }

  return (
    <div className="workspace-shell">
      <aside className="workspace-sidebar">
        <div className="wordmark wordmark-inverse"><span className="wordmark-mark" aria-hidden="true">H</span><span>Holocron</span></div>
        <nav className="workspace-nav" aria-label="Workspace sections">
          <a href="#schedule" className="is-active"><Inbox aria-hidden="true" /><span>Scheduling</span></a>
          <a href="#briefings"><BookOpen aria-hidden="true" /><span>Briefings</span></a>
          <a href="#relationships"><Link2 aria-hidden="true" /><span>Relationships</span></a>
          <a href="#overview"><Database aria-hidden="true" /><span>Foundation</span></a>
          <a href="#members"><UsersRound aria-hidden="true" /><span>Members</span></a>
          <a href="#audit"><ScrollText aria-hidden="true" /><span>Audit log</span></a>
        </nav>
        <div className="sidebar-profile">
          <span className="profile-initials">{initials(session.display_name)}</span>
          <div><strong>{session.display_name}</strong><span>{formatRole(session.role)}</span></div>
        </div>
      </aside>

      <div className="workspace-body">
        <header className="workspace-header">
          <div><span className="header-label">Workspace</span><strong>{foundation.workspace.name}</strong></div>
          <button className="icon-text-button" type="button" onClick={signOut}><LogOut aria-hidden="true" /><span>Sign out</span></button>
        </header>

        <main className="workspace-main">
          <section id="schedule" className="workspace-section overview-section scheduling-section">
            <div className="section-heading-row">
              <div><p className="eyebrow">Scheduling intake</p><h1>Requests</h1></div>
              <div className="section-heading-actions">
                <button className="icon-text-button" type="button" onClick={beginRequestExtraction} disabled={!canMutate} title={canMutate ? "Extract a request from email text" : "Use an active workspace member email to extract requests"}>
                  <Sparkles aria-hidden="true" /><span>Extract email</span>
                </button>
                <button className="primary-command" type="button" onClick={beginNewRequest} disabled={!canMutate} title={canMutate ? "Create a scheduling request" : "Use an active workspace member email to create requests"}>
                  <Plus aria-hidden="true" /><span>New request</span>
                </button>
              </div>
            </div>
            {!canMutate ? <p className="read-only-notice">This email can view the workspace, but only active office members can create or edit requests.</p> : null}
            {error ? <p className="form-error workflow-error" role="alert">{error}</p> : null}

            <div className="request-workbench">
              <div className="request-inbox" aria-label="Scheduling request inbox">
                <div className="request-inbox-head"><span>{requests.length} {requests.length === 1 ? "request" : "requests"}</span><span>Updated</span></div>
                {requests.length === 0 ? <div className="empty-inbox"><Inbox aria-hidden="true" /><strong>No scheduling requests yet</strong><span>New requests will appear here.</span></div> : requests.map((request) => (
                  <button className={`request-row ${selectedRequest?.id === request.id && mode === "inbox" ? "is-selected" : ""}`} type="button" key={request.id} onClick={() => selectRequest(request.id)}>
                    <span className="request-source">{sourceLabels[request.source_channel]}</span>
                    <span className={`request-status request-status-${request.status}`}>{formatStatus(request.status)}</span>
                    <strong>{request.requester_name}</strong>
                    <span className="request-purpose">{request.purpose}</span>
                    <span className="request-row-meta">{request.requested_duration_minutes} min · {request.assigned_scheduler_name}</span>
                    <time dateTime={request.updated_at}>{formatDateTime(request.updated_at)}</time>
                  </button>
                ))}
              </div>

              <div className="request-panel">
                {mode === "extract" ? (
                  <RequestExtractionComposer
                    inputText={extractionText}
                    lastAttempt={requestExtraction}
                    isExtracting={isExtracting}
                    onInputChange={setExtractionText}
                    onCancel={cancelEditing}
                    onExtract={extractRequest}
                  />
                ) : mode === "new" || mode === "edit" ? (
                  <RequestComposer
                    form={form!}
                    extraction={requestExtraction}
                    formErrors={formErrors}
                    isSaving={isSaving}
                    isEditing={mode === "edit"}
                    schedulerMembers={schedulerMembers}
                    onCancel={cancelEditing}
                    onSave={saveRequest}
                    onFieldChange={updateForm}
                    onParticipantChange={updateParticipant}
                    onCandidateWindowChange={updateCandidateWindow}
                    onAddParticipant={() => setForm((current) => current ? {...current, participants: [...current.participants, {name: "", email: "", organization: "", role: "required"}]} : current)}
                    onRemoveParticipant={(index) => setForm((current) => current ? {...current, participants: current.participants.filter((_, participantIndex) => participantIndex !== index)} : current)}
                    onAddCandidateWindow={() => setForm((current) => current ? {...current, candidate_windows: [...current.candidate_windows, {candidate_date: "", starts_at: "", ends_at: "", notes: ""}]} : current)}
                    onRemoveCandidateWindow={(index) => setForm((current) => current ? {...current, candidate_windows: current.candidate_windows.filter((_, windowIndex) => windowIndex !== index)} : current)}
                  />
                ) : selectedRequest ? (
                  <RequestDetail
                    key={selectedRequest.id}
                    request={selectedRequest}
                    briefing={briefings.find((entry) => entry.meeting.scheduling_request_id === selectedRequest.id)}
                    canMutate={canMutate}
                    isTransitioning={isTransitioning}
                    isBriefingSaving={isBriefingSaving}
                    onEdit={beginEditing}
                    onTransition={transitionRequest}
                    onCreateMeeting={createMeetingAndBriefing}
                    onOpenBriefing={(id) => selectBriefing(id, true)}
                  />
                ) : (
                  <div className="request-empty-panel"><CalendarDays aria-hidden="true" /><h2>Select a request</h2><p>Review its intake details, candidate windows, and recorded activity here.</p></div>
                )}
              </div>
            </div>
          </section>

          <BriefingsSection
            key={selectedBriefing?.id ?? "briefings"}
            briefings={briefings}
            selectedBriefing={selectedBriefing}
            canMutate={canMutate}
            isSaving={isBriefingSaving}
            onSelect={selectBriefing}
            onGenerate={generateBriefing}
            onSaveVersion={saveBriefingVersion}
            onSubmitReview={submitBriefingForReview}
            onReview={reviewBriefing}
          />

          {relationships ? (
            <RelationshipsSection
              relationships={relationships}
              canMutate={canMutate}
              isSaving={isRelationshipSaving}
              onSave={saveRelationship}
            />
          ) : null}

          <section id="overview" className="workspace-section">
            <div className="section-heading-row compact"><div><p className="eyebrow">Project foundation</p><h2>{foundation.workspace.name}</h2></div><span className="status-badge"><i aria-hidden="true" /> Active</span></div>
            <div className="stat-grid">
              <article className="stat-item"><UserRound aria-hidden="true" /><span>Principal</span><strong>{foundation.principal?.display_name ?? "Unassigned"}</strong></article>
              <article className="stat-item"><Inbox aria-hidden="true" /><span>Requests</span><strong>{requests.length}</strong></article>
              <article className="stat-item"><Clock3 aria-hidden="true" /><span>Timezone</span><strong>{foundation.workspace.timezone}</strong></article>
              <article className="stat-item"><ShieldCheck aria-hidden="true" /><span>Retention</span><strong>{foundation.workspace.retention_days} days</strong></article>
            </div>
          </section>

          <section id="members" className="workspace-section">
            <div className="section-heading-row compact"><div><p className="eyebrow">Office directory</p><h2>Workspace members</h2></div><span className="section-count">{foundation.members.length} members</span></div>
            <div className="member-table" role="table" aria-label="Workspace members">
              <div className="member-row member-table-head" role="row"><span role="columnheader">Name</span><span role="columnheader">Role</span><span role="columnheader">Email</span><span role="columnheader">Status</span></div>
              {foundation.members.map((member) => <div className="member-row" role="row" key={member.id}>
                <div className="member-name" role="cell"><span className="member-initials">{initials(member.display_name)}</span><div><strong>{member.display_name}</strong><small>{member.job_title}</small></div></div>
                <span role="cell" data-label="Role">{formatRole(member.role)}</span><span role="cell" data-label="Email">{member.email}</span><span role="cell" data-label="Status" className="member-status"><i aria-hidden="true" /> {member.status}</span>
              </div>)}
            </div>
          </section>

          <section id="audit" className="workspace-section">
            <div className="section-heading-row compact"><div><p className="eyebrow">System activity</p><h2>Audit log</h2></div><span className="section-count">Append-only</span></div>
            <div className="audit-list">{foundation.audit_events.map((auditEvent) => <article className="audit-row" key={auditEvent.id}><span className="audit-icon"><ScrollText aria-hidden="true" /></span><div><strong>{formatEvent(auditEvent.event_type)}</strong><span>{auditEvent.subject_type ?? "scheduling request"}</span></div><time dateTime={auditEvent.occurred_at}>{formatDateTime(auditEvent.occurred_at)}</time></article>)}</div>
          </section>
        </main>
      </div>
    </div>
  );
}

function BriefingsSection({ briefings, selectedBriefing, canMutate, isSaving, onSelect, onGenerate, onSaveVersion, onSubmitReview, onReview }: {
  briefings: BriefingListItem[];
  selectedBriefing: BriefingDetail | null;
  canMutate: boolean;
  isSaving: boolean;
  onSelect: (id: string) => Promise<void>;
  onGenerate: () => Promise<boolean>;
  onSaveVersion: (payload: Record<string, unknown>) => Promise<boolean>;
  onSubmitReview: () => Promise<boolean>;
  onReview: (decision: string, notes: string) => Promise<boolean>;
}) {
  const [mode, setMode] = useState<"view" | "edit">("view");
  const [viewedVersionNumber, setViewedVersionNumber] = useState<number | null>(null);
  const [sections, setSections] = useState<BriefingSectionForm[]>([]);
  const [changeSummary, setChangeSummary] = useState("");
  const [reviewNotes, setReviewNotes] = useState("");
  const [pendingSources, setPendingSources] = useState<Record<number, string>>({});

  const currentVersion = selectedBriefing?.versions.find(
    (version) => version.version_number === selectedBriefing.current_version_number,
  ) ?? null;
  const viewedVersion = selectedBriefing?.versions.find(
    (version) => version.version_number === viewedVersionNumber,
  ) ?? currentVersion;
  const viewingCurrentVersion = Boolean(
    viewedVersion && selectedBriefing && viewedVersion.version_number === selectedBriefing.current_version_number,
  );
  const hasGeneratedCurrentVersion = currentVersion?.change_summary === "AI-generated draft from grounded workspace context.";

  async function select(id: string) {
    setMode("view");
    setViewedVersionNumber(null);
    setReviewNotes("");
    await onSelect(id);
  }

  function beginRevision() {
    if (!currentVersion) return;
    setSections(briefingSectionsFromVersion(currentVersion));
    setChangeSummary("");
    setPendingSources({});
    setViewedVersionNumber(null);
    setMode("edit");
  }

  function updateSection(index: number, field: keyof Omit<BriefingSectionForm, "sources">, value: string) {
    setSections((current) => current.map((section, sectionIndex) => (
      sectionIndex === index ? {...section, [field]: value} : section
    )));
  }

  function moveSection(index: number, direction: -1 | 1) {
    const target = index + direction;
    if (target < 0 || target >= sections.length) return;
    setSections((current) => {
      const next = [...current];
      [next[index], next[target]] = [next[target], next[index]];
      return next;
    });
  }

  function addSource(index: number) {
    const reference = pendingSources[index];
    if (!reference) return;
    const separator = reference.indexOf(":");
    const source = {source_type: reference.slice(0, separator), source_id: reference.slice(separator + 1)};
    setSections((current) => current.map((section, sectionIndex) => {
      if (sectionIndex !== index) return section;
      const exists = section.sources.some((candidate) => (
        candidate.source_type === source.source_type && candidate.source_id === source.source_id
      ));
      return exists ? section : {...section, sources: [...section.sources, source]};
    }));
    setPendingSources((current) => ({...current, [index]: ""}));
  }

  function removeSource(sectionIndex: number, sourceIndex: number) {
    setSections((current) => current.map((section, index) => (
      index === sectionIndex
        ? {...section, sources: section.sources.filter((_, candidateIndex) => candidateIndex !== sourceIndex)}
        : section
    )));
  }

  async function saveVersion(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedBriefing) return;
    const succeeded = await onSaveVersion({
      expected_lock_version: selectedBriefing.lock_version,
      change_summary: changeSummary,
      sections,
    });
    if (succeeded) {
      setMode("view");
      setViewedVersionNumber(null);
    }
  }

  async function submitForReview() {
    if (await onSubmitReview()) setViewedVersionNumber(null);
  }

  async function generateDraft() {
    if (await onGenerate()) {
      setMode("view");
      setViewedVersionNumber(null);
    }
  }

  async function decide(decision: string) {
    if (await onReview(decision, reviewNotes)) {
      setReviewNotes("");
      setViewedVersionNumber(null);
    }
  }

  function sourceLabel(source: {source_type: string; source_id: string}) {
    return selectedBriefing?.source_catalog.find((candidate) => (
      candidate.source_type === source.source_type && candidate.source_id === source.source_id
    ))?.source_label ?? source.source_id;
  }

  return (
    <section id="briefings" className="workspace-section briefings-section">
      <div className="section-heading-row compact">
        <div><p className="eyebrow">Meeting preparation</p><h2>Briefings</h2></div>
        <span className="section-count">{briefings.length} {briefings.length === 1 ? "briefing" : "briefings"}</span>
      </div>

      <div className="briefing-workbench">
        <div className="briefing-inbox" aria-label="Meeting briefings">
          {briefings.length === 0 ? (
            <div className="briefing-empty"><BookOpen aria-hidden="true" /><strong>No briefings yet</strong><span>Scheduled meetings will appear here.</span></div>
          ) : briefings.map((briefing) => (
            <button className={`briefing-row ${selectedBriefing?.id === briefing.id ? "is-selected" : ""}`} type="button" key={briefing.id} onClick={() => select(briefing.id)}>
              <span className={`briefing-status briefing-status-${briefing.status}`}>{briefingStatusLabels[briefing.status]}</span>
              <strong>{briefing.meeting.title}</strong>
              <span>{briefing.requester_name}{briefing.requester_organization ? ` · ${briefing.requester_organization}` : ""}</span>
              <small>Version {briefing.current_version_number} · {briefing.section_count} sections</small>
              <time dateTime={briefing.meeting.starts_at}>{formatDateTime(briefing.meeting.starts_at)}</time>
            </button>
          ))}
        </div>

        <div className="briefing-panel">
          {!selectedBriefing || !viewedVersion ? (
            <div className="briefing-empty-panel"><BookOpen aria-hidden="true" /><h3>Select a briefing</h3><p>Meeting preparation and approved versions appear here.</p></div>
          ) : (
            <article className="briefing-detail">
              <div className="briefing-detail-head">
                <div><p className="eyebrow">{selectedBriefing.request.requester_name}</p><h3>{selectedBriefing.meeting.title}</h3><span>{selectedBriefing.request.requester_organization || "Independent requester"}</span></div>
                <span className={`briefing-status briefing-status-${selectedBriefing.status}`}>{briefingStatusLabels[selectedBriefing.status]}</span>
              </div>

              <div className="briefing-version-bar">
                <label><span>Version</span><select value={viewedVersion.version_number} onChange={(event) => { setViewedVersionNumber(Number(event.target.value)); setMode("view"); }}>
                  {selectedBriefing.versions.map((version) => <option key={version.id} value={version.version_number}>Version {version.version_number} · {briefingStatusLabels[version.status]}</option>)}
                </select></label>
                <div><strong>{viewedVersion.change_summary || `Version ${viewedVersion.version_number}`}</strong><span>{viewedVersion.created_by.display_name} · {formatDateTime(viewedVersion.created_at)}</span></div>
              </div>

              <div className="briefing-meeting-facts">
                <div><CalendarCheck aria-hidden="true" /><span><small>Meeting</small><strong>{formatDateTime(selectedBriefing.meeting.starts_at)}</strong></span></div>
                <div><Clock3 aria-hidden="true" /><span><small>Ends</small><strong>{formatDateTime(selectedBriefing.meeting.ends_at)}</strong></span></div>
                <div><MapPin aria-hidden="true" /><span><small>Location</small><strong>{selectedBriefing.meeting.location || "Not specified"}</strong></span></div>
              </div>

              {mode === "edit" ? (
                <form className="briefing-editor" onSubmit={saveVersion}>
                  <Field label="Change summary"><input value={changeSummary} onChange={(event) => setChangeSummary(event.target.value)} /></Field>
                  <div className="briefing-editor-sections">
                    {sections.map((section, index) => (
                      <section className="briefing-editor-section" key={`${section.section_type}-${index}`}>
                        <div className="briefing-editor-toolbar">
                          <strong>Section {index + 1}</strong>
                          <div>
                            <button className="icon-button" type="button" onClick={() => moveSection(index, -1)} disabled={index === 0} title="Move section up"><ArrowUp aria-hidden="true" /></button>
                            <button className="icon-button" type="button" onClick={() => moveSection(index, 1)} disabled={index === sections.length - 1} title="Move section down"><ArrowDown aria-hidden="true" /></button>
                            <button className="icon-button" type="button" onClick={() => setSections((current) => current.filter((_, sectionIndex) => sectionIndex !== index))} disabled={sections.length === 1} title="Remove section"><X aria-hidden="true" /></button>
                          </div>
                        </div>
                        <div className="field-grid two">
                          <Field label="Type"><select value={section.section_type} onChange={(event) => updateSection(index, "section_type", event.target.value)}>{Object.entries(briefingSectionLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></Field>
                          <Field label="Title"><input required value={section.title} onChange={(event) => updateSection(index, "title", event.target.value)} /></Field>
                        </div>
                        <Field label="Content"><textarea rows={5} value={section.body} onChange={(event) => updateSection(index, "body", event.target.value)} /></Field>
                        <div className="briefing-source-editor">
                          <span>Sources</span>
                          <div className="briefing-source-tags">{section.sources.map((source, sourceIndex) => <span key={`${source.source_type}-${source.source_id}`}><Link2 aria-hidden="true" />{sourceLabel(source)}<button type="button" onClick={() => removeSource(index, sourceIndex)} title="Remove source"><X aria-hidden="true" /></button></span>)}</div>
                          <div className="briefing-source-add"><select value={pendingSources[index] ?? ""} onChange={(event) => setPendingSources((current) => ({...current, [index]: event.target.value}))}><option value="">Select source</option>{selectedBriefing.source_catalog.map((source) => <option key={`${source.source_type}-${source.source_id}`} value={`${source.source_type}:${source.source_id}`}>{formatRelationshipType(source.source_type)} · {source.source_label}</option>)}</select><button className="subtle-command" type="button" onClick={() => addSource(index)} disabled={!pendingSources[index]}><Plus aria-hidden="true" />Add source</button></div>
                        </div>
                      </section>
                    ))}
                  </div>
                  <div className="briefing-editor-actions">
                    <button className="subtle-command" type="button" onClick={() => setSections((current) => [...current, {section_type: "notes", title: "Notes", body: "", sources: []}])}><Plus aria-hidden="true" />Add section</button>
                    <div><button className="icon-text-button" type="button" onClick={() => setMode("view")}><X aria-hidden="true" /><span>Cancel</span></button><button className="primary-command" type="submit" disabled={isSaving}><Save aria-hidden="true" /><span>{isSaving ? "Saving" : "Save new version"}</span></button></div>
                  </div>
                </form>
              ) : (
                <>
                  <div className="briefing-sections">
                    {viewedVersion.sections.map((section) => (
                      <section className="briefing-content-section" key={section.id}>
                        <div><span>{briefingSectionLabels[section.section_type]}</span><h4>{section.title}</h4></div>
                        {section.body ? <p>{section.body}</p> : <p className="muted-value">Not yet drafted.</p>}
                        {section.sources.length > 0 ? <div className="briefing-sources">{section.sources.map((source) => <div key={`${source.source_type}-${source.source_id}`}><Link2 aria-hidden="true" /><span><strong>{source.source_label}</strong><small>{formatRelationshipType(source.source_type)}{source.source_excerpt ? ` · ${source.source_excerpt}` : ""}</small></span></div>)}</div> : null}
                      </section>
                    ))}
                  </div>

                  {viewedVersion.review ? <div className={`briefing-review-record briefing-review-${viewedVersion.review.decision}`}><CheckCircle2 aria-hidden="true" /><div><strong>{briefingStatusLabels[viewedVersion.review.decision]}</strong><span>{viewedVersion.review.reviewed_by.display_name} · {formatDateTime(viewedVersion.review.reviewed_at)}</span>{viewedVersion.review.notes ? <p>{viewedVersion.review.notes}</p> : null}</div></div> : null}

                  {canMutate && viewingCurrentVersion ? (
                    <div className="briefing-actions">
                      {selectedBriefing.status === "draft" ? <><button className="icon-text-button" type="button" onClick={generateDraft} disabled={isSaving}><Sparkles aria-hidden="true" /><span>{isSaving ? "Generating" : hasGeneratedCurrentVersion ? "Regenerate draft" : "Generate draft"}</span></button><button className="icon-text-button" type="button" onClick={beginRevision} disabled={isSaving}><Save aria-hidden="true" /><span>Edit as new version</span></button><button className="primary-command" type="button" onClick={submitForReview} disabled={isSaving}><Send aria-hidden="true" /><span>{isSaving ? "Submitting" : "Submit for review"}</span></button></> : null}
                      {selectedBriefing.status === "approved" || selectedBriefing.status === "changes_requested" ? <><button className="icon-text-button" type="button" onClick={generateDraft} disabled={isSaving}><Sparkles aria-hidden="true" /><span>{isSaving ? "Generating" : "Generate revision"}</span></button><button className="primary-command" type="button" onClick={beginRevision} disabled={isSaving}><Plus aria-hidden="true" /><span>Create revision</span></button></> : null}
                      {selectedBriefing.status === "in_review" ? <div className="briefing-review-form"><Field label="Review notes"><textarea rows={2} value={reviewNotes} onChange={(event) => setReviewNotes(event.target.value)} /></Field><div><button className="icon-text-button" type="button" onClick={() => decide("changes_requested")} disabled={isSaving || !reviewNotes.trim()}><XCircle aria-hidden="true" /><span>Request changes</span></button><button className="primary-command" type="button" onClick={() => decide("approved")} disabled={isSaving}><CheckCircle2 aria-hidden="true" /><span>{isSaving ? "Saving" : "Approve version"}</span></button></div></div> : null}
                    </div>
                  ) : null}
                </>
              )}
            </article>
          )}
        </div>
      </div>
    </section>
  );
}

function RelationshipsSection({ relationships, canMutate, isSaving, onSave }: {
  relationships: RelationshipsOverview;
  canMutate: boolean;
  isSaving: boolean;
  onSave: (resource: string, payload: Record<string, unknown>, method?: "POST" | "PATCH") => Promise<boolean>;
}) {
  const [view, setView] = useState<"people" | "organizations" | "history">("people");
  const [personForm, setPersonForm] = useState({display_name: "", primary_email: "", primary_phone: "", organization_id: "", job_title: "", notes: ""});
  const [organizationForm, setOrganizationForm] = useState({name: "", website_url: "", notes: ""});
  const [assignmentForm, setAssignmentForm] = useState({person_id: "", organization_id: "", job_title: ""});
  const [interactionForm, setInteractionForm] = useState({person_id: "", interaction_type: "note", summary: "", occurred_at: datetimeLocalValue(new Date().toISOString())});

  async function submitPerson(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (await onSave("people", personForm)) {
      setPersonForm({display_name: "", primary_email: "", primary_phone: "", organization_id: "", job_title: "", notes: ""});
    }
  }

  async function submitOrganization(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (await onSave("organizations", organizationForm)) {
      setOrganizationForm({name: "", website_url: "", notes: ""});
    }
  }

  async function submitAssignment(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!assignmentForm.person_id) return;
    if (await onSave(`people/${assignmentForm.person_id}`, {
      organization_id: assignmentForm.organization_id,
      job_title: assignmentForm.job_title,
    }, "PATCH")) {
      setAssignmentForm({person_id: "", organization_id: "", job_title: ""});
    }
  }

  function selectAssignmentPerson(personId: string) {
    const person = relationships.people.find((candidate) => candidate.id === personId);
    setAssignmentForm({
      person_id: personId,
      organization_id: person?.organization?.id ?? "",
      job_title: person?.job_title ?? "",
    });
  }

  async function submitInteraction(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const succeeded = await onSave("interactions", {
      ...interactionForm,
      occurred_at: officeLocalToIso(interactionForm.occurred_at),
    });
    if (succeeded) {
      setInteractionForm({person_id: "", interaction_type: "note", summary: "", occurred_at: datetimeLocalValue(new Date().toISOString())});
    }
  }

  return (
    <section id="relationships" className="workspace-section relationships-section">
      <div className="section-heading-row compact">
        <div><p className="eyebrow">Context graph</p><h2>Relationships</h2></div>
        <span className="section-count">{relationships.counts.people} people · {relationships.counts.organizations} organizations</span>
      </div>

      <div className="relationship-metrics" aria-label="Relationship totals">
        <div><UserRound aria-hidden="true" /><span>People</span><strong>{relationships.counts.people}</strong></div>
        <div><Building2 aria-hidden="true" /><span>Organizations</span><strong>{relationships.counts.organizations}</strong></div>
        <div><BriefcaseBusiness aria-hidden="true" /><span>People with organizations</span><strong>{relationships.counts.linked_people}</strong></div>
        <div><MessageSquareText aria-hidden="true" /><span>Interactions</span><strong>{relationships.counts.interactions}</strong></div>
      </div>

      <div className="relationship-tabs" role="tablist" aria-label="Relationship views">
        <button type="button" role="tab" aria-selected={view === "people"} className={view === "people" ? "is-active" : ""} onClick={() => setView("people")}><UserRound aria-hidden="true" />People</button>
        <button type="button" role="tab" aria-selected={view === "organizations"} className={view === "organizations" ? "is-active" : ""} onClick={() => setView("organizations")}><Building2 aria-hidden="true" />Organizations</button>
        <button type="button" role="tab" aria-selected={view === "history"} className={view === "history" ? "is-active" : ""} onClick={() => setView("history")}><MessageSquareText aria-hidden="true" />History</button>
      </div>

      {view === "people" ? (
        <div role="tabpanel" className="relationship-view">
          {canMutate ? (
            <div className="relationship-form-grid">
              <form className="relationship-form-band" onSubmit={submitPerson}>
                <div className="relationship-form-heading"><UserRoundPlus aria-hidden="true" /><div><strong>Add person</strong><span>Exact email matches prevent duplicates.</span></div></div>
                <div className="field-grid two">
                  <Field label="Name"><input required value={personForm.display_name} onChange={(event) => setPersonForm({...personForm, display_name: event.target.value})} /></Field>
                  <Field label="Email"><input type="email" value={personForm.primary_email} onChange={(event) => setPersonForm({...personForm, primary_email: event.target.value})} /></Field>
                  <Field label="Phone"><input value={personForm.primary_phone} onChange={(event) => setPersonForm({...personForm, primary_phone: event.target.value})} /></Field>
                  <Field label="Organization"><select value={personForm.organization_id} onChange={(event) => setPersonForm({...personForm, organization_id: event.target.value})}><option value="">No organization</option>{relationships.organizations.map((organization) => <option key={organization.id} value={organization.id}>{organization.name}</option>)}</select></Field>
                  <Field label="Job title"><input value={personForm.job_title} onChange={(event) => setPersonForm({...personForm, job_title: event.target.value})} /></Field>
                  <Field label="Notes"><input value={personForm.notes} onChange={(event) => setPersonForm({...personForm, notes: event.target.value})} /></Field>
                </div>
                <button className="primary-command" type="submit" disabled={isSaving}><Plus aria-hidden="true" /><span>Add person</span></button>
              </form>

              <form className="relationship-form-band" onSubmit={submitAssignment}>
                <div className="relationship-form-heading"><BriefcaseBusiness aria-hidden="true" /><div><strong>Assign organization</strong><span>Each person can have one current organization.</span></div></div>
                <div className="field-grid two">
                  <Field label="Person"><select required value={assignmentForm.person_id} onChange={(event) => selectAssignmentPerson(event.target.value)}><option value="">Select person</option>{relationships.people.map((person) => <option key={person.id} value={person.id}>{person.display_name}</option>)}</select></Field>
                  <Field label="Organization"><select value={assignmentForm.organization_id} onChange={(event) => setAssignmentForm({...assignmentForm, organization_id: event.target.value})}><option value="">No organization</option>{relationships.organizations.map((organization) => <option key={organization.id} value={organization.id}>{organization.name}</option>)}</select></Field>
                  <Field label="Job title"><input value={assignmentForm.job_title} onChange={(event) => setAssignmentForm({...assignmentForm, job_title: event.target.value})} /></Field>
                </div>
                <button className="primary-command" type="submit" disabled={isSaving || relationships.people.length === 0}><Save aria-hidden="true" /><span>Save assignment</span></button>
              </form>
            </div>
          ) : null}

          <div className="relationship-table" role="table" aria-label="People">
            <div className="relationship-row relationship-table-head" role="row"><span>Name</span><span>Organization</span><span>Requests</span><span>History</span></div>
            {relationships.people.map((person) => <div className="relationship-row" role="row" key={person.id}>
                <div className="relationship-identity"><span className="member-initials">{initials(person.display_name)}</span><div><strong>{person.display_name}</strong><small>{person.primary_email || person.primary_phone || "No contact details"}</small></div></div>
                <div className="relationship-organization">{person.organization ? <span>{person.job_title ? `${person.job_title}, ` : ""}{person.organization.name}</span> : <span className="muted-value">No organization</span>}</div>
                <span>{person.request_count}</span>
                <span>{person.interaction_count} {person.interaction_count === 1 ? "interaction" : "interactions"}</span>
              </div>)}
          </div>
        </div>
      ) : null}

      {view === "organizations" ? (
        <div role="tabpanel" className="relationship-view">
          {canMutate ? (
            <form className="relationship-form-band organization-form" onSubmit={submitOrganization}>
              <div className="relationship-form-heading"><Building2 aria-hidden="true" /><div><strong>Add organization</strong><span>Names are normalized for deterministic matching.</span></div></div>
              <div className="field-grid two">
                <Field label="Name"><input required value={organizationForm.name} onChange={(event) => setOrganizationForm({...organizationForm, name: event.target.value})} /></Field>
                <Field label="Website"><input type="url" value={organizationForm.website_url} onChange={(event) => setOrganizationForm({...organizationForm, website_url: event.target.value})} /></Field>
                <Field label="Notes"><input value={organizationForm.notes} onChange={(event) => setOrganizationForm({...organizationForm, notes: event.target.value})} /></Field>
              </div>
              <button className="primary-command" type="submit" disabled={isSaving}><Plus aria-hidden="true" /><span>Add organization</span></button>
            </form>
          ) : null}
          <div className="relationship-table organization-table" role="table" aria-label="Organizations">
            <div className="relationship-row relationship-table-head" role="row"><span>Organization</span><span>People</span><span>Requests</span><span>History</span></div>
            {relationships.organizations.map((organization) => <div className="relationship-row" role="row" key={organization.id}>
              <div className="relationship-identity"><span className="organization-mark"><Building2 aria-hidden="true" /></span><div><strong>{organization.name}</strong><small>{organization.website_url || organization.notes || "No additional details"}</small></div></div>
              <span>{organization.people_count}</span><span>{organization.request_count}</span><span>{organization.interaction_count} {organization.interaction_count === 1 ? "interaction" : "interactions"}</span>
            </div>)}
          </div>
        </div>
      ) : null}

      {view === "history" ? (
        <div role="tabpanel" className="relationship-view">
          {canMutate ? (
            <form className="relationship-form-band interaction-form" onSubmit={submitInteraction}>
              <div className="relationship-form-heading"><MessageSquareText aria-hidden="true" /><div><strong>Record interaction</strong><span>Every entry retains its author and source.</span></div></div>
              <div className="field-grid interaction-grid">
                <Field label="Person"><select required value={interactionForm.person_id} onChange={(event) => setInteractionForm({...interactionForm, person_id: event.target.value})}><option value="">Select person</option>{relationships.people.map((person) => <option key={person.id} value={person.id}>{person.display_name}</option>)}</select></Field>
                <Field label="Type"><select value={interactionForm.interaction_type} onChange={(event) => setInteractionForm({...interactionForm, interaction_type: event.target.value})}>{["call", "email", "meeting", "note", "event", "other"].map((value) => <option key={value} value={value}>{formatRelationshipType(value)}</option>)}</select></Field>
                <Field label="Occurred"><input required type="datetime-local" value={interactionForm.occurred_at} onChange={(event) => setInteractionForm({...interactionForm, occurred_at: event.target.value})} /></Field>
              </div>
              <Field label="Summary"><textarea required rows={2} value={interactionForm.summary} onChange={(event) => setInteractionForm({...interactionForm, summary: event.target.value})} /></Field>
              <button className="primary-command" type="submit" disabled={isSaving}><Save aria-hidden="true" /><span>Record interaction</span></button>
            </form>
          ) : null}
          <div className="interaction-list">
            {relationships.interactions.length === 0 ? <p className="empty-fieldset">No relationship history has been recorded.</p> : relationships.interactions.map((interaction) => <article className="interaction-row" key={interaction.id}>
              <span className="interaction-icon"><MessageSquareText aria-hidden="true" /></span>
              <div><strong>{interaction.summary}</strong><span>{formatRelationshipType(interaction.interaction_type)} · {interaction.person?.display_name}</span><small>{interaction.author?.display_name ?? "System"} · {formatRelationshipType(interaction.source_type)}</small></div>
              <time dateTime={interaction.occurred_at}>{formatDateTime(interaction.occurred_at)}</time>
            </article>)}
          </div>
        </div>
      ) : null}
    </section>
  );
}

function RequestExtractionComposer({ inputText, lastAttempt, isExtracting, onInputChange, onCancel, onExtract }: {
  inputText: string;
  lastAttempt: RequestExtraction | null;
  isExtracting: boolean;
  onInputChange: (value: string) => void;
  onCancel: () => void;
  onExtract: (event: FormEvent<HTMLFormElement>) => void;
}) {
  return <form className="extraction-composer" onSubmit={onExtract}>
    <div className="request-panel-head"><div><p className="eyebrow">Request extraction</p><h2>Paste an email</h2></div><button className="icon-button" type="button" onClick={onCancel} title="Close request extraction"><X aria-hidden="true" /></button></div>
    {lastAttempt && lastAttempt.status !== "succeeded" ? <div className="extraction-attempt-status" role="status"><XCircle aria-hidden="true" /><div><strong>{lastAttempt.status === "refused" ? "Extraction refused" : "Extraction failed"}</strong><span>{lastAttempt.provider} · {lastAttempt.model} · {lastAttempt.attempt_count} {lastAttempt.attempt_count === 1 ? "attempt" : "attempts"}</span></div></div> : null}
    <Field label="Email text"><textarea className="extraction-input" rows={18} required maxLength={8000} value={inputText} onChange={(event) => onInputChange(event.target.value)} placeholder={"From: Name <name@example.org>\nSubject: Meeting request\nDuration: 30 minutes\n\nRequest details..."} /></Field>
    <div className="composer-actions"><button className="icon-text-button" type="button" onClick={onCancel}><ArrowLeft aria-hidden="true" /><span>Cancel</span></button><button className="primary-command" type="submit" disabled={isExtracting || !inputText.trim()}><Sparkles aria-hidden="true" /><span>{isExtracting ? "Extracting" : "Extract request"}</span></button></div>
  </form>;
}

function RequestComposer({ form, extraction, formErrors, isSaving, isEditing, schedulerMembers, onCancel, onSave, onFieldChange, onParticipantChange, onCandidateWindowChange, onAddParticipant, onRemoveParticipant, onAddCandidateWindow, onRemoveCandidateWindow }: {
  form: RequestForm;
  extraction: RequestExtraction | null;
  formErrors: Record<string, string>;
  isSaving: boolean;
  isEditing: boolean;
  schedulerMembers: WorkspaceMember[];
  onCancel: () => void;
  onSave: (event: FormEvent<HTMLFormElement>) => void;
  onFieldChange: (field: keyof Omit<RequestForm, "participants" | "candidate_windows">, value: string) => void;
  onParticipantChange: (index: number, field: keyof Participant, value: string) => void;
  onCandidateWindowChange: (index: number, field: keyof CandidateWindow, value: string) => void;
  onAddParticipant: () => void;
  onRemoveParticipant: (index: number) => void;
  onAddCandidateWindow: () => void;
  onRemoveCandidateWindow: (index: number) => void;
}) {
  return <form className="request-composer" onSubmit={onSave} noValidate>
    <div className="request-panel-head"><div><p className="eyebrow">{isEditing ? "Edit intake" : "New intake"}</p><h2>{isEditing ? "Update request" : "Create request"}</h2></div><button className="icon-button" type="button" onClick={onCancel} title="Close request editor"><X aria-hidden="true" /></button></div>
    {extraction ? <div className="extraction-review-band"><Sparkles aria-hidden="true" /><div><strong>AI draft · Review before creating</strong><span>{extraction.provider} · {extraction.model} · {extraction.prompt_version}</span>{extraction.warnings.length > 0 ? <div className="extraction-warnings">{extraction.warnings.map((warning) => <small key={warning}>{warning}</small>)}</div> : null}</div></div> : null}
    {Object.keys(formErrors).length > 0 ? <p className="form-error form-error-summary" role="alert">{Object.values(formErrors).join(" ")}</p> : null}
    <fieldset className="request-fieldset"><legend>Requester</legend><div className="field-grid two"><Field label="Name" error={formErrors.requester_name}><input value={form.requester_name} onChange={(event) => onFieldChange("requester_name", event.target.value)} /></Field><Field label="Organization"><input value={form.requester_organization} onChange={(event) => onFieldChange("requester_organization", event.target.value)} /></Field><Field label="Email" error={formErrors.requester_email}><input type="email" value={form.requester_email} onChange={(event) => onFieldChange("requester_email", event.target.value)} /></Field><Field label="Source" error={formErrors.source_channel}><select value={form.source_channel} disabled={Boolean(extraction)} onChange={(event) => onFieldChange("source_channel", event.target.value)}>{Object.entries(sourceLabels).map(([value, label]) => <option key={value} value={value}>{label}</option>)}</select></Field></div></fieldset>
    <fieldset className="request-fieldset"><legend>Request</legend><div className="field-grid two"><Field label="Duration (minutes)" error={formErrors.requested_duration_minutes}><input type="number" min="15" max="480" step="15" value={form.requested_duration_minutes} onChange={(event) => onFieldChange("requested_duration_minutes", event.target.value)} /></Field><Field label="Assigned scheduler" error={formErrors.assigned_scheduler_member_id}><select value={form.assigned_scheduler_member_id} onChange={(event) => onFieldChange("assigned_scheduler_member_id", event.target.value)}>{schedulerMembers.map((member) => <option key={member.id} value={member.id}>{member.display_name} · {formatRole(member.role)}</option>)}</select></Field></div><Field label="Purpose" error={formErrors.purpose}><textarea rows={3} value={form.purpose} onChange={(event) => onFieldChange("purpose", event.target.value)} /></Field><Field label="Availability notes"><textarea rows={2} value={form.availability_notes} onChange={(event) => onFieldChange("availability_notes", event.target.value)} placeholder="Any useful context that does not fit a candidate window." /></Field><Field label="Original request text"><textarea rows={3} readOnly={Boolean(extraction)} value={form.original_request_text} onChange={(event) => onFieldChange("original_request_text", event.target.value)} /></Field></fieldset>
    <fieldset className="request-fieldset"><div className="fieldset-heading"><legend>Candidate windows</legend><button className="subtle-command" type="button" onClick={onAddCandidateWindow}><Plus aria-hidden="true" />Add window</button></div>{form.candidate_windows.length === 0 ? <p className="empty-fieldset">No structured windows yet. Notes can still capture a general preference.</p> : form.candidate_windows.map((window, index) => <div className="repeat-row" key={`window-${index}`}><div className="field-grid candidate-grid"><Field label="Date" error={formErrors[`candidate_windows.${index}.candidate_date`]}><input type="date" value={window.candidate_date} onChange={(event) => onCandidateWindowChange(index, "candidate_date", event.target.value)} /></Field><Field label="Start"><input type="datetime-local" value={window.starts_at ?? ""} onChange={(event) => onCandidateWindowChange(index, "starts_at", event.target.value)} /></Field><Field label="End" error={formErrors[`candidate_windows.${index}.ends_at`]}><input type="datetime-local" value={window.ends_at ?? ""} onChange={(event) => onCandidateWindowChange(index, "ends_at", event.target.value)} /></Field></div><Field label="Notes"><input value={window.notes} onChange={(event) => onCandidateWindowChange(index, "notes", event.target.value)} placeholder="Location, timezone, or preference" /></Field><button className="remove-button" type="button" onClick={() => onRemoveCandidateWindow(index)} title="Remove candidate window"><X aria-hidden="true" /></button></div>)}</fieldset>
    <fieldset className="request-fieldset"><div className="fieldset-heading"><legend>Participants</legend><button className="subtle-command" type="button" onClick={onAddParticipant}><UserPlus aria-hidden="true" />Add participant</button></div>{form.participants.length === 0 ? <p className="empty-fieldset">Add people beyond the requester when they are relevant to the meeting.</p> : form.participants.map((participant, index) => <div className="repeat-row participant-row" key={`participant-${index}`}><div className="field-grid participant-grid"><Field label="Name"><input value={participant.name} onChange={(event) => onParticipantChange(index, "name", event.target.value)} /></Field><Field label="Email"><input type="email" value={participant.email} onChange={(event) => onParticipantChange(index, "email", event.target.value)} /></Field><Field label="Role"><select value={participant.role} onChange={(event) => onParticipantChange(index, "role", event.target.value)}><option value="">Select role</option><option value="required">Required</option><option value="optional">Optional</option><option value="staff">Staff</option></select></Field></div><Field label="Organization"><input value={participant.organization} onChange={(event) => onParticipantChange(index, "organization", event.target.value)} /></Field><button className="remove-button" type="button" onClick={() => onRemoveParticipant(index)} title="Remove participant"><X aria-hidden="true" /></button></div>)}</fieldset>
    <div className="composer-actions"><button className="icon-text-button" type="button" onClick={onCancel}><ArrowLeft aria-hidden="true" /><span>Cancel</span></button><button className="primary-command" type="submit" disabled={isSaving}><Save aria-hidden="true" /><span>{isSaving ? "Saving" : isEditing ? "Save changes" : "Create request"}</span></button></div>
  </form>;
}

function Field({ label, error, children }: {label: string; error?: string; children: React.ReactNode}) {
  return <label className="request-field"><span>{label}</span>{children}{error ? <small className="field-error">{error}</small> : null}</label>;
}

function RequestDetail({ request, briefing, canMutate, isTransitioning, isBriefingSaving, onEdit, onTransition, onCreateMeeting, onOpenBriefing }: {
  request: SchedulingRequest;
  briefing?: BriefingListItem;
  canMutate: boolean;
  isTransitioning: boolean;
  isBriefingSaving: boolean;
  onEdit: () => void;
  onTransition: (toStatus: string, reasonCode: string, notes: string) => Promise<boolean>;
  onCreateMeeting: (payload: Record<string, unknown>) => Promise<boolean>;
  onOpenBriefing: (id: string) => void;
}) {
  const [selectedTransition, setSelectedTransition] = useState<AvailableTransition | null>(null);
  const [reasonCode, setReasonCode] = useState("");
  const [notes, setNotes] = useState("");
  const preferredWindow = request.candidate_windows.find((window) => window.starts_at && window.ends_at);
  const [meetingForm, setMeetingForm] = useState({
    title: request.purpose,
    starts_at: datetimeLocalValue(preferredWindow?.starts_at ?? null),
    ends_at: datetimeLocalValue(preferredWindow?.ends_at ?? null),
    location: preferredWindow?.notes ?? "",
  });

  function chooseTransition(transition: AvailableTransition) {
    setSelectedTransition(transition);
    setReasonCode(transition.reasons[0]?.code ?? "");
    setNotes("");
  }

  async function submitTransition(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!selectedTransition || !reasonCode) return;

    const succeeded = await onTransition(selectedTransition.to_status, reasonCode, notes);
    if (succeeded) {
      setSelectedTransition(null);
      setReasonCode("");
      setNotes("");
    }
  }

  async function createMeeting(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    await onCreateMeeting({
      title: meetingForm.title,
      starts_at: officeLocalToIso(meetingForm.starts_at),
      ends_at: officeLocalToIso(meetingForm.ends_at),
      location: meetingForm.location,
    });
  }

  return (
    <article className="request-detail">
      <div className="request-panel-head">
        <div>
          <p className="eyebrow">{sourceLabels[request.source_channel]}</p>
          <div className="detail-title-row">
            <h2>{request.requester.name}</h2>
            <span className={`request-status request-status-${request.status}`}>{formatStatus(request.status)}</span>
          </div>
          <p className="detail-subtitle">{request.requester.organization ?? "Independent requester"}</p>
        </div>
        {canMutate ? <button className="icon-text-button" type="button" onClick={onEdit}><Save aria-hidden="true" /><span>Edit</span></button> : null}
      </div>

      {request.request_extraction ? <div className="request-extraction-origin"><Sparkles aria-hidden="true" /><div><strong>Created from reviewed AI extraction</strong><span>{request.request_extraction.provider} · {request.request_extraction.model} · {request.request_extraction.prompt_version}</span></div></div> : null}

      {canMutate && request.available_transitions.length > 0 ? (
        <section className="workflow-actions" aria-labelledby="workflow-actions-title">
          <h3 id="workflow-actions-title">Workflow actions</h3>
          <div className="workflow-action-row">
            {request.available_transitions.map((transition) => (
              <button
                className={`workflow-action workflow-action-${transition.to_status} ${selectedTransition?.to_status === transition.to_status ? "is-selected" : ""}`}
                type="button"
                key={transition.to_status}
                onClick={() => chooseTransition(transition)}
                disabled={isTransitioning}
              >
                <WorkflowIcon status={transition.to_status} />
                <span>{transition.label}</span>
              </button>
            ))}
          </div>

          {selectedTransition ? (
            <form className="transition-form" onSubmit={submitTransition}>
              <Field label="Reason">
                <select value={reasonCode} onChange={(event) => setReasonCode(event.target.value)}>
                  {selectedTransition.reasons.map((reason) => <option key={reason.code} value={reason.code}>{reason.label}</option>)}
                </select>
              </Field>
              <Field label="Notes">
                <textarea rows={2} value={notes} onChange={(event) => setNotes(event.target.value)} />
              </Field>
              <div className="transition-form-actions">
                <button className="icon-text-button" type="button" onClick={() => setSelectedTransition(null)} disabled={isTransitioning}><X aria-hidden="true" /><span>Cancel</span></button>
                <button className={`primary-command ${selectedTransition.to_status === "declined" ? "danger-command" : ""}`} type="submit" disabled={isTransitioning || !reasonCode}>
                  <WorkflowIcon status={selectedTransition.to_status} />
                  <span>{isTransitioning ? "Updating" : `Confirm ${selectedTransition.label.toLowerCase()}`}</span>
                </button>
              </div>
            </form>
          ) : null}
        </section>
      ) : null}

      {request.status === "scheduled" ? (
        <section className="meeting-briefing-block">
          <div className="meeting-briefing-heading"><div><p className="eyebrow">Meeting preparation</p><h3>Meeting and briefing</h3></div>{briefing ? <span className={`briefing-status briefing-status-${briefing.status}`}>{briefingStatusLabels[briefing.status]}</span> : null}</div>
          {briefing ? (
            <div className="meeting-briefing-summary">
              <div><CalendarCheck aria-hidden="true" /><span><strong>{briefing.meeting.title}</strong><small>{formatDateTime(briefing.meeting.starts_at)} · {briefing.meeting.location || "Location not specified"}</small></span></div>
              <button className="primary-command" type="button" onClick={() => onOpenBriefing(briefing.id)}><BookOpen aria-hidden="true" /><span>Open briefing</span></button>
            </div>
          ) : canMutate ? (
            <form className="meeting-create-form" onSubmit={createMeeting}>
              <div className="field-grid two">
                <Field label="Meeting title"><input required value={meetingForm.title} onChange={(event) => setMeetingForm({...meetingForm, title: event.target.value})} /></Field>
                <Field label="Location"><input value={meetingForm.location} onChange={(event) => setMeetingForm({...meetingForm, location: event.target.value})} /></Field>
                <Field label="Starts"><input required type="datetime-local" value={meetingForm.starts_at} onChange={(event) => setMeetingForm({...meetingForm, starts_at: event.target.value})} /></Field>
                <Field label="Ends"><input required type="datetime-local" value={meetingForm.ends_at} onChange={(event) => setMeetingForm({...meetingForm, ends_at: event.target.value})} /></Field>
              </div>
              <button className="primary-command" type="submit" disabled={isBriefingSaving}><BookOpen aria-hidden="true" /><span>{isBriefingSaving ? "Creating" : "Create meeting and briefing"}</span></button>
            </form>
          ) : <p className="muted-value">No briefing has been created for this meeting.</p>}
        </section>
      ) : null}

      <div className="detail-facts">
        <div><span>Purpose</span><strong>{request.purpose}</strong></div>
        <div><span>Duration</span><strong>{request.requested_duration_minutes} minutes</strong></div>
        <div><span>Scheduler</span><strong>{request.assigned_scheduler?.display_name ?? "Unassigned"}</strong></div>
        <div><span>Requester email</span><strong>{request.requester.email ?? "Not provided"}</strong></div>
      </div>

      <section className="detail-block request-relationship-context">
        <h3>Relationship context</h3>
        <div className="context-people-list">
          {request.relationship_context.people.map((person) => {
            const organizationLabel = person.organization ? `${person.job_title ? `${person.job_title}, ` : ""}${person.organization.name}` : "No organization";
            return <div className="context-person" key={`${person.id}-${person.request_role}`}>
              <span className="member-initials">{initials(person.display_name)}</span>
              <div><strong>{person.display_name}</strong><small>{formatRelationshipType(person.request_role ?? "related")} · {organizationLabel}</small></div>
              <span>{person.interaction_count} {person.interaction_count === 1 ? "interaction" : "interactions"}</span>
            </div>;
          })}
        </div>
        {request.relationship_context.organizations.length > 0 ? <div className="context-organizations">{request.relationship_context.organizations.map((organization) => <span key={`${organization.id}-${organization.request_role}`}><Building2 aria-hidden="true" />{organization.name}</span>)}</div> : null}
        <div className="context-history">
          <strong>Prior history</strong>
          {request.relationship_context.interactions.filter((interaction) => !interaction.current_request).length === 0 ? <p>No earlier interactions are recorded for these people or organizations.</p> : request.relationship_context.interactions.filter((interaction) => !interaction.current_request).slice(0, 5).map((interaction) => <div key={interaction.id}><MessageSquareText aria-hidden="true" /><span><strong>{interaction.summary}</strong><small>{formatRelationshipType(interaction.interaction_type)} · {interaction.author?.display_name ?? "System"} · {formatDateTime(interaction.occurred_at)}</small></span></div>)}
        </div>
      </section>

      {request.availability_notes ? <section className="detail-block"><h3>Availability notes</h3><p>{request.availability_notes}</p></section> : null}
      <section className="detail-block">
        <h3>Candidate windows</h3>
        {request.candidate_windows.length === 0 ? <p>No structured candidate windows were supplied.</p> : <div className="detail-list">{request.candidate_windows.map((window) => <div key={`${window.candidate_date}-${window.starts_at ?? "notes"}`}><CalendarDays aria-hidden="true" /><span><strong>{window.candidate_date}</strong><small>{window.starts_at && window.ends_at ? `${formatDateTime(window.starts_at)} to ${formatDateTime(window.ends_at)}` : "Date preference"}{window.notes ? ` · ${window.notes}` : ""}</small></span></div>)}</div>}
      </section>
      <section className="detail-block">
        <h3>Participants</h3>
        {request.participants.length === 0 ? <p>No additional participants.</p> : <div className="detail-list">{request.participants.map((participant) => <div key={participant.id ?? participant.email}><UserRound aria-hidden="true" /><span><strong>{participant.name}</strong><small>{participant.role} · {participant.organization || participant.email || "No organization"}</small></span></div>)}</div>}
      </section>
      {request.original_request_text ? <section className="detail-block"><h3>Original request</h3><blockquote>{request.original_request_text}</blockquote></section> : null}

      <section className="detail-block">
        <h3>Workflow timeline</h3>
        <div className="workflow-timeline">
          {[...request.transitions].reverse().map((transition) => (
            <div className="timeline-event" key={transition.id}>
              <span className={`timeline-icon request-status-${transition.to_status}`}><WorkflowIcon status={transition.to_status} /></span>
              <div>
                <strong>{transition.from_status ? `${formatStatus(transition.from_status)} to ${formatStatus(transition.to_status)}` : formatStatus(transition.to_status)}</strong>
                <span>{formatReason(transition.reason_code)} · {transition.actor?.display_name ?? "System"}</span>
                {transition.notes ? <p>{transition.notes}</p> : null}
              </div>
              {transition.decision ? <span className={`decision-marker decision-${transition.decision.decision}`}>{formatStatus(transition.decision.decision)}</span> : null}
              <time dateTime={transition.occurred_at}>{formatDateTime(transition.occurred_at)}</time>
            </div>
          ))}
        </div>
      </section>
    </article>
  );
}

function WorkflowIcon({ status }: {status: string}) {
  if (status === "approved") return <CheckCircle2 aria-hidden="true" />;
  if (status === "declined") return <XCircle aria-hidden="true" />;
  if (status === "scheduled") return <CalendarCheck aria-hidden="true" />;
  if (status === "needs_information") return <CircleHelp aria-hidden="true" />;
  return <ScrollText aria-hidden="true" />;
}
