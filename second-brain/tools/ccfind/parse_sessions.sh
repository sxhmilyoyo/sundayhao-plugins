#!/usr/bin/env bash
# parse_sessions.sh - Extract YAML frontmatter from session.md files
#
# Usage:
#   parse_sessions.sh <sessions_dir>
#
# Output: tab-delimited lines (one per session, newest first)
#   display_line\tsession_id\tcwd\tsession_path\traw_task_tag\traw_tags

set -euo pipefail

SESSIONS_DIR="${1:-}"
if [ -z "$SESSIONS_DIR" ] || [ ! -d "$SESSIONS_DIR" ]; then
    echo "Usage: $0 <sessions_dir>" >&2
    exit 1
fi

# Single awk program processes all session.md files at once.
# Extracts frontmatter, parses fields, formats display line, outputs TSV.
# -print0 / -0 handles paths with spaces; single xargs invocation guaranteed
# Sort relies on _sessions/YYYY-MM-DD/UUID/ path structure for date ordering
find "$SESSIONS_DIR" -name "session.md" -type f -print0 | sort -rz | xargs -0 awk '
BEGIN {
    FS = "\n"
    OFS = "\t"
}

FNR == 1 {
    if (session_id != "" && session_id != "(empty)") {
        output_line()
    }
    in_fm = 0; fm_count = 0; in_tags = 0
    session_id = ""; date_val = ""; project = ""; cwd = ""
    git_branch = ""; session_name = ""; task_tag = ""; summary = ""
    tags = ""; current_file = FILENAME
}

# Skip body lines after frontmatter ends
!in_fm && fm_count >= 2 { next }

/^---$/ {
    fm_count++
    if (fm_count == 1) { in_fm = 1; next }
    if (fm_count == 2) { in_fm = 0; next }
}

in_fm && /^tags:/ { in_tags = 1; next }
in_fm && in_tags && /^[[:space:]]+-[[:space:]]/ {
    val = $0
    sub(/^[[:space:]]+-[[:space:]]+/, "", val)
    gsub(/^"|"$/, "", val)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
    if (val != "" && val != "(empty)") {
        tags = (tags == "") ? val : tags "," val
    }
    next
}
in_fm && in_tags && !/^[[:space:]]+-/ { in_tags = 0 }

in_fm && !in_tags && /^[a-z_]+:/ {
    # Parse key: value pairs (BSD awk compatible)
    key = $0
    sub(/:.*/, "", key)
    val = $0
    sub(/^[a-z_]+:[[:space:]]*/, "", val)
    gsub(/^"|"$/, "", val)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", val)
    if (val == "(empty)" || val == "null") val = ""

    if (key == "session_id") session_id = val
    else if (key == "date") date_val = val
    else if (key == "project") project = val
    else if (key == "cwd") cwd = val
    else if (key == "git_branch") git_branch = val
    else if (key == "session_name") session_name = val
    else if (key == "task_tag") task_tag = val
    else if (key == "summary") summary = val
}

function output_line() {
    # Display: date | session_name (or project if no name) | task_tag | tags
    d_date = (date_val == "") ? "-" : date_val
    d_task_tag = (task_tag == "") ? "-" : task_tag
    d_tags = (tags == "") ? "-" : tags

    # session_name first, fall back to project
    d_label = (session_name != "") ? session_name : project
    if (d_label == "") d_label = "-"

    # Truncate for display
    d_label = substr(d_label, 1, 30)
    d_task_tag = substr(d_task_tag, 1, 30)
    d_tags_display = substr(d_tags, 1, 40)

    # Fixed-width display
    display = sprintf("%-10s | %-30s | %-30s | %s", \
        d_date, d_label, d_task_tag, d_tags_display)

    # Raw values for filtering
    raw_tt = (task_tag == "") ? "-" : task_tag
    raw_tags = (tags == "") ? "-" : tags
    raw_cwd = (cwd == "") ? "-" : cwd

    print display, session_id, raw_cwd, current_file, raw_tt, raw_tags
}

END {
    # Output last file
    if (session_id != "" && session_id != "(empty)") {
        output_line()
    }
}
'
