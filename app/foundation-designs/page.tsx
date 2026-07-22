"use client";

import {
  ArrowLeft,
  ArrowRight,
  ArrowUpRight,
  CalendarDays,
  Check,
  ChevronLeft,
  ChevronRight,
  CircleAlert,
  Clock3,
  FileText,
  Inbox,
  LayoutDashboard,
  ListTodo,
  Sparkles,
  Users,
  X,
} from "lucide-react";
import { CSSProperties, useState } from "react";
import { HolocronMark } from "../holocron-mark";
import "./foundation-designs.css";

type EventStatus = "scheduled" | "proposed";
type CalendarEvent = {
  id: string;
  day: number;
  date: number;
  start: string;
  end: string;
  slot: number;
  span: number;
  title: string;
  person: string;
  organization: string;
  location: string;
  status: EventStatus;
  preparation: string;
};

type Task = {
  id: string;
  title: string;
  due: string;
  tone: "urgent" | "normal";
};

type Concept = {
  id: "week-command" | "day-focus" | "month-pulse" | "briefing-desk" | "horizon";
  title: string;
  shortTitle: string;
  description: string;
  recommendation?: string;
};

const concepts: Concept[] = [
  {
    id: "week-command",
    title: "Week Command",
    shortTitle: "Week",
    description: "The strongest all-purpose dashboard: a true workweek calendar with a compact action rail.",
    recommendation: "Recommended",
  },
  {
    id: "day-focus",
    title: "Day Focus",
    shortTitle: "Day",
    description: "A calmer daily timeline with more room for preparation, travel, and the next decision.",
  },
  {
    id: "month-pulse",
    title: "Month Pulse",
    shortTitle: "Month",
    description: "A month-scale planning surface for balancing proposed meetings against confirmed commitments.",
  },
  {
    id: "briefing-desk",
    title: "Briefing Desk",
    shortTitle: "Desk",
    description: "A three-day calendar paired with a persistent destination preview for every meeting.",
  },
  {
    id: "horizon",
    title: "Horizon",
    shortTitle: "Horizon",
    description: "A colorful, glanceable week built around time bands, protected focus, and office signals.",
  },
];

const weekDays = [
  {name: "Mon", date: 20},
  {name: "Tue", date: 21},
  {name: "Wed", date: 22},
  {name: "Thu", date: 23},
  {name: "Fri", date: 24},
];

const events: CalendarEvent[] = [
  {id: "cabinet", day: 0, date: 20, start: "9:00 AM", end: "10:00 AM", slot: 0, span: 2, title: "Cabinet priorities", person: "Maya Chen", organization: "Mayor's Office", location: "Cabinet Room", status: "scheduled", preparation: "Briefing approved"},
  {id: "arts", day: 0, date: 20, start: "2:00 PM", end: "2:45 PM", slot: 10, span: 2, title: "Arts grant briefing", person: "Avery Morgan", organization: "North River Arts Council", location: "City Hall", status: "proposed", preparation: "Candidate window"},
  {id: "mobility", day: 1, date: 21, start: "10:30 AM", end: "11:15 AM", slot: 3, span: 2, title: "Regional mobility", person: "Priya Shah", organization: "Front Range Mobility Coalition", location: "Video call", status: "proposed", preparation: "Needs response"},
  {id: "press", day: 1, date: 21, start: "3:30 PM", end: "4:00 PM", slot: 13, span: 1, title: "Press preparation", person: "Sam Rivera", organization: "Mayor's Office", location: "Executive Office", status: "scheduled", preparation: "Briefing ready"},
  {id: "schools", day: 2, date: 22, start: "9:30 AM", end: "10:00 AM", slot: 1, span: 1, title: "School safety update", person: "Priya Nanduri", organization: "Cedar Grove Public Schools", location: "Video call", status: "scheduled", preparation: "2 open questions"},
  {id: "budget", day: 2, date: 22, start: "11:30 AM", end: "12:15 PM", slot: 5, span: 2, title: "Budget review", person: "Maya Chen", organization: "Mayor's Office", location: "Cabinet Room", status: "scheduled", preparation: "Briefing approved"},
  {id: "roundtable", day: 2, date: 22, start: "2:30 PM", end: "3:30 PM", slot: 11, span: 2, title: "Small-business roundtable", person: "Darius Holt", organization: "Cedar Grove Chamber", location: "Downtown Chamber", status: "proposed", preparation: "Awaiting confirmation"},
  {id: "planning", day: 3, date: 23, start: "10:00 AM", end: "11:00 AM", slot: 2, span: 2, title: "Quarterly planning", person: "Maya Chen", organization: "Mayor's Office", location: "Strategy Room", status: "scheduled", preparation: "Briefing in review"},
  {id: "developers", day: 3, date: 23, start: "1:00 PM", end: "1:45 PM", slot: 8, span: 2, title: "Riverfront development", person: "Rafael Kim", organization: "Planning Coalition", location: "Mayor's Office", status: "proposed", preparation: "Review request"},
  {id: "community", day: 4, date: 24, start: "9:00 AM", end: "10:00 AM", slot: 0, span: 2, title: "Community office hours", person: "Public session", organization: "Cedar Grove", location: "Council Chambers", status: "scheduled", preparation: "Briefing ready"},
  {id: "staff", day: 4, date: 24, start: "3:00 PM", end: "3:30 PM", slot: 12, span: 1, title: "Senior staff check-in", person: "Leadership team", organization: "Mayor's Office", location: "Cabinet Room", status: "scheduled", preparation: "No preparation needed"},
];

