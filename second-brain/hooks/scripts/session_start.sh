#!/bin/bash
# SessionStart hook - creates session folder with session.md and injects docs path
# This script is called when a new Claude Code session starts.
# Creates session.md with full YAML frontmatter via direct filesystem write.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
CWD=$(echo "$INPUT" | jq -r '.cwd')

# Write ghost ID for resume cleanup coordination.
# TODO: Remove ghost cleanup (this + session_resume.sh lines 27-35) if Claude Code
# stops firing the "startup" matcher on SessionStart during resume.
CWD_HASH=$(echo "$CWD" | md5)
echo "$SESSION_ID" > "/tmp/second-brain-startup-$CWD_HASH"

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

# Detect git branch and project
GIT_BRANCH=""
if [ -d "$CWD/.git" ] || git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
    GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
fi
PROJECT=$(detect_project "$CWD")

# Timestamps
STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%S)

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
transcript_source:
session_name:
ended_at:
duration_seconds:
summary:
tags:"

write_session_md "$SESSION_FOLDER/session.md" "$FRONTMATTER" "# Session: $SESSION_ID"

# Inject system prompt with docs path
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Session folder created: $SESSION_FOLDER\n\nSession docs path: $DOCS_PATH\n\nWhen generating working documents (designs, plans, reviews, SOPs, issues, handoffs), write them to the session docs path above. Use subdirectories by type:\n- docs/designs/    — architecture and design documents\n- docs/plans/      — implementation plans\n- docs/reviews/    — code/design review notes\n- docs/issues/     — issue investigation and resolution\n- docs/sops/       — standard operating procedures\n- docs/            — anything else (handoffs, quick-start guides, etc.)"
  }
}
EOF
