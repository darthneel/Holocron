"use client";

import { useState } from "react";
import "./designs.css";

type ProductView = "requests" | "briefings";
type Theme = "dark" | "light";
type Concept = {
  id: string;
  family: "Foundation" | "Minimalist" | "Industrial" | "High-End";
  title: string;
  subtitle: string;
  description: string;
};

type RequestRecord = {
  id: string;
  requester: string;
  email: string;
  organization: string;
  purpose: string;
  duration: number;
  availability: string;
  source: string;
  status: "Submitted" | "Scheduled";
  updated: string;
  scheduler: string;
  windows: Array<{date: string; time: string; note: string}>;
  participants: Array<{name: string; role: string; organization: string}>;
};

type BriefingRecord = {
  id: string;
  title: string;
  requester: string;
  organization: string;
  status: "Draft";
  date: string;
  time: string;
  duration: string;
  location: string;
  attendees: string[];
  overview: string;
  objectives: string[];
  history: string[];
  limitations: string[];
};

const concepts: Concept[] = [
  {id: "cabinet", family: "Foundation", title: "The Cabinet", subtitle: "Decision dossier", description: "The real request workbench as a composed executive dossier with a persistent office rail."},
  {id: "signal-room", family: "Foundation", title: "The Signal Room", subtitle: "Live intake board", description: "The same workflow recast as a wide operational board with a horizontal intake queue."},
  {id: "ledger", family: "Minimalist", title: "Ledger", subtitle: "Reading workspace", description: "Requests and briefings become a quiet document index with a continuous reading pane."},
  {id: "margin", family: "Minimalist", title: "Margin", subtitle: "Calendar workspace", description: "Meeting requests are organized around time, availability, and a broad spatial calendar."},
  {id: "system-01", family: "Industrial", title: "System 01", subtitle: "Command review", description: "A sparse aviation-red command surface for decisive intake review and workflow transitions."},
  {id: "operations-array", family: "Industrial", title: "Operations Array", subtitle: "Routing terminal", description: "A dense phosphor matrix for scanning every request, meeting fact, and briefing state."},
  {id: "aperture", family: "High-End", title: "Aperture", subtitle: "Cinematic workbench", description: "The workbench becomes a full-bleed briefing room with one primary glass action surface."},
  {id: "parlor", family: "High-End", title: "Parlor", subtitle: "Sculptural workspace", description: "A cold-luxury planning room built from floating briefing shelves and a staged agenda."},
];

const requests: RequestRecord[] = [
  {
    id: "priya-nanduri",
    requester: "Priya Nanduri",
    email: "priya.nanduri@cedargroveps.org",
    organization: "Cedar Grove Public Schools",
    purpose: "School safety and summer program briefing",
    duration: 30,
    availability: "Please include the superintendent if the Mayor is available before the August board meeting.",
    source: "Web",
    status: "Scheduled",
    updated: "Jul 15, 10:50 PM",
    scheduler: "Jordan Lee",
    windows: [
      {date: "Aug 13", time: "9:30-10:00 AM", note: "Video call is acceptable"},
      {date: "Aug 14", time: "3:00-3:30 PM", note: "District office"},
    ],
    participants: [{name: "Marcus Bell", role: "Required", organization: "Cedar Grove Public Schools"}],
  },
  {
    id: "priya-shah",
    requester: "Priya Shah",
    email: "priya.demo@example.org",
    organization: "Front Range Mobility Coalition",
    purpose: "Regional mobility briefing",
    duration: 45,
    availability: "Tuesday afternoon is preferred.",
    source: "Email",
    status: "Submitted",
    updated: "Jul 13, 5:04 PM",
    scheduler: "Jordan Lee",
    windows: [{date: "Sep 8", time: "2:00-2:45 PM", note: "Mountain time"}],
    participants: [{name: "Rafael Kim", role: "Optional", organization: "Front Range Mobility Coalition"}],
  },
  {
    id: "darius-holt",
    requester: "Darius Holt",
    email: "dholt@cedargrovechamber.org",
    organization: "Cedar Grove Chamber of Commerce",
    purpose: "Quarterly small-business roundtable",
    duration: 60,
    availability: "Flexible during the week of August 17. The chamber can host downtown if helpful.",
    source: "Phone",
    status: "Scheduled",
    updated: "Jul 13, 12:23 AM",
    scheduler: "Jordan Lee",
    windows: [
      {date: "Aug 18", time: "Morning", note: "Morning preferred"},
      {date: "Aug 20", time: "After 1:00 PM", note: "Any afternoon time"},
    ],
    participants: [
      {name: "Rina Patel", role: "Required", organization: "Cedar Grove Chamber of Commerce"},
      {name: "Sam Rivera", role: "Staff", organization: "Mayor Office"},
    ],
  },
  {
    id: "north-river",
    requester: "North River Arts Council",
    email: "contact@northriverarts.org",
    organization: "North River Arts Council",
    purpose: "Community arts grant briefing",
    duration: 45,
    availability: "Tuesday afternoon is preferred. A City Hall meeting is ideal.",
    source: "Email",
    status: "Submitted",
    updated: "Jul 10, 11:00 PM",
    scheduler: "Jordan Lee",
    windows: [{date: "Aug 11", time: "2:00-2:45 PM", note: "City Hall preferred"}],
    participants: [{name: "Avery Morgan", role: "Required", organization: "North River Arts Council"}],
  },
];

