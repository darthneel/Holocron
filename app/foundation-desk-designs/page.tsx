"use client";

import {
  ArrowUpRight,
  CalendarDays,
  Check,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  Clock3,
  ListTodo,
  Sparkles,
} from "lucide-react";
import { CSSProperties, useMemo, useState } from "react";
import { HolocronMark } from "../holocron-mark";
import "./foundation-desk-designs.css";

type ConceptId = "balanced" | "candidates" | "ledger" | "agenda" | "gradient";
type MeetingStatus = "scheduled" | "proposed";
type Day = {key: string; name: string; longName: string; month: string; date: number};
type Occurrence = {id: string; dayKey: string; time: string; end: string; slot: number; span: number};
type Meeting = {
  id: string;
  title: string;
  person: string;
  organization: string;
  location: string;
  status: MeetingStatus;
  readiness: string;
  occurrences: Occurrence[];
};
type Task = {id: string; title: string; due: string; urgent?: boolean};

const concepts: Array<{id: ConceptId; name: string; label: string; description: string; recommended?: boolean}> = [
  {id: "balanced", name: "Balanced Desk", label: "Balanced", description: "A practical three-day calendar with briefing context and tasks held close.", recommended: true},
  {id: "candidates", name: "Candidate Desk", label: "Options", description: "Multiple proposed times are treated as one grouped request across the calendar."},
  {id: "ledger", name: "Briefing Ledger", label: "Ledger", description: "A quieter document-led desk with meeting preparation taking visual priority."},
  {id: "agenda", name: "Agenda Desk", label: "Agenda", description: "Three days read as structured agendas with a compact request queue beside them."},
  {id: "gradient", name: "Gradient Desk", label: "Gradient", description: "The same operational desk with a stronger version of Holocron's coral and mineral atmosphere."},
];

const calendarDays: Day[] = [
  {key: "2026-07-20", name: "Mon", longName: "Monday", month: "Jul", date: 20},
  {key: "2026-07-21", name: "Tue", longName: "Tuesday", month: "Jul", date: 21},
  {key: "2026-07-22", name: "Wed", longName: "Wednesday", month: "Jul", date: 22},
  {key: "2026-07-23", name: "Thu", longName: "Thursday", month: "Jul", date: 23},
  {key: "2026-07-24", name: "Fri", longName: "Friday", month: "Jul", date: 24},
  {key: "2026-07-27", name: "Mon", longName: "Monday", month: "Jul", date: 27},
  {key: "2026-07-28", name: "Tue", longName: "Tuesday", month: "Jul", date: 28},
];

