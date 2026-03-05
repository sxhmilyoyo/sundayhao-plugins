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
        silent 2>/dev/null
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
        path="$vault_path" 2>/dev/null
}

# Append content to session.md
# Args: $1=vault_relative_path, $2=content
append_to_session_note() {
    local vault_path="$1"
    local content="$2"
    obsidian vault="$OBSIDIAN_VAULT" append \
        path="$vault_path" \
        content="$content" 2>/dev/null
}

# Read session.md content
# Args: $1=vault_relative_path
read_session_note() {
    local vault_path="$1"
    obsidian vault="$OBSIDIAN_VAULT" read \
        path="$vault_path" 2>/dev/null
}

export -f get_vault_relative_path
export -f create_session_note
export -f set_session_property
export -f append_to_session_note
export -f read_session_note
