#!/bin/bash
# SessionStart:resume hook - ensures session folder exists and re-injects docs path
# Called when a Claude Code session is resumed (--continue or --resume).
# Creates session.md via Obsidian CLI if the session folder doesn't exist yet.

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
  "continue": true,
  "systemMessage": "Resume: Knowledge bank not configured."
}
EOF
    exit 0
fi

# Find the session folder
SESSION_FOLDER=$(find "$KB_PATH/_sessions" -type d -name "$SESSION_ID" 2>/dev/null | head -1)

if [ -z "$SESSION_FOLDER" ]; then
    # Create session folder as fallback
    TODAY=$(date +%Y-%m-%d)
    SESSION_FOLDER="$KB_PATH/_sessions/$TODAY/$SESSION_ID"
    mkdir -p "$SESSION_FOLDER/docs"

    # Detect git branch and project
    GIT_BRANCH=""
    if [ -d "$CWD/.git" ] || git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
        GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
    fi
    PROJECT=$(detect_project "$CWD")

    # Create session.md via Obsidian CLI
    VAULT_PATH=$(get_vault_relative_path "$SESSION_FOLDER/session.md" "$KB_PATH")
    create_session_note "$VAULT_PATH" "$SESSION_ID"
    set_session_property "$VAULT_PATH" "schema_version" "2.0"
    set_session_property "$VAULT_PATH" "session_id" "$SESSION_ID"
    set_session_property "$VAULT_PATH" "date" "$TODAY" "date"
    set_session_property "$VAULT_PATH" "project" "$PROJECT"
    set_session_property "$VAULT_PATH" "cwd" "$CWD"
    set_session_property "$VAULT_PATH" "git_branch" "$GIT_BRANCH"
    set_session_property "$VAULT_PATH" "started_at" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "datetime"
    set_session_property "$VAULT_PATH" "docs_path" "_sessions/$TODAY/$SESSION_ID/docs"
    set_session_property "$VAULT_PATH" "session_name" ""
    set_session_property "$VAULT_PATH" "ended_at" ""
    set_session_property "$VAULT_PATH" "duration_seconds" "" "number"
    set_session_property "$VAULT_PATH" "summary" ""
    set_session_property "$VAULT_PATH" "task_tag" ""
    set_session_property "$VAULT_PATH" "tags" "" "list"
    set_session_property "$VAULT_PATH" "generated_artifacts" "" "list"
else
    # Ensure docs/ dir exists for existing sessions
    mkdir -p "$SESSION_FOLDER/docs"
fi

# Re-inject docs path into system prompt
DOCS_PATH="$SESSION_FOLDER/docs"
cat << EOF
{
  "continue": true,
  "systemMessage": "Session resumed: $SESSION_FOLDER\n\nSession docs path: $DOCS_PATH\n\nWhen generating working documents (designs, plans, reviews, SOPs, issues, handoffs), write them to the session docs path above. Use subdirectories by type:\n- docs/designs/    — architecture and design documents\n- docs/plans/      — implementation plans\n- docs/reviews/    — code/design review notes\n- docs/issues/     — issue investigation and resolution\n- docs/sops/       — standard operating procedures\n- docs/            — anything else (handoffs, quick-start guides, etc.)"
}
EOF
