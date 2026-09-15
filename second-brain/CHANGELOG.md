# Changelog - Second Brain Plugin

All notable changes to the second-brain plugin are documented in this file.
This covers plugin-level changes (hooks, tools, configuration, cross-cutting features).
For skill-specific changes, see the CHANGELOG.md in each skill's directory.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.10.0] - 2026-09-14

### Fixed
- **Session folders are no longer deleted by a peer session.** `session_resume.sh` cleaned up "ghost" folders through a rendezvous file keyed by `md5(cwd)`. Because that key is shared by every session in a directory while the folder it removed belonged to a single session, any second session resuming or compacting in the same directory deleted a live session's folder. Confirmed collateral across the corpus was six real sessions, one of them 2709 lines and 442 turns, against one confirmed ghost caught. The rendezvous and the `rm -rf` are both gone; no hook deletes a session folder any more. See `docs/adr/0001-hooks-never-delete-session-folders.md`.
- **A lost note is now rebuilt mid-session, not only at session end.** `session_resume.sh` rebuilt only when the whole folder was missing, so a folder that survived as a shell (recreated by a later document write) kept a missing `session.md` for the rest of the session's life, which made the session-manager skill fail against it.
- **`session_end.sh` no longer files a recovered session under today's date with blank metadata.** It read the properties it wanted to preserve out of the very file that was missing, producing notes with empty `date`, `project`, `cwd` and `started_at`. It now reconstructs from the transcript and takes the date from the existing folder. Same fix in `pre_compact.sh`, which could record a compaction boundary into a freshly invented folder.
- **`/clear` no longer discards tags, summary and name.** `session_start.sh` also fires for `clear` with the same session id and rewrote the note unconditionally. It now writes only when the note is absent.
- **Hook timeouts were in the wrong units.** Values of `5000` and `30000` were written as milliseconds, but the field is seconds. Corrected to 5 and 10. Removed from `SessionEnd`, whose 1.5 second budget is fixed by the harness and cannot be raised by a plugin.

### Added
- **Forked sessions are registered.** New `fork` SessionStart matcher routed to `session_start.sh`. Previously a fork fired no matcher at all, so it got no folder at start and `session_end.sh` invented a bare one, which is what made forks look like empty duplicates of a real session.
- **`forked_from` frontmatter property**, derived from the parent's replayed folder marker in the fork's own transcript, and backfilled at session end because the transcript is written asynchronously and the fork-time scan can lose the race.
- **`resolve_session_folder`, `transcript_forked_from` and `rebuild_session_md`** in `skills/common/obsidian_helpers.sh`, shared by the resume, pre-compact and end hooks so all three agree on how a session folder is found and repaired. Timing comes from the transcript's birth time, which is the session's own start even for a fork, whose first records are its parent's replayed history.
- **kb-lint check 6, ghost session folders.** Collecting ghosts moved out of the hooks and into lint, on a signature no live session can match: a note nobody updated, no documents, no end time, older than a day, and a transcript that is absent or never grew. Reports by default and quarantines rather than deletes.

- **Regression suite** at `tests/hook-regression-suite.sh`, 25 cases against a scratch knowledge bank in a temp directory, never the real vault. Covers the failures above directly: a peer resuming in the same directory cannot delete another session's folder, a lost note is rebuilt without being refiled under today, `/clear` preserves tags and summary, a fork records its parent, and unknown frontmatter properties survive the end rewrite. Resolves the plugin from its own location, or from `PLUGIN=` to test an installed copy.

### Changed
- `session_end.sh` now preserves unknown frontmatter properties verbatim instead of rebuilding from a fixed list, so properties written by skills survive a rewrite.

## [2.9.0] - 2026-09-12

### Added
- **Herdr agent name**: Session names now also propagate to the Herdr *agent name* (`herdr agent rename`), not just the pane label. New `rename_herdr_agent()` helper in `skills/common/obsidian_helpers.sh`, called from `rename_terminal_window()`, so both session-manager step 4 and `session_resume.sh` pick it up. The name is sanitized to Herdr's `^[a-z][a-z0-9_-]{0,31}$` rule (lowercased, invalid runs collapsed to `-`, truncated to 32 chars); on `agent_name_taken` it retries once with a pane-id suffix (e.g. `-w2p5`). Best-effort: never fails the caller. Once named, other agents can address the session with `herdr agent prompt|wait|get <name>`.

## [2.8.0] - 2026-07-31

### Added
- **Herdr pane rename**: Session names now propagate to Herdr pane labels, not just tmux windows. New `rename_terminal_window()` helper in `skills/common/obsidian_helpers.sh` detects the environment (`$TMUX_PANE` / `$HERDR_PANE_ID`) and renames whichever container encloses the session — both when nested. Uses `herdr pane rename` over the socket API; resolves the binary via `command -v` with `~/.local/bin` fallback for minimal hook PATHs.