const meetings: Meeting[] = [
  {
    id: "cabinet",
    title: "Cabinet priorities",
    person: "Maya Chen",
    organization: "Mayor's Office",
    location: "Cabinet Room",
    status: "scheduled",
    readiness: "Briefing approved",
    occurrences: [{id: "cabinet-1", dayKey: "2026-07-20", time: "9:00 AM", end: "10:00 AM", slot: 0, span: 2}],
  },
  {
    id: "arts",
    title: "Arts grant briefing",
    person: "Avery Morgan",
    organization: "North River Arts Council",
    location: "City Hall",
    status: "proposed",
    readiness: "Two candidate windows",
    occurrences: [
      {id: "arts-1", dayKey: "2026-07-20", time: "2:00 PM", end: "2:45 PM", slot: 10, span: 2},
      {id: "arts-2", dayKey: "2026-07-21", time: "3:30 PM", end: "4:15 PM", slot: 13, span: 2},
    ],
  },
  {
    id: "mobility",
    title: "Regional mobility",
    person: "Priya Shah",
    organization: "Front Range Mobility Coalition",
    location: "Video call",
    status: "proposed",
    readiness: "Three candidate windows",
    occurrences: [
      {id: "mobility-1", dayKey: "2026-07-21", time: "10:30 AM", end: "11:15 AM", slot: 3, span: 2},
      {id: "mobility-2", dayKey: "2026-07-22", time: "4:00 PM", end: "4:45 PM", slot: 14, span: 2},
      {id: "mobility-3", dayKey: "2026-07-23", time: "1:00 PM", end: "1:45 PM", slot: 8, span: 2},
    ],
  },
  {
    id: "schools",
    title: "School safety update",
    person: "Priya Nanduri",
    organization: "Cedar Grove Public Schools",
    location: "Video call",
    status: "scheduled",
    readiness: "Two open questions",
    occurrences: [{id: "schools-1", dayKey: "2026-07-22", time: "9:30 AM", end: "10:00 AM", slot: 1, span: 1}],
  },
  {
    id: "budget",
    title: "Budget review",
    person: "Maya Chen",
    organization: "Mayor's Office",
    location: "Cabinet Room",
    status: "scheduled",
    readiness: "Briefing approved",
    occurrences: [{id: "budget-1", dayKey: "2026-07-22", time: "11:30 AM", end: "12:15 PM", slot: 5, span: 2}],
  },
  {
    id: "roundtable",
    title: "Small-business roundtable",
    person: "Darius Holt",
    organization: "Cedar Grove Chamber",
    location: "Downtown Chamber",
    status: "proposed",
    readiness: "Three candidate windows",
    occurrences: [
      {id: "roundtable-1", dayKey: "2026-07-22", time: "2:30 PM", end: "3:30 PM", slot: 11, span: 2},
      {id: "roundtable-2", dayKey: "2026-07-23", time: "11:30 AM", end: "12:30 PM", slot: 5, span: 2},
      {id: "roundtable-3", dayKey: "2026-07-24", time: "9:30 AM", end: "10:30 AM", slot: 1, span: 2},
    ],
  },
  {
    id: "planning",
    title: "Quarterly planning",
    person: "Maya Chen",
    organization: "Mayor's Office",
    location: "Strategy Room",
    status: "scheduled",
    readiness: "Briefing in review",
    occurrences: [{id: "planning-1", dayKey: "2026-07-23", time: "10:00 AM", end: "11:00 AM", slot: 2, span: 2}],
  },
  {
    id: "community",
    title: "Community office hours",
    person: "Public session",
    organization: "Cedar Grove",
    location: "Council Chambers",
    status: "scheduled",
    readiness: "Briefing ready",
    occurrences: [{id: "community-1", dayKey: "2026-07-24", time: "9:00 AM", end: "10:00 AM", slot: 0, span: 2}],
  },
  {
    id: "parks",
    title: "Parks capital update",
    person: "Sam Rivera",
    organization: "Mayor's Office",
    location: "Executive Office",
    status: "scheduled",
    readiness: "Briefing draft",
    occurrences: [{id: "parks-1", dayKey: "2026-07-27", time: "10:00 AM", end: "10:45 AM", slot: 2, span: 2}],
  },
];

const tasks: Task[] = [
  {id: "t1", title: "Approve school safety talking points", due: "Due 8:45 AM", urgent: true},
  {id: "t2", title: "Respond to mobility candidate windows", due: "Due today", urgent: true},
  {id: "t3", title: "Review roundtable attendee list", due: "Due Thursday"},
];

const hours = ["9 AM", "10 AM", "11 AM", "12 PM", "1 PM", "2 PM", "3 PM", "4 PM"];

function getGreeting() {
  const hour = Number(new Intl.DateTimeFormat("en-US", {
    hour: "numeric",
    hourCycle: "h23",
    timeZone: "America/Los_Angeles",
  }).format(new Date()));
  if (hour < 12) return "Good morning";
  if (hour < 18) return "Good afternoon";
  return "Good evening";
}

function TopNavigation() {
  return <header className="dd-top-navigation">
    <div className="dd-topline">
      <div className="dd-brand"><HolocronMark /><strong>Holocron</strong><span>|</span><small>Cedar Grove Mayor&apos;s Office</small></div>
      <div className="dd-user"><span><strong>Neel</strong><small>Workspace owner</small></span><b>NP</b></div>
    </div>
    <nav aria-label="Workspace sections">
      <button className="is-active" type="button"><small>01</small>Foundation</button>
      <button type="button"><small>02</small>Meetings</button>
      <button type="button"><small>03</small>Relationships</button>
      <button type="button"><small>04</small>Members</button>
      <button type="button"><small>05</small>Audit log</button>
    </nav>
  </header>;
}

function StatusKey() {
  return <div className="dd-status-key"><span><i className="scheduled" />Scheduled</span><span><i className="proposed" />Proposed times</span></div>;
}

