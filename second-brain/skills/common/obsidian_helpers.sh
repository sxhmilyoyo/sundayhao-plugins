#!/bin/bash
# obsidian_helpers.sh - Filesystem-based helper functions for session management
#
# All functions operate directly on the filesystem (no Obsidian CLI dependency).
# Obsidian's file watcher indexes changes automatically.

# project is derived in one place for every caller (ADR-0004); sourcing it here
# means a note rebuilt mid-session gets the same domain a fresh one would.
#
# BASH_SOURCE is unset under zsh, which sets $0 to the sourced file instead. This
# file is the one the session-manager skill tells the model to source from a
# shell that is zsh on macOS, so relying on BASH_SOURCE alone resolved the path
# against the caller's cwd and left the resolver undefined.
_SB_COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$_SB_COMMON_DIR/resolve_project.sh"

# Escape a value for use inside a double-quoted YAML scalar. A session name is
# chosen by a person and can contain a quote, which would otherwise end the
# scalar early and leave the whole note unparseable.
# Args: $1=value
yaml_escape() { local v="${1//\\/\\\\}"; printf '%s' "${v//\"/\\\"}"; }

# The inverse. Every writer here escapes, so every reader has to unescape, or a
# value that survives one rewrite is escaped twice and the note stops parsing.
# Args: $1=value as stored
yaml_unescape() { local v="${1//\\\"/\"}"; printf '%s' "${v//\\\\/\\}"; }

# Read a YAML frontmatter property directly from a markdown file (no CLI).
# Args: $1=absolute_file_path, $2=property_name
# Returns: unquoted value on stdout (empty if not found)
read_frontmatter_prop() {
    local file="$1"
    local prop="$2"
    local raw
    [ -f "$file" ] || return 0
    raw=$(sed -n '/^---$/,/^---$/p' "$file" \
        | grep "^${prop}:" | head -1 \
        | sed "s/^${prop}: *//")
    # Unquoting is not enough: a double-quoted value was escaped on the way in, so
    # a caller that wrote it back would escape it again. A plain scalar is the
    # opposite case — YAML does no escape processing there, so its backslashes are
    # literal and unescaping one would corrupt it. Which form it is decides.
    #
    # Both forms are common here even though every writer in this plugin quotes.
    # Obsidian drops quotes it does not need when a person edits a note, which is
    # why 118 of 524 session notes hold an unquoted project and 94 an unquoted
    # session_name. A single-quoted scalar is deliberately not handled: there are
    # zero in this vault, and the one value that does contain a double quote is
    # still double-quoted, so that is the form the emitter reaches for.
    case "$raw" in
        '"'*'"')
            raw="${raw#\"}"
            yaml_unescape "${raw%\"}"
            ;;
        *)
            printf '%s' "$raw"
            ;;
    esac
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
    # The value travels through the environment, not through `awk -v`, which
    # processes escape sequences in its assignments: a `\"` would be turned back
    # into a bare quote, and a `\n` into a real newline that splits the scalar and
    # injects a second key. Newlines are stripped for the same reason, since a
    # YAML scalar written this way cannot hold one.
    SB_PROP="$prop" SB_VALUE="$(yaml_escape "$(printf '%s' "$value" | tr -d '\n\r')")" \
    awk '
        BEGIN { fm = 0; done = 0; p = ENVIRON["SB_PROP"]; v = ENVIRON["SB_VALUE"] }
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

