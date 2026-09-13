#!/bin/bash
# obsidian_helpers.sh - Filesystem-based helper functions for session management
#
# All functions operate directly on the filesystem (no Obsidian CLI dependency).
# Obsidian's file watcher indexes changes automatically.

# Read a YAML frontmatter property directly from a markdown file (no CLI).
# Args: $1=absolute_file_path, $2=property_name
# Returns: unquoted value on stdout (empty if not found)
read_frontmatter_prop() {
    local file="$1"
    local prop="$2"
    [ -f "$file" ] || return 0
    sed -n '/^---$/,/^---$/p' "$file" \
        | grep "^${prop}:" | head -1 \
        | sed "s/^${prop}: *//" | sed 's/^"//;s/"$//'
}

# Read a YAML list property directly from a markdown file (no CLI).
# Args: $1=absolute_file_path, $2=property_name
# Returns: comma-separated string (e.g., "item1, item2")
read_frontmatter_list() {
    local file="$1"
    local prop="$2"
    [ -f "$file" ] || return 0
    sed -n '/^---$/,/^---$/p' "$file" \
        | sed -n "/^${prop}:/,/^[^ -]/p" \
        | grep '^ *- ' | sed 's/^ *- //' \
        | paste -sd ',' - | sed 's/,/, /g'
}

# Write session.md atomically — YAML frontmatter + body in one filesystem write.
# Bypasses Obsidian CLI for reliability; Obsidian's file watcher indexes it.
# Args: $1=absolute_file_path, $2=frontmatter (no --- delimiters), $3=body
write_session_md() {
    local file_path="$1"
    local frontmatter="$2"
    local body="$3"
    mkdir -p "$(dirname "$file_path")"
    printf '%s\n' "---" "$frontmatter" "---" "" "$body" > "$file_path"
}

# Append an entry to the KB operation log (_meta/log.md).
# Creates the file with a table header if it does not exist.
# Args: $1=kb_path, $2=operation_type (ingest|query|lint|index-rebuild),
#       $3=operator (session-recap|kb-ingest|kb-lookup|kb-lint), $4=details
append_kb_log() {
    local kb_path="$1"
    local op_type="$2"
    local operator="$3"
    local details="$4"
    local log_file="$kb_path/_meta/log.md"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%d %H:%M')

    mkdir -p "$kb_path/_meta"

    if [ ! -f "$log_file" ]; then
        cat > "$log_file" << 'HEADER'
---
title: Knowledge Bank Operation Log
type: log
---

# Operation Log

| Timestamp | Operation | Operator | Details |
|-----------|-----------|----------|---------|
HEADER
    fi

    echo "| ${timestamp} | ${op_type} | ${operator} | ${details} |" >> "$log_file"
}

# Read customTitle from a Claude Code session transcript.
# Args: $1=cwd (working directory of the session)
#       $2=session_id
# Returns: customTitle on stdout (empty if not found or no /rename was used)
# Note: Claude Code uses cwd (not git repo root) for the project hash.
read_custom_title() {
    local cwd="$1"
    local session_id="$2"
    local hash=$(echo "$cwd" | sed 's|[/.]|-|g')
    local transcript="$HOME/.claude/projects/$hash/${session_id}.jsonl"
    [ -f "$transcript" ] || return 0
    tail -r "$transcript" 2>/dev/null \
        | grep -m1 '"type":"custom-title"' \
        | jq -r '.customTitle // empty' 2>/dev/null
}

# Rename the enclosing terminal container to the session name.
# Supports tmux (window) and Herdr (pane); no-op outside both.
# Args: $1=session_name (empty → no-op)
# Never returns non-zero (callers may run under set -e); output suppressed
# (hook stdout is reserved for the hook protocol JSON).
rename_terminal_window() {
    local name="$1"
    [ -n "$name" ] || return 0

    if [ -n "$TMUX_PANE" ]; then
        tmux set-window-option -t "$TMUX_PANE" automatic-rename off 2>/dev/null
        tmux rename-window -t "$TMUX_PANE" "$name" 2>/dev/null
    fi

    if [ -n "$HERDR_PANE_ID" ]; then
        # Hooks may run with a minimal PATH; herdr installs to ~/.local/bin
        local herdr_bin
        herdr_bin=$(command -v herdr 2>/dev/null || echo "$HOME/.local/bin/herdr")
        if [ -x "$herdr_bin" ]; then
            "$herdr_bin" pane rename "$HERDR_PANE_ID" "$name" >/dev/null 2>&1
            rename_herdr_agent "$name" "$herdr_bin"
        fi
    fi

    return 0
}

# Name the Herdr agent in the current pane after the session name, so other
# agents can target it by name (herdr agent prompt|wait|get <name>).
# Herdr requires ^[a-z][a-z0-9_-]{0,31}$ and uniqueness across live agents;
# on collision, retry with the pane id as a suffix (e.g. "...-w2p5").
# Re-applying the current name to the same agent is a no-op (exit 0).
# Args: $1=session_name, $2=path_to_herdr_binary
# Returns: always 0 (best-effort; callers may run under set -e)
rename_herdr_agent() {
    local name="$1"
    local herdr_bin="$2"
    local agent_name suffix err

    agent_name=$(printf '%s' "$name" | tr '[:upper:]' '[:lower:]' \
        | sed -E 's/[^a-z0-9_-]+/-/g; s/^[^a-z]+//' | cut -c1-32 | sed -E 's/-+$//')
    [ -n "$agent_name" ] || return 0

    err=$("$herdr_bin" agent rename "$HERDR_PANE_ID" "$agent_name" 2>&1 >/dev/null) && return 0
    case "$err" in
        *agent_name_taken*)
            suffix=$(printf '%s' "$HERDR_PANE_ID" | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z0-9')
            agent_name=$(printf '%s' "$agent_name" | cut -c1-$((31 - ${#suffix})) | sed -E 's/-+$//')
            "$herdr_bin" agent rename "$HERDR_PANE_ID" "${agent_name}-${suffix}" >/dev/null 2>&1 || true
            ;;
    esac

    return 0
}

export -f read_frontmatter_prop
export -f read_frontmatter_list
export -f write_session_md
export -f append_kb_log
export -f read_custom_title
export -f rename_terminal_window
export -f rename_herdr_agent
