# Changelog - Second Brain Plugin

All notable changes to the second-brain plugin are documented in this file.
This covers plugin-level changes (hooks, tools, configuration, cross-cutting features).
For skill-specific changes, see the CHANGELOG.md in each skill's directory.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.12.0] - 2026-09-15

Session metadata is now seeded when a session starts instead of waiting to be asked for. See
`docs/adr/0004-project-names-a-knowledge-bank-domain.md` and
`docs/adr/0005-delegation-is-declared-not-detected.md`.

### Added
- **`project` is a knowledge-bank domain**, resolved by a new shared `skills/common/resolve_project.sh` from a `project_domains` map in the plugin config. A map key matches a directory it equals or contains, and a key ending in `*` matches any path beginning with the stem, so one entry covers a family of sibling packages. The longest match wins. Anything unmapped resolves to empty, and so does any stored value outside the domain set, which is what lets older notes keep their directory basenames without a reader ever mistaking one for a domain. `list_project_domains` is the single source of truth every consumer validates against.
- **The name is taken from the hook's stdin.** `session_start.sh` now reads the `session_title` and `source` input fields, so `session_name` is written at registration instead of being recovered later from a transcript that is documented to lag.
- **Lineage properties `forked_from_name`, `delegated_by` and `delegated_by_name`**, and a `## Lineage` body section that both the start and the end hook regenerate from those properties. The section links the counterpart's full `_sessions/<date>/<id>/session` path with its name as the alias, because every note is called `session.md` and a bare link would be ambiguous across the whole vault.
- **Delegation is recorded when it is declared.** A launcher sets `SECOND_BRAIN_DELEGATED_BY` and `SECOND_BRAIN_DELEGATED_BY_NAME` inline on the launched command and the delegate's own hook records them. Honoured only when `source` is `startup`, so a variable that leaked into a shell cannot make every later session in it look delegated.
- **`skills/common/launch_delegate.sh`**, one thin helper that starts a delegated session with the marker set, names it `<role>-<launcher>` so the distinguishing part survives the 32-character agent-name limit, and opens a Herdr pane or prints the command when there is none.
- **Forks and delegates inherit** their source's domain and tags at registration. An untagged source leaves them untagged rather than falling through to the model, whose request would otherwise land in the middle of a fork's conversation or on top of a delegate's first instruction.
- **The hook asks for what it cannot derive.** A named session with no stamp gets an instruction to run the `session-manager` skill in automatic mode, carrying the resolved domain and the mapped directory's tag hints. Gated on a genuine startup with no declared launcher, no parent and a known name, and stamped with `metadata_requested_at` at the moment the request is made, so a session whose model never ran the skill is asked once rather than on every later start.
- **The terminal is named at startup.** The name is on stdin from the first event, so a freshly launched session no longer sits in an unlabelled pane until its first resume.
- **`--set` and `--set-domain`** in `setup_kb_path.sh`, both read-modify-write, and `get_plugin_config_value` in `get_kb_path.sh`, which falls back on every failure so a broken config disables a feature rather than enabling it. A domain that does not exist in the bank is refused rather than stored.
- **`set_frontmatter_prop`, `yaml_escape`, `session_folder_relpath` and `session_lineage_body`** in `skills/common/obsidian_helpers.sh`.
- **Regression cases 9 to 15** in `tests/hook-regression-suite.sh`, 49 new assertions: the resolver's boundary, wildcard, longest-prefix and out-of-set rules, config preservation, the full injection gate, a stray marker on a resume, fork and delegate inheritance including the untagged case, the quoted-marker false positive, and lineage backfill at exit.

### Fixed
- **A conversation that merely quoted another session's registration line was read as its fork.** `transcript_forked_from` matched the marker text anywhere in the first 200 lines. It now also requires the record to be an `attachment`, which is the only shape a replayed marker has; verified against four fork transcripts in the corpus. A session that reads a hook script or another transcript early, which a recap session does, was the case at risk.
- **Notes rebuilt mid-session no longer invent a project.** `rebuild_session_md` computed its own `basename "$cwd"`, so a note recovered at resume, pre-compact or exit kept getting a directory name after the change. It calls the shared resolver, and writes the lineage properties, so a rebuilt note matches a freshly registered one.
- **`--configure` no longer discards the rest of the config.** It rewrote `config.json` wholesale from a heredoc, which would have wiped the domain map and any other key on every reconfigure.
- **The start hook's output is built with `jq`** instead of a heredoc. Two of the strings it carries are chosen by a person, and a single quote in a session name produced invalid JSON that silenced the hook for every consumer of it.

### Changed
- `session_end.sh` backfills `forked_from_name` alongside `forked_from`, never tags: inheritance belongs at registration, where a fork had not yet done work of its own to describe. It also manages the three new lineage properties, while `metadata_requested_at` flows through the unknown-property preserve loop untouched.
- `skills/session-manager/SKILL.md`: the ownership rule now reads as hooks seed at registration and the skill is the only mid-session writer; `project` is described as a domain from a closed set; the report gains a lineage line.
- `skills/session-manager/tag-canonicalization.md` step 4 splits into interactive and automatic modes. Automatic writes tags that already have a canonical form without asking, reports any it could not match, and never prompts, so a derivation never interrupts the user's first request.

### Removed
- `skills/common/detect_project.sh`. Its `basename "$cwd"` was the single reason a session note ever recorded `data`, `src` or a bare home-directory name as a project.

### Fixed after review

A code review of the above found fifteen defects, each reproduced before being fixed. The ones worth
knowing about:

