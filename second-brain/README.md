<div align="center">
  <img src="misc/second-brain-icon.png" alt="Second Brain" width="200"/>

  # Second Brain

  ![Version](https://img.shields.io/badge/version-2.0.0-blue)
  ![License](https://img.shields.io/badge/license-Apache--2.0-green)
  ![Claude Code](https://img.shields.io/badge/Claude%20Code-Plugin-purple)
  ![Author](https://img.shields.io/badge/author-sxhmilyoyo-orange)
</div>

> **Agentic Workflow with Memory and Tribal Knowledge**

Transform Claude from a brilliant goldfish into an elephant with persistent knowledge across sessions.

---

## The Problem: The "Brilliant Goldfish" Problem

Your AI is a genius with no long-term memory.

- **The Amnesia Loop**: It forgets your architecture, decisions, and history the moment the session ends, forcing you to explain the context repeatedly
- **The Productivity Tax**: Developers lose 5+ hours/week just hunting for syncing on information. Each interruption breaks "flow state" and costs 20 minutes of focus to recover
- It cannot learn lessons from the session, making you show the correct approach repeatedly

Every new AI session is like working with a brilliant goldfish—amazing capabilities, but zero memory of what you taught it yesterday.

---

## The Solution: An Agentic Workflow

This plugin provides two skills that work together to create a **Second Brain** for your AI assistant:

### The Automated Loop

<div align="center">
  <img src="misc/workflow-diagram.excalidraw.png" alt="Workflow Diagram" width="700"/>
</div>

The diagram shows the continuous learning loop:
1. **User Request** triggers an investigation
2. **Investigation** consults the knowledge bank via `knowledge-bank-lookup`
3. **Implementation** applies learned patterns and best practices
4. **Session Transcripts** capture the work done
5. **`session-recap`** distills insights back into the knowledge bank
6. The cycle continues, making the AI smarter with each session

### 1. `session-recap` - Auto-Document Your Sessions

At the end of every work session, automatically captures what matters:
- **Not chat logs** - distilled, actionable knowledge
- **95% size reduction** with 100% knowledge retention (139 KB → 5 KB)
- Creates concepts, components, best practices, and process reflections
- Rich cross-referencing (10-15 WikiLinks) across knowledge categories

**Triggers**: "recap the session", "summarize the work", "document this", or automatically after significant work

### 2. `knowledge-bank-lookup` - Instant Context Retrieval

When you start a new session, instantly retrieves relevant context:
- **No manual searching** or documentation diving
- **69-94% context reduction** per lookup (varies by lookup type: Quick/Standard/Deep)
- **Reflections-first strategy** - learns from past mistakes before consulting documentation
- **WikiLink following** with DFS traversal for comprehensive knowledge discovery
- **Frontmatter filtering** - property-based document discovery for efficient navigation

**Triggers**: Project mentions, investigation requests, or "how should I..."

---

## Session Management Architecture

The plugin integrates with Claude Code's lifecycle through hooks that automatically capture and process session data.

<div align="center">
  <img src="misc/session-management.excalidraw.png" alt="Session Management Architecture" width="700"/>
</div>

**Lifecycle Events:**
- **SessionStart (startup)** - Creates `session.md` hub note via Obsidian CLI, sets frontmatter properties
- **SessionStart (resume)** - Saves current segment before resuming
- **PreCompact** - Saves segment before context summarization
- **SessionEnd** - Saves final segment, rebuilds `session.md` as hub note with wikilinks to all artifacts

**Output Files:**
- `session.md` - Obsidian hub note with frontmatter metadata and wikilinks to all session artifacts
- `docs/` - Generated documentation artifacts
- `segment-N/` - Segment data (transcript.jsonl, agents/*.jsonl, plans/*.md, metadata.json)

---

## Benefits

| Metric | Value |
|--------|-------|
| Context reduction per lookup | **69-94%** (Quick/Standard/Deep) |
| Manual documentation time | **Zero** |
| Knowledge retention across sessions | **100%** |
| Session size reduction | **95%** (139 KB → 5 KB typical) |

### For You (The Engineer)
Never explain your codebase from scratch again.

### For Your Team
Instant access to every pattern, every lesson, every decision that came before.

### For New Hires
Onboarding in hours, not weeks. They get the collective wisdom of your entire team immediately.

### For The Organization
Knowledge compounds. Every insight builds on the last. Your AI becomes as experienced as your most senior architect.

---

## Prerequisites

- **Claude Code CLI** installed and configured
- **Bash shell** (macOS/Linux or WSL on Windows)
- A directory for your **knowledge bank** (where session data will be stored)
- **Obsidian** (required) for viewing the knowledge bank and session management
- **Obsidian CLI** (required) for session note operations (create, property:set, property:read)
  - Install from: https://help.obsidian.md/cli
- **Obsidian skills** (recommended) for proper Obsidian Flavored Markdown generation
  - Install from: https://github.com/kepano/obsidian-skills

---

## Installation

### Step 1: Add the Marketplace (one-time)

**Via Claude Code CLI:**
```bash
claude plugin marketplace add sxhmilyoyo/sundayhao-plugins
```

**Or via slash command (in Claude Code):**
```
/plugin marketplace add sxhmilyoyo/sundayhao-plugins
```

### Step 2: Install the Plugin

**Via Claude Code CLI:**
```bash
claude plugin install second-brain@sundayhao-plugins
```

**Or via slash command (in Claude Code):**
```
/plugin install second-brain@sundayhao-plugins
```

### Step 3: Configure Knowledge Bank Path

Create the config file at `~/.claude/plugins/config/second-brain/config.json`:

```bash
mkdir -p ~/.claude/plugins/config/second-brain
cat > ~/.claude/plugins/config/second-brain/config.json << 'EOF'
{
  "version": "1.0",
  "knowledge_bank_path": "/path/to/your/knowledge-bank"
}
EOF
```

Replace `/path/to/your/knowledge-bank` with your actual knowledge bank directory path.

**Then restart Claude Code.**

---

## Usage

### Session Recap

When Claude Code starts, it displays the session folder path:
```
Session: /path-to-knowledge-bank/_sessions/<yyyy-mm-dd>/<session-id>
```

**Workflow:**
1. **Work on your task** - Claude Code captures everything
2. **Note the session path** (shown at startup)
3. **Exit the session** when done
4. **Start a NEW session** and invoke:
   ```bash
   # Slash command:
   /session-recap /path/to/session-folder
   # /path/to/session-folder looks like "/<path-to-knowledge-bank>/_sessions/yyyy-mm-dd>/<session-id>"

   # Or natural language:
   "Recap the session at /path/to/session-folder"
   ```

### Knowledge Lookup
```
# Manual invocation:
/knowledge-bank-lookup

# Natural language triggers:
"Look up the knowledge bank and tell me how to implement X"
"What's the pattern for Y in our codebase?"
```

---

## Skills Reference

| Skill | Trigger Examples | Output |
|-------|------------------|--------|
| `session-recap` | "recap the session", significant work completion | Concepts, components, best practices, daily logs |
| `knowledge-bank-lookup` | Service mentions, "how should I..." | Structured insights with patterns, gotchas, recommendations |
| `session-manager` | "tag this session", "set task tag", "summarize session" | Updated session.md frontmatter (task_tag, tags, summary) |

---

## ccfind - Session Finder

A shell + fzf tool for searching and resuming Claude Code sessions by their metadata.

### Commands

```bash
ccfind                  # Search all sessions (fuzzy match on all fields)
ccfind --by-tag         # Two-step: pick a tag, then browse matching sessions
ccfind --by-task-tag    # Two-step: pick a task_tag, then browse matching sessions
ccfind --tags           # List all unique tags
ccfind --task-tags      # List all unique task_tags
```

### Keybindings (in fzf)

| Key       | Action                                         |
|-----------|-------------------------------------------------|
| `Enter`   | Resume session (`cd` to cwd + `claude -r`)      |
| `Ctrl-O`  | Open the session's docs folder                   |

### Installation

Add a shell alias to your `.zshrc`:

```bash
alias ccfind="<plugin-path>/tools/ccfind/ccfind.sh"
```

Where `<plugin-path>` is the plugin installation directory (e.g., `~/.claude/plugins/cache/sundayhao-plugins/second-brain/1.0.0`).

### tmux Integration

```bash
# Add to .tmux.conf
bind-key "F" display-popup -E -w 80% -h 70% "ccfind"
```

### Dependencies

- [fzf](https://github.com/junegunn/fzf)
- Claude Code CLI (for `claude -r` resume)

---

## The Knowledge Bank Philosophy

> **Knowledge Bank = BRAIN, not ARCHIVE**

Preserve what matters (workflows, edge cases, decisions), not every detail (investigation traces, all alternatives, verbose analysis).

- **Compound Learning**: Your AI literally gets smarter every day
- **Institutional Intelligence**: Stop working with goldfish, start building institutional intelligence

---

## Obsidian Integration

### Viewing the Knowledge Bank

The knowledge bank directory can be opened directly as an **Obsidian vault**:

1. Open Obsidian
2. Select "Open folder as vault"
3. Choose your knowledge bank directory

**Benefits:**
- **Graph View** - Visualize connections between concepts, components, and reflections
- **WikiLink Navigation** - Click `[[links]]` to jump between related documents
- **Full-text Search** - Find anything across your entire knowledge base
- **Backlinks** - See all documents that reference the current note

<div align="center">
  <img src="misc/obsidian-graph.png" alt="Obsidian Graph View" width="700"/>
  <p><em>Knowledge bank graph showing interconnected concepts and components</em></p>
</div>

### Obsidian Skills Integration

For optimal document generation, install the **[obsidian-skills](https://github.com/kepano/obsidian-skills)** plugin for Claude Code.

**Installation:**

```bash
# 1. Add the marketplace (one-time)
/plugin marketplace add kepano/obsidian-skills

# 2. Install the plugin
/plugin install obsidian-markdown@kepano/obsidian-skills
```

Or via Claude Code CLI:
```bash
claude plugin marketplace add kepano/obsidian-skills
claude plugin install obsidian-markdown@kepano/obsidian-skills
```

When creating knowledge bank documents, the skill is automatically invoked:
```
/obsidian:obsidian-markdown
```

This ensures proper Obsidian Flavored Markdown syntax:
- WikiLinks: `[[Note]]`, `[[Note#Heading]]`, `[[Note|Display]]`
- Callouts: `> [!note]`, `> [!warning]`, `> [!tip]`
- Properties (YAML frontmatter)
- Tags: `#tag`, `#nested/tag`
- Embeds: `![[Note]]`, `![[image.png]]`

---

## License

Apache-2.0
