#!/bin/bash
# lint_orphans.sh - Find documents with zero incoming WikiLinks
# Usage: ./lint_orphans.sh <kb_path>
# Output: One line per orphan: <file_path>

set -e

KB_PATH="${1:?Usage: $0 <kb_path>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKILINK_UTILS="$SCRIPT_DIR/../../knowledge-bank-lookup/scripts/wikilink-utils.sh"

if [ ! -f "$WIKILINK_UTILS" ]; then
    echo "ERROR: wikilink-utils.sh not found" >&2
    exit 1
fi
source "$WIKILINK_UTILS"

# Build reverse-link index: count incoming references per file
declare -A INCOMING_REFS
ORPHANS=0

# First pass: collect all WikiLinks and record what they point to
while IFS= read -r -d '' file; do
    links=$(extract_wikilinks "$file" 2>/dev/null) || continue
    while IFS= read -r link; do
        [ -z "$link" ] && continue
        resolved=$(resolve_wikilink "$link" "$KB_PATH" 2>/dev/null)
        if [ -n "$resolved" ] && [ -f "$resolved" ]; then
            INCOMING_REFS["$resolved"]=$(( ${INCOMING_REFS["$resolved"]:-0} + 1 ))
        fi
    done <<< "$links"
done < <(find "$KB_PATH" -name "*.md" \
    -not -path "*/_sessions/*" \
    -not -path "*/_meta/*" \
    -not -path "*/_index/*" \
    -not -path "*/.obsidian/*" \
    -not -path "*/archive/*" \
    -print0)

# Second pass: find files with zero incoming references
while IFS= read -r -d '' file; do
    if [ -z "${INCOMING_REFS["$file"]}" ]; then
        rel_path="${file#"$KB_PATH"/}"
        echo "$rel_path"
        ORPHANS=$((ORPHANS + 1))
    fi
done < <(find "$KB_PATH" -name "*.md" \
    -not -path "*/_sessions/*" \
    -not -path "*/_meta/*" \
    -not -path "*/_index/*" \
    -not -path "*/.obsidian/*" \
    -not -path "*/archive/*" \
    -not -path "*/daily-log/*" \
    -print0)

echo "TOTAL_ORPHANS=$ORPHANS" >&2