function DateControls({days, canBack, canForward, direction, onNavigate}: {days: Day[]; canBack: boolean; canForward: boolean; direction: "back" | "forward"; onNavigate: (delta: number) => void}) {
  return <div className="dd-date-controls">
    <button type="button" disabled={!canBack} onClick={() => onNavigate(-1)} aria-label="Show previous three days"><ChevronLeft /></button>
    <strong>{days[0].month} {days[0].date} - {days[2].month} {days[2].date}</strong>
    <button type="button" disabled={!canForward} onClick={() => onNavigate(1)} aria-label="Show next three days"><ChevronRight /></button>
    <span className={`dd-direction-cue is-${direction}`} aria-hidden="true" />
  </div>;
}

function GreetingHeader({days, canBack, canForward, direction, onNavigate, compact = false}: {days: Day[]; canBack: boolean; canForward: boolean; direction: "back" | "forward"; onNavigate: (delta: number) => void; compact?: boolean}) {
  const greeting = useMemo(() => getGreeting(), []);
  return <section className={`dd-greeting ${compact ? "is-compact" : ""}`}>
    <div><p>{greeting}, Neel</p><h1>Mayor Park&apos;s next three days</h1><span>Briefings, proposed times, and open work in one operating view.</span></div>
    <DateControls days={days} canBack={canBack} canForward={canForward} direction={direction} onNavigate={onNavigate} />
  </section>;
}

function meetingOccurrences(days: Day[]) {
  return meetings.flatMap((meeting) => meeting.occurrences.map((occurrence, optionIndex) => ({
    meeting,
    occurrence,
    optionIndex,
    dayIndex: days.findIndex((day) => day.key === occurrence.dayKey),
  }))).filter((item) => item.dayIndex >= 0);
}

function CalendarEvent({meeting, occurrence, dayIndex, optionIndex, activeOccurrenceId, onSelect}: {meeting: Meeting; occurrence: Occurrence; dayIndex: number; optionIndex: number; activeOccurrenceId: string; onSelect: (meeting: Meeting, occurrence: Occurrence) => void}) {
  const optionCount = meeting.occurrences.length;
  const style = {"--event-day": dayIndex, "--event-slot": occurrence.slot, "--event-span": occurrence.span} as CSSProperties;
  return <button
    type="button"
    className={`dd-calendar-event is-${meeting.status} ${activeOccurrenceId === occurrence.id ? "is-selected" : ""}`}
    style={style}
    onClick={() => onSelect(meeting, occurrence)}
    aria-label={`${meeting.title}, ${meeting.status}, ${occurrence.time}${optionCount > 1 ? `, option ${optionIndex + 1} of ${optionCount}` : ""}`}
  >
    <span>{occurrence.time}</span>
    <strong>{meeting.title}</strong>
    {optionCount > 1 ? <small>Option {optionIndex + 1} of {optionCount}</small> : <small>{meeting.location}</small>}
    <ArrowUpRight aria-hidden="true" />
  </button>;
}

function ThreeDayCalendar({days, animationKey, direction, selectedOccurrenceId, onSelect}: {days: Day[]; animationKey: number; direction: "back" | "forward"; selectedOccurrenceId: string; onSelect: (meeting: Meeting, occurrence: Occurrence) => void}) {
  const visible = meetingOccurrences(days);
  return <section className="dd-calendar">
    <header><div><CalendarDays /><h2>Principal calendar</h2></div><StatusKey /></header>
    <div key={animationKey} className={`dd-calendar-window slide-${direction}`}>
      <div className="dd-calendar-corner">MDT</div>
      {days.map((day) => <div className={`dd-day-heading ${day.key === "2026-07-22" ? "is-today" : ""}`} key={day.key}><span>{day.longName}</span><strong>{day.month} {day.date}</strong></div>)}
      <div className="dd-time-axis">{hours.map((hour) => <span key={hour}>{hour}</span>)}</div>
      <div className="dd-time-lines" aria-hidden="true">{hours.map((hour) => <i key={hour} />)}</div>
      {days.map((day) => <div className="dd-day-column" key={day.key} />)}
      {visible.map(({meeting, occurrence, dayIndex, optionIndex}) => <CalendarEvent meeting={meeting} occurrence={occurrence} dayIndex={dayIndex} optionIndex={optionIndex} activeOccurrenceId={selectedOccurrenceId} onSelect={onSelect} key={occurrence.id} />)}
    </div>
  </section>;
}

