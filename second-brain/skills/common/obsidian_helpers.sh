#!/bin/bash
# obsidian_helpers.sh - Filesystem-based helper functions for session management
#
# All functions operate directly on the filesystem (no Obsidian CLI dependency).
# Obsidian's file watcher indexes changes automatically.

# project is derived in one place for every caller (ADR-0004); sourcing it here
# means a note rebuilt mid-session gets the same domain a fresh one would.
_SB_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_SB_COMMON_DIR/resolve_project.sh"

# Escape a value for use inside a double-quoted YAML scalar. A session name is
# chosen by a person and can contain a quote, which would otherwise end the
# scalar early and leave the whole note unparseable.
# Args: $1=value
yaml_escape() { printf '%s' "${1//\"/\\\"}"; }

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

# Set one scalar frontmatter property in place, leaving the rest of the note
# untouched. Replaces the property when present; otherwise inserts it above the
# tags block, which is a list and has to stay last, or above the closing
# delimiter when the note has no tags.
# Args: $1=absolute_file_path, $2=property_name, $3=value
set_frontmatter_prop() {
    local file="$1" prop="$2" value="$3" tmp
    [ -f "$file" ] || return 0
    tmp="${file}.setprop.$$"
    awk -v p="$prop" -v v="$(yaml_escape "$value")" '
        BEGIN { fm = 0; done = 0 }
        /^---$/ {
            fm++
            if (fm == 2 && !done) { print p ": \"" v "\""; done = 1 }
            print; next
        }
        fm == 1 && !done && index($0, p ":") == 1 { print p ": \"" v "\""; done = 1; next }
        fm == 1 && !done && $0 == "tags:" { print p ": \"" v "\""; done = 1 }
        { print }
    ' "$file" > "$tmp" && mv "$tmp" "$file"
    rm -f "$tmp"
    return 0
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
    # Only a hook-injected marker replayed as an attachment counts. The text
    # alone is not enough: a conversation that reads a hook script, or quotes
    # another session's registration line inside a tool result, puts the same
    # words in the transcript and would be misread as a parent.
    head -200 "$transcript" 2>/dev/null \
        | grep '"type":"attachment"' \
        | grep 'Session folder created' \
        | grep -o '_sessions/[0-9][0-9-]*/[0-9a-f-]\{36\}' \
        | sed 's|.*/||' \
        | grep -v "^${self}$" \
        | tail -1
    return 0
}

# Vault-relative folder path for a session that already has one.
# Args: $1=kb_path, $2=session_id
# Returns: "_sessions/<date>/<id>" on stdout (empty when the session has none)
session_folder_relpath() {
    local kb_path="$1" session_id="$2" folder
    [ -n "$session_id" ] || return 0
    folder=$(resolve_session_folder "$kb_path" "$session_id")
    [ -n "$folder" ] || return 0
    printf '_sessions/%s/%s' "$(basename "$(dirname "$folder")")" "$(basename "$folder")"
}

# The Lineage body section, regenerated from the note's own properties by both
# the start and the end hook. Every note is called session.md, so a bare
# [[session]] link is ambiguous across the whole vault; the link carries the
# full dated folder path and shows the name as its alias. A session whose
# counterpart has no folder is recorded by id, which is still followable.
# Args: $1=kb_path, $2=forked_from, $3=forked_from_name,
#       $4=delegated_by, $5=delegated_by_name
# Returns: the section on stdout, or nothing when there is no lineage
session_lineage_body() {
    local kb_path="$1" fid="$2" fname="$3" did="$4" dname="$5" rel lines=""
    if [ -n "$fid" ]; then
        rel=$(session_folder_relpath "$kb_path" "$fid")
        if [ -n "$rel" ]; then
            lines="${lines}- Forked from: [[${rel}/session|${fname:-$fid}]]
"
        else
            lines="${lines}- Forked from: ${fid}
"
        fi
    fi
    if [ -n "$did" ]; then
        rel=$(session_folder_relpath "$kb_path" "$did")
        if [ -n "$rel" ]; then
            lines="${lines}- Delegated by: [[${rel}/session|${dname:-$did}]]
"
        else
            lines="${lines}- Delegated by: ${did}
"
        fi
    fi
    [ -n "$lines" ] || return 0
    printf '## Lineage\n%s' "$lines"
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
    local forked_name forked_folder body lineage

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
        # The domain comes from the shared resolver, never the directory name:
        # a rebuild that invented a basename here would undo ADR-0004 for every
        # note recovered at resume, pre-compact or exit.
        [ -n "$cwd" ] && project=$(resolve_project "$cwd" "$kb_path")
        [ -n "$cwd" ] && branch=$(git -C "$cwd" branch --show-current 2>/dev/null)
        forked=$(transcript_forked_from "$transcript" "$session_id")
        title=$(tail -r "$transcript" 2>/dev/null \
            | grep -m1 '"type":"custom-title"' \
            | jq -r '.customTitle // empty' 2>/dev/null)
        forked_name=""
        if [ -n "$forked" ]; then
            forked_folder=$(resolve_session_folder "$kb_path" "$forked")
            [ -n "$forked_folder" ] && forked_name=$(read_frontmatter_prop \
                "$forked_folder/session.md" "session_name")
        fi
        body="# Session: $session_id"
        lineage=$(session_lineage_body "$kb_path" "$forked" "$forked_name" "" "")
        [ -n "$lineage" ] && body="$body

$lineage"
        write_session_md "$folder/session.md" "schema_version: \"2.0\"
session_id: \"$session_id\"
date: $date_dir
project: \"$project\"
cwd: \"$cwd\"
git_branch: \"$branch\"
started_at: $started
docs_path: \"_sessions/$date_dir/$session_id/docs\"
forked_from: \"$forked\"
forked_from_name: \"$forked_name\"
delegated_by: \"\"
delegated_by_name: \"\"
transcript_source: \"$transcript\"
session_name: \"$title\"
ended_at:
duration_seconds:
summary:
tags:" "$body"
    fi

    echo "$folder"
}

export -f yaml_escape
export -f read_frontmatter_prop
export -f read_frontmatter_list
export -f set_frontmatter_prop
export -f write_session_md
export -f session_folder_relpath
export -f session_lineage_body
export -f append_kb_log
export -f read_custom_title
export -f rename_terminal_window
export -f rename_herdr_agent
export -f resolve_session_folder
export -f transcript_forked_from
export -f rebuild_session_md
