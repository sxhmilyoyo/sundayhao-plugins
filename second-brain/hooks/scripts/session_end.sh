#!/bin/bash
# SessionEnd hook - saves session-end segment AND updates session.md with final metadata
# Saves segment data (transcript, agents, plans) then enriches session.md with
# session_name (from customTitle), ended_at, duration_seconds, and generated_artifacts.

shopt -s nullglob

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path')
SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../skills/common/get_kb_path.sh"
source "$SCRIPT_DIR/../../skills/common/obsidian_helpers.sh"

KB_PATH=$(get_kb_path 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$KB_PATH" ]; then
    cat << 'EOF'
{
  "continue": true,
  "systemMessage": "Session ended. Knowledge bank not configured - session not saved."
}
EOF
    exit 0
fi

# Find existing session folder
SESSION_FOLDER=$(find "$KB_PATH/_sessions" -type d -name "$SESSION_ID" 2>/dev/null | head -1)

if [ -z "$SESSION_FOLDER" ]; then
    TODAY=$(date +%Y-%m-%d)
    SESSION_FOLDER="$KB_PATH/_sessions/$TODAY/$SESSION_ID"
    mkdir -p "$SESSION_FOLDER"
fi

# ── Segment-saving logic (unchanged from v1.0) ─────────────────────────

SEGMENT_COUNT=$(find "$SESSION_FOLDER" -maxdepth 1 -type d -name "segment-*" ! -name "segment-final" 2>/dev/null | wc -l | tr -d ' ')
SEGMENT_FOLDER="$SESSION_FOLDER/segment-$SEGMENT_COUNT"

mkdir -p "$SEGMENT_FOLDER/agents"
mkdir -p "$SEGMENT_FOLDER/plans"

cp "$TRANSCRIPT_PATH" "$SEGMENT_FOLDER/transcript.jsonl"

TRANSCRIPT_DIR=$(dirname "$TRANSCRIPT_PATH")
AGENTS_COPIED=""

AGENT_IDS=$(grep -o 'agent-[a-f0-9]\{7\}' "$TRANSCRIPT_PATH" 2>/dev/null | sort -u)

EXISTING_AGENTS=""
for prev_segment in "$SESSION_FOLDER"/segment-*/agents/; do
    if [ -d "$prev_segment" ]; then
        for existing in "$prev_segment"*.jsonl; do
            [ -f "$existing" ] && EXISTING_AGENTS="$EXISTING_AGENTS $(basename "$existing" .jsonl)"
        done
    fi
done

for agent_id in $AGENT_IDS; do
    if ! echo "$EXISTING_AGENTS" | grep -q "$agent_id"; then
        agent_file="$TRANSCRIPT_DIR/${agent_id}.jsonl"
        if [ -f "$agent_file" ]; then
            cp "$agent_file" "$SEGMENT_FOLDER/agents/"
            AGENTS_COPIED="$AGENTS_COPIED\"agents/${agent_id}.jsonl\","
        fi
    fi
done

PLANS_COPIED=""
PLAN_FILES=$(grep -o 'plans/[^"]*\.md' "$TRANSCRIPT_PATH" 2>/dev/null | sort -u)

EXISTING_PLANS=""
for prev_segment in "$SESSION_FOLDER"/segment-*/plans/; do
    if [ -d "$prev_segment" ]; then
        for existing in "$prev_segment"*.md; do
            [ -f "$existing" ] && EXISTING_PLANS="$EXISTING_PLANS $(basename "$existing")"
        done
    fi
done

for plan_rel_path in $PLAN_FILES; do
    plan_name=$(basename "$plan_rel_path")
    if ! echo "$EXISTING_PLANS" | grep -q "$plan_name"; then
        plan_full_path="$HOME/.claude/$plan_rel_path"
        if [ -f "$plan_full_path" ]; then
            cp "$plan_full_path" "$SEGMENT_FOLDER/plans/"
            PLANS_COPIED="$PLANS_COPIED\"plans/$plan_name\","
        fi
    fi
done

cat > "$SEGMENT_FOLDER/metadata.json" << EOF
{
  "segment": $SEGMENT_COUNT,
  "type": "session-end",
  "ended_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "files": {
    "transcript": "transcript.jsonl",
    "agents": [${AGENTS_COPIED%,}],
    "plans": [${PLANS_COPIED%,}]
  }
}
EOF

# ── Update session.md with end-time metadata ───────────────────────────

VAULT_PATH=$(get_vault_relative_path "$SESSION_FOLDER/session.md" "$KB_PATH")
ENDED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Read session.md to get started_at for duration calculation
SESSION_CONTENT=$(read_session_note "$VAULT_PATH")
STARTED_AT=$(echo "$SESSION_CONTENT" | grep "^started_at:" | head -1 | sed 's/started_at:[[:space:]]*//')

# Calculate duration
DURATION=""
if [ -n "$STARTED_AT" ]; then
    START_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$STARTED_AT" +%s 2>/dev/null)
    END_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$ENDED_AT" +%s 2>/dev/null)
    if [ -n "$START_EPOCH" ] && [ -n "$END_EPOCH" ]; then
        DURATION=$(( END_EPOCH - START_EPOCH ))
    fi
fi

# Read customTitle from Claude Code's sessions-index.json
CWD=$(echo "$SESSION_CONTENT" | grep "^cwd:" | head -1 | sed 's/cwd:[[:space:]]*//')
SESSION_NAME=""
if [ -n "$CWD" ]; then
    PROJECT_HASH=$(echo "$CWD" | sed 's|/|-|g')
    SESSIONS_INDEX="$HOME/.claude/projects/${PROJECT_HASH}/sessions-index.json"
    if [ -f "$SESSIONS_INDEX" ]; then
        SESSION_NAME=$(jq -r --arg sid "$SESSION_ID" \
            '.entries[] | select(.sessionId == $sid) | .customTitle // empty' \
            "$SESSIONS_INDEX" 2>/dev/null)
    fi
fi

# Update session.md properties
set_session_property "$VAULT_PATH" "ended_at" "$ENDED_AT" "datetime"
[ -n "$DURATION" ] && set_session_property "$VAULT_PATH" "duration_seconds" "$DURATION" "number"
[ -n "$SESSION_NAME" ] && set_session_property "$VAULT_PATH" "session_name" "$SESSION_NAME"

# Scan docs/ folder for generated artifacts
DOCS_DIR="$SESSION_FOLDER/docs"
if [ -d "$DOCS_DIR" ]; then
    ARTIFACTS_SECTION=""
    while IFS= read -r doc_file; do
        doc_name=$(basename "$doc_file" .md)
        if [ -n "$ARTIFACTS_SECTION" ]; then
            ARTIFACTS_SECTION="$ARTIFACTS_SECTION\n"
        fi
        ARTIFACTS_SECTION="${ARTIFACTS_SECTION}- [[${doc_name}]]"
    done < <(find "$DOCS_DIR" -name "*.md" -type f 2>/dev/null | sort)

    if [ -n "$ARTIFACTS_SECTION" ]; then
        append_to_session_note "$VAULT_PATH" "\n## Generated Artifacts\n${ARTIFACTS_SECTION}"
    fi
fi

# ── Output ──────────────────────────────────────────────────────────────

cat << EOF
{
  "continue": true,
  "systemMessage": "Segment $SEGMENT_COUNT saved (session-end). Session complete: $SESSION_FOLDER"
}
EOF
