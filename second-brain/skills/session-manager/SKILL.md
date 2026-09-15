---
name: session-manager
description: Set the current session's name, project, tags, or summary on its session note. Use when the user names, tags, or summarizes this session, sets its project, or mentions in passing what this session has been about.
---

# Session Manager

You **own** four properties on the current session's note: `session_name`, `project`, `tags` and
`summary`. The hooks own every other property, so those four are the only ones you write.

| Property | Type | Holds |
|----------|------|-------|
| `session_name` | text | The session's name, kept in step with `/rename` |
| `project` | text | Project name, seeded from the working directory and yours to override |
| `tags` | list | Categorization, drawn from the vault's existing tags |
| `summary` | text | One line on what the session accomplished |

## Preflight

Run all five steps on every invocation, before the user's request and whatever they asked for.

**1. Locate the note.** The SessionStart hook injects a docs path into your system prompt:

```
Session docs path: {KB_PATH}/_sessions/2026-03-04/abc123-def456/docs/
```

Everything from `_sessions/` onward is vault-relative. Drop the trailing `docs/` and append
`session.md`, giving `_sessions/2026-03-04/abc123-def456/session.md`. Read it:

```bash
obsidian vault="knowledge-bank" read path="<vault-relative-path>"
```

If no docs path was injected, ask the user for the session folder.

**2. Sync the name.** `/rename` writes a `customTitle` to the transcript, which the note does not see:

```bash
source skills/common/obsidian_helpers.sh
read_custom_title "<cwd from the note>" "<session_id from the note>"
```

When that title differs from `session_name`, adopt it:

```bash
obsidian vault="knowledge-bank" property:set name="session_name" value="<title>" path="<vault-relative-path>"
```

**3. Name the terminal.** Give the enclosing container the session's name, as a real Bash call. The
helper detects tmux or Herdr from `$TMUX_PANE` and `$HERDR_PANE_ID` itself, and under Herdr it also
names the agent so other agents can reach this session by name:

```bash
source skills/common/obsidian_helpers.sh
rename_terminal_window "<session_name>"
```

The helper is best-effort and reports nothing, so confirm the result yourself rather than assuming it:

```bash
[ -n "$HERDR_PANE_ID" ] && herdr pane list | grep -o "\"label\":\"[^\"]*\"" | grep -c "<session_name>"
[ -n "$TMUX_PANE" ] && tmux display-message -p '#W'
```

**Done when:** the container's label reads back as the session name, or `session_name` is empty and
there was nothing to apply.

**4. Report the four properties.**

```
**Current Session**
- session_name: <value or empty>
- project: <value or empty>
- tags: <value or empty>
- summary: <value or empty>
```

**5. Dispatch.** Carry out the user's request. When the request names no property, ask with the
**AskUserQuestion** tool which of the four to update.

## Writing a property

```bash
obsidian vault="knowledge-bank" property:set name="<property>" value="<value>" [type="list"] path="<vault-relative-path>"
```

Tags take an extra step: they are canonicalized against the vault's existing tags and confirmed
before anything is written. Read [tag-canonicalization.md](tag-canonicalization.md) when the request
involves tags.

Confirm every write back to the user, and use the **AskUserQuestion** tool for confirmations so the
user gets a real prompt. This skill acts on the current session alone.