### Changed
- **session-manager step 4 + session_resume.sh**: Both now call the shared `rename_terminal_window()` helper instead of duplicating inline tmux commands.

## [2.7.0] - 2026-04-09

### Added
- **session-recap: Full Recap enforcement**: New "No Shortcuts" section — every recap executes all 5 phases completely. A daily log alone is not a recap.
- **session-recap: Batch Recap**: Guidance for processing multiple sessions chronologically — discover, triage, process per-session with full phases, parallelize independent projects, integrate once at end.
- **kb-lint: Fix step (Step 4)**: After reporting, offer resolution via AskUserQuestion — batch stub creation, alias resolution, template placeholder removal, index drift fix, or skip.
- **kb-lint: `references/fix-guide.md`**: Stub creation templates, classification heuristics, alias resolution, template cleanup details.
- **KB schema: Stub Documents section**: Explains lifecycle (stub → active/deleted), type inference, `> [!stub]` callout convention.

## [2.6.1] - 2026-04-09

### Fixed
- **kb-lint `set -e` incompatibility**: `extract_wikilinks()` uses `grep` which returns exit 1 on files with no WikiLinks, and `resolve_wikilink()` returns 1 for unresolvable links — both expected behaviors for lint but caused silent script exit under `set -e`. Added `|| true` guards in the pipeline and lint script calls.

## [2.6.0] - 2026-04-09

### Added
- **Session-manager AskUserQuestion**: All confirmations and prompts (tag suggestions, ambiguous requests, no-request invocations) use the `AskUserQuestion` tool for proper user input.

### Changed
- **Tmux window rename**: Now runs on every session-manager invocation regardless of user request (tags, summary, etc.), not just when customTitle changes. Disables tmux `automatic-rename` to prevent overwrite.

## [2.5.0] - 2026-04-08

### Changed
- **kb-ingest v1.1.0**: Refactored from single-mode to dual-mode skill (Quick + Study) based on real-world usage. Study mode adds theme-by-theme walkthrough with online research, three-layer KB output (source/digest/learning notes), and optional blog/slack synthesis. All decision points use AskUserQuestion tool. New `study` and `source` document types added to KB schema.

## [2.4.0] - 2026-04-08

### Added
- **Session-manager tag suggestions**: When setting tags, skill reads existing tags from ccfind cache and suggests reusing similar ones (e.g., `rule-forge` → `ruleforge`). Presents a confirmation table with usage counts before setting.
- **Session-manager customTitle auto-sync**: On every invocation, reads `/rename` customTitle from transcript via `read_custom_title()` and auto-sets `session_name` in session.md if missing or different.
- **Tmux window rename**: Session resume hook and session-manager skill rename the tmux window to `session_name`. Uses `$TMUX_PANE` for correct window targeting.
- **`read_custom_title()` helper**: New function in `obsidian_helpers.sh` — reads customTitle from transcript via reverse-scan. Uses cwd hash (not git repo root) matching Claude Code's project directory structure.

### Changed
- **Session folder lookup**: Replaced `find` (330ms on 500+ sessions) with temp file caching across hook lifecycle (<1ms). SessionStart writes path to `/tmp/second-brain-folder-$SESSION_ID`, other hooks read it back. Falls back to glob then mkdir.

### Fixed
- **SessionEnd hook timeout on large KBs**: `find` across 500+ session directories consumed 330ms (22% of 1.5s budget). Glob fallback takes 10ms; temp file takes <1ms.

## [2.3.0] - 2026-04-05

### Added
- **`_meta/index.md`**: Auto-generated content catalog covering all 188 KB documents, organized by project and type. Regenerated after every write operation via `generate_index.sh`.
- **`_meta/log.md`**: Chronological operation log tracking ingests, queries, lint passes, and index rebuilds via `append_kb_log()` in `obsidian_helpers.sh`.
- **`_meta/schema.md`**: Unified KB conventions file consolidating document types, frontmatter requirements, WikiLink standards, naming conventions, and operations reference.
- **kb-ingest skill**: Standalone source ingestion for articles, gists, docs, and URLs outside of Claude Code sessions. Interactive READ → DISCUSS → CREATE → INTEGRATE workflow following the LLM Wiki pattern.
- **kb-lint skill**: Knowledge bank health-check with 5 checks — broken WikiLinks, missing frontmatter, orphan documents, index drift, and stale content. Severity-graded reports at `_meta/lint-report-*.md`.
- **session-recap source detection**: Phase 1.4 scans session.md body sections (`## Generated Artifacts`, `## Plans`, `## Memory Snapshot`) and transcript for ingestible artifacts and references. Phase 2.4 plans which sources to ingest as KB docs.
- **ccfind `Ctrl-R`**: Refresh keybinding reloads session list without reopening fzf popup.

