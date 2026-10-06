---
status: accepted
date: 2026-10-06
---

# A new domain is proposed by the recap, created on a person's approval

A recap whose plan holds concepts, components or best practices that fit no existing knowledge-bank
domain now derives a proposed domain — a slug name, a one-line description, a `project_domains` map
entry for the subject's repository root — and asks the person attending its pane, with the one prompt
the skill is allowed. Approval creates the domain through `skills/common/create_domain.sh`, which makes
the folder and delegates the map entry to `setup_kb_path.sh --set-domain`, the existing writer; the
recap then files under it and completes. Naming an existing domain instead files there. Choosing "no
project" completes the recap `done` with an empty `project`.

[ADR-0004](0004-project-names-a-knowledge-bank-domain.md) made no-fit a visible gap: the recap failed
and the notice asked a person. In practice that threw away the evidence. The recap is the only reader
of the whole conversation; it knows which docs need a home and why each near-miss domain is wrong, and
the person it deferred to started over from a one-line reason. The gap's resolution — set a project by
hand, map a directory, retry — reconstructed a decision the recap had already done the work for.

The prompt is tolerable because every path that actually runs a recap ends in a pane a person reaches:
inside Herdr the launcher opens one, and anywhere else it only prints a command for a person to paste.
Panes are checked, not watched, so the question may wait; a pane closed on an open question leaves the
subject `running`, which the stale-running notice already surfaces, and the forced retry re-derives and
re-asks. Phase 1.0's rule narrows from "never prompt" to "prompt exactly once, here" — everything else,
tags included, stays promptless.

## Considered Options

**Asynchronous approval through failed → notice → approval command.** The recap records a proposal
payload, fails, and the start-of-session notice prints an approve command that creates the domain and
relaunches. Rejected: it adds a durable payload format, a parser in the notice, and a second full
recap for a decision the attending person can make in the pane while the evidence is live.

**Create without asking.** Rejected. ADR-0004 exists so the domain set changes only by a person's
hand, and an unattended writer that coins freely is how a shared vocabulary drifts. This decision moves
the question to where the evidence is; the hand on the vocabulary is still a person's.

**Keep plain failure.** Retained, but only as the branch with nothing to propose: a plan with no
domain-needing docs, or docs that cohere into no single domain. A proposal without a filing need would
invent structure for its own sake.

## Consequences

A batch recap blocks at each proposal until the person answers; later sessions in the batch weigh names
proposed earlier, so related sessions converge on one domain rather than a family of near-synonyms.

`done` with an empty `project` becomes a deliberate state — a person decided the session belongs to no
domain — distinguishable from a legacy gap only by the `proposal=` and `decision=` lines in the
subject's `recap.log`. Index views and lint treat it as before: nothing files under it, and nothing
nags about it again.

ADR-0004's consequence that a recap which cannot place the work "marks the subject failed, which is how
the decision reaches a person", and the same sentence in
[ADR-0006](0006-the-description-is-written-after-the-session-ends.md), are amended: the decision now
reaches the person in the recap's own pane first, and only a session with nothing to propose still
fails.
