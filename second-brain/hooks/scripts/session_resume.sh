#!/bin/bash
# SessionStart:resume hook - ensures session folder exists and re-injects docs path
# Called when a Claude Code session is resumed (--continue or --resume).
# Creates session.md via filesystem write if the session folder doesn't exist yet.

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

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

# Resolve the folder, and rebuild the note when it is the note that is missing —
# not only when the whole folder is. A folder can survive as a shell (a later doc
# write recreates it) while the note stays gone, which is how a lost note used to
# persist for the rest of a session's life.
SESSION_FOLDER=$(resolve_session_folder "$KB_PATH" "$SESSION_ID")
if [ -z "$SESSION_FOLDER" ] || [ ! -f "$SESSION_FOLDER/session.md" ]; then
    SESSION_FOLDER=$(rebuild_session_md "$KB_PATH" "$SESSION_ID" "$TRANSCRIPT_PATH" "$CWD")
else
    # Ensure docs/ dir exists for existing sessions
    mkdir -p "$SESSION_FOLDER/docs"
fi

# Rename terminal container (tmux window / Herdr pane) if session has a name
SESSION_NAME=$(read_frontmatter_prop "$SESSION_FOLDER/session.md" "session_name")
rename_terminal_window "$SESSION_NAME"

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
