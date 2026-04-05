#!/bin/bash
# PreCompact hook - records compaction boundary (stateless!)
# Appends a line-count + timestamp to compaction-points.txt so session_end.sh
# can reconstruct segment boundaries in session.md.

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')

# Derive session_id from transcript path
SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)

# Source common utilities for KB path discovery
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../skills/common/get_kb_path.sh"

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

# Find existing session folder (glob is 32x faster than find on 500+ sessions)
MATCHES=("$KB_PATH/_sessions"/*/"$SESSION_ID")
SESSION_FOLDER="${MATCHES[0]}"
if [ ! -d "$SESSION_FOLDER" ]; then
    TODAY=$(date +%Y-%m-%d)
    SESSION_FOLDER="$KB_PATH/_sessions/$TODAY/$SESSION_ID"
    mkdir -p "$SESSION_FOLDER"
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
