#!/bin/bash
# PreCompact hook - records compaction boundary (stateless!)
# Appends a line-count + timestamp to compaction-points.txt so session_end.sh
# can reconstruct segment boundaries in session.md.

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')

# Derive session_id from transcript path
SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)

# Source common utilities for KB path discovery and session folder resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../skills/common/get_kb_path.sh"
source "$SCRIPT_DIR/../../skills/common/obsidian_helpers.sh"

# Get KB path (exit silently if not configured)
KB_PATH=$(get_kb_path 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$KB_PATH" ]; then
    cat << 'EOF'
{
  "continue": true,
  "systemMessage": "Pre-compact: Knowledge bank not configured."
}
EOF
    exit 0
fi

# Resolve the folder, reconstructing the note when there is none, so a compaction
# boundary is never recorded into a blank folder stamped with today's date.
SESSION_FOLDER=$(resolve_session_folder "$KB_PATH" "$SESSION_ID")
if [ -z "$SESSION_FOLDER" ] || [ ! -f "$SESSION_FOLDER/session.md" ]; then
    SESSION_FOLDER=$(rebuild_session_md "$KB_PATH" "$SESSION_ID" "$TRANSCRIPT_PATH" "")
fi

# Record compaction boundary: line count + timestamp
LINE_COUNT=$(wc -l < "$TRANSCRIPT_PATH" | tr -d ' ')
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)
echo "$LINE_COUNT $TIMESTAMP" >> "$SESSION_FOLDER/compaction-points.txt"

cat << EOF
{
  "continue": true,
  "systemMessage": "Compaction point recorded: $LINE_COUNT lines at $TIMESTAMP"
}
EOF