const briefings: BriefingRecord[] = [
  {
    id: "school-safety",
    title: "School safety and summer program briefing",
    requester: "Priya Nanduri",
    organization: "Cedar Grove Public Schools",
    status: "Draft",
    date: "Thursday, August 13",
    time: "9:30-10:00 AM",
    duration: "30 minutes",
    location: "Video call is acceptable",
    attendees: ["Priya Nanduri, requester", "Marcus Bell, required"],
    overview: "School safety and summer program briefing.",
    objectives: ["Discuss school safety and summer programs.", "Confirm whether the superintendent should join before the August board meeting."],
    history: ["No prior interaction history is recorded for the linked people."],
    limitations: ["The Mayor's availability is not confirmed.", "The superintendent's attendance is not confirmed."],
  },
  {
    id: "small-business",
    title: "Quarterly small-business roundtable",
    requester: "Darius Holt",
    organization: "Cedar Grove Chamber of Commerce",
    status: "Draft",
    date: "Tuesday, August 18",
    time: "10:00-11:00 AM",
    duration: "60 minutes",
    location: "Cedar Grove City Hall - Conference Room A",
    attendees: ["Darius Holt, requester", "Rina Patel, required", "Sam Rivera, staff"],
    overview: "Quarterly small-business roundtable requested by Darius Holt.",
    objectives: ["Confirm priorities for the quarterly roundtable.", "Invite feedback on the permitting liaison.", "Revisit storefront-permitting follow-up where relevant."],
    history: ["March 2026: Darius shared positive feedback on the permitting liaison.", "November 2025: Mayor Park joined the Chamber's fall small-business roundtable."],
    limitations: ["No detailed agenda or decision items were provided.", "The confirmed attendee list is limited to linked participants."],
  },
];

function Topline({concept, theme}: {concept: Concept; theme: Theme}) {
  return <header className="concept-topline"><div className="concept-wordmark">HOLOCRON</div><p>{concept.family} concept</p><div className="concept-title-lockup"><strong>{concept.title}</strong><span>{concept.subtitle}</span><i>{theme}</i></div></header>;
}

function Status({value}: {value: string}) {
  return <span className={`product-status status-${value.toLowerCase().replaceAll(" ", "-")}`}>{value}</span>;
}

function RequestList({selectedId, onSelect}: {selectedId: string; onSelect: (id: string) => void}) {
  return <div className="product-list" aria-label="Scheduling request inbox"><header><span>4 requests</span><span>Updated</span></header>{requests.map((request) => <button type="button" className={selectedId === request.id ? "is-selected" : ""} key={request.id} onClick={() => onSelect(request.id)}><span className="product-source">{request.source}</span><Status value={request.status} /><strong>{request.requester}</strong><p>{request.purpose}</p><small>{request.duration} min <b>{request.scheduler}</b></small><time>{request.updated}</time></button>)}</div>;
}