const tasks: Task[] = [
  {id: "task-1", title: "Approve school safety talking points", due: "Due 8:45 AM", tone: "urgent"},
  {id: "task-2", title: "Respond to mobility candidate window", due: "Due today", tone: "urgent"},
  {id: "task-3", title: "Review roundtable attendee list", due: "Due Thursday", tone: "normal"},
  {id: "task-4", title: "Confirm arts council location", due: "Due Friday", tone: "normal"},
];

const hours = ["9 AM", "10 AM", "11 AM", "12 PM", "1 PM", "2 PM", "3 PM", "4 PM"];

function StatusKey({compact = false}: {compact?: boolean}) {
  return <div className={`fd-status-key ${compact ? "is-compact" : ""}`} aria-label="Calendar status key">
    <span><i className="scheduled" />Scheduled</span>
    <span><i className="proposed" />Proposed</span>
  </div>;
}

function CalendarEventButton({event, onOpen, mode = "grid"}: {event: CalendarEvent; onOpen: (event: CalendarEvent) => void; mode?: "grid" | "agenda" | "chip" | "lane"}) {
  const style = mode === "grid" ? ({"--event-day": event.day, "--event-slot": event.slot, "--event-span": event.span} as CSSProperties) : undefined;
  return <button
    className={`fd-event fd-event-${mode} is-${event.status}`}
    style={style}
    type="button"
    onClick={() => onOpen(event)}
    aria-label={`${event.title}, ${event.status}, ${event.start}`}
  >
    <span className="fd-event-time">{event.start}</span>
    <strong>{event.title}</strong>
    {mode !== "chip" ? <small>{event.location}</small> : null}
    <ArrowUpRight aria-hidden="true" />
  </button>;
}

function OpenTasks({done, onToggle, condensed = false}: {done: Record<string, boolean>; onToggle: (id: string) => void; condensed?: boolean}) {
  const openCount = tasks.filter((task) => !done[task.id]).length;
  return <section className={`fd-tasks ${condensed ? "is-condensed" : ""}`}>
    <header><div><ListTodo aria-hidden="true" /><h3>Open tasks</h3></div><span>{openCount}</span></header>
    <div className="fd-task-list">
      {tasks.map((task) => <button className={done[task.id] ? "is-done" : ""} type="button" key={task.id} onClick={() => onToggle(task.id)}>
        <i>{done[task.id] ? <Check aria-hidden="true" /> : null}</i>
        <span><strong>{task.title}</strong><small className={task.tone === "urgent" ? "is-urgent" : ""}>{task.due}</small></span>
      </button>)}
    </div>
  </section>;
}

