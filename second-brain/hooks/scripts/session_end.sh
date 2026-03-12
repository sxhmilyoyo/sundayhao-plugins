#!/bin/bash
# SessionEnd hook - saves session-end segment AND updates session.md with final metadata
# Saves segment data (transcript, agents, plans) then enriches session.md with
# session_name (from customTitle), ended_at, and duration_seconds.

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
  "ended_at": "$(date -u +%Y-%m-%dT%H:%M:%S)",
  "files": {
    "transcript": "transcript.jsonl",
    "agents": [${AGENTS_COPIED%,}],
    "plans": [${PLANS_COPIED%,}]
  }
}
EOF

# ── Rebuild session.md as hub note ─────────────────────────────────────
# Overwrites session.md body with links to all session artifacts, then
# re-sets all frontmatter properties. This is idempotent — running
# session_end multiple times produces the same result.

VAULT_PATH=$(get_vault_relative_path "$SESSION_FOLDER/session.md" "$KB_PATH")
ENDED_AT=$(date -u +%Y-%m-%dT%H:%M:%S)

# ── 1. Read properties to preserve across overwrite ───────────────────
# Read directly from filesystem (no Obsidian CLI — avoids timeout)
SESSION_MD="$SESSION_FOLDER/session.md"
SCHEMA_VERSION=$(read_frontmatter_prop "$SESSION_MD" "schema_version")
STARTED_AT=$(read_frontmatter_prop "$SESSION_MD" "started_at")
PROJECT=$(read_frontmatter_prop "$SESSION_MD" "project")
CWD=$(read_frontmatter_prop "$SESSION_MD" "cwd")
GIT_BRANCH=$(read_frontmatter_prop "$SESSION_MD" "git_branch")
DOCS_PATH_PROP=$(read_frontmatter_prop "$SESSION_MD" "docs_path")
DATE_PROP=$(read_frontmatter_prop "$SESSION_MD" "date")
# Properties set mid-session by user (via session-manager skill)
TASK_TAG=$(read_frontmatter_prop "$SESSION_MD" "task_tag")
TAGS=$(read_frontmatter_list "$SESSION_MD" "tags")
SUMMARY=$(read_frontmatter_prop "$SESSION_MD" "summary")
SESSION_NAME=$(read_frontmatter_prop "$SESSION_MD" "session_name")

# ── 2. Compute end-time metadata ─────────────────────────────────────
DURATION=""
if [ -n "$STARTED_AT" ]; then
    START_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$STARTED_AT" +%s 2>/dev/null)
    END_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$ENDED_AT" +%s 2>/dev/null)
    if [ -n "$START_EPOCH" ] && [ -n "$END_EPOCH" ]; then
        DURATION=$(( END_EPOCH - START_EPOCH ))
    fi
fi

# Read customTitle from transcript (overrides any existing session_name)
if [ -f "$TRANSCRIPT_PATH" ]; then
    CUSTOM_TITLE=$(grep '"type":"custom-title"' "$TRANSCRIPT_PATH" 2>/dev/null \
        | tail -1 | jq -r '.customTitle // empty' 2>/dev/null)
    [ -n "$CUSTOM_TITLE" ] && SESSION_NAME="$CUSTOM_TITLE"
fi

# ── 2b. Copy auto memory snapshot ─────────────────────────────────────
if [ -n "$CWD" ]; then
    REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
    MEMORY_ROOT="${REPO_ROOT:-$CWD}"
    MEMORY_HASH=$(echo "$MEMORY_ROOT" | sed 's|[/.]|-|g')
    MEMORY_SRC="$HOME/.claude/projects/$MEMORY_HASH/memory"
    if [ -d "$MEMORY_SRC" ]; then
        cp -r "$MEMORY_SRC" "$SESSION_FOLDER/memory"
    fi
fi

# ── 3. Build hub body ────────────────────────────────────────────────
BODY="# Session: $SESSION_ID"