function AgendaCalendar({days, animationKey, direction, selectedOccurrenceId, onSelect}: {days: Day[]; animationKey: number; direction: "back" | "forward"; selectedOccurrenceId: string; onSelect: (meeting: Meeting, occurrence: Occurrence) => void}) {
  return <section className="dd-agenda-calendar">
    <header><div><CalendarDays /><h2>Principal calendar</h2></div><StatusKey /></header>
    <div key={animationKey} className={`dd-agenda-days slide-${direction}`}>
      {days.map((day) => {
        const dayItems = meetingOccurrences([day]);
        return <article className={day.key === "2026-07-22" ? "is-today" : ""} key={day.key}>
          <header><span>{day.longName}</span><strong>{day.month} {day.date}</strong></header>
          <div>{dayItems.length ? dayItems.sort((a, b) => a.occurrence.slot - b.occurrence.slot).map(({meeting, occurrence, optionIndex}) => <button className={`dd-agenda-event is-${meeting.status} ${selectedOccurrenceId === occurrence.id ? "is-selected" : ""}`} type="button" key={occurrence.id} onClick={() => onSelect(meeting, occurrence)}><time>{occurrence.time}</time><span><strong>{meeting.title}</strong><small>{meeting.occurrences.length > 1 ? `Option ${optionIndex + 1} of ${meeting.occurrences.length}` : meeting.location}</small></span><ArrowUpRight /></button>) : <div className="dd-open-day"><Clock3 /><span>Open for principal time</span></div>}</div>
        </article>;
      })}
    </div>
  </section>;
}

function MeetingDetail({meeting, occurrence, onSelectOccurrence, mode = "panel"}: {meeting: Meeting; occurrence: Occurrence; onSelectOccurrence: (occurrence: Occurrence) => void; mode?: "panel" | "band"}) {
  const isProposed = meeting.status === "proposed";
  return <section className={`dd-meeting-detail is-${meeting.status} is-${mode}`}>
    <header><span>{isProposed ? "Meeting request" : "Meeting briefing"}</span><b>{isProposed ? `${meeting.occurrences.length} proposed times` : "Scheduled"}</b></header>
    <h2>{meeting.title}</h2>
    <p>{meeting.person}, {meeting.organization}</p>
    {isProposed ? <div className="dd-candidate-list">
      <span>Candidate windows</span>
      {meeting.occurrences.map((candidate, index) => <button className={candidate.id === occurrence.id ? "is-active" : ""} type="button" onClick={() => onSelectOccurrence(candidate)} key={candidate.id}><i>{index + 1}</i><span><strong>{calendarDays.find((day) => day.key === candidate.dayKey)?.longName}, {calendarDays.find((day) => day.key === candidate.dayKey)?.month} {calendarDays.find((day) => day.key === candidate.dayKey)?.date}</strong><small>{candidate.time} - {candidate.end}</small></span>{candidate.id === occurrence.id ? <em>Reviewing</em> : null}</button>)}
    </div> : <div className="dd-briefing-summary"><Sparkles /><span><small>Preparation</small><strong>{meeting.readiness}</strong><p>Objectives, relationship context, and open questions are ready for review.</p></span></div>}
    <dl><div><dt>Location</dt><dd>{meeting.location}</dd></div><div><dt>Principal</dt><dd>Mayor Elena Park</dd></div></dl>
    <button className="dd-primary-action" type="button">Open full {isProposed ? "request" : "briefing"}<ArrowUpRight /></button>
  </section>;
}

function OpenTasks({done, onToggle, horizontal = false}: {done: Record<string, boolean>; onToggle: (id: string) => void; horizontal?: boolean}) {
  return <section className={`dd-tasks ${horizontal ? "is-horizontal" : ""}`}>
    <header><div><ListTodo /><h2>Open tasks</h2></div><span>{tasks.filter((task) => !done[task.id]).length}</span></header>
    <div>{tasks.map((task) => <button className={done[task.id] ? "is-done" : ""} type="button" key={task.id} onClick={() => onToggle(task.id)}><i>{done[task.id] ? <Check /> : null}</i><span><strong>{task.title}</strong><small className={task.urgent ? "is-urgent" : ""}>{task.due}</small></span></button>)}</div>
  </section>;
}

