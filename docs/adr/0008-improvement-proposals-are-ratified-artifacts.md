---
status: accepted
date: 2026-10-06
---

# Improvement proposals are ratified artifacts, not reflection prose

A recap now scans the subject's transcript for evidence that the agent's environment should
change — seven categories with use-when triggers: navigation, guardrails, steering files, tool
economy, tool reliability, information access, validation approach — and writes each finding as a
**proposed improvement**: one file in `{KB}/_proposals/`, carrying a severity, a concretely named
target, a mechanical-or-judgment classification, the transcript evidence, and `status: pending`.
Only a person moves a proposal past `pending`. Reflections lose their forward-looking half
("What Could Be Improved", "What Would Make This Seamless", "Action Items") and become what the
glossary now says they are: a backward-looking record, mined later, that never proposes.

The conflation was measurably rotten. 264 reflections had accumulated action items as prose
checkboxes, and nothing in the skill — no phase, no checklist, no script — ever read one again
after the file was written. The two halves have different consumers (future pattern mining vs.
immediate approval), different lifecycles (permanent record vs. apply-and-done), and different
success criteria; one template serving both meant the proposals half defaulted to the record
half's fate. An improvement captured as a hook runs every time; one captured as prose works only
if someone happens to reread it.

The scan's shape — named categories with use-when triggers, severity ordering, evidence per
finding, "build the check over writing the rule" — is adapted from mattpocock's `retro` skill.
Runtime integration was rejected: `retro` is `disable-model-invocation: true`, so a recap session
cannot invoke it; depending on another marketplace's plugin would break every other user of this
one; and its final step, presenting candidates interactively, has no audience in an unattended
recap. The discipline is borrowed; no coupling is.

Surfacing is a queue and a notice, never a prompt. ADR-0007 narrowed "never prompt" to "prompt
exactly once", for the domain decision — and that boundary is load-bearing: the domain question
*blocks* the recap (docs cannot file without one), while an improvement never blocks anything.
So proposals follow the proposed-tag precedent instead — derive, record durably, let a person
ratify later — with one addition that fixes that precedent's weakness: the record is a structured
file in a dedicated queue rather than a line of prose, and the start-of-session notice counts
what is pending, so the queue cannot become write-only.

## Considered Options

**Keep one reflection document and sharpen its improvement sections.** Rejected: the consumers
stay mixed, the approval channel would have to parse prose out of KB docs, and the rot mechanism
— improvements living where nothing re-reads them — survives the rewrite.

**Prompt for each proposal in the pane, like the domain proposal.** Rejected. ADR-0007's prompt
is tolerable because it is single and blocking; N non-blocking questions at the end of every
recap is a different contract, and reviewing a proposed environment change (reading a diff,
weighing a severity) is not a one-keypress decision made while the evidence scrolls past.

**Route everything to `_proposals/`, validation techniques included.** Rejected: "note it down to
look up in the future" names reference knowledge, and lookups search `reflections/` and
`best-practices/`, never a work queue that approval drains. A technique with nothing to ratify
becomes a best-practice doc the recap already writes unattended; only mechanizable validation
becomes a proposal.

## Consequences

Phase 2.1's gate shrinks to two questions; tool/process friction stops forcing a reflection and
feeds the scan instead, where zero candidates is a legitimate outcome. The 264 existing
reflections stay untouched — `type: reflection`, the category folders, and the ≥5 WikiLink
minimum survive, so mining and the verify scripts keep working — but new reflections follow the
lean evidence-per-claim template and old ones carry sections new ones will not have.

`_proposals/` becomes an interface: `verify_session_recap.sh --proposals/--no-proposals` checks
that the scan's record and the files agree, the session-start notice counts `status: pending`,
and whatever approval channel is built later consumes the same files. Proposals are queue items,
not knowledge docs — no WikiLink minimum, no MOC entry — and the recap never edits an existing
proposal's status; that hand is a person's.