# Generated Artifacts (docs/*.md)
DOCS_DIR="$SESSION_FOLDER/docs"
if [ -d "$DOCS_DIR" ]; then
    ARTIFACTS=""
    while IFS= read -r doc_file; do
        doc_name=$(basename "$doc_file" .md)
        ARTIFACTS="${ARTIFACTS}\n- [[${doc_name}]]"
    done < <(find "$DOCS_DIR" -name "*.md" -type f 2>/dev/null | sort)
    [ -n "$ARTIFACTS" ] && BODY="$BODY\n\n## Generated Artifacts${ARTIFACTS}"
fi

# Transcripts, Agents, Plans (from all segments)
TRANSCRIPTS=""
AGENTS=""
PLANS=""
for seg_dir in "$SESSION_FOLDER"/segment-*/; do
    [ -d "$seg_dir" ] || continue
    seg_name=$(basename "$seg_dir")

    # Transcript
    if [ -f "$seg_dir/transcript.jsonl" ]; then
        TRANSCRIPTS="${TRANSCRIPTS}\n- \`${seg_name}/transcript.jsonl\`"
    fi

    # Agents
    for agent_file in "$seg_dir"/agents/*.jsonl; do
        [ -f "$agent_file" ] || continue
        agent_name=$(basename "$agent_file" .jsonl)
        AGENTS="${AGENTS}\n- \`${seg_name}/agents/${agent_name}.jsonl\`"
    done

    # Plans
    for plan_file in "$seg_dir"/plans/*.md; do
        [ -f "$plan_file" ] || continue
        plan_name=$(basename "$plan_file" .md)
        PLANS="${PLANS}\n- [[${plan_name}]]"
    done
done

[ -n "$TRANSCRIPTS" ] && BODY="$BODY\n\n## Transcripts${TRANSCRIPTS}"
[ -n "$AGENTS" ] && BODY="$BODY\n\n## Agents${AGENTS}"
[ -n "$PLANS" ] && BODY="$BODY\n\n## Plans${PLANS}"

# Memory Snapshot (memory/*.md)
MEMORY_DIR="$SESSION_FOLDER/memory"
if [ -d "$MEMORY_DIR" ]; then
    MEMORY_FILES=""
    for mem_file in "$MEMORY_DIR"/*.md; do
        [ -f "$mem_file" ] || continue
        mem_name=$(basename "$mem_file" .md)
        MEMORY_FILES="${MEMORY_FILES}\n- [[${mem_name}]]"
    done
    [ -n "$MEMORY_FILES" ] && BODY="$BODY\n\n## Memory Snapshot${MEMORY_FILES}"
fi

# ── 4. Write session.md atomically (frontmatter + body) ───────────────
# Format tags as YAML list
TAGS_YAML=""
if [ -n "$TAGS" ]; then
    TAGS_YAML=$(echo "$TAGS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | while read -r tag; do
        [ -n "$tag" ] && echo "  - $tag"
    done)
fi

# Escape double quotes in user-provided values for YAML safety
_yaml_escape() { echo "${1//\"/\\\"}"; }

FRONTMATTER="schema_version: \"${SCHEMA_VERSION:-2.0}\"
session_id: \"$SESSION_ID\"
date: ${DATE_PROP:-}
project: \"$(_yaml_escape "${PROJECT:-}")\"
cwd: \"$(_yaml_escape "${CWD:-}")\"
git_branch: \"$(_yaml_escape "${GIT_BRANCH:-}")\"
started_at: ${STARTED_AT:-}
docs_path: \"$(_yaml_escape "${DOCS_PATH_PROP:-}")\"
session_name: \"$(_yaml_escape "${SESSION_NAME:-}")\"
ended_at: $ENDED_AT
duration_seconds: ${DURATION:-}
summary: \"$(_yaml_escape "${SUMMARY:-}")\"
task_tag: \"$(_yaml_escape "${TASK_TAG:-}")\"
tags:
${TAGS_YAML}"

RESOLVED_BODY=$(printf '%b' "$BODY")
write_session_md "$SESSION_FOLDER/session.md" "$FRONTMATTER" "$RESOLVED_BODY"

# ── Output ──────────────────────────────────────────────────────────────

cat << EOF
{
  "continue": true,
  "systemMessage": "Segment $SEGMENT_COUNT saved (session-end). Session complete: $SESSION_FOLDER"
}
EOF
