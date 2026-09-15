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

# Resolve an existing session folder. Never creates anything, never guesses a
# date: returns empty when the session has no folder yet, so callers decide.
# Args: $1=kb_path, $2=session_id
# Returns: absolute folder path on stdout (empty if none exists)
resolve_session_folder() {
    local kb_path="$1" session_id="$2" cached matches
    cached=$(cat "/tmp/second-brain-folder-$session_id" 2>/dev/null)
    if [ -n "$cached" ] && [ -d "$cached" ]; then
        echo "$cached"
        return 0
    fi
    matches=("$kb_path/_sessions"/*/"$session_id")
    [ -d "${matches[0]}" ] && echo "${matches[0]}"
    return 0
}

# Nearest ancestor session id for a forked session, read from the folder markers
# the fork replays from its parent's history. Empty for a session that is not a
# fork. The last marker is the nearest ancestor; the first is the lineage root.
# Args: $1=transcript_path, $2=own_session_id
# Returns: session id on stdout (empty if none)
transcript_forked_from() {
    local transcript="$1" self="$2"
    [ -f "$transcript" ] || return 0
    # Only a hook-injected marker counts. Matching a bare session path anywhere
    # would treat any conversation that merely mentions a folder as a parent.
    head -200 "$transcript" 2>/dev/null \
        | grep 'Session folder created' \
        | grep -o '_sessions/[0-9][0-9-]*/[0-9a-f-]\{36\}' \
        | sed 's|.*/||' \
        | grep -v "^${self}$" \
        | tail -1
    return 0
}

# Rebuild a missing session note from what the transcript still knows.
# Never overwrites an existing note, and never refiles a session under today
# when its folder already says which day it belongs to. Timing comes from the
# transcript's birth time, which is the session's own start even for a fork,
# whose first records are its parent's replayed history.
# tags and summary are deliberately left empty: nothing outside the note holds them.
# Args: $1=kb_path, $2=session_id, $3=transcript_path, $4=cwd (optional hint)
# Returns: the session folder path on stdout
rebuild_session_md() {
    local kb_path="$1" session_id="$2" transcript="$3" cwd="$4"
    local folder date_dir started project branch forked title birth

    folder=$(resolve_session_folder "$kb_path" "$session_id")
    [ -n "$cwd" ] || cwd=$(head -200 "$transcript" 2>/dev/null \
        | grep -o '"cwd":"[^"]*"' | head -1 | sed 's/"cwd":"//; s/"$//')

    birth=$(stat -f '%B' "$transcript" 2>/dev/null)
    if [ -n "$birth" ]; then
        started=$(date -u -r "$birth" +%Y-%m-%dT%H:%M:%S)
        date_dir=$(date -r "$birth" +%Y-%m-%d)
    fi

    # An existing folder is authoritative about the date; only fall back to the
    # transcript's birth day, and to today only when even that is unavailable.
    if [ -n "$folder" ]; then
        date_dir=$(basename "$(dirname "$folder")")
    else
        [ -n "$date_dir" ] || date_dir=$(date +%Y-%m-%d)
        folder="$kb_path/_sessions/$date_dir/$session_id"
    fi

    mkdir -p "$folder/docs"
    echo "$folder" > "/tmp/second-brain-folder-$session_id"

    if [ ! -f "$folder/session.md" ]; then
        [ -n "$cwd" ] && project=$(basename "$cwd")
        [ -n "$cwd" ] && branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
        forked=$(transcript_forked_from "$transcript" "$session_id")
        title=$(tail -r "$transcript" 2>/dev/null \
            | grep -m1 '"type":"custom-title"' \
            | jq -r '.customTitle // empty' 2>/dev/null)
        write_session_md "$folder/session.md" "schema_version: \"2.0\"
session_id: \"$session_id\"
date: $date_dir
project: \"$project\"
cwd: \"$cwd\"
git_branch: \"$branch\"
started_at: $started
docs_path: \"_sessions/$date_dir/$session_id/docs\"
forked_from: \"$forked\"
transcript_source: \"$transcript\"
session_name: \"$title\"
ended_at:
duration_seconds:
summary:
tags:" "# Session: $session_id"
    fi

    echo "$folder"
}

export -f read_frontmatter_prop
export -f read_frontmatter_list
export -f write_session_md
export -f append_kb_log
export -f read_custom_title
export -f rename_terminal_window
export -f rename_herdr_agent
export -f resolve_session_folder
export -f transcript_forked_from
export -f rebuild_session_md
