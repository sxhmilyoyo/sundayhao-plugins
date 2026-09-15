#!/bin/bash
# lint_ghost_folders.sh - Find ghost session folders: a folder registered for a
# session id that never became a conversation.
#
# Hooks never delete a session folder (see docs/adr/0001), so collecting ghosts is
# this check's job. The signature is deliberately one that no live session can
# match: a note nobody ever updated, no documents, and a transcript that never grew.
#
# Usage: ./lint_ghost_folders.sh <kb_path> [min_age_hours]
# Output: One line per ghost: <rel_path>|<date>|<age>|<transcript_state>

set -e

KB_PATH="${1:?Usage: $0 <kb_path> [min_age_hours]}"
MIN_AGE_HOURS="${2:-24}"
PROJECTS_DIR="${CLAUDE_PROJECTS_DIR:-$HOME/.claude/projects}"
NOW_EPOCH=$(date +%s)
GHOSTS=0

# Index every transcript once. Looking each one up with find instead costs a full
# scan of the projects tree per candidate folder, which is minutes, not seconds.
TRANSCRIPT_INDEX=$(find "$PROJECTS_DIR" -maxdepth 2 -name '*.jsonl' 2>/dev/null || true)

for folder in "$KB_PATH"/_sessions/*/*; do
    [ -d "$folder" ] || continue
    note="$folder/session.md"
    # A folder with no note at all is a different finding, not a ghost.
    [ -f "$note" ] || continue

    # Any of these means work happened here: files, documents, an end time, a
    # name, or a summary.
    [ -n "$(find "$folder" -mindepth 1 -maxdepth 1 ! -name session.md ! -name docs ! -name .DS_Store -print -quit 2>/dev/null)" ] && continue
    [ -n "$(find "$folder/docs" -mindepth 1 -print -quit 2>/dev/null)" ] && continue
    grep -qE '^ended_at: *[^[:space:]]' "$note" && continue
    grep -qE '^session_name: *"?[^"[:space:]]' "$note" && continue
    grep -qE '^summary: *"?[^"[:space:]]' "$note" && continue

    # Age gate, so a session that started moments ago is never mistaken for a ghost.
    if [[ "$OSTYPE" == "darwin"* ]]; then
        mod_epoch=$(stat -f %m "$note")
    else
        mod_epoch=$(stat -c %Y "$note")
    fi
    age_hours=$(( (NOW_EPOCH - mod_epoch) / 3600 ))
    [ "$age_hours" -lt "$MIN_AGE_HOURS" ] && continue

    # The decisive test: a real conversation grows a transcript.
    session_id=$(basename "$folder")
    transcript=$(printf '%s\n' "$TRANSCRIPT_INDEX" | grep -m1 "/${session_id}\.jsonl$" || true)
    if [ -z "$transcript" ]; then
        state="no transcript"
    else
        lines=$(wc -l < "$transcript" | tr -d ' ')
        [ "$lines" -gt 3 ] && continue
        state="${lines}-line transcript"
    fi

    echo "${folder#"$KB_PATH"/}|$(basename "$(dirname "$folder")")|${age_hours}h|${state}"
    GHOSTS=$((GHOSTS + 1))
done

echo "TOTAL_GHOSTS=$GHOSTS" >&2
