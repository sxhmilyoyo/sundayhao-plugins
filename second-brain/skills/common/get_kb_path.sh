#!/bin/bash
# get_kb_path.sh - Knowledge Bank Path Discovery Utility
#
# Reads the knowledge bank path from the plugin config file:
#   ~/.claude/plugins/config/second-brain/config.json
#
# Usage:
#   source get_kb_path.sh
#   KB_PATH=$(get_kb_path)

# Plugin config file location
PLUGIN_CONFIG_FILE="${HOME}/.claude/plugins/config/second-brain/config.json"

get_kb_path() {
    # Check if config file exists
    if [ ! -f "$PLUGIN_CONFIG_FILE" ]; then
        echo "ERROR: Knowledge bank not configured!" >&2
        echo "Run: setup_kb_path.sh --configure" >&2
        return 1
    fi

    # Extract path from JSON config
    local kb_path=""
    if command -v jq &> /dev/null; then
        kb_path=$(jq -r '.knowledge_bank_path // empty' "$PLUGIN_CONFIG_FILE" 2>/dev/null)
    else
        # Fallback: Simple grep-based extraction if jq not available
        kb_path=$(grep -o '"knowledge_bank_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$PLUGIN_CONFIG_FILE" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')
    fi

    # Clean up path (remove trailing slash)
    kb_path=$(echo "$kb_path" | sed 's|/$||')

    # Validate path
    if [ -z "$kb_path" ]; then
        echo "ERROR: Invalid config file - knowledge_bank_path not found" >&2
        echo "Run: setup_kb_path.sh --configure" >&2
        return 1
    fi

    if [ ! -d "$kb_path" ]; then
        echo "ERROR: Knowledge bank directory not found: $kb_path" >&2
        echo "Run: setup_kb_path.sh --configure" >&2
        return 1
    fi

    echo "$kb_path"
    return 0
}

# Read one key from the plugin config.
# Falls back on every failure — missing file, missing key, unreadable JSON, no
# jq — so a broken config disables a feature rather than enabling it.
# Args: $1=key, $2=default
# Returns: the configured value, or the default
get_plugin_config_value() {
    local key="$1" default="$2" value=""
    [ -f "$PLUGIN_CONFIG_FILE" ] || { echo "$default"; return 0; }
    if command -v jq &> /dev/null; then
        value=$(jq -r --arg k "$key" '.[$k] // empty' "$PLUGIN_CONFIG_FILE" 2>/dev/null)
    fi
    if [ -n "$value" ]; then echo "$value"; else echo "$default"; fi
    return 0
}

# Validate that KB path exists
validate_kb_path() {
    local kb_path="$1"

    if [ -z "$kb_path" ]; then
        echo "ERROR: Knowledge bank path is empty" >&2
        return 1
    fi

    if [ ! -d "$kb_path" ]; then
        echo "ERROR: Knowledge bank not found at: $kb_path" >&2
        return 1
    fi

    return 0
}

# Discover available projects in knowledge bank
# Returns: newline-separated list of project directory names
discover_projects() {
    local kb_path="${1:-}"

    # Use get_kb_path if no path provided
    if [ -z "$kb_path" ]; then
        kb_path=$(get_kb_path 2>/dev/null) || return 1
    fi

    local projects_dir="$kb_path/projects"

    if [ -d "$projects_dir" ]; then
        ls -1 "$projects_dir" 2>/dev/null | sort
    fi
}

# Discover categories (subdirectories) within a project
# Returns: newline-separated list of category directory names
discover_categories() {
    local project_path="$1"

    if [ -d "$project_path" ]; then
        # Find immediate subdirectories only
        find "$project_path" -maxdepth 1 -mindepth 1 -type d -exec basename {} \; 2>/dev/null | sort
    fi
}

# Check if a project exists in the knowledge bank
project_exists() {
    local project_name="$1"
    local kb_path="${2:-}"

    if [ -z "$kb_path" ]; then
        kb_path=$(get_kb_path 2>/dev/null) || return 1
    fi

    [ -d "$kb_path/projects/$project_name" ]
}

# Get the first available MOC file in the knowledge bank
# Useful for testing and fallback scenarios
find_first_moc() {
    local kb_path="${1:-}"

    if [ -z "$kb_path" ]; then
        kb_path=$(get_kb_path 2>/dev/null) || return 1
    fi

    # First check _index directory
    local moc_file=$(find "$kb_path/_index" -name "*MOC*.md" -type f 2>/dev/null | head -1)

    # If not found, search entire knowledge bank
    if [ -z "$moc_file" ]; then
        moc_file=$(find "$kb_path" -name "*MOC*.md" -type f 2>/dev/null | head -1)
    fi

    echo "$moc_file"
}

# Export functions for use in scripts
export -f get_kb_path
export -f get_plugin_config_value
export -f validate_kb_path
export -f discover_projects
export -f discover_categories
export -f project_exists
export -f find_first_moc
