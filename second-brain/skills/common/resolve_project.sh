#!/bin/bash
# resolve_project.sh - the one place a session's project is derived.
#
# project names a knowledge-bank domain, not the directory a session ran in
# (ADR-0004). The domain set is the vault's projects/ folders. The map from
# working directory to domain lives in the plugin config:
#
#   "project_domains": {
#     "/path/to/tree":     { "domain": "a2x", "default_tags": ["a2x"] },
#     "/path/to/packages*: { "domain": "aax" }
#   }
#
# A key matches a working directory it equals or contains; a key ending in `*`
# matches any path beginning with the stem, which is what covers a family of
# sibling package directories with one entry. The longest matching key wins.
#
# An unmatched directory, and any domain outside the set, resolve to empty. That
# is the point: an unrecognised domain stays visibly missing instead of being
# invented, and a legacy note holding a directory basename reads as unresolved
# without every consumer having to know it predates this decision.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get_kb_path.sh"

# The knowledge bank's domain set: one directory per domain under projects/.
# The single source of truth every consumer validates against.
# Args: $1=kb_path (optional; discovered from config when omitted)
# Returns: one domain per line, sorted
list_project_domains() {
    local kb_path="${1:-}"
    [ -n "$kb_path" ] || kb_path=$(get_kb_path 2>/dev/null) || return 0
    [ -d "$kb_path/projects" ] || return 0
    find "$kb_path/projects" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; \
        2>/dev/null | sort
}

# Echo a project value only when it is a member of the domain set.
# Args: $1=value, $2=kb_path (optional)
# Returns: the value, or empty when it is unresolved
validate_project() {
    local value="$1" kb_path="${2:-}"
    [ -n "$value" ] || return 0
    list_project_domains "$kb_path" | grep -qx -- "$value" && echo "$value"
    return 0
}

# Map keys, one per line. Empty when the config or the map is absent.
_domain_map_keys() {
    [ -f "$PLUGIN_CONFIG_FILE" ] || return 0
    jq -r '.project_domains // {} | keys[]' "$PLUGIN_CONFIG_FILE" 2>/dev/null
    return 0
}

# The longest map key matching a working directory.
# Args: $1=cwd
# Returns: the matched key, or empty
_match_domain_key() {
    local cwd="$1" best="" best_len=0 key stem len
    [ -n "$cwd" ] || return 0
    while IFS= read -r key; do
        [ -n "$key" ] || continue
        case "$key" in
            *'*')
                stem="${key%\*}"
                case "$cwd" in "$stem"*) ;; *) continue ;; esac
                ;;
            *)
                if [ "$cwd" != "$key" ]; then
                    case "$cwd" in "$key"/*) ;; *) continue ;; esac
                fi
                ;;
        esac
        len=${#key}
        if [ "$len" -gt "$best_len" ]; then best="$key"; best_len="$len"; fi
    done < <(_domain_map_keys)
    echo "$best"
}

# The knowledge-bank domain for a working directory.
# Args: $1=cwd, $2=kb_path (optional)
# Returns: a domain from the set, or empty when unmapped or out of set
resolve_project() {
    local cwd="$1" kb_path="${2:-}" key domain
    key=$(_match_domain_key "$cwd")
    [ -n "$key" ] || return 0
    domain=$(jq -r --arg k "$key" '.project_domains[$k].domain // empty' \
        "$PLUGIN_CONFIG_FILE" 2>/dev/null)
    validate_project "$domain" "$kb_path"
}

# The matched path's default tags, comma-separated.
# These are hints for the derivation instruction and nothing else: a hook that
# wrote them would leave every mapped session already tagged, and the trigger
# that asks the model to derive metadata would never fire again.
# Args: $1=cwd
# Returns: "tag, tag" or empty
project_default_tags() {
    local cwd="$1" key
    key=$(_match_domain_key "$cwd")
    [ -n "$key" ] || return 0
    jq -r --arg k "$key" '.project_domains[$k].default_tags // [] | join(", ")' \
        "$PLUGIN_CONFIG_FILE" 2>/dev/null
    return 0
}

export -f list_project_domains
export -f validate_project
export -f resolve_project
export -f project_default_tags
export -f _domain_map_keys
export -f _match_domain_key