### Changed
- **knowledge-bank-lookup navigation**: "Index or MOC-First" strategy — `_meta/index.md` as fallback for projects without MOCs (CC, supply-opt).
- **knowledge-bank-lookup query write-back**: After high-value lookups, offer to file the synthesis as a KB document via kb-ingest workflow.
- **session-recap Phase 3 priority order**: Expanded from 5 to 7 levels — artifact-derived docs (5-8 WikiLinks) and reference-derived docs (5-8 WikiLinks) inserted at priorities 4-5.
- **session-recap Phase 5**: Added steps 5.2 (regenerate `_meta/index.md`) and 5.3 (append operation log).
- **Tiered WikiLink minimums**: Session-derived docs keep 10-15; ingested/artifact/reference docs require 5-8. `count_wikilinks.sh` accepts optional `min-links` parameter.

### Notes
- Inspired by [Karpathy's LLM Wiki gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)
- All changes are backward-compatible with existing KB documents

## [2.2.0] - 2026-03-22

### Changed
- **Reference-only session architecture**: Hooks no longer copy transcripts, agents, or plans into `segment-*` directories. `session.md` stores a `transcript_source` frontmatter property pointing to the original transcript at `~/.claude/projects/`. Eliminates ~99.8% of `_sessions/` storage overhead.
- **SessionEnd performance fix**: Removed 3 full-file grep operations (agents, plans, customTitle) that exceeded the 1.5s `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` cap. CustomTitle extraction now uses `tail -r` reverse-scan (14ms vs 322ms on 42MB transcripts).
- **PreCompact hook**: Replaced segment copying with a `compaction-points.txt` sidecar file that records line count + timestamp per compaction boundary.
- **session-recap Phase 1.1**: Reads `transcript_source` from session.md frontmatter first; falls back to `segment-*/transcript.jsonl` walking for old sessions.
- **SessionStart matchers**: Added `clear` and `compact` matchers for `/clear` and post-compaction events.

### Added
- **ccfind `--by-name` / `Ctrl-N`**: Browse only named sessions (sessions with `session_name` set via `/rename`). Replaces the old `--by-task-tag` mode.

### Removed
- **`task_tag` property**: Merged into `session_name` + `tags`. In practice, `task_tag` was identical to `session_name` in most sessions (one task = one session). Use `tags` for grouping related sessions.
- **ccfind `--by-task-tag` / `--task-tags`**: Replaced by `--by-name` / `Ctrl-N`.

### Fixed
- **SessionEnd hook cancelled**: Root-caused the "Hook cancelled" error — `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` (default 1.5s) silently caps per-hook `timeout` settings in hooks.json.

## [2.1.0] - 2026-03-06

### Added
- **Auto memory snapshot**: SessionEnd hook copies `~/.claude/projects/{hash}/memory/` to session folder, with `## Memory Snapshot` section in session.md body
- **Session-manager skill**: `project` is now a customizable property (was hook-only); skill shows current session info on every invocation
- **ccfind**: Shell + fzf tool for searching and resuming sessions by metadata (`--by-tag`, `--by-task-tag`, keybindings for resume and open docs)

### Changed
- **session-recap v3.1.0**: Reads session.md as hub for metadata and content discovery; adds `session-folder` back-reference to all recap-created KB docs

### Removed
- **`generated_artifacts` property**: Dead placeholder — initialized but never populated

## [2.0.0] - 2026-01-12

### Added
- **Centralized session management**: Hooks for SessionStart, SessionEnd, PreCompact, and Resume
- **session.md**: Obsidian hub note with YAML frontmatter replaces `session-info.json` as single source of truth
- **Obsidian CLI integration**: All session note creation and property updates via CLI
- **Session-manager skill**: Tag sessions with `task_tag`, `tags`, and `summary` via Obsidian CLI
- **Dataview MOC**: `_sessions/MOC-Sessions.md` for task-first session browsing
- **Ghost cleanup**: Resume hook detects and removes ghost folders created by startup matcher firing during resume
- **hookSpecificOutput schema**: SessionStart hooks inject docs path into system prompt

### Fixed
- Obsidian datetime format: removed `Z` suffix for compatibility
- Empty list placeholders: skip `type="list"` with empty value to avoid `[""]`
- Obsidian CLI stdout pollution: redirect writes, filter loading messages on reads
- Obsidian app launches on CLI use: hide window via osascript after create

## [1.0.0] - 2026-01-08

### Added
- **session-recap skill**: Distill Claude Code sessions into knowledge bank documents (concepts, components, best practices, reflections, daily logs)
- **knowledge-bank-lookup skill**: Retrieve relevant context from knowledge bank with reflections-first strategy and WikiLink DFS traversal
- **Plugin configuration**: `~/.claude/plugins/config/second-brain/config.json` for knowledge bank path
- **Knowledge bank structure**: Projects, daily logs, sessions, index with Obsidian vault support

---

## Skill Changelogs

| Skill | Changelog |
|-------|-----------|
| session-recap | `skills/session-recap/CHANGELOG.md` |
| knowledge-bank-lookup | `skills/knowledge-bank-lookup/CHANGELOG.md` |