type SharedProps = {
  days: Day[];
  dayStart: number;
  direction: "back" | "forward";
  selectedMeeting: Meeting;
  selectedOccurrence: Occurrence;
  done: Record<string, boolean>;
  onNavigate: (delta: number) => void;
  onSelect: (meeting: Meeting, occurrence: Occurrence) => void;
  onSelectOccurrence: (occurrence: Occurrence) => void;
  onToggleTask: (id: string) => void;
};

function headerProps(props: SharedProps) {
  return {days: props.days, canBack: props.dayStart > 0, canForward: props.dayStart < calendarDays.length - 3, direction: props.direction, onNavigate: props.onNavigate};
}

function BalancedDesk(props: SharedProps) {
  return <DeskShell className="dd-balanced">
    <GreetingHeader {...headerProps(props)} />
    <div className="dd-balanced-grid">
      <ThreeDayCalendar days={props.days} animationKey={props.dayStart} direction={props.direction} selectedOccurrenceId={props.selectedOccurrence.id} onSelect={props.onSelect} />
      <aside><MeetingDetail meeting={props.selectedMeeting} occurrence={props.selectedOccurrence} onSelectOccurrence={props.onSelectOccurrence} /><OpenTasks done={props.done} onToggle={props.onToggleTask} /></aside>
    </div>
  </DeskShell>;
}

function CandidateDesk(props: SharedProps) {
  const proposed = meetings.filter((meeting) => meeting.status === "proposed");
  return <DeskShell className="dd-candidates">
    <GreetingHeader {...headerProps(props)} compact />
    <section className="dd-option-ribbon"><div><CircleAlert /><span><strong>3 requests have multiple proposed times</strong><small>Each dashed calendar block opens the same request.</small></span></div>{proposed.map((meeting) => <button className={meeting.id === props.selectedMeeting.id ? "is-active" : ""} type="button" key={meeting.id} onClick={() => props.onSelect(meeting, meeting.occurrences[0])}><span>{meeting.occurrences.length} options</span><strong>{meeting.title}</strong></button>)}</section>
    <div className="dd-candidate-grid"><ThreeDayCalendar days={props.days} animationKey={props.dayStart} direction={props.direction} selectedOccurrenceId={props.selectedOccurrence.id} onSelect={props.onSelect} /><MeetingDetail meeting={props.selectedMeeting} occurrence={props.selectedOccurrence} onSelectOccurrence={props.onSelectOccurrence} /></div>
  </DeskShell>;
}

function LedgerDesk(props: SharedProps) {
  return <DeskShell className="dd-ledger">
    <GreetingHeader {...headerProps(props)} compact />
    <div className="dd-ledger-grid">
      <MeetingDetail meeting={props.selectedMeeting} occurrence={props.selectedOccurrence} onSelectOccurrence={props.onSelectOccurrence} />
      <ThreeDayCalendar days={props.days} animationKey={props.dayStart} direction={props.direction} selectedOccurrenceId={props.selectedOccurrence.id} onSelect={props.onSelect} />
    </div>
    <OpenTasks done={props.done} onToggle={props.onToggleTask} horizontal />
  </DeskShell>;
}

function AgendaDesk(props: SharedProps) {
  return <DeskShell className="dd-agenda">
    <GreetingHeader {...headerProps(props)} compact />
    <div className="dd-agenda-grid">
      <AgendaCalendar days={props.days} animationKey={props.dayStart} direction={props.direction} selectedOccurrenceId={props.selectedOccurrence.id} onSelect={props.onSelect} />
      <aside><section className="dd-attention"><span>Needs attention</span><strong>Five proposed windows</strong><p>Three requests are waiting for a scheduling decision.</p></section><OpenTasks done={props.done} onToggle={props.onToggleTask} /></aside>
    </div>
    <MeetingDetail mode="band" meeting={props.selectedMeeting} occurrence={props.selectedOccurrence} onSelectOccurrence={props.onSelectOccurrence} />
  </DeskShell>;
}

