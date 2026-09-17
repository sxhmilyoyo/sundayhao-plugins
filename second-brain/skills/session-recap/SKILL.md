---
name: session-recap
description: Document Claude Code sessions by extracting knowledge into cross-referenced documentation. Triggers on "recap the session", "summarize the work", or after significant code changes.
user-invocable: true
---

# Session Recap

Systematically document Claude Code sessions into the knowledge bank.

**Knowledge Bank Location**: Read from `~/.claude/plugins/config/second-brain/config.json`. Configure via `skills/common/setup_kb_path.sh --configure`.

**Philosophy**: Knowledge Bank = BRAIN, not ARCHIVE. Preserve workflows, edge cases, decisions—not verbose traces. Target 95% size reduction, 100% actionable knowledge.

---

## Invocation

### Recommended Workflow

**Important**: a recap runs in a **dedicated recap session**, started by the launcher. Not in the session
being recapped, and not in whatever session you happen to have open. Phase 1.0 stops it otherwise.

1. **Exit the work session.** The SessionEnd hook finishes `session.md` and, when `auto_recap` is not
   `off`, stamps `recap_status: requested` on it.

2. **Start the recap through the launcher**, which is also the command the start-of-session notice prints:
   ```bash
   <plugin root>/hooks/scripts/recap_launcher.sh --manual {KB_PATH}/_sessions/YYYY-MM-DD/{session_id}/
   ```
   Inside Herdr this runs the recap in the pane you typed it in, if that pane is at a shell prompt, and
   opens one beside it if something is already running there — which is the case when a session runs this
   through its Bash tool. Anywhere else it prints a command to paste into a new terminal. Either way the recap session carries `SECOND_BRAIN_RECAP_OF`, which is what makes
   its own hooks register it as a recap and never recap it in turn
   ([ADR-0003](../../../docs/adr/0003-recap-sessions-are-registered-guarded-by-env.md)).

Typing `/second-brain:session-recap <folder>` into an ordinary session stops at the gate on purpose. That
session has no `recap_of`, so finishing the recap there would either write the subject's description onto
the wrong note or leave this session to be recapped as if it had done the work.

### Legacy: Raw Transcript Path

If no session folder exists (e.g., hooks were not configured), you can still provide a raw `.jsonl` transcript path:
```
Recap the session at /path/to/session-id.jsonl
```

### Why a Dedicated Session?

Two reasons, and the second is why a merely *new* session is not enough. Running inside the subject would
miss the end of its own conversation, since the transcript has to be fully written before knowledge can be
extracted from it. And the recap now writes the subject's `project`, `tags` and `summary` as well as its
status, so it has to be unambiguous which note is the subject's and which is its own. `recap_of`, set at
registration from the launcher's marker, is that answer.

### Manual Invocation
- **Launcher** (the supported path): `recap_launcher.sh --manual <subject folder>`
- **Slash command**: `/second-brain:session-recap <subject folder>` — only inside a recap session; it stops
  at the Phase 1.0 gate anywhere else
- **Skill tool**: `Skill({ skill: "second-brain:session-recap" })`

### Visibility Settings

| Setting | Value | Effect |
|---------|-------|--------|
| `user-invocable` | `true` | Visible in slash menu, Skill tool allowed |

---

## RFC 2119 Keywords

This skill uses RFC 2119 keywords:
- **MUST**: Absolute requirement, cannot be skipped
- **SHOULD**: Valid exceptions may exist but require conscious weighing
- **MAY**: Truly optional

---

## Full Recap — No Shortcuts

Every session recap executes all 5 phases completely — no exceptions. A daily log alone is not a recap; it's a log entry. The knowledge bank compounds from extracted concepts, reflections, and best practices, not from session summaries. Skipping phases produces a diary, not a brain.

Even when processing many sessions, each session gets its own full Phase 2.1 reflection gate, Phase 2.4 source ingestion plan, and Phase 3 document creation. Do not batch sessions into a single daily log or skip phases for throughput.

## Batch Recap

When recapping multiple sessions (e.g., "recap all sessions since March 29"):

