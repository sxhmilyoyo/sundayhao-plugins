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

# A private name, because callers of this file have their own SCRIPT_DIR, and
# ${BASH_SOURCE[0]:-$0} because zsh sets only the latter for a sourced file.
_SB_RP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$_SB_RP_DIR/get_kb_path.sh"

# The knowledge bank's domain set: one directory per domain under projects/.
# The single source of truth every consumer validates against.
# Args: $1=kb_path (optional; discovered from config when omitted)
# Returns: one domain per line, sorted
list_project_domains() {
    local kb_path="${1:-}"
    [ -n "$kb_path" ] || kb_path=$(get_kb_path 2>/dev/null) || return 0
    [ -d "$kb_path/projects" ] || return 0
    # sed rather than -exec basename, which forks once per domain on a path this
    # hook reads on every session start.
    find "$kb_path/projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
        | sed 's|.*/||' | sort
}

# Echo a project value only when it is a member of the domain set.
# Args: $1=value, $2=kb_path (optional)
# Returns: the value, or empty when it is unresolved
validate_project() {
    local value="$1" kb_path="${2:-}"
    [ -n "$value" ] || return 0
    # -F because the value is data, not a pattern: a legacy basename like `a.x`
    # would otherwise match the domain `a2x` and read as resolved.
    list_project_domains "$kb_path" | grep -qxF -- "$value" && echo "$value"
    return 0
}

# Map keys, one per line. Empty when the config or the map is absent.
_domain_map_keys() {
    [ -f "$PLUGIN_CONFIG_FILE" ] || return 0
    jq -r '.project_domains // {} | keys[]' "$PLUGIN_CONFIG_FILE" 2>/dev/null
    return 0
}

# The most specific map key matching a working directory.
#
# Specificity is the length of the path the key actually constrains, so a
# wildcard's trailing `*` does not count towards it. Without that, `/w/a*` scored
# one character longer than its own stem and so outranked the strictly more
# specific `/w/ab`, quietly filing that tree's knowledge under the broader
# domain. A directory match also outranks a wildcard of equal reach, since it
# names a real place rather than a family.
# Args: $1=cwd
# Returns: the matched key, or empty
_match_domain_key() {
    local cwd="$1" best="" best_len=-1 best_exact=0 key stem len exact
    [ -n "$cwd" ] || return 0
    # Trailing slashes are stripped from both sides. A hook's cwd never has one,
    # but shell completion appends one to every directory, so a key typed that way
    # would match nothing and look exactly like an unmapped directory.
    while [ "${cwd%/}" != "$cwd" ] && [ "$cwd" != "/" ]; do cwd="${cwd%/}"; done
    while IFS= read -r key; do
        [ -n "$key" ] || continue
        case "$key" in
            *'*')
                stem="${key%\*}"
                while [ "${stem%/}" != "$stem" ] && [ "$stem" != "/" ]; do stem="${stem%/}"; done
                case "$cwd" in "$stem"*) ;; *) continue ;; esac
                len=${#stem}; exact=0
                ;;
            *)
                stem="$key"
                while [ "${stem%/}" != "$stem" ] && [ "$stem" != "/" ]; do stem="${stem%/}"; done
                if [ "$cwd" != "$stem" ]; then
                    case "$cwd" in "$stem"/*) ;; *) continue ;; esac
                fi
                len=${#stem}; exact=1
                ;;
        esac
        if [ "$len" -gt "$best_len" ] \
           || { [ "$len" -eq "$best_len" ] && [ "$exact" -gt "$best_exact" ]; }; then
            best="$key"; best_len="$len"; best_exact="$exact"
        fi
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
# Hints for whoever is choosing tags, and never values to write: a hook that wrote them
# would leave every mapped session tagged by its directory rather than by its work. The
# reader is the recap now, which weighs them against the conversation before deciding
# (ADR-0006); until 2.13.0 it was the start hook's derivation request, which is gone.
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
