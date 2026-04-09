#!/bin/bash
# lint_broken_links.sh - Find WikiLinks that don't resolve to any KB file
# Usage: ./lint_broken_links.sh <kb_path>
# Output: One line per broken link: <source_file>|<broken_link>

set -e

KB_PATH="${1:?Usage: $0 <kb_path>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WIKILINK_UTILS="$SCRIPT_DIR/../../knowledge-bank-lookup/scripts/wikilink-utils.sh"

if [ ! -f "$WIKILINK_UTILS" ]; then
    echo "ERROR: wikilink-utils.sh not found at $WIKILINK_UTILS" >&2
    exit 1
fi
source "$WIKILINK_UTILS"

BROKEN=0

while IFS= read -r -d '' file; do
    links=$(extract_wikilinks "$file" 2>/dev/null || true)
    [ -z "$links" ] && continue
    while IFS= read -r link; do
        [ -z "$link" ] && continue
        resolved=$(resolve_wikilink "$link" "$KB_PATH" 2>/dev/null || true)
        if [ -z "$resolved" ] || [ ! -f "$resolved" ]; then
            rel_path="${file#"$KB_PATH"/}"
            echo "${rel_path}|${link}"
            BROKEN=$((BROKEN + 1))
        fi
    done <<< "$links"
done < <(find "$KB_PATH" -name "*.md" \
    -not -path "*/_sessions/*" \
    -not -path "*/_meta/*" \
    -not -path "*/.obsidian/*" \
    -not -path "*/archive/*" \
    -print0)

echo "TOTAL_BROKEN=$BROKEN" >&2