1. **Discover** — list all sessions in date range, read each session.md for metadata
2. **Triage** — by `recap_status` on each subject's note, which is the recorded answer rather than a guess:

   | `recap_status` | Meaning | Action |
   |---|---|---|
   | `done` | already recapped | skip; only a person's `--force requested` reopens it |
   | `exempt` | deliberately never recapped | skip |
   | `running` | a recap holds the claim, unless it is this session's own subject | skip, unless your `recap_of` names it, in which case the claim is yours and you proceed |
   | `requested` or `failed` | waiting, or stalled | candidate; claim each one as you reach it |
   | empty | never requested | candidate if it has a transcript |

   A batch claims each subject itself, because no wrapper ran for the ones it picks up. That is the
   difference from the single-subject path in Phase 1.0, where the claim already exists. A subject a person
   wants re-requested is cleared with `recap_status.sh <folder> clear --force`, which removes the status so
   the session is requested again at its next exit.

   Also skip a session with no transcript, and one that is trivial: **fewer than five assistant records**
   (`grep -c -m5 '"type":"assistant"'`), the same test the end hook applies. Not a count of user messages:
   sessions here are long autonomous runs on a handful of prompts, and that test exempted a third of the
   real ones. Every candidate gets Phases 1.2 and 5.5 in full — a batch describes every session it recaps.
3. **Process chronologically** — full 5-phase workflow per session, each gets its own daily log + extracted docs
4. **Parallelize when independent** — different projects/topics can use parallel agents; same investigation thread should be sequential for cross-references
5. **Integrate once at end** — index regeneration and log append after all sessions, not per session

---

## Workflow

### Phase 1: ANALYZE

**Goal**: Load session data and extract facts.

#### 1.0 Gate, Claim, Inventory (MUST complete first, in this order)

**Never prompt anywhere in this skill.** A recap session is launched, not attended: it runs in a pane
nobody is looking at, so a question stalls forever. Where something is missing, do what needs nothing,
record the gap, and mark the subject `failed` with the reason. The start-of-session notice asks a person.

**(1) Dedicated-session gate.** Read your own session's note — its folder is in the SessionStart context
you were given — and require its `recap_of` to equal the subject folder you were asked to recap:

```bash
source "$PLUGIN_ROOT/skills/common/obsidian_helpers.sh"
OWN_RECAP_OF=$(read_frontmatter_prop "$OWN_SESSION_FOLDER/session.md" "recap_of")
```

If it does not match, **stop**. Print exactly this and do nothing else:

```
This session is not a recap session, so recapping here would misfile both sessions.
Run:  <plugin root>/hooks/scripts/recap_launcher.sh --manual <subject folder>
```

Two failures this prevents. A recap run inside a working session would either mark that session's note
with the subject's outcome, or leave it unmarked so that it is itself recapped afterwards; and this skill
writes the subject's `project`, `tags` and `summary`, which in the wrong session overwrites the
description of real work with someone else's.

**(2) Verify the claim. Do not re-take it.** In every sanctioned path your wrapper already moved the
subject from `requested` to `running` before `claude` started, so the claim is normally *yours* and calling
the writer for it again would be refused and would leave a misleading `refused running->running` in
`recap.log`. Read the status and decide:

```bash
SUBJECT_STATUS=$(read_frontmatter_prop "$SUBJECT/session.md" "recap_status")
```

| Status | What it means | What to do |
|---|---|---|
| `running`, and step 1 matched your `recap_of` to this subject | your own wrapper claimed it | **proceed**, and make no writer call |
| `requested` or `failed` | the wrapper never claimed: it died first, or the command was pasted without the child script | claim it now with `recap_status.sh "$SUBJECT" running`, and stop if that is refused |
| `done` | already recapped | **stop**; only a person's `--force requested` reopens it |
| `running`, but your `recap_of` names a different subject, or you have none | another recap holds it | **stop** |
| empty | nothing requested this | **stop**; a recap should not invent its own subject |

A refusal is fatal only when this session is **not** the registered recap session for that subject. That is
the distinction step 1 already established, so use it rather than asking the writer a question it will
answer with a refusal either way.

**(3) Prior recap inventory.** A retry resumes rather than starts over, and recap never deletes a
document:

```bash
grep -rl "^session-folder: _sessions/<date>/<id>" "$KB_PATH" --include="*.md"
```

One root, not four. Adding `daily-log/ projects/ reflections/` beside `$KB_PATH` gives grep four
search roots, so every hit is printed twice under two different path forms, and the relative ones resolve
only when the working directory happens to be the vault. Phase 3.0 then treats one daily log as two
documents to reconcile, which is the duplication it exists to prevent. `$KB_PATH` already covers all three
directories.