# Set one list frontmatter property in place: the list counterpart of
# set_frontmatter_prop, which writes a quoted scalar and must never be used for a
# list. Replaces the block when the property is present, otherwise inserts it above
# the tags block, or at the end of the frontmatter when the property IS tags.
# Keeping tags last is a convention every writer here depends on, including the
# replace below, which ends an existing block by scanning to the end of its items.
#
# Three rules the tags block really reaches in this vault:
#   - Empty input writes nothing at all. A recap that matched no canonical tag has
#     made no decision, and ADR-0006 authorises overwriting a value the recap
#     decided, not erasing the tags a fork inherited when it decided nothing.
#   - An item that is not a slug is refused and named on stderr, never quoted
#     around: a colon, a quote, a leading dash or a space breaks the block, and
#     yaml_escape is a scalar escaper. The caller records it as a proposal instead.
#   - Zero items is the common case, `tags:` with nothing under it being the shape
#     of every freshly registered note, so the replace has to cope with an empty run
#     of items rather than assuming there is one to consume.
# Args: $1=absolute_file_path, $2=property_name, $3=comma-separated items
# Returns: always 0; refused items are named on stderr for the caller to log
set_frontmatter_list() {
    local file="$1" prop="$2" raw="$3" item block="" tmp
    [ -f "$file" ] || return 0

    while IFS= read -r item; do
        item=$(printf '%s' "$item" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        [ -n "$item" ] || continue
        # A canonical tag is a slug. Anything else is a proposal, not a value.
        case "$item" in
            -*|*[!A-Za-z0-9_/-]*)
                printf 'set_frontmatter_list: refused non-slug item: %s\n' "$item" >&2
                continue ;;
        esac
        if [ -z "$block" ]; then block="  - $item"; else block="$block
  - $item"; fi
    # printf '%s\n', not '%s': without the terminator the last field arrives as an
    # unterminated line, read returns non-zero on it, and the loop body never runs
    # for it. That silently dropped the last tag, which for a single-tag list meant
    # the write was skipped altogether and the note looked unchanged.
    done < <(printf '%s\n' "$raw" | tr ',' '\n')

    [ -n "$block" ] || return 0

    tmp="${file}.setlist.$$"
    # The block travels through the environment for the same reason the scalar
    # setter's value does: awk -v processes escape sequences in its assignments.
    SB_PROP="$prop" SB_BLOCK="$block" \
    awk '
        BEGIN { fm = 0; done = 0; skip = 0; p = ENVIRON["SB_PROP"]; b = ENVIRON["SB_BLOCK"] }
        /^---$/ {
            fm++
            if (fm == 2 && !done) { print p ":"; print b; done = 1 }
            print; next
        }
        fm == 1 && skip { if ($0 ~ /^[ \t]*-[ \t]/) next; skip = 0 }
        fm == 1 && !done && index($0, p ":") == 1 {
            print p ":"; print b; done = 1; skip = 1; next
        }
        fm == 1 && !done && $0 == "tags:" { print p ":"; print b; done = 1 }
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

# The per-folder recap lock, shared by recap_status.sh and session_end.sh so there is
# one implementation of the protocol rather than two that can drift apart.
#
# mkdir is atomic on every filesystem this runs on, and macOS has no flock. The lock
# serialises two writers that would otherwise lose each other's work: the end hook,
# which reads a note's properties and rewrites the whole file, and a recap marking its
# subject done in between those two steps.
#
# A holder must release before invoking recap_status.sh, which takes the lock itself.
# Nesting would deadlock the hook against its own stamp. That is safe to do because
# each part is atomic on its own and the transition table refuses anything a writer
# slipped into the gap.
#
# Every caller that acquires must release on exit through a trap, not only on the happy
# path: a process killed while holding this lock leaves a directory that blocks every
# writer until it ages past a minute.
# Args: $1=session_folder, $2=max attempts in 50 ms steps (default 40, so 2 s)
# Returns: 0 when held, 1 when it timed out (callers proceed unlocked rather than
#          abandon a write; the note matters more than the serialisation)
recap_lock_acquire() {
    local folder="$1" max="${2:-40}" lock="$1/.recap.lock" i=0 mtime now
    [ -d "$folder" ] || return 1

    # The overwhelmingly common case: nobody holds it, one syscall, no forks.
    mkdir "$lock" 2>/dev/null && return 0

    # Held. Decide once whether it is a corpse, before spending anything on waiting: a
    # lock older than a minute belongs to a writer that crashed, since no writer here
    # holds it for more than a few file writes. Checking this per iteration cost a stat
    # and a date fork each time round for an answer that cannot change in the 0.2 s a
    # caller on a clock is prepared to wait.
    #
    # BSD then GNU, the idiom this repo already uses in ccfind and kb-lint. `stat -f`
    # means something else entirely on GNU (report the filesystem), so without the second
    # form every mtime read as 0, the staleness test could never be true, and one leaked
    # lock would refuse every recap of that session forever.
    mtime=$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo 0)
    now=$(date +%s)
    if [ "$mtime" -gt 0 ] && [ $(( now - mtime )) -gt 60 ]; then
        rm -rf "$lock" 2>/dev/null || true
        printf '%s broke stale lock pid=%s\n' \
            "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$" >> "$folder/recap.log" 2>/dev/null || true
        mkdir "$lock" 2>/dev/null && return 0
    fi

    # Live, so wait for it. max counts attempts; each costs a `sleep` fork, which measures
    # nearer 70 ms than the 50 ms asked for, so the default 40 is about 2.8 s in practice.
    # A caller on a clock passes far less: SessionEnd has about 1.5 s for the whole hook,
    # and spending it here would get the hook killed before writing the note at all —
    # losing ended_at, the duration, the transcript pointer and the rebuilt body, which is
    # a far worse outcome than the lost update this lock exists to prevent.
    while [ "$i" -lt "$max" ]; do
        sleep 0.05
        mkdir "$lock" 2>/dev/null && return 0
        i=$(( i + 1 ))
    done
    return 1
}

