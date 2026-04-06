#!/bin/bash
# detect_session_sources.sh - Detect ingestible references and artifacts from a session
#
# Scans session.md body sections and transcript for knowledge-bearing sources:
#   - Generated Artifacts (docs/ files)
#   - Plans (Claude Code plan files)
#   - Memory Snapshot files
#   - External references (non-code files read, URLs fetched)
#
# Usage: ./detect_session_sources.sh <session_folder> [transcript_path]
#
# Output: Classified list, one per line:
#   artifact|<path>|<description>
#   reference|<path_or_url>|<description>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$SCRIPT_DIR/../../common"
source "$COMMON_DIR/obsidian_helpers.sh"

if [ $# -lt 1 ]; then
    echo "Usage: $0 <session_folder> [transcript_path]" >&2
    exit 1
fi

SESSION_FOLDER="$1"
TRANSCRIPT="${2:-}"

SESSION_MD="$SESSION_FOLDER/session.md"

if [ ! -f "$SESSION_MD" ]; then
    echo "Error: session.md not found at $SESSION_MD" >&2
    exit 1
fi

# If no transcript provided, read from session.md frontmatter
if [ -z "$TRANSCRIPT" ]; then
    TRANSCRIPT=$(read_frontmatter_prop "$SESSION_MD" "transcript_source")
fi

# --- Artifacts from docs/ directory ---
DOCS_DIR="$SESSION_FOLDER/docs"
if [ -d "$DOCS_DIR" ]; then
    while IFS= read -r -d '' file; do
        local_path="${file#"$SESSION_FOLDER"/}"
        echo "artifact|${file}|Session doc: ${local_path}"
    done < <(find "$DOCS_DIR" -name "*.md" -print0 | sort -z)
fi

# --- Plans from ## Plans ---
# WikiLinks like: - [[plan-name]]
# Plans are stored at ~/.claude/plans/ — extract names from session.md
sed -n '/^## Plans$/,/^## /p' "$SESSION_MD" \
    | grep -o '\[\[[^]]*\]\]' | sed 's/\[\[//;s/\]\]//' \
    | while IFS= read -r plan_name; do
        # Claude Code stores plans at ~/.claude/plans/<name>.md
        plan_file="${HOME}/.claude/plans/${plan_name}.md"
        if [ -f "$plan_file" ]; then
            echo "artifact|${plan_file}|Plan: ${plan_name}"
        fi
    done

# --- Memory Snapshot from ## Memory Snapshot ---
MEMORY_DIR="$SESSION_FOLDER/memory"
if [ -d "$MEMORY_DIR" ]; then
    while IFS= read -r -d '' file; do
        local_path="${file#"$SESSION_FOLDER"/}"
        echo "reference|${file}|Memory: ${local_path}"
    done < <(find "$MEMORY_DIR" -name "*.md" -print0 | sort -z)
fi

# --- External references from transcript (single jq pass) ---
if [ -n "$TRANSCRIPT" ] && [ -f "$TRANSCRIPT" ]; then
    CWD=$(read_frontmatter_prop "$SESSION_MD" "cwd")

    # Extract both Read file paths and WebFetch URLs in one jq pass
    jq -r '.message.content[]? | select(.type == "tool_use") |
      if .name == "Read" then "READ|\(.input.file_path)"
      elif .name == "WebFetch" then "FETCH|\(.input.url)"
      else empty end' "$TRANSCRIPT" 2>/dev/null \
    | sort -u \
    | while IFS='|' read -r type value; do
        [ -z "$value" ] && continue
        if [ "$type" = "READ" ]; then
            # Filter to knowledge-bearing extensions only
            echo "$value" | grep -iqE '\.(md|txt|pdf|rst|adoc|org)$' || continue
            # Skip project source files and session folder files
            if [ -n "$CWD" ] && [[ "$value" == "$CWD"/* ]]; then continue; fi
            if [[ "$value" == "$SESSION_FOLDER"/* ]]; then continue; fi
            echo "reference|${value}|File read: $(basename "$value")"
        elif [ "$type" = "FETCH" ]; then
            echo "reference|${value}|URL fetched: ${value}"
        fi
    done
fi
