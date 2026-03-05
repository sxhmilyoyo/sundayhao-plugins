#!/bin/bash
# SessionStart hook - creates session folder with session.md and injects docs path
# This script is called when a new Claude Code session starts.
# Creates session.md via Obsidian CLI with rich metadata frontmatter.

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

# Create session.md via Obsidian CLI
VAULT_PATH=$(get_vault_relative_path "$SESSION_FOLDER/session.md" "$KB_PATH")
create_session_note "$VAULT_PATH" "$SESSION_ID"

# Set frontmatter properties (start-time fields)
set_session_property "$VAULT_PATH" "schema_version" "2.0"
set_session_property "$VAULT_PATH" "session_id" "$SESSION_ID"
set_session_property "$VAULT_PATH" "date" "$TODAY" "date"
set_session_property "$VAULT_PATH" "project" "$PROJECT"
set_session_property "$VAULT_PATH" "cwd" "$CWD"
set_session_property "$VAULT_PATH" "git_branch" "$GIT_BRANCH"
set_session_property "$VAULT_PATH" "started_at" "$STARTED_AT" "datetime"
set_session_property "$VAULT_PATH" "docs_path" "_sessions/$TODAY/$SESSION_ID/docs"

# Set empty placeholders for fields populated later
set_session_property "$VAULT_PATH" "session_name" ""
set_session_property "$VAULT_PATH" "ended_at" ""
set_session_property "$VAULT_PATH" "duration_seconds" "" "number"
set_session_property "$VAULT_PATH" "summary" ""
set_session_property "$VAULT_PATH" "task_tag" ""
set_session_property "$VAULT_PATH" "tags" "" "list"
set_session_property "$VAULT_PATH" "generated_artifacts" "" "list"

# Inject system prompt with docs path
cat << EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Session folder created: $SESSION_FOLDER\n\nSession docs path: $DOCS_PATH\n\nWhen generating working documents (designs, plans, reviews, SOPs, issues, handoffs), write them to the session docs path above. Use subdirectories by type:\n- docs/designs/    — architecture and design documents\n- docs/plans/      — implementation plans\n- docs/reviews/    — code/design review notes\n- docs/issues/     — issue investigation and resolution\n- docs/sops/       — standard operating procedures\n- docs/            — anything else (handoffs, quick-start guides, etc.)"
  }
}
EOF