function OfficeNav() {
  return <aside className="fd-sidebar">
    <div className="fd-brand"><HolocronMark /><span><strong>Holocron</strong><small>Cedar Grove Mayor&apos;s Office</small></span></div>
    <nav aria-label="Prototype workspace sections">
      <button className="is-active" type="button"><LayoutDashboard aria-hidden="true" /><span><small>01</small>Foundation</span></button>
      <button type="button"><CalendarDays aria-hidden="true" /><span><small>02</small>Meetings</span></button>
      <button type="button"><Users aria-hidden="true" /><span><small>03</small>Relationships</span></button>
      <button type="button"><Inbox aria-hidden="true" /><span><small>04</small>Members</span></button>
      <button type="button"><FileText aria-hidden="true" /><span><small>05</small>Audit log</span></button>
    </nav>
    <footer><b>NP</b><span><strong>Neel</strong><small>Workspace owner</small></span></footer>
  </aside>;
}

function WorkspaceHeader({title = "Foundation"}: {title?: string}) {
  return <header className="fd-workspace-header">
    <div><span>Workspace</span><strong>{title}</strong></div>
    <div className="fd-principal"><span><strong>Mayor Elena Park</strong><small>Principal calendar</small></span><b>EP</b></div>
  </header>;
}

function Shell({children, className}: {children: React.ReactNode; className: string}) {
  return <div className={`fd-shell ${className}`}>
    <OfficeNav />
    <WorkspaceHeader />
    <main>{children}</main>
  </div>;
}

function WeekGrid({onOpen, dayCount = 5}: {onOpen: (event: CalendarEvent) => void; dayCount?: number}) {
  const displayedDays = weekDays.slice(0, dayCount);
  const displayedEvents = events.filter((event) => event.day < dayCount);
  return <div className="fd-week-grid" style={{"--day-count": dayCount} as CSSProperties}>
    <div className="fd-week-corner">MDT</div>
    {displayedDays.map((day, index) => <div className={`fd-day-head ${index === 2 ? "is-today" : ""}`} key={day.name}><span>{day.name}</span><strong>{day.date}</strong></div>)}
    <div className="fd-time-axis">{hours.map((hour) => <span key={hour}>{hour}</span>)}</div>
    <div className="fd-grid-lines" aria-hidden="true">{hours.map((hour) => <i key={hour} />)}</div>
    {displayedDays.map((day) => <div className="fd-day-column" key={day.name} />)}
    {displayedEvents.map((event) => <CalendarEventButton event={event} key={event.id} onOpen={onOpen} />)}
  </div>;
}

function WeekCommand({onOpen, done, onToggle}: PrototypeProps) {
  return <Shell className="fd-week-command">
    <div className="fd-page-heading">
      <div><p>Good morning, Neel</p><h1>Mayor Park&apos;s week</h1></div>
      <div className="fd-date-controls"><button type="button" aria-label="Previous week"><ChevronLeft /></button><strong>July 20-24</strong><button type="button" aria-label="Next week"><ChevronRight /></button><button type="button">Today</button></div>
    </div>
    <div className="fd-command-layout">
      <section className="fd-calendar-panel">
        <header><div><CalendarDays /><h2>Principal calendar</h2></div><StatusKey /></header>
        <WeekGrid onOpen={onOpen} />
      </section>
      <aside className="fd-command-rail">
        <OpenTasks done={done} onToggle={onToggle} condensed />
        <section className="fd-signal-card fd-briefing-ready"><span><Sparkles />Briefing readiness</span><strong>4 of 5 ready</strong><p>School safety still has two open questions.</p><button type="button" onClick={() => onOpen(events[4])}>Review briefing <ArrowRight /></button></section>
        <section className="fd-signal-card fd-decision-card"><span><CircleAlert />Decision waiting</span><strong>Regional mobility</strong><p>Priya Shah proposed Tuesday at 10:30 AM.</p><button type="button" onClick={() => onOpen(events[2])}>Open request <ArrowRight /></button></section>
      </aside>
    </div>
  </Shell>;
}