Record the list. Non-empty means this is a resumed recap, which changes Phase 3.

#### 1.1 Load Session Data

**If session folder provided**:

First, read `session.md` as the hub note for both metadata and content navigation:
```bash
obsidian vault="knowledge-bank" read path="_sessions/{date}/{session_id}/session.md"
```

**Frontmatter metadata** (supplements later phases):
- `project`, `session_name`, `tags`, `summary`, `duration_seconds`, `started_at`, `ended_at`, `transcript_source`

**Body navigation** — follow session.md body sections:

| Section | Content | How to use |
|---------|---------|------------|
| `## Generated Artifacts` | WikiLinks to docs in `docs/` | Read for additional context |
| `## Transcript` | Source path to original `.jsonl` | Use for `parse_transcript.sh` |
| `## Compaction Points` | Line counts per segment boundary | Context on session length/compaction |
| `## Memory Snapshot` | WikiLinks to memory/*.md | Read auto-memory for project context |

Then locate the transcript:
```bash
# Preferred: read transcript_source from session.md frontmatter (v2.1+)
TRANSCRIPT_SOURCE=$(read_frontmatter_prop "$SESSION_FOLDER/session.md" "transcript_source")

if [ -n "$TRANSCRIPT_SOURCE" ] && [ -f "$TRANSCRIPT_SOURCE" ]; then
    TRANSCRIPT="$TRANSCRIPT_SOURCE"
else
    # Fallback for old sessions: find latest segment copy
    LATEST_SEGMENT=$(ls -d "$SESSION_FOLDER"/segment-* 2>/dev/null | grep -v 'segment-final' | sort -t- -k2 -n | tail -1)
    [ -z "$LATEST_SEGMENT" ] && [ -d "$SESSION_FOLDER/segment-final" ] && LATEST_SEGMENT="$SESSION_FOLDER/segment-final"
    TRANSCRIPT="$LATEST_SEGMENT/transcript.jsonl"
fi
```

**If no folder (current conversation mode)**: Skip session.md reading. Analyze current conversation context.

#### 1.2 Decide the Project — three sources, never ask

`project` names a knowledge-bank domain, one of the folders under `projects/`
([ADR-0004](../../../docs/adr/0004-project-names-a-knowledge-bank-domain.md)). Non-empty is not the
same as resolved: notes written before that decision hold a directory basename, and hundreds of them
exist. Validate, never trust. Try three sources in order and stop at the first that resolves:

```bash
source ../common/resolve_project.sh
# 1. what the note already says, but only if it names a real domain
PROJECT=$(validate_project "$(read_frontmatter_prop "$SESSION_FOLDER/session.md" project)")
# 2. the directory the subject ran in, through the shared map
[ -n "$PROJECT" ] || PROJECT=$(resolve_project "$CWD")
# 3. the conversation itself — choose only from this set, never invent a name
[ -n "$PROJECT" ] || list_project_domains
```

The third source is yours to judge: read what the session was actually about and pick the domain it
belongs to, drawn only from `list_project_domains`. You are the first reader with the whole conversation,
which is why this decision is here and not at session start
([ADR-0006](../../../docs/adr/0006-the-description-is-written-after-the-session-ends.md)).

Phase 5.5 writes the result. Because the note's own valid value is the first source, writing it back
overwrites only a value that is **not** a domain, which is exactly the legacy-basename case.

**When no domain fits, carry on without one.** Do not ask, and do not invent. Write the daily log and any
reflections, which need no domain; list in the daily log the concepts and components that could not be
filed and why; then at Phase 5.5 write the tags and summary, leave `project` empty, and mark the subject
failed with the reason, which the notice shows to a person:

```bash
printf '%s failed reason=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "no knowledge-bank domain fits, set project on its note" >> "$SUBJECT/recap.log"
"$PLUGIN_ROOT/skills/common/recap_status.sh" "$SUBJECT" failed --tags "$TAGS" --summary "$SUMMARY"
```

Write the reason as `reason=<text>` on its own line in `recap.log`: the notice reads the last such line
and shows it, so anything else leaves a person with "failed" and nowhere to look. A retry resumes in place
through the Phase 1.0 inventory once the project is set.

Never fall back to `./scripts/parse_transcript.sh project` for a decision: it reports the working
directory and the domain that directory maps to, and nothing more. Filing under a name no domain matches
invents the very thing ADR-0004 exists to keep visibly missing.

#### 1.3 Extract Session Facts

```bash
./scripts/parse_transcript.sh "$TRANSCRIPT" all
```

Extracts: user requests, files read, files modified, commands, errors, subagents, **insights**.

#### 1.4 Detect Session Sources (SHOULD complete when session folder provided)

Scan session.md body sections and transcript for ingestible knowledge:

```bash
./scripts/detect_session_sources.sh "$SESSION_FOLDER" "$TRANSCRIPT"
```

Outputs classified sources, one per line: `artifact|<path>|<description>` or `reference|<path>|<description>`.

| session.md Section | What it contains | Ingest as |
|---|---|---|
| `## Generated Artifacts` | Docs in `docs/` (designs, plans, research, investigations, SOPs) | artifact — high-value, already distilled |
| `## Plans` | Claude Code plan files (architectural decisions, implementation approaches) | artifact — captures decision rationale |
| `## Memory Snapshot` | Auto-memory files (project context, lessons learned) | reference — supplements context |
| Transcript | Non-code files read (.md, .pdf, .txt) and URLs fetched (WebFetch) | reference — external knowledge consumed |

Record the classified list for Phase 2.5.

---

### Phase 2: PLAN

**Goal**: Determine what to document and whether reflection is required.

#### 2.1 Reflection Decision Gate (MUST complete)

Answer these questions:

| Question | Answer |
|----------|--------|
| 1. Did this session involve debugging or problem-solving? | YES / NO |
| 2. Did this session discover a workflow pattern? | YES / NO |
| 3. Did this session encounter tool/process friction? | YES / NO |

**Decision**:
- **If ANY answer is YES** → MUST create at least 1 reflection
- **If ALL answers are NO** → MAY skip reflections

Record decision for Phase 4 verification.

#### 2.2 Search Cross-References (MUST complete before Phase 3)

```bash
./scripts/search_cross_references.sh "keyword"
```

Target 10-15 cross-references distributed across:
- Concepts (3-5)
- Components (3-5)
- Best Practices (1-2)
- Recent Sessions (1-2)
- MOCs (1-2)

See [cross-reference-guide.md](references/cross-reference-guide.md) for methodology.

#### 2.3 External Document Distillation (MUST complete when investigation docs exist)

**If external investigation documents exist (100+ KB)**:

1. **MUST** detect documents for distillation:
```bash
./scripts/detect_external_docs.sh "$SESSION_FOLDER"
```

2. **MUST** analyze distillation requirements:
```bash
./scripts/analyze_for_distillation.sh "$DOC_PATH"
```

See [distillation-guide.md](references/distillation-guide.md) for detailed methodology.

#### 2.4 Source Ingestion Plan (SHOULD complete when sources detected in 1.4)

For each source detected in Phase 1.4, decide:

| Decision | When | Action |
|----------|------|--------|
| **Ingest as KB doc** | High-value, reusable knowledge (design doc, investigation, best practice) | Create concept/component/best-practice doc (5-8 WikiLinks) |
| **Distill and ingest** | Large source (>100KB) needing reduction | Apply [distillation-guide.md](references/distillation-guide.md), then create doc |
| **Skip** | Transient, already covered by daily log, or not knowledge-bearing | Note in daily log only |

Guidelines:
- **Artifacts** in `docs/` are high-value by default — they were already distilled during the session
- **Plans** capture decision rationale — ingest when they document non-obvious architectural choices
- **Memory snapshots** supplement context but rarely need their own KB doc — skip unless they contain unique project insights
- **External references** need judgment — don't ingest the entire article, extract its key insights relevant to the session's work

Record decisions for Phase 3 creation.

#### 2.5 Insight Classification (SHOULD complete when insights exist)

If insights were extracted in Phase 1.3, classify each:

| Insight Content | Classification | Action |
|-----------------|----------------|--------|
| Reveals architectural pattern | Concept | SHOULD create concept doc |
| Describes component behavior | Component | SHOULD update/create component doc |
| Documents methodology | Best Practice | SHOULD create best practice doc |
| Reveals workflow pattern | Reflection | SHOULD create reflection |
| Identifies anti-pattern | Reflection | SHOULD create reflection |
| General educational context | Daily Log | MUST include in daily log |

**Record classifications for Phase 3.**

---

### Phase 3: CREATE

**Goal**: Write documentation in priority order.

#### 3.0 A Resumed Recap Updates, Never Duplicates (MUST when Phase 1.0's inventory was non-empty)

When the inventory found documents already carrying this subject's `session-folder`, this is a retry of a
recap that got part-way. You **MUST** update those documents in place and reuse the existing daily-log
filename rather than choosing a new topic; create only what is missing. Recap never deletes a
knowledge-bank document ([ADR-0001](../../../docs/adr/0001-hooks-never-delete-session-folders.md)), and a
second daily log for one session is how a retry turns into a duplicate that nobody reconciles.

#### Priority Order

1. **Concept docs** - MUST if patterns discovered OR insight reveals architecture
2. **Component docs** - MUST if components modified OR insight describes behavior
3. **Best practice docs** - SHOULD if methodology identified OR insight documents technique
4. **Artifact-derived docs** - SHOULD if Phase 2.4 decision = ingest (from session `docs/` artifacts, plans). Use 5-8 WikiLinks. Frontmatter: `source-type: artifact`, `ingested-from: {path}`
5. **Reference-derived docs** - MAY if Phase 2.4 decision = ingest (from external references). Use 5-8 WikiLinks. Frontmatter: `source-type: reference`, `ingested-from: {path or URL}`
6. **Process reflections** - **MUST if Phase 2.1 decision = required** OR insight reveals workflow/anti-pattern
7. **Daily session log** - MUST (always required, includes all insights)

#### Document Locations

| Type | Location | Template |
|------|----------|----------|
| Concept | `{KB}/projects/{project}/concepts/` | [concept-template.md](references/concept-template.md) |
| Component | `{KB}/projects/{project}/components/` | [component-template.md](references/component-template.md) |
| Best Practice | `{KB}/projects/{project}/best-practices/` | [best-practice-template.md](references/best-practice-template.md) |
| Reflection | `{KB}/reflections/{category}/` | [process-reflection-template.md](references/process-reflection-template.md) |
| Daily Log | `{KB}/daily-log/YYYY-MM-DD [Topic].md` | [daily-log-template.md](references/daily-log-template.md) |

#### Reflection Categories

| Category | Folder | Trigger |
|----------|--------|---------|
| Architecture Patterns | `architecture-patterns/` | Threading, state, design patterns |
| Development Workflow | `development-workflow/` | Utility discovery, test-first, deps |
| Anti-Patterns | `anti-patterns/` | Wrong approaches, confusion |
| DX Improvements | `dx-improvements/` | Search gaps, missing docs, tools |

> **Note**: These are example categories. The system discovers reflection categories dynamically from subdirectories in `{KB}/reflections/`. Create any category folders that fit your workflow.

#### Cross-Reference Requirements

Every document MUST include:
- **Technical docs**: 10-15 WikiLinks (minimum 10)
- **Reflections**: 5-8 WikiLinks (minimum 5)

Verify with:
```bash
./scripts/count_wikilinks.sh document.md
```

#### YAML Frontmatter (MUST include)

```yaml
---
title: Document Title
aliases: [Alt 1, Alt 2]
tags: [category, topic]
type: concept|component|best-practice|daily-log|reflection
created: YYYY-MM-DD
modified: YYYY-MM-DD
project: Claude Code
session-folder: _sessions/YYYY-MM-DD/{session_id}
source-type: session|artifact|reference    # Optional: how this knowledge entered the KB
ingested-from: /path/to/source.md          # Optional: provenance for artifact/reference docs
---
```

The `session-folder` field applies to ALL recap-created docs (daily log, concepts, components, best practices, reflections). It creates a reverse reference — Obsidian's backlinks panel on `session.md` will show all KB docs extracted from that session. Omit if no session folder was provided (current conversation mode).

#### Obsidian Syntax (MUST invoke when obsidian skills installed)

When obsidian skills are available, **MUST** invoke before creating knowledge bank documents:

```
/obsidian:obsidian-markdown
```

This ensures proper Obsidian Flavored Markdown syntax for:
- WikiLinks: `[[Note]]`, `[[Note#Heading]]`, `[[Note|Display]]`
- Callouts: `> [!note]`, `> [!warning]`, `> [!tip]`, etc.
- Properties (YAML frontmatter)
- Tags: `#tag`, `#nested/tag`
- Embeds: `![[Note]]`, `![[image.png]]`
- Block references: `[[Note#^block-id]]`

**Verification**: Check if obsidian skills exist in available skills list before creating documents.

---

### Phase 4: VERIFY

**Goal**: Confirm all requirements met before declaring complete.

#### 4.1 Run Verification Script (MUST complete)

```bash
./scripts/verify_session_recap.sh \
  --kb-path "$KB_PATH" \
  --project "$PROJECT" \
  --daily-log "YYYY-MM-DD [Topic].md" \
  --reflection-required  # or --no-reflection based on Phase 2.1
```

#### 4.2 Validate Obsidian Syntax (MUST complete)

```bash
./scripts/validate_obsidian_syntax.sh "$DAILY_LOG_PATH"
./scripts/validate_obsidian_syntax.sh "$REFLECTION_PATH"  # if reflection created
```

**MUST** validate:
- Frontmatter required fields (title, tags, type, created)
- Callout syntax (`[!note]`, `[!warning]`, etc.)
- WikiLink format and heading anchors

#### 4.3 Verification Checklist

**Documentation** (MUST verify):
- [ ] Daily session log created
- [ ] Cross-references ≥ 10 in daily log
- [ ] YAML frontmatter present

**Reflection Gate** (MUST verify):
- [ ] Phase 2.1 decision recorded
- [ ] If decision = required → reflection exists
- [ ] Reflection has ≥ 5 cross-references

**Quality** (MUST verify):
- [ ] No broken WikiLinks
- [ ] Code references include file paths and line numbers

**Syntax Validation** (MUST verify):
- [ ] `validate_obsidian_syntax.sh` exits with code 0 for daily log
- [ ] `validate_obsidian_syntax.sh` exits with code 0 for reflections (if created)

**Index Maintenance** (MUST verify):
- [ ] Obsidian Base indices regenerated for project
- [ ] Knowledge Bank index regenerated (`_meta/index.md`)
- [ ] Operation log entry appended (`_meta/log.md`)
- [ ] MOC Canvas updated (if MOC modified)

**Subject Note** (MUST verify):
- [ ] Phase 5.5 will describe the subject and set `recap_status` to `done`, in one call

#### 4.4 MOC Updates (conditional)

**If new categories or significant content**: Add links to relevant MOC.

---

### Phase 5: MAINTAIN

**Goal**: Update knowledge bank indices and visualizations.

#### 5.1 Regenerate Obsidian Base Indices (MUST complete when new docs created)

**MUST** regenerate indices when new documents added to knowledge bank:
```bash
./scripts/generate_knowledge_base.sh --project "$PROJECT"
```

Generates queryable indices for concepts, components, practices, and sessions.

#### 5.2 Regenerate Knowledge Bank Index (MUST complete when new docs created)

Without this, newly created docs won't appear in `_meta/index.md` and knowledge-bank-lookup can't discover them via the unified catalog:
```bash
source skills/common/generate_index.sh
generate_index "$KB_PATH"
```

#### 5.3 Append Operation Log (MUST complete)

The operation log feeds kb-lint's staleness detection and provides an audit trail of what changed when:
```bash
source skills/common/obsidian_helpers.sh
append_kb_log "$KB_PATH" "ingest" "session-recap" "Created: [list created docs]. Updated: [list updated docs]"
```

#### 5.4 Update MOC Canvas (MUST complete when MOC modified)

**MUST** update canvas when MOC files modified:
```bash
./scripts/generate_moc_canvas.sh "$MOC_PATH"
```

Creates visual JSON Canvas representation of knowledge relationships.

#### 5.5 Describe the Subject, Then Mark It Done (MUST complete, only after 4.1 passed)

One call, one lock, one order: `project`, `tags`, `summary`, then the status.

```bash
"$PLUGIN_ROOT/skills/common/recap_status.sh" "$SUBJECT" done "$OWN_SESSION_FOLDER" \
    --project "$PROJECT" --tags "$TAGS" --summary "$SUMMARY"
```

**All three overwrite what is on the note, deliberately.** By now you have read the whole conversation and
nothing else ever will, so the values already there were inputs to your decision, not limits on it
([ADR-0006](../../../docs/adr/0006-the-description-is-written-after-the-session-ends.md)). They travel
through this one script because it holds a per-folder lock and writes all four inside it, which is what
keeps a concurrent SessionEnd rewrite from reading a half-written description.

| Value | What it is |
|---|---|
| `--project` | The domain from Phase 1.2. Omit it when nothing fits, and mark `failed` instead of `done` |
| `--tags` | Canonical tags for the work, from `tag-canonicalization.md` **automatic** mode |
| `--summary` | One line on what the session accomplished |

Tags follow [tag-canonicalization.md](../session-manager/tag-canonicalization.md), whose automatic mode is
yours now: load the vault's tags, write every tag that has a canonical form, and coin a tag the vault has
never seen **only** when the conversation gives repeated evidence for it, such as a tool, component or
technique that recurs. Otherwise record it as a proposed tag in the daily log and in `recap.log` and write
nothing for it. Do not call the Obsidian CLI for tags: that writes outside the lock and would duplicate or
contradict the write above. An empty `--tags` writes nothing rather than clearing the note, so a subject
that inherited tags from a fork keeps them when you matched none. `project_default_tags` from the subject
directory's map entry is a hint to weigh, never a value to pass through unexamined.

**Write nothing on your own session's note.** Registration already recorded what it is, from the marker
the launcher passed. A skill that reclassified the session it runs in is the hazard Phase 1.0 exists to
prevent.

---

## Scripts Reference

| Script | Purpose | Phase |
|--------|---------|-------|
| `recap_status.sh` | Claim the subject, describe it, set its status (the only writer) | 1.0, 1.2, 5.5 |
| `parse_transcript.sh` | Extract data from session transcript | 1.3 |
| `detect_session_sources.sh` | Detect ingestible references and artifacts | 1.4 |
| `resolve_project.sh` | Resolve and validate a knowledge-bank domain | 1.2 |
| `search_cross_references.sh` | Find cross-reference targets | 2.2 |
| `detect_external_docs.sh` | Scan for investigation documents | 2.3 |
| `analyze_for_distillation.sh` | Analyze docs for distillation | 2.3 |
| `count_wikilinks.sh` | Count WikiLinks in document | 3 |
| `verify_session_recap.sh` | Final verification gate | 4.1 |
| `validate_obsidian_syntax.sh` | Validate Obsidian markdown syntax | 4.2 |
| `validate_cross_references.sh` | Check for broken WikiLinks | 4.3 |
| `verify_quality.sh` | Verify document quality | 4.3 |
| `generate_knowledge_base.sh` | Generate Obsidian Base indices | 5.1 |
| `generate_index.sh` | Regenerate `_meta/index.md` content catalog | 5.2 |
| `append_kb_log` | Append operation entry to `_meta/log.md` | 5.3 |
| `generate_moc_canvas.sh` | Create MOC visualization canvas | 5.4 |

---

## Completion Criteria

Session recap is complete when:

1. ✅ `verify_session_recap.sh` exits with code 0
2. ✅ Daily log created with ≥ 10 cross-references
3. ✅ Reflection created (if Phase 2.1 decision = required)
4. ✅ All documents have YAML frontmatter
5. ✅ No broken WikiLinks
6. ✅ Obsidian syntax validation passes
7. ✅ Knowledge bank indices updated (if new docs created)
8. ✅ The subject's `recap_status` is `done`, with its `project`, `tags` and `summary` written by 5.5 —
   or `failed` with the reason in `recap.log` when no domain fit

**Only then declare**: "✅ Session Recap Complete"

---

## Resources

- [KB Schema](_meta/schema.md) — Unified conventions for all KB documents (document types, frontmatter, WikiLinks, naming)
- [Templates](references/templates.md)
- [Cross-Reference Guide](references/cross-reference-guide.md)
- [Quality Standards](references/quality-standards.md)
- [Completion Checklist](references/completion-checklist.md)
- [Common Mistakes](references/common-mistakes.md) — top 3: skipping reflections, insufficient cross-refs, premature completion
- [Decision Reference](references/completion-checklist.md) — when reflection is required, when to create each doc type
- [Distillation Guide](references/distillation-guide.md)
