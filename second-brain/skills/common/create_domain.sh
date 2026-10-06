#!/bin/bash
# create_domain.sh - the one way a new knowledge-bank domain comes into being.
#
#   create_domain.sh <name> [--map <path-prefix>] [--tags "a, b"]
#
# A domain is a folder under the vault's projects/ (ADR-0004), so creating one is a
# vocabulary mutation. It happens only here, and only downstream of a person's answer
# to a recap's proposal (ADR-0007): nothing calls this without an approval in hand.
# The name is refused unless it is a slug shaped like every existing domain —
# lowercase letters, digits, hyphens — because a folder becomes a domain the moment
# it exists, and the set is read by frontmatter joins and index filters that all
# assume that shape.
#
# The folder is idempotent: a retry re-approving the same name must resume, not
# fail. The map entry is delegated to setup_kb_path.sh --set-domain, which stays
# the one writer of project_domains; it requires the domain folder to exist, which
# is why the folder comes first.
#
# Exit: 0 domain ready (and mapped, when asked); 1 bank or map failure; 2 usage.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/get_kb_path.sh"

usage() {
    cat >&2 <<'USAGE'
Usage: create_domain.sh <name> [--map <path-prefix>] [--tags "a, b"]

  name     the new domain: lowercase letters, digits and hyphens, like `a2x`
  --map    also map this working-directory prefix to the domain, so future
           sessions there resolve without a proposal (delegated to
           setup_kb_path.sh --set-domain; a trailing * matches a family)
  --tags   default tags for the map entry, comma-separated
USAGE
    exit 2
}

NAME=""; PREFIX=""; TAGS=""
while [ $# -gt 0 ]; do
    case "$1" in
        --map)  [ $# -ge 2 ] || usage; PREFIX="$2"; shift ;;
        --tags) [ $# -ge 2 ] || usage; TAGS="$2";   shift ;;
        -*)     printf 'create_domain.sh: unknown option: %s\n' "$1" >&2; usage ;;
        *)      [ -z "$NAME" ] || usage; NAME="$1" ;;
    esac
    shift
done

[ -n "$NAME" ] || usage

printf '%s' "$NAME" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || {
    printf "create_domain.sh: '%s' is not a domain name (lowercase letters, digits, hyphens)\n" "$NAME" >&2
    exit 2
}

KB_PATH=$(get_kb_path) || exit 1

if [ -d "$KB_PATH/projects/$NAME" ]; then
    printf 'domain exists: %s\n' "$KB_PATH/projects/$NAME"
else
    mkdir -p "$KB_PATH/projects/$NAME" || exit 1
    printf 'domain created: %s\n' "$KB_PATH/projects/$NAME"
fi

if [ -n "$PREFIX" ]; then
    "$SCRIPT_DIR/setup_kb_path.sh" --set-domain "$PREFIX" "$NAME" "$TAGS" || exit 1
fi