function DayFocus({onOpen, done, onToggle}: PrototypeProps) {
  const todayEvents = events.filter((event) => event.day === 2);
  return <Shell className="fd-day-focus">
    <div className="fd-day-hero">
      <div><p>Wednesday, July 22</p><h1>Three meetings.<br />Two decisions.</h1><span>Mayor Park&apos;s day is 58% committed, with a protected 90-minute focus block.</span></div>
      <div className="fd-day-stat"><Clock3 /><span>Next meeting</span><strong>School safety update</strong><small>9:30 AM, video call</small></div>
    </div>
    <div className="fd-focus-layout">
      <section className="fd-focus-timeline">
        <header><h2>Today</h2><StatusKey /></header>
        <div className="fd-agenda-list">
          {hours.map((hour, index) => <div className="fd-agenda-row" key={hour}><time>{hour}</time><div>{todayEvents.filter((event) => Math.floor(event.slot / 2) === index).map((event) => <CalendarEventButton mode="agenda" event={event} key={event.id} onOpen={onOpen} />)}{index === 7 ? <span className="fd-focus-block">Focus time</span> : null}</div></div>)}
        </div>
      </section>
      <aside className="fd-focus-side">
        <section className="fd-next-decision"><span>Needs your response</span><h2>Small-business roundtable</h2><p>Darius Holt requested a one-hour meeting with the Mayor and senior advisor.</p><button type="button" onClick={() => onOpen(events[6])}>Review proposed meeting <ArrowUpRight /></button></section>
        <OpenTasks done={done} onToggle={onToggle} condensed />
        <section className="fd-relationship-note"><Users /><div><span>Relationship context</span><strong>6 prior interactions with the Chamber</strong><small>Last contact was 28 days ago.</small></div></section>
      </aside>
    </div>
  </Shell>;
}

const monthCells = [
  {date: 29, muted: true}, {date: 30, muted: true}, {date: 1}, {date: 2}, {date: 3}, {date: 4}, {date: 5},
  {date: 6}, {date: 7}, {date: 8}, {date: 9}, {date: 10}, {date: 11}, {date: 12},
  {date: 13}, {date: 14}, {date: 15}, {date: 16}, {date: 17}, {date: 18}, {date: 19},
  {date: 20}, {date: 21}, {date: 22, today: true}, {date: 23}, {date: 24}, {date: 25}, {date: 26},
  {date: 27}, {date: 28}, {date: 29}, {date: 30}, {date: 31}, {date: 1, muted: true}, {date: 2, muted: true},
];

