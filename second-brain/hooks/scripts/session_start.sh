#!/bin/bash
# SessionStart hook - creates session folder with session.md and injects docs path
# This script is called when a new Claude Code session starts.
# Creates session.md with full YAML frontmatter via direct filesystem write.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../skills/common/get_kb_path.sh"
source "$SCRIPT_DIR/../../skills/common/detect_project.sh"
source "$SCRIPT_DIR/../../skills/common/obsidian_helpers.sh"

# Try to get KB path (will fail if not configured)
KB_PATH=$(get_kb_path 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$KB_PATH" ]; then
    SETUP_SCRIPT="$SCRIPT_DIR/../../skills/common/setup_kb_path.sh"
    cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Second Brain Plugin: Knowledge bank not configured!\n\nRun this command to configure:\n  $SETUP_SCRIPT --configure"
  }
}
EOF
    exit 0
fi

# Session folder setup
TODAY=$(date +%Y-%m-%d)
SESSION_FOLDER="$KB_PATH/_sessions/$TODAY/$SESSION_ID"
DOCS_PATH="$SESSION_FOLDER/docs"
mkdir -p "$DOCS_PATH"

# Cache folder path so SessionEnd/PreCompact can skip folder search
echo "$SESSION_FOLDER" > "/tmp/second-brain-folder-$SESSION_ID"

# Write the note only when it is absent. This hook also fires for /clear and for
# a fork, and a /clear keeps the same session id, so rewriting here would discard
# the tags, summary and name set earlier in the very same session.
if [ ! -f "$SESSION_FOLDER/session.md" ]; then
    # Detect git branch and project
    GIT_BRANCH=""
    if [ -d "$CWD/.git" ] || git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
        GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
    fi
    PROJECT=$(detect_project "$CWD")

    # Timestamps
    STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%S)

    # A forked session continues another conversation under a new id, and replays
    # its parent's history, so the parent is recoverable from this transcript.
    FORKED_FROM=$(transcript_forked_from "$TRANSCRIPT_PATH" "$SESSION_ID")

    # Create session.md with full frontmatter in one atomic filesystem write.
    # Bypasses Obsidian CLI for reliability — CLI create can fail silently.
    FRONTMATTER="schema_version: \"2.0\"
session_id: \"$SESSION_ID\"
date: $TODAY
project: \"$PROJECT\"
cwd: \"$CWD\"
git_branch: \"$GIT_BRANCH\"
started_at: $STARTED_AT
docs_path: \"_sessions/$TODAY/$SESSION_ID/docs\"
forked_from: \"$FORKED_FROM\"
transcript_source:
session_name:
ended_at:
duration_seconds:
summary:
tags:"

    write_session_md "$SESSION_FOLDER/session.md" "$FRONTMATTER" "# Session: $SESSION_ID"
fi

# Inject system prompt with docs path
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Session folder created: $SESSION_FOLDER\n\nSession docs path: $DOCS_PATH\n\nWhen generating working documents (designs, plans, reviews, SOPs, issues, handoffs), write them to the session docs path above. Use subdirectories by type:\n- docs/designs/    — architecture and design documents\n- docs/plans/      — implementation plans\n- docs/reviews/    — code/design review notes\n- docs/issues/     — issue investigation and resolution\n- docs/sops/       — standard operating procedures\n- docs/            — anything else (handoffs, quick-start guides, etc.)"
  }
}
EOF
