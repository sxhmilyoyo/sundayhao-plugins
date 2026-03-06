#!/usr/bin/env bash
# preview.sh - Show session.md content for fzf preview pane
#
# Usage: preview.sh <fzf-line>
# The fzf line is tab-delimited; field 4 is the session.md path.

set -euo pipefail

IFS=$'\t' read -r _ _ _ SESSION_PATH _ <<< "$1"

if [ -f "$SESSION_PATH" ]; then
    cat "$SESSION_PATH"
else
    echo "Session file not found: $SESSION_PATH"
fi
