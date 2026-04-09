#!/bin/bash
# SessionStart:resume hook - ensures session folder exists and re-injects docs path
# Called when a Claude Code session is resumed (--continue or --resume).
# Creates session.md via filesystem write if the session folder doesn't exist yet.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
CWD=$(echo "$INPUT" | jq -r '.cwd')

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../skills/common/get_kb_path.sh"
source "$SCRIPT_DIR/../../skills/common/detect_project.sh"
source "$SCRIPT_DIR/../../skills/common/obsidian_helpers.sh"

KB_PATH=$(get_kb_path 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$KB_PATH" ]; then
    cat << 'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Resume: Knowledge bank not configured."
  }
}
EOF
    exit 0
fi

# Clean up ghost folder created by session_start.sh (startup matcher).
# On resume, Claude Code fires both "startup" and "resume" SessionStart matchers
# with different session_ids. The startup hook creates a ghost folder with a new
# ephemeral ID. This block reads that ID and deletes the ghost.
# TODO: Remove this cleanup (+ session_start.sh lines 10-13) if Claude Code
# stops firing the "startup" matcher on SessionStart during resume.
CWD_HASH=$(echo "$CWD" | md5)
GHOST_ID_FILE="/tmp/second-brain-startup-$CWD_HASH"
GHOST_ID=$(cat "$GHOST_ID_FILE" 2>/dev/null)
rm -f "$GHOST_ID_FILE"
if [ -n "$GHOST_ID" ] && [ "$GHOST_ID" != "$SESSION_ID" ]; then
    GHOST_MATCHES=("$KB_PATH/_sessions"/*/"$GHOST_ID")
    GHOST_FOLDER="${GHOST_MATCHES[0]}"
    [ -d "$GHOST_FOLDER" ] && rm -rf "$GHOST_FOLDER"
fi

# Read cached folder path from SessionStart, fall back to glob
SESSION_FOLDER=$(cat "/tmp/second-brain-folder-$SESSION_ID" 2>/dev/null)
if [ ! -d "$SESSION_FOLDER" ]; then
    MATCHES=("$KB_PATH/_sessions"/*/"$SESSION_ID")
    SESSION_FOLDER="${MATCHES[0]}"
fi

if [ ! -d "$SESSION_FOLDER" ]; then
    # Create session folder as fallback
    TODAY=$(date +%Y-%m-%d)
    SESSION_FOLDER="$KB_PATH/_sessions/$TODAY/$SESSION_ID"
    mkdir -p "$SESSION_FOLDER/docs"
    echo "$SESSION_FOLDER" > "/tmp/second-brain-folder-$SESSION_ID"

    # Detect git branch and project
    GIT_BRANCH=""
    if [ -d "$CWD/.git" ] || git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
        GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
    fi
    PROJECT=$(detect_project "$CWD")

    # Create session.md with full frontmatter in one atomic filesystem write
    FRONTMATTER="schema_version: \"2.0\"
session_id: \"$SESSION_ID\"
date: $TODAY
project: \"$PROJECT\"
cwd: \"$CWD\"
git_branch: \"$GIT_BRANCH\"
started_at: $(date -u +%Y-%m-%dT%H:%M:%S)
docs_path: \"_sessions/$TODAY/$SESSION_ID/docs\"
transcript_source:
session_name:
ended_at:
duration_seconds:
summary:
tags:"

    write_session_md "$SESSION_FOLDER/session.md" "$FRONTMATTER" "# Session: $SESSION_ID"
else
    # Ensure docs/ dir exists for existing sessions
    mkdir -p "$SESSION_FOLDER/docs"
fi

# Rename tmux window if session has a name
SESSION_NAME=$(read_frontmatter_prop "$SESSION_FOLDER/session.md" "session_name")
[ -n "$SESSION_NAME" ] && tmux rename-window "$SESSION_NAME" 2>/dev/null

# Re-inject docs path into system prompt
DOCS_PATH="$SESSION_FOLDER/docs"
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Session resumed: $SESSION_FOLDER\n\nSession docs path: $DOCS_PATH\n\nWhen generating working documents (designs, plans, reviews, SOPs, issues, handoffs), write them to the session docs path above. Use subdirectories by type:\n- docs/designs/    — architecture and design documents\n- docs/plans/      — implementation plans\n- docs/reviews/    — code/design review notes\n- docs/issues/     — issue investigation and resolution\n- docs/sops/       — standard operating procedures\n- docs/            — anything else (handoffs, quick-start guides, etc.)"
  }
}
EOF