function MonthPulse({onOpen, done, onToggle}: PrototypeProps) {
  return <Shell className="fd-month-pulse">
    <div className="fd-month-heading">
      <div><span>Principal calendar</span><h1>July 2026</h1></div>
      <div><StatusKey /><button type="button"><ChevronLeft /></button><button type="button"><ChevronRight /></button></div>
    </div>
    <div className="fd-month-layout">
      <section className="fd-month-calendar">
        <header>{["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((day) => <span key={day}>{day}</span>)}</header>
        <div className="fd-month-cells">
          {monthCells.map((cell, index) => {
            const cellEvents = !cell.muted ? events.filter((event) => event.date === cell.date) : [];
            return <div className={`${cell.muted ? "is-muted" : ""} ${cell.today ? "is-today" : ""}`} key={`${cell.date}-${index}`}>
              <time>{cell.date}</time>
              {cellEvents.slice(0, 2).map((event) => <CalendarEventButton mode="chip" event={event} key={event.id} onOpen={onOpen} />)}
            </div>;
          })}
        </div>
      </section>
      <aside className="fd-month-rail">
        <section className="fd-balance-card"><span>Calendar balance</span><strong>18.5 hours committed</strong><div><i style={{"--fill": "67%"} as CSSProperties} /><small>67% scheduled</small></div><p>Thursday afternoon remains the best window for external meetings.</p></section>
        <section className="fd-month-requests"><header><h3>Proposed meetings</h3><span>4</span></header>{events.filter((event) => event.status === "proposed").slice(0, 3).map((event) => <button type="button" onClick={() => onOpen(event)} key={event.id}><i /><span><strong>{event.title}</strong><small>{event.person}, {event.start}</small></span><ArrowRight /></button>)}</section>
        <OpenTasks done={done} onToggle={onToggle} condensed />
      </aside>
    </div>
  </Shell>;
}

function BriefingDesk({onOpen, done, onToggle, selected}: PrototypeProps & {selected: CalendarEvent}) {
  return <Shell className="fd-briefing-desk">
    <div className="fd-desk-heading"><div><span>Foundation</span><h1>Calendar and context</h1></div><div className="fd-date-controls"><button type="button"><ArrowLeft /></button><strong>July 21-23</strong><button type="button"><ArrowRight /></button></div></div>
    <div className="fd-desk-layout">
      <section className="fd-desk-calendar">
        <header><h2>Principal calendar</h2><StatusKey /></header>
        <WeekGrid onOpen={onOpen} dayCount={3} />
      </section>
      <aside className={`fd-destination-preview is-${selected.status}`}>
        <div className="fd-preview-image"><span>{selected.status === "scheduled" ? "Briefing" : "Meeting request"}</span></div>
        <div className="fd-preview-copy">
          <span>{selected.start}, {selected.location}</span>
          <h2>{selected.title}</h2>
          <p>{selected.person}, {selected.organization}</p>
          <div className="fd-preview-facts"><div><small>Status</small><strong>{selected.status}</strong></div><div><small>Preparation</small><strong>{selected.preparation}</strong></div></div>
          <button type="button" onClick={() => onOpen(selected)}>Open {selected.status === "scheduled" ? "briefing" : "meeting request"}<ArrowUpRight /></button>
        </div>
      </aside>
    </div>
    <OpenTasks done={done} onToggle={onToggle} />
  </Shell>;
}

function Horizon({onOpen, done, onToggle}: PrototypeProps) {
  return <Shell className="fd-horizon">
    <div className="fd-horizon-hero">
      <div><p>Good morning, Neel</p><h1>Clear the path for the week ahead.</h1></div>
      <section><span>Attention</span><strong>2 proposed meetings need a response today.</strong><button type="button" onClick={() => onOpen(events[2])}>Review now <ArrowRight /></button></section>
    </div>
    <section className="fd-horizon-calendar">
      <header><div><span>Mayor Elena Park</span><h2>Week of July 20</h2></div><StatusKey /></header>
      <div className="fd-horizon-days">
        {weekDays.map((day, index) => <article className={index === 2 ? "is-today" : ""} key={day.name}>
          <header><span>{day.name}</span><strong>{day.date}</strong></header>
          <div>{events.filter((event) => event.day === index).map((event) => <CalendarEventButton mode="lane" event={event} key={event.id} onOpen={onOpen} />)}{events.filter((event) => event.day === index).length < 2 ? <span className="fd-open-window">Open after 10 AM</span> : null}</div>
        </article>)}
      </div>
    </section>
    <div className="fd-horizon-lower">
      <OpenTasks done={done} onToggle={onToggle} condensed />
      <section className="fd-horizon-intel">
        <div><span>Briefing ready</span><strong>Budget review</strong><p>Decision memo and revenue outlook are attached.</p></div>
        <div><span>Relationship watch</span><strong>Cedar Grove Chamber</strong><p>Engagement has increased across three policy topics.</p></div>
        <div><span>Protected time</span><strong>4.5 hours</strong><p>Focus blocks remain intact across Wednesday and Friday.</p></div>
      </section>
    </div>
  </Shell>;
}

type PrototypeProps = {
  onOpen: (event: CalendarEvent) => void;
  done: Record<string, boolean>;
  onToggle: (id: string) => void;
};

function DestinationDrawer({event, onClose}: {event: CalendarEvent; onClose: () => void}) {
  const isBriefing = event.status === "scheduled";
  return <aside className={`fd-drawer is-${event.status}`} role="dialog" aria-modal="true" aria-label={isBriefing ? "Briefing preview" : "Meeting request preview"}>
    <header><span>{isBriefing ? "Briefing" : "Meeting request"}</span><button type="button" onClick={onClose} aria-label="Close preview"><X /></button></header>
    <div className="fd-drawer-state"><i>{isBriefing ? <FileText /> : <CalendarDays />}</i><span><small>{event.start} - {event.end}</small><strong>{isBriefing ? "Scheduled" : "Proposed"}</strong></span></div>
    <h2>{event.title}</h2>
    <p>{event.person}, {event.organization}</p>
    <dl><div><dt>Location</dt><dd>{event.location}</dd></div><div><dt>Preparation</dt><dd>{event.preparation}</dd></div><div><dt>Principal</dt><dd>Mayor Elena Park</dd></div></dl>
    {isBriefing ? <section><span>Briefing snapshot</span><p>Review objectives, relationship history, open questions, and the latest approved talking points.</p></section> : <section><span>Request snapshot</span><p>Review the requester, candidate window, participants, and any scheduling constraints before responding.</p></section>}
    <button className="fd-drawer-primary" type="button">Open full {isBriefing ? "briefing" : "request"}<ArrowUpRight /></button>
  </aside>;
}

export default function FoundationDesignsPage() {
  const [activeId, setActiveId] = useState<Concept["id"]>("week-command");
  const [selectedEvent, setSelectedEvent] = useState<CalendarEvent | null>(null);
  const [lastSelected, setLastSelected] = useState<CalendarEvent>(events[4]);
  const [done, setDone] = useState<Record<string, boolean>>({});
  const activeConcept = concepts.find((concept) => concept.id === activeId) ?? concepts[0];

  function openEvent(event: CalendarEvent) {
    setLastSelected(event);
    setSelectedEvent(event);
  }

  function toggleTask(id: string) {
    setDone((current) => ({...current, [id]: !current[id]}));
  }

  const prototypeProps = {onOpen: openEvent, done, onToggle: toggleTask};

  return <main className="foundation-lab">
    <header className="fd-lab-header">
      <div><span>Holocron design study</span><h1>Foundation dashboard prototypes</h1><p>Five calendar-first directions grounded in the current app&apos;s dark, editorial operating system.</p></div>
      <a href="/designs">View prior explorations <ArrowUpRight /></a>
    </header>
    <nav className="fd-concept-picker" aria-label="Foundation design prototypes">
      {concepts.map((concept, index) => <button className={concept.id === activeId ? "is-active" : ""} type="button" onClick={() => {setActiveId(concept.id); setSelectedEvent(null);}} key={concept.id}>
        <small>0{index + 1}</small><span><strong>{concept.shortTitle}</strong>{concept.recommendation ? <em>{concept.recommendation}</em> : null}</span>
      </button>)}
    </nav>
    <section className="fd-concept-summary" aria-live="polite"><div><span>Current direction</span><h2>{activeConcept.title}</h2></div><p>{activeConcept.description}</p></section>
    <section className="fd-prototype-stage">
      {activeId === "week-command" ? <WeekCommand {...prototypeProps} /> : null}
      {activeId === "day-focus" ? <DayFocus {...prototypeProps} /> : null}
      {activeId === "month-pulse" ? <MonthPulse {...prototypeProps} /> : null}
      {activeId === "briefing-desk" ? <BriefingDesk {...prototypeProps} selected={lastSelected} /> : null}
      {activeId === "horizon" ? <Horizon {...prototypeProps} /> : null}
      {selectedEvent ? <><button className="fd-drawer-scrim" type="button" aria-label="Close preview" onClick={() => setSelectedEvent(null)} /><DestinationDrawer event={selectedEvent} onClose={() => setSelectedEvent(null)} /></> : null}
    </section>
    <footer className="fd-lab-footer"><span>Prototype data uses the Cedar Grove workspace and representative calendar states.</span><span>Scheduled opens a briefing. Proposed opens a meeting request.</span></footer>
  </main>;
}