function GradientDesk(props: SharedProps) {
  return <DeskShell className="dd-gradient">
    <GreetingHeader {...headerProps(props)} />
    <div className="dd-gradient-grid">
      <ThreeDayCalendar days={props.days} animationKey={props.dayStart} direction={props.direction} selectedOccurrenceId={props.selectedOccurrence.id} onSelect={props.onSelect} />
      <aside><MeetingDetail meeting={props.selectedMeeting} occurrence={props.selectedOccurrence} onSelectOccurrence={props.onSelectOccurrence} /><section className="dd-gradient-signal"><span>Briefing readiness</span><strong>4 meetings ready</strong><p>School safety has two open questions before tomorrow morning.</p></section></aside>
    </div>
    <OpenTasks done={props.done} onToggle={props.onToggleTask} horizontal />
  </DeskShell>;
}

function DeskShell({className, children}: {className: string; children: React.ReactNode}) {
  return <div className={`dd-product-shell ${className}`}><TopNavigation /><main>{children}</main></div>;
}

export default function FoundationDeskDesignsPage() {
  const [activeId, setActiveId] = useState<ConceptId>("balanced");
  const [dayStart, setDayStart] = useState(0);
  const [direction, setDirection] = useState<"back" | "forward">("forward");
  const [selectedMeetingId, setSelectedMeetingId] = useState("mobility");
  const [selectedOccurrenceId, setSelectedOccurrenceId] = useState("mobility-1");
  const [done, setDone] = useState<Record<string, boolean>>({});
  const activeConcept = concepts.find((concept) => concept.id === activeId) ?? concepts[0];
  const days = calendarDays.slice(dayStart, dayStart + 3);
  const selectedMeeting = meetings.find((meeting) => meeting.id === selectedMeetingId) ?? meetings[2];
  const selectedOccurrence = selectedMeeting.occurrences.find((occurrence) => occurrence.id === selectedOccurrenceId) ?? selectedMeeting.occurrences[0];

  function navigate(delta: number) {
    setDirection(delta > 0 ? "forward" : "back");
    setDayStart((current) => Math.min(calendarDays.length - 3, Math.max(0, current + delta)));
  }

  function selectMeeting(meeting: Meeting, occurrence: Occurrence) {
    setSelectedMeetingId(meeting.id);
    setSelectedOccurrenceId(occurrence.id);
  }

  function selectOccurrence(occurrence: Occurrence) {
    setSelectedOccurrenceId(occurrence.id);
    const occurrenceIndex = calendarDays.findIndex((day) => day.key === occurrence.dayKey);
    if (occurrenceIndex < dayStart || occurrenceIndex > dayStart + 2) {
      setDirection(occurrenceIndex > dayStart ? "forward" : "back");
      setDayStart(Math.min(calendarDays.length - 3, Math.max(0, occurrenceIndex - 1)));
    }
  }

  const shared: SharedProps = {days, dayStart, direction, selectedMeeting, selectedOccurrence, done, onNavigate: navigate, onSelect: selectMeeting, onSelectOccurrence: selectOccurrence, onToggleTask: (id) => setDone((current) => ({...current, [id]: !current[id]}))};

  return <main className="desk-design-lab">
    <header className="dd-lab-header"><div><span>Holocron design study</span><h1>Five more Desk directions</h1><p>Three-day calendar prototypes with the production top navigation and grouped candidate times.</p></div><a href="/foundation-designs">Previous round <ArrowUpRight /></a></header>
    <nav className="dd-concept-picker" aria-label="Desk design concepts">{concepts.map((concept, index) => <button type="button" className={activeId === concept.id ? "is-active" : ""} onClick={() => setActiveId(concept.id)} key={concept.id}><small>0{index + 1}</small><span><strong>{concept.label}</strong>{concept.recommended ? <em>Recommended</em> : null}</span></button>)}</nav>
    <section className="dd-concept-summary"><div><span>Current direction</span><h2>{activeConcept.name}</h2></div><p>{activeConcept.description}</p></section>
    <section className="dd-stage">
      {activeId === "balanced" ? <BalancedDesk {...shared} /> : null}
      {activeId === "candidates" ? <CandidateDesk {...shared} /> : null}
      {activeId === "ledger" ? <LedgerDesk {...shared} /> : null}
      {activeId === "agenda" ? <AgendaDesk {...shared} /> : null}
      {activeId === "gradient" ? <GradientDesk {...shared} /> : null}
    </section>
    <footer className="dd-lab-footer"><span>Scheduled meetings use coral and open a briefing.</span><span>Proposed meetings use mineral blue. Every candidate block opens the same request.</span></footer>
  </main>;
}