- **A quote in a session name could leave a whole note unparseable.** `read_frontmatter_prop` stripped the surrounding quotes but not the escaping inside them, so a value read off a note and written back was escaped twice. Seeding `session_name` from the launch name made this reachable on a session's first exit rather than never. There is now a `yaml_unescape` inverse and reading applies it, so a value round-trips unchanged however many times it passes through.
- **`set_frontmatter_prop` handed its value to `awk -v`,** which processes escape sequences: a `\"` came back out as a bare quote, and a `\n` became a real newline that split the scalar and injected a second YAML key. The value now travels through the environment, and newlines are stripped.
- **`rebuild_session_md` wrote every value unescaped.** It is the one writer nothing rewrites afterwards, so a quote there left a note broken for the rest of the session rather than for one hop.
- **The helpers did not load under zsh,** which is the shell the session-manager skill is documented to source them from. `BASH_SOURCE` is unset there, so the resolver was looked for in the caller's directory and silently never defined. Both files now fall back to `$0`.
- **Seeding a name at registration exempted every named session from the ghost-folder check,** which treated a non-empty `session_name` as proof that work happened. That inference was sound only while a finished conversation was the only thing that could set it. Since hooks never delete a folder, kb-lint is the only collector, so a failed launch would have accumulated permanently. The check no longer looks at the name; the transcript, the documents, the end time and the summary decide.
- **The start hook assumed the session's folder was under today's date** instead of resolving it, which the other three hooks already do. A `/clear` after midnight, or a reused `--session-id`, therefore checked a path that was not the session's folder: the "write only when absent" guard saw nothing, a second blank note appeared, and the note holding the real metadata was orphaned.
- **The one-shot derivation request could be spent without being made.** The stamp was written before the instruction was emitted, so a timeout or a jq failure consumed it, and since `startup` fires once per session id nothing could ask again. It is now written last. The gate also checks that the note has no tags, which the instruction had been asserting without verifying.
- **Declared delegation was recorded in one narrow window.** The launcher's name was resolved only while creating a note, so a session whose note already existed lost the relationship for good: the marker is gone by exit and nothing downstream can rediscover it. A session that is both forked and delegated now records both.
- **A wildcard mapping outranked a more specific exact one,** because specificity counted the trailing `*`. Since `project` decides where distilled knowledge is filed, that filed a whole tree under the wrong domain silently.
- **Two mappings the tool accepted could never match anything**: a prefix with a trailing slash, which is what shell completion produces, and a `*` anywhere but the end. The first is now normalised and the second refused. `--set-domain` without tags failed outright, which was the form the help text and the README both documented.
- **`--set` could overwrite keys with their own validated writers.** Setting the knowledge bank path through it skipped the directory check and left every hook reporting an unconfigured bank; setting the domain map replaced the object with a string, after which every directory resolved to empty with nothing to show why. Both are now refused with a pointer to the right command.
- **The unknown-property preserve loop dropped list values.** It kept only key lines, so an unknown list property survived as a bare null key with every item deleted. That is exactly the preservation ADR-0002 promises. Continuation lines now travel with their key.
- **Person-chosen names reached a `printf '%b'`.** A name containing `\c` truncated the note body and took the `## Transcript` pointer with it, which under the reference-only architecture is the only pointer to the conversation. The lineage section is assembled outside that expansion.
- **`validate_project` matched its argument as a regular expression,** so a legacy basename like `a.x` validated against the domain `a2x`.
- **`PLUGIN_CONFIG_FILE` was not exported** although the functions reading it were, so a child shell resolved every project to empty. `resolve_project.sh` also no longer clobbers a caller's `SCRIPT_DIR`.
- **ccfind showed nothing for an unnamed session** in an unmapped directory, since its label fell back to `project`. It now falls back to the directory the session ran in.
- **`schema_version` is `2.1`** on newly written notes, four properties having been added. Existing notes keep the version they were written with.
- **The regression suite gave false confidence.** It passed with the escaping made a no-op, with the fork detector's hardening removed, and with the terminal rename unscoped. Those three are now covered, along with the review's own findings, taking it from 74 assertions to 104. Two hygiene bugs fixed: one assertion was vacuous because `/tmp` is a symlink on macOS and `find` does not descend it, and the suite left per-session cache files in `/tmp` that could hand a stale path to the next run.

## [2.11.0] - 2026-09-14

### Changed
- **session-manager skill rewritten** against the skill-authoring guidance, 160 lines down to 93 plus a 50-line disclosed reference. The mandatory opening sequence now sits at the top rather than below all the reference material, where it had needed three separate emphatics to overcome its own placement. Its header also claimed "steps 1-4" while listing six, so which steps were mandatory was genuinely ambiguous.
- **Tag canonicalization disclosed** to `tag-canonicalization.md`. Only the tags branch reaches it, so setting a project or summary no longer carries it.
- **Description pruned** from 90 words to 36. It had one branch written five ways, which cost context on every turn without adding a trigger.
- **Leading words** replace restatement: *own* carries the boundary between the four properties the skill writes and the rest that the hooks manage, which had been stated in three places; *preflight* names the opening sequence; *canonical* replaces the prohibition against setting tags directly.
- **Prohibitions turned positive**, four down to zero, since naming a banned behaviour makes it more available rather than less.

### Added
- **A verifiable completion criterion for the terminal rename.** `rename_terminal_window` is best-effort and reports nothing, so a failed rename was silent and the skill could not tell done from not-done. It now reads the label back from Herdr or tmux and confirms it matches.

### Removed
- The Examples and Constraints sections, which restated the command form, the property table and the tag workflow already defined above them.

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
