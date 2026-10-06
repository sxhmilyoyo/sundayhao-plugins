# Improvement Scan

How Phase 2.7 turns session friction into **proposed improvements**: changes to the agent's
environment, derived from transcript evidence, ratified by a person (see `GLOSSARY.md`;
[ADR-0008](../../../../docs/adr/0008-improvement-proposals-are-ratified-artifacts.md)). A
reflection records how the work went; a proposed improvement changes how the next run goes.
Keeping them apart is the point: prose action items inside reflections were never revisited,
while a queue a notice counts gets drained.

Categories and discipline adapted from mattpocock's `retro` skill (mattpocock-skills).

## The scan

Walk the seven categories against the transcript. A category fires only when its *use when*
matched something that actually happened; cite that evidence. **Zero candidates is a
legitimate outcome** — a forced finding with no concrete target is filler, not insight.

| Category | Use when |
|---|---|
| `navigation` | The agent took long to find a file or fact that a pointer would fix — in a repo (CLAUDE.md/AGENTS.md pointer) **or** in the knowledge bank (missing MOC link, misfiled doc) |
| `guardrails` | The agent made a mistake an automated check could have caught — or the repo/script it worked in has no check at all, which is itself a finding |
| `steering-files` | A rule should be added, clarified, or removed in CLAUDE.md, `rules/*.md`, or a skill doc; includes instructions that demonstrably changed nothing (no-ops) |
| `tool-economy` | A tool call pattern was expensive or token-inefficient and could be streamlined |
| `tool-reliability` | Tooling silently failed, needed retries, or returned wrong results |
| `information-access` | A crucial piece of information was not reachable by the agent (logs not teed, no read access, missing export) |
| `validation-approach` | The session validated work in a way it didn't start with — a check, harness, query, or technique that would have caught issues earlier if used initially |

## Routing

Classify every candidate before writing anything:

| Classification | Meaning | Route |
|---|---|---|
| `mechanical` | A fixed, automatable change: a hook, a lint rule, a CI job, a script fix, a config edit | Proposal file in `{KB}/_proposals/` — include the actual change, not a description of one |
| `judgment` | A prose rule no check can substitute for (cross-file consistency, "match surrounding style") | Proposal file in `{KB}/_proposals/` — name exactly where the rule would live |
| technique (`validation-approach` only) | A validation method worth knowing, not worth mechanizing | **Best-practice doc**, not a proposal — created directly in Phase 3 like any best practice, so `knowledge-bank-lookup` finds it later. Nothing to ratify |

Default to mechanical over judgment: a check beats a rule everywhere one is possible.

A proposal may target anything on the machine as long as the target is named concretely —
the repo the subject worked in, `~/.claude` (CLAUDE.md, rules, keybindings, hooks), this
plugin, the knowledge bank's structure. "The build is slow" is not a candidate;
"`parse_transcript.sh` greps the transcript four times where one awk pass would do" is.

## Severity

Ordered; a person drains the queue top-down.

| Severity | Meaning |
|---|---|
| `critical` | Produced wrong results, lost work, or risked either |
| `high` | Cost significant time or tokens, or failed silently so the session acted on bad data |
| `medium` | Real friction with a workaround the session found |
| `low` | Polish; worth doing when touching the target anyway |

## Proposal file

`{KB}/_proposals/YYYY-MM-DD-<slug>.md`, one file per proposal:

```markdown
---
type: proposed-improvement
severity: high
category: tool-reliability
target: sundayhao-plugins/second-brain/scripts/ccfind
classification: mechanical
session-folder: _sessions/YYYY-MM-DD/{session_id}
status: pending
---
ccfind resolves fzf off the invoking shell's PATH; under the popup
launcher that PATH lacks the fzf dir, so every popup invocation
silently finds nothing.

**Evidence**: 3 tool calls retried the search before falling back to grep.

**Proposed change**: resolve fzf via absolute path at install time;
add a regression test invoking ccfind with a stripped PATH.
```

All seven frontmatter fields are required. `status` is written as `pending` and only a
person moves it (`approved` / `rejected`); the recap never touches an existing proposal's
status. Proposals are queue items, not knowledge docs: no WikiLink minimum, no KB index
entry, no MOC. The body is the dossier a person approves on — defect, evidence, change —
and nothing else.

## Recording

For each proposal written:

- one line in the daily log — the severity, the claim, and the file path
- one `proposed_improvement=<filename>` line in the subject's `recap.log`

Pass the created files to Phase 4.1 as `--proposals <file1,file2,...>`, or
`--no-proposals` when the scan found nothing — the verifier checks the scan's record and
the files agree.

## Surfacing

Nothing here prompts. The recap runs unattended; pending proposals are surfaced by the
start-of-session notice ("N proposed improvements pending"), and a person reviews the
queue when they choose. The one sanctioned prompt in this skill remains the Phase 2.6
domain proposal, which blocks the recap; an improvement never does
([ADR-0008](../../../../docs/adr/0008-improvement-proposals-are-ratified-artifacts.md)).
