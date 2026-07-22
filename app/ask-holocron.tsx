"use client";

import {
  ArrowUp,
  BookOpen,
  CircleHelp,
  MessageSquareText,
  Sparkles,
} from "lucide-react";
import {FormEvent, KeyboardEvent, useState} from "react";

type AskClaim = {
  text: string;
  source_refs: string[];
};

type AskSource = {
  source_ref: string;
  source_type: "interaction";
  source_id: string;
  person_name: string | null;
  organization_name: string | null;
  interaction_type: string;
  occurred_at: string;
  excerpt: string;
};

type AskResult = {
  question: string;
  answer: string;
  claims: AskClaim[];
  sources: AskSource[];
  limitations: string[];
};

type AskErrorResponse = {
  error?: string;
  fields?: Record<string, string>;
};

function formatSourceDate(value: string) {
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat("en-US", {
    month: "short",
    day: "numeric",
    year: "numeric",
  }).format(date);
}

function formatInteractionType(value: string) {
  return value
    .split("_")
    .map((word) => word[0]?.toUpperCase() + word.slice(1))
    .join(" ");
}

function sourceDomId(sourceRef: string) {
  return `ask-source-${sourceRef.replace(/[^a-zA-Z0-9_-]/g, "-")}`;
}

export function AskHolocron({apiUrl, actorEmail, canAsk}: {
  apiUrl: string;
  actorEmail: string;
  canAsk: boolean;
}) {
  const [question, setQuestion] = useState("");
  const [result, setResult] = useState<AskResult | null>(null);
  const [error, setError] = useState("");
  const [fieldError, setFieldError] = useState("");
  const [isLoading, setIsLoading] = useState(false);

  async function ask(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalizedQuestion = question.trim();
    setError("");
    setFieldError("");

    if (normalizedQuestion.length < 3) {
      setFieldError("Enter a question with at least 3 characters.");
      return;
    }
    if (normalizedQuestion.length > 1_000) {
      setFieldError("Keep the question to 1,000 characters or fewer.");
      return;
    }
    if (!canAsk) {
      setError("Ask Holocron is available to active workspace members.");
      return;
    }

    setIsLoading(true);
    setResult(null);
    try {
      const response = await fetch(`${apiUrl}/api/ask`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "X-Holocron-Actor-Email": actorEmail,
        },
        body: JSON.stringify({question: normalizedQuestion}),
      });
      const body = await response.json() as AskResult & AskErrorResponse;
      if (!response.ok) {
        if (body.fields?.question) setFieldError(body.fields.question);
        throw new Error(body.error ?? "Ask Holocron could not complete the request.");
      }
      setResult(body);
    } catch (requestError) {
      setError(
        requestError instanceof Error
          ? requestError.message
          : "Ask Holocron could not complete the request.",
      );
    } finally {
      setIsLoading(false);
    }
  }

  function handleQuestionKeyDown(event: KeyboardEvent<HTMLTextAreaElement>) {
    if (event.key !== "Enter" || event.shiftKey || event.nativeEvent.isComposing) return;
    event.preventDefault();
    event.currentTarget.form?.requestSubmit();
  }

  return (
    <section id="ask" className="workspace-section ask-holocron-view">
      <header className="ask-holocron-heading">
        <div>
          <p className="eyebrow">Workspace intelligence</p>
          <h1>Ask Holocron</h1>
          <p>Ask one question about the people, organizations, and topics recorded in interaction history.</p>
        </div>
        <span className="ask-scope-note"><BookOpen aria-hidden="true" />Interactions only</span>
      </header>

      <form className="ask-composer" onSubmit={ask} aria-busy={isLoading}>
        <label htmlFor="ask-question">Question</label>
        <div className="ask-input-row">
          <textarea
            id="ask-question"
            name="question"
            rows={3}
            maxLength={1_000}
            value={question}
            onChange={(event) => setQuestion(event.target.value)}
            onKeyDown={handleQuestionKeyDown}
            placeholder="What do we know about Darius Holt?"
            aria-describedby="ask-question-help ask-question-error"
            aria-invalid={Boolean(fieldError)}
            disabled={isLoading || !canAsk}
          />
          <button type="submit" disabled={isLoading || !canAsk || question.trim().length < 3}>
            <span>{isLoading ? "Asking" : "Ask Holocron"}</span>
            <ArrowUp aria-hidden="true" />
          </button>
        </div>
        <div className="ask-composer-meta">
          <span id="ask-question-help">Enter to ask. Shift + Enter for a new line.</span>
          <span>{question.length}/1,000</span>
        </div>
        {!canAsk ? <p className="ask-access-note">Sign in with an active workspace member email to ask a question.</p> : null}
        {fieldError ? <p id="ask-question-error" className="ask-inline-error" role="alert">{fieldError}</p> : null}
      </form>

      {error ? <div className="ask-error-state" role="alert"><CircleHelp aria-hidden="true" /><div><strong>Unable to answer</strong><p>{error}</p></div></div> : null}

      {isLoading ? (
        <div className="ask-loading-state" role="status" aria-live="polite">
          <span className="ask-loading-label"><Sparkles aria-hidden="true" />Reviewing interaction history</span>
          <span className="ask-skeleton ask-skeleton-wide" />
          <span className="ask-skeleton" />
          <span className="ask-skeleton ask-skeleton-short" />
        </div>
      ) : null}

      {!isLoading && !result && !error ? (
        <div className="ask-empty-state">
          <MessageSquareText aria-hidden="true" />
          <div>
            <strong>One question at a time</strong>
            <p>Holocron will answer from retrieved interactions and show the evidence attached to each factual claim.</p>
          </div>
        </div>
      ) : null}

      {!isLoading && result ? (
        <div className={`ask-result ${result.sources.length === 0 ? "is-no-evidence" : ""}`} aria-live="polite">
          <div className="ask-answer-column">
            <header className="ask-answer-head">
              <span>Answer</span>
              <p>{result.question}</p>
            </header>
            <div className="ask-answer-copy">{result.answer}</div>

            {result.claims.length > 0 ? (
              <div className="ask-claims">
                <h2>Grounded claims</h2>
                <ol>
                  {result.claims.map((claim, claimIndex) => (
                    <li key={`${claim.text}-${claimIndex}`}>
                      <p>{claim.text}</p>
                      <span className="ask-claim-citations" aria-label="Claim citations">
                        {claim.source_refs.map((sourceRef) => {
                          const sourceIndex = result.sources.findIndex((source) => source.source_ref === sourceRef);
                          if (sourceIndex < 0) return null;
                          return <a key={sourceRef} href={`#${sourceDomId(sourceRef)}`} aria-label={`View source ${sourceIndex + 1}`}>{sourceIndex + 1}</a>;
                        })}
                      </span>
                    </li>
                  ))}
                </ol>
              </div>
            ) : null}

            {result.limitations.length > 0 ? (
              <aside className="ask-limitations">
                <strong>What Holocron could not verify</strong>
                {result.limitations.map((limitation) => <p key={limitation}>{limitation}</p>)}
              </aside>
            ) : null}
          </div>

          {result.sources.length > 0 ? (
            <aside className="ask-sources-column" aria-label="Answer sources">
              <header><span>Sources</span><strong>{result.sources.length}</strong></header>
              <div className="ask-source-list">
                {result.sources.map((source, sourceIndex) => (
                  <article id={sourceDomId(source.source_ref)} className="ask-source-card" key={source.source_ref}>
                    <header>
                      <span>{sourceIndex + 1}</span>
                      <time dateTime={source.occurred_at}>{formatSourceDate(source.occurred_at)}</time>
                    </header>
                    <strong>{source.person_name ?? "Unknown person"}</strong>
                    {source.organization_name ? <p className="ask-source-organization">{source.organization_name}</p> : null}
                    <span className="ask-source-type">{formatInteractionType(source.interaction_type)}</span>
                    <blockquote>{source.excerpt}</blockquote>
                  </article>
                ))}
              </div>
            </aside>
          ) : null}
        </div>
      ) : null}
    </section>
  );
}