function BriefingList({selectedId, onSelect}: {selectedId: string; onSelect: (id: string) => void}) {
  return <div className="product-list product-briefing-list" aria-label="Briefing inbox"><header><span>2 briefings</span><span>Meeting</span></header>{briefings.map((briefing) => <button type="button" className={selectedId === briefing.id ? "is-selected" : ""} key={briefing.id} onClick={() => onSelect(briefing.id)}><span className="product-source">{briefing.requester}</span><Status value={briefing.status} /><strong>{briefing.title}</strong><p>{briefing.organization}</p><small>{briefing.duration}</small><time>{briefing.date}</time></button>)}</div>;
}

function RequestDetail({request}: {request: RequestRecord}) {
  return <article className="product-detail request-preview-detail">
    <header className="product-detail-head"><div><span>{request.source}</span><div><h2>{request.requester}</h2><Status value={request.status} /></div><p>{request.organization}</p></div><button type="button">Edit</button></header>
    {request.status === "Submitted" ? <section className="product-actions"><h3>Workflow actions</h3><div><button type="button">Start review</button><button type="button">Decline</button></div></section> : <section className="product-meeting"><div><span>Meeting preparation</span><h3>Meeting and briefing</h3><p>{request.purpose}</p></div><button type="button">Open briefing</button></section>}
    <section className="product-facts"><div><span>Purpose</span><strong>{request.purpose}</strong></div><div><span>Duration</span><strong>{request.duration} minutes</strong></div><div><span>Scheduler</span><strong>{request.scheduler}</strong></div><div><span>Requester email</span><strong>{request.email}</strong></div></section>
    <section className="product-block"><h3>Candidate windows</h3><div className="product-window-list">{request.windows.map((window) => <div key={`${window.date}-${window.time}`}><time>{window.date}</time><strong>{window.time}</strong><span>{window.note}</span></div>)}</div></section>
    <section className="product-block product-participants"><h3>Participants</h3>{request.participants.map((participant) => <div key={participant.name}><b>{participant.name.slice(0, 2).toUpperCase()}</b><span><strong>{participant.name}</strong><small>{participant.role} - {participant.organization}</small></span></div>)}</section>
    <section className="product-block product-availability"><h3>Availability notes</h3><p>{request.availability}</p></section>
  </article>;
}

function BriefingDetail({briefing}: {briefing: BriefingRecord}) {
  return <article className="product-detail briefing-preview-detail">
    <header className="product-detail-head"><div><span>Meeting briefing</span><div><h2>{briefing.title}</h2><Status value={briefing.status} /></div><p>{briefing.requester} - {briefing.organization}</p></div><button type="button">Edit version</button></header>
    <section className="briefing-facts"><div><span>Date</span><strong>{briefing.date}</strong></div><div><span>Time</span><strong>{briefing.time}</strong></div><div><span>Location</span><strong>{briefing.location}</strong></div></section>
    <section className="briefing-section"><span>Overview</span><h3>Meeting overview</h3><p>{briefing.overview}</p><button type="button">2 sources</button></section>
    <section className="briefing-section briefing-objectives"><span>Objectives</span><h3>Suggested talking points</h3><ul>{briefing.objectives.map((objective) => <li key={objective}>{objective}</li>)}</ul><button type="button">3 sources</button></section>
    <section className="briefing-section briefing-history"><span>Prior history</span><h3>Relationship context</h3>{briefing.history.map((item) => <p key={item}>{item}</p>)}</section>
    <section className="briefing-section briefing-limitations"><span>Notes</span><h3>Known limitations</h3><ul>{briefing.limitations.map((item) => <li key={item}>{item}</li>)}</ul></section>
    <footer className="briefing-actions"><button type="button">Generate draft</button><button type="button">Edit as new version</button><button type="button">Submit for review</button></footer>
  </article>;
}

