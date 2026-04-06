#!/bin/bash
# obsidian_helpers.sh - Filesystem-based helper functions for session management
#
# All functions operate directly on the filesystem (no Obsidian CLI dependency).
# Obsidian's file watcher indexes changes automatically.

# Read a YAML frontmatter property directly from a markdown file (no CLI).
# Args: $1=absolute_file_path, $2=property_name
# Returns: unquoted value on stdout (empty if not found)
read_frontmatter_prop() {
    local file="$1"
    local prop="$2"
    [ -f "$file" ] || return 0
    sed -n '/^---$/,/^---$/p' "$file" \
        | grep "^${prop}:" | head -1 \
        | sed "s/^${prop}: *//" | sed 's/^"//;s/"$//'
}

# Read a YAML list property directly from a markdown file (no CLI).
# Args: $1=absolute_file_path, $2=property_name
# Returns: comma-separated string (e.g., "item1, item2")
read_frontmatter_list() {
    local file="$1"
    local prop="$2"
    [ -f "$file" ] || return 0
    sed -n '/^---$/,/^---$/p' "$file" \
        | sed -n "/^${prop}:/,/^[^ -]/p" \
        | grep '^ *- ' | sed 's/^ *- //' \
        | paste -sd ',' - | sed 's/,/, /g'
}

# Write session.md atomically — YAML frontmatter + body in one filesystem write.
# Bypasses Obsidian CLI for reliability; Obsidian's file watcher indexes it.
# Args: $1=absolute_file_path, $2=frontmatter (no --- delimiters), $3=body
write_session_md() {
    local file_path="$1"
    local frontmatter="$2"
    local body="$3"
    mkdir -p "$(dirname "$file_path")"
    printf '%s\n' "---" "$frontmatter" "---" "" "$body" > "$file_path"
}

# Append an entry to the KB operation log (_meta/log.md).
# Creates the file with a table header if it does not exist.
# Args: $1=kb_path, $2=operation_type (ingest|query|lint|index-rebuild),
#       $3=operator (session-recap|kb-ingest|kb-lookup|kb-lint), $4=details
append_kb_log() {
    local kb_path="$1"
    local op_type="$2"
    local operator="$3"
    local details="$4"
    local log_file="$kb_path/_meta/log.md"
    local timestamp
    timestamp=$(date -u '+%Y-%m-%d %H:%M')

    mkdir -p "$kb_path/_meta"

    if [ ! -f "$log_file" ]; then
        cat > "$log_file" << 'HEADER'
---
title: Knowledge Bank Operation Log
type: log
---

# Operation Log

| Timestamp | Operation | Operator | Details |
|-----------|-----------|----------|---------|
HEADER
    fi

    echo "| ${timestamp} | ${op_type} | ${operator} | ${details} |" >> "$log_file"
}

export -f read_frontmatter_prop
export -f read_frontmatter_list
export -f write_session_md
export -f append_kb_log
