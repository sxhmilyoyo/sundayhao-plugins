#!/bin/bash
# obsidian_helpers.sh - Obsidian CLI helper functions for session management
#
# Usage:
#   source obsidian_helpers.sh
#   create_session_note "$vault_rel_path" "$session_id"
#   set_session_property "$vault_rel_path" "property_name" "value" ["type"]

# Vault name for Obsidian CLI (KB is its own vault)
OBSIDIAN_VAULT="knowledge-bank"

# Convert absolute KB file path to vault-relative path
# e.g., /Volumes/.../knowledge-bank/_sessions/2026-03-04/abc/session.md
#     → _sessions/2026-03-04/abc/session.md
get_vault_relative_path() {
    local absolute_path="$1"
    local kb_path="$2"
    # Strip KB path prefix (and leading slash) to get vault-relative path
    echo "${absolute_path#$kb_path/}"
}

# Create a new session.md note via Obsidian CLI
# Args: $1=vault_relative_path, $2=session_id
create_session_note() {
    local vault_path="$1"
    local session_id="$2"
    obsidian vault="$OBSIDIAN_VAULT" create \
        path="$vault_path" \
        content="# Session: $session_id" \
        silent >/dev/null 2>&1
}

# Set a frontmatter property on session.md
# Args: $1=vault_relative_path, $2=name, $3=value, $4=type (optional, default "text")
set_session_property() {
    local vault_path="$1"
    local name="$2"
    local value="$3"
    local type="${4:-text}"
    obsidian vault="$OBSIDIAN_VAULT" property:set \
        name="$name" value="$value" type="$type" \
        path="$vault_path" >/dev/null 2>&1
}

# Append content to session.md
# Args: $1=vault_relative_path, $2=content
append_to_session_note() {
    local vault_path="$1"
    local content="$2"
    obsidian vault="$OBSIDIAN_VAULT" append \
        path="$vault_path" \
        content="$content" >/dev/null 2>&1
}

# Read session.md content
# Args: $1=vault_relative_path
read_session_note() {
    local vault_path="$1"
    obsidian vault="$OBSIDIAN_VAULT" read \
        path="$vault_path" 2>/dev/null
}

# Read a single frontmatter property value
# Args: $1=vault_relative_path, $2=property_name
# Returns: property value on stdout (empty if not found or error)
# For list properties, returns one item per line
read_session_property() {
    local vault_path="$1"
    local name="$2"
    local output
    output=$(obsidian vault="$OBSIDIAN_VAULT" property:read \
        name="$name" path="$vault_path" 2>/dev/null)
    # Obsidian CLI prints "Error: ..." to stdout on failure (exit code always 0)
    if [[ "$output" == Error:* ]]; then
        return 0
    fi
    echo "$output"
}

# Read a list property as comma-separated string (for passing back to property:set)
# Args: $1=vault_relative_path, $2=property_name
# Returns: "item1, item2, item3" on stdout (empty if not found)
read_session_property_list() {
    local vault_path="$1"
    local name="$2"
    read_session_property "$vault_path" "$name" | paste -sd ',' - | sed 's/,/, /g'
}

# Overwrite session.md content (preserves nothing — caller must re-set properties)
# Args: $1=vault_relative_path, $2=content
overwrite_session_note() {
    local vault_path="$1"
    local content="$2"
    obsidian vault="$OBSIDIAN_VAULT" create \
        path="$vault_path" \
        content="$content" \
        overwrite silent >/dev/null 2>&1
}

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

export -f get_vault_relative_path
export -f create_session_note
export -f set_session_property
export -f append_to_session_note
export -f read_session_note
export -f read_session_property
export -f read_session_property_list
export -f overwrite_session_note
export -f write_session_md
export -f read_frontmatter_prop
export -f read_frontmatter_list
