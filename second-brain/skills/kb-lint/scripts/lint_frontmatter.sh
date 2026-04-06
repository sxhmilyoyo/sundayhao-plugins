#!/bin/bash
# lint_frontmatter.sh - Find documents missing required frontmatter fields
# Usage: ./lint_frontmatter.sh <kb_path>
# Output: One line per issue: <file_path>|<missing_fields>

set -e

KB_PATH="${1:?Usage: $0 <kb_path>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../common/obsidian_helpers.sh"

REQUIRED_FIELDS="title type created"
ISSUES=0

while IFS= read -r -d '' file; do
    missing=""
    for field in $REQUIRED_FIELDS; do
        value=$(read_frontmatter_prop "$file" "$field")
        if [ -z "$value" ]; then
            [ -n "$missing" ] && missing+=", "
            missing+="$field"
        fi
    done
    if [ -n "$missing" ]; then
        rel_path="${file#"$KB_PATH"/}"
        echo "${rel_path}|missing: ${missing}"
        ISSUES=$((ISSUES + 1))
    fi
done < <(find "$KB_PATH" -name "*.md" \
    -not -path "*/_sessions/*" \
    -not -path "*/_meta/*" \
    -not -path "*/.obsidian/*" \
    -not -path "*/archive/*" \
    -not -path "*/.claude/*" \
    -print0)

echo "TOTAL_MISSING_FRONTMATTER=$ISSUES" >&2
