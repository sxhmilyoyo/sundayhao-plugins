#!/bin/bash
# lint_index_drift.sh - Find documents missing from _meta/index.md or vice versa
# Usage: ./lint_index_drift.sh <kb_path>
# Output: One line per drift: missing_from_index|<file_path>|<title> or stale_in_index||<title>

set -e

KB_PATH="${1:?Usage: $0 <kb_path>}"
INDEX_FILE="$KB_PATH/_meta/index.md"

if [ ! -f "$INDEX_FILE" ]; then
    echo "ERROR: _meta/index.md not found. Run generate_index.sh first." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/obsidian_helpers.sh"

DRIFT=0

# Build set of index titles for O(1) lookup
declare -A INDEX_SET
while IFS= read -r title; do
    [ -n "$title" ] && INDEX_SET["$title"]=1
done < <(grep -o '\[\[[^]]*\]\]' "$INDEX_FILE" | sed 's/\[\[//;s/\]\]//')

# Build set of filesystem titles during the forward pass (for reverse check)
declare -A FS_SET

# Forward check: files missing from index
while IFS= read -r -d '' file; do
    title=$(read_frontmatter_prop "$file" "title")
    [ -z "$title" ] && title=$(basename "$file" .md)
    FS_SET["$title"]=1

    if [ -z "${INDEX_SET["$title"]}" ]; then
        rel_path="${file#"$KB_PATH"/}"
        echo "missing_from_index|${rel_path}|${title}"
        DRIFT=$((DRIFT + 1))
    fi
done < <(find "$KB_PATH/projects" "$KB_PATH/reflections" "$KB_PATH/rules" "$KB_PATH/manual" "$KB_PATH/best-practices" \
    -name "*.md" -not -path "*/archive/*" -print0 2>/dev/null)

# Reverse check: index titles with no backing file (O(1) per title)
for title in "${!INDEX_SET[@]}"; do
    if [ -z "${FS_SET["$title"]}" ]; then
        echo "stale_in_index||${title}"
        DRIFT=$((DRIFT + 1))
    fi
done

echo "TOTAL_INDEX_DRIFT=$DRIFT" >&2
