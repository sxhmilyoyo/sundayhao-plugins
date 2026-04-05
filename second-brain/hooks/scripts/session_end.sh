#!/bin/bash
# SessionEnd hook - updates session.md with final metadata (reference-only architecture)
# No segment copies — stores transcript_source path in frontmatter.
# Reads compaction-points.txt (written by pre_compact.sh) for segment boundaries.

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

# Read cached folder path from SessionStart (O(1)), fall back to glob
SESSION_FOLDER=$(cat "/tmp/second-brain-folder-$SESSION_ID" 2>/dev/null)
if [ ! -d "$SESSION_FOLDER" ]; then
    MATCHES=("$KB_PATH/_sessions"/*/"$SESSION_ID")
    SESSION_FOLDER="${MATCHES[0]}"
fi
if [ ! -d "$SESSION_FOLDER" ]; then
    TODAY=$(date +%Y-%m-%d)
    SESSION_FOLDER="$KB_PATH/_sessions/$TODAY/$SESSION_ID"
    mkdir -p "$SESSION_FOLDER"
fi

# ── 1. Read properties to preserve across overwrite ───────────────────
SESSION_MD="$SESSION_FOLDER/session.md"
SCHEMA_VERSION=$(read_frontmatter_prop "$SESSION_MD" "schema_version")
STARTED_AT=$(read_frontmatter_prop "$SESSION_MD" "started_at")
PROJECT=$(read_frontmatter_prop "$SESSION_MD" "project")
CWD=$(read_frontmatter_prop "$SESSION_MD" "cwd")
GIT_BRANCH=$(read_frontmatter_prop "$SESSION_MD" "git_branch")
DOCS_PATH_PROP=$(read_frontmatter_prop "$SESSION_MD" "docs_path")
DATE_PROP=$(read_frontmatter_prop "$SESSION_MD" "date")
# Properties set mid-session by user (via session-manager skill)
TAGS=$(read_frontmatter_list "$SESSION_MD" "tags")
SUMMARY=$(read_frontmatter_prop "$SESSION_MD" "summary")
SESSION_NAME=$(read_frontmatter_prop "$SESSION_MD" "session_name")

# ── 2. Compute end-time metadata ─────────────────────────────────────
ENDED_AT=$(date -u +%Y-%m-%dT%H:%M:%S)

DURATION=""
if [ -n "$STARTED_AT" ]; then
    START_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$STARTED_AT" +%s 2>/dev/null)
    END_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$ENDED_AT" +%s 2>/dev/null)
    if [ -n "$START_EPOCH" ] && [ -n "$END_EPOCH" ]; then
        DURATION=$(( END_EPOCH - START_EPOCH ))
    fi
fi

# Read customTitle from transcript (reverse-scan — fast on large files)
if [ -f "$TRANSCRIPT_PATH" ]; then
    CUSTOM_TITLE=$(tail -r "$TRANSCRIPT_PATH" 2>/dev/null \
        | grep -m1 '"type":"custom-title"' \
        | jq -r '.customTitle // empty' 2>/dev/null)
    [ -n "$CUSTOM_TITLE" ] && SESSION_NAME="$CUSTOM_TITLE"
fi

# ── 3. Copy auto memory snapshot ─────────────────────────────────────
if [ -n "$CWD" ]; then
    REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
    MEMORY_ROOT="${REPO_ROOT:-$CWD}"
    MEMORY_HASH=$(echo "$MEMORY_ROOT" | sed 's|[/.]|-|g')
    MEMORY_SRC="$HOME/.claude/projects/$MEMORY_HASH/memory"
    if [ -d "$MEMORY_SRC" ]; then
        cp -r "$MEMORY_SRC" "$SESSION_FOLDER/memory"
    fi
fi

# ── 4. Build hub body ────────────────────────────────────────────────
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

# Transcript source reference
BODY="$BODY\n\n## Transcript\n- Source: \`$TRANSCRIPT_PATH\`"

# Compaction Points (from pre_compact.sh sidecar)
CP_FILE="$SESSION_FOLDER/compaction-points.txt"
if [ -f "$CP_FILE" ]; then
    CP_LINES=""
    SEG_NUM=0
    while IFS=' ' read -r line_count timestamp; do
        CP_LINES="${CP_LINES}\n- Segment $SEG_NUM: $line_count lines ($timestamp)"
        SEG_NUM=$((SEG_NUM + 1))
    done < "$CP_FILE"
    [ -n "$CP_LINES" ] && BODY="$BODY\n\n## Compaction Points${CP_LINES}"
fi

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

# ── 5. Write session.md atomically (frontmatter + body) ───────────────
TAGS_YAML=""
if [ -n "$TAGS" ]; then
    TAGS_YAML=$(echo "$TAGS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | while read -r tag; do
        [ -n "$tag" ] && echo "  - $tag"
    done)
fi

_yaml_escape() { echo "${1//\"/\\\"}"; }

FRONTMATTER="schema_version: \"${SCHEMA_VERSION:-2.0}\"
session_id: \"$SESSION_ID\"
date: ${DATE_PROP:-}
project: \"$(_yaml_escape "${PROJECT:-}")\"
cwd: \"$(_yaml_escape "${CWD:-}")\"
git_branch: \"$(_yaml_escape "${GIT_BRANCH:-}")\"
started_at: ${STARTED_AT:-}
docs_path: \"$(_yaml_escape "${DOCS_PATH_PROP:-}")\"
transcript_source: \"$(_yaml_escape "$TRANSCRIPT_PATH")\"
session_name: \"$(_yaml_escape "${SESSION_NAME:-}")\"
ended_at: $ENDED_AT
duration_seconds: ${DURATION:-}
summary: \"$(_yaml_escape "${SUMMARY:-}")\"
tags:
${TAGS_YAML}"

RESOLVED_BODY=$(printf '%b' "$BODY")
write_session_md "$SESSION_FOLDER/session.md" "$FRONTMATTER" "$RESOLVED_BODY"

# ── Output ──────────────────────────────────────────────────────────────

cat << EOF
{
  "continue": true,
  "systemMessage": "Session complete: $SESSION_FOLDER"
}
EOF
