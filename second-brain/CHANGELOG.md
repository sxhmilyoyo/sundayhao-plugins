# Changelog - Second Brain Plugin

All notable changes to the second-brain plugin are documented in this file.
This covers plugin-level changes (hooks, tools, configuration, cross-cutting features).
For skill-specific changes, see the CHANGELOG.md in each skill's directory.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
