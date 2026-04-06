#!/bin/bash
# lint_stale.sh - Find documents not modified in 90+ days
# Usage: ./lint_stale.sh <kb_path> [days]
# Output: One line per stale doc: <file_path>|<last_modified_date>|<days_ago>

set -e

KB_PATH="${1:?Usage: $0 <kb_path> [days]}"
STALE_DAYS="${2:-90}"
STALE=0
NOW_EPOCH=$(date +%s)

while IFS= read -r -d '' file; do
    # Get modification time in epoch seconds
    if [[ "$OSTYPE" == "darwin"* ]]; then
        mod_epoch=$(stat -f %m "$file")
    else
        mod_epoch=$(stat -c %Y "$file")
    fi

    days_ago=$(( (NOW_EPOCH - mod_epoch) / 86400 ))

    if [ "$days_ago" -ge "$STALE_DAYS" ]; then
        rel_path="${file#"$KB_PATH"/}"
        mod_date=$(date -r "$mod_epoch" '+%Y-%m-%d' 2>/dev/null || date -d "@$mod_epoch" '+%Y-%m-%d' 2>/dev/null)
        echo "${rel_path}|${mod_date}|${days_ago} days"
        STALE=$((STALE + 1))
    fi
done < <(find "$KB_PATH/projects" "$KB_PATH/reflections" "$KB_PATH/rules" "$KB_PATH/manual" "$KB_PATH/best-practices" \
    -name "*.md" -not -path "*/archive/*" -print0 2>/dev/null)

echo "TOTAL_STALE=$STALE" >&2