function Workbench({concept, view, setView, selectedRequestId, setSelectedRequestId, selectedBriefingId, setSelectedBriefingId}: {
  concept: Concept;
  view: ProductView;
  setView: (view: ProductView) => void;
  selectedRequestId: string;
  setSelectedRequestId: (id: string) => void;
  selectedBriefingId: string;
  setSelectedBriefingId: (id: string) => void;
}) {
  const selectedRequest = requests.find((request) => request.id === selectedRequestId) ?? requests[0];
  const selectedBriefing = briefings.find((briefing) => briefing.id === selectedBriefingId) ?? briefings[0];
  return <div className={`product-shell layout-${concept.id}`}>
    <aside className="product-nav"><div className="product-brand"><b>H</b><strong>Holocron</strong></div><nav aria-label="Workspace sections"><button className="is-active" type="button"><span>01</span>Meetings</button><button type="button"><span>02</span>Relationships</button><button type="button"><span>03</span>Foundation</button><button type="button"><span>04</span>Members</button><button type="button"><span>05</span>Audit log</button></nav><footer><b>NP</b><span><strong>Neel</strong><small>Workspace Owner</small></span></footer></aside>
    <header className="product-header"><div><span>Workspace</span><strong>Cedar Grove Mayor&apos;s Office</strong></div><button type="button">Sign out</button></header>
    <main className="product-main">
      <nav className="product-tabs" aria-label="Meeting workspace views"><button type="button" className={view === "requests" ? "is-active" : ""} onClick={() => setView("requests")}>Requests</button><button type="button" className={view === "briefings" ? "is-active" : ""} onClick={() => setView("briefings")}>Briefings</button></nav>
      <header className="product-page-head"><div><span>{view === "requests" ? "Scheduling intake" : "Meeting preparation"}</span><h1>{view === "requests" ? "Requests" : "Briefings"}</h1></div><div>{view === "requests" ? <><button type="button">Extract email</button><button type="button">New request</button></> : <button type="button">Generate draft</button>}</div></header>
      <div className="product-workbench">
        {view === "requests" ? <><RequestList selectedId={selectedRequest.id} onSelect={setSelectedRequestId} /><RequestDetail request={selectedRequest} /></> : <><BriefingList selectedId={selectedBriefing.id} onSelect={setSelectedBriefingId} /><BriefingDetail briefing={selectedBriefing} /></>}
      </div>
    </main>
  </div>;
}

export default function DesignExplorationsPage() {
  const [activeId, setActiveId] = useState(concepts[0].id);
  const [theme, setTheme] = useState<Theme>("dark");
  const [view, setView] = useState<ProductView>("requests");
  const [selectedRequestId, setSelectedRequestId] = useState(requests[0].id);
  const [selectedBriefingId, setSelectedBriefingId] = useState(briefings[0].id);
  const activeConcept = concepts.find((concept) => concept.id === activeId) ?? concepts[0];

  return <main className={`design-gallery theme-${theme}`}>
    <header className="gallery-header"><div><p className="gallery-kicker">Holocron product directions</p><h1>One real workspace. Eight designs.</h1></div><p>Compare the actual Requests and Briefings workbench across every visual direction and both themes.</p></header>
    <section className="gallery-controls" aria-label="Preview controls"><div><span>Page</span><button type="button" className={view === "requests" ? "is-selected" : ""} onClick={() => setView("requests")}>Requests</button><button type="button" className={view === "briefings" ? "is-selected" : ""} onClick={() => setView("briefings")}>Briefings</button></div><div><span>Appearance</span><button type="button" className={theme === "light" ? "is-selected" : ""} aria-pressed={theme === "light"} onClick={() => setTheme("light")}>Light</button><button type="button" className={theme === "dark" ? "is-selected" : ""} aria-pressed={theme === "dark"} onClick={() => setTheme("dark")}>Dark</button></div></section>
    <nav className="concept-picker" aria-label="Design concepts">{concepts.map((concept) => <button key={concept.id} type="button" className={concept.id === activeConcept.id ? "is-selected" : ""} onClick={() => setActiveId(concept.id)}><span>{concept.family}</span><strong>{concept.title}</strong></button>)}</nav>
    <section className="concept-context" aria-live="polite"><div><span>{activeConcept.family} direction</span><h2>{activeConcept.title}</h2></div><p>{activeConcept.description}</p></section>
    <section className={`concept-frame concept-${activeConcept.id} theme-${theme}`}><Topline concept={activeConcept} theme={theme} /><Workbench concept={activeConcept} view={view} setView={setView} selectedRequestId={selectedRequestId} setSelectedRequestId={setSelectedRequestId} selectedBriefingId={selectedBriefingId} setSelectedBriefingId={setSelectedBriefingId} /></section>
    <footer className="gallery-footer">These previews use the current Cedar Grove seed records and the real Holocron workspace information architecture.</footer>
  </main>;
}