# Args: $1=session_folder
# Returns: always 0; releasing a lock this process does not hold is a no-op worth
#          tolerating, because the alternative is a hook that exits holding one.
recap_lock_release() {
    rmdir "$1/.recap.lock" 2>/dev/null || rm -rf "$1/.recap.lock" 2>/dev/null || true
    return 0
}

# Count prompt-shaped user records in a transcript, for the recap's statistics only.
# The SessionEnd predicate deliberately does not call this: measured over 245 vault
# sessions, a "fewer than five messages" test exempted 129 of them, several above a
# thousand lines, because sessions here are long autonomous runs driven by a slash
# command and a handful of prompts. The predicate tests transcript length instead,
# which also keeps a jq pass out of the hook's budget.
#
# A slash command the user typed arrives as a <command-name> record and counts as the
# human input it is; only the echo shapes <local-command-stdout> and
# <local-command-caveat> are excluded. The number also includes messages from other
# sessions and the compaction preamble, which is why callers label it "User prompts
# (approx.)" rather than claiming it counts human-typed messages. A malformed record
# ends the jq pass, so a truncated transcript undercounts rather than failing.
# Args: $1=transcript_path
# Returns: a count on stdout; 0 when the file is missing
count_user_messages() {
    local transcript="$1"
    [ -f "$transcript" ] || { echo 0; return 0; }
    jq -r 'select(.type == "user" and .isMeta != true)
           | (.message.content // empty) as $c
           | if ($c | type) == "string" then
                 (if ($c | startswith("<local-command")) then empty else 1 end)
             elif ($c | type) == "array" then
                 (if ([$c[] | select(.type == "text")] | length) > 0 then 1 else empty end)
             else empty end' "$transcript" 2>/dev/null \
        | wc -l | tr -d ' '
    return 0
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
        # Every value a person can influence is escaped. This is the one writer
        # nothing rewrites afterwards, so an unescaped quote here leaves the note
        # unparseable for the rest of the session rather than for one hop.
        write_session_md "$folder/session.md" "schema_version: \"2.1\"
session_id: \"$session_id\"
date: $date_dir
project: \"$(yaml_escape "$project")\"
cwd: \"$(yaml_escape "$cwd")\"
git_branch: \"$(yaml_escape "$branch")\"
started_at: $started
docs_path: \"_sessions/$date_dir/$session_id/docs\"
forked_from: \"$(yaml_escape "$forked")\"
forked_from_name: \"$(yaml_escape "$forked_name")\"
delegated_by: \"\"
delegated_by_name: \"\"
transcript_source: \"$(yaml_escape "$transcript")\"
session_name: \"$(yaml_escape "$title")\"
ended_at:
duration_seconds:
summary:
tags:" "$body"
    fi

    echo "$folder"
}

export -f yaml_escape
export -f yaml_unescape
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
export -f set_frontmatter_list
export -f count_user_messages
export -f recap_lock_acquire
export -f recap_lock_release
