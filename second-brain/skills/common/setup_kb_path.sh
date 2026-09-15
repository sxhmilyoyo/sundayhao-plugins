#!/bin/bash
# setup_kb_path.sh - Knowledge Bank Configuration Tool
#
# Usage:
#   ./setup_kb_path.sh --configure              # Interactive configuration
#   ./setup_kb_path.sh --configure /path/to/kb  # Non-interactive (provide path)
#   ./setup_kb_path.sh --show                   # Show current configuration
#   ./setup_kb_path.sh                          # Same as --show
#
# Config file: ~/.claude/plugins/config/second-brain/config.json

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Config file location
CONFIG_DIR="${HOME}/.claude/plugins/config/second-brain"
CONFIG_FILE="${CONFIG_DIR}/config.json"

# Apply a jq expression to the config file, preserving every key the expression
# does not touch. Writes through a temp file so a jq failure cannot truncate a
# working config. Trailing args are the jq arguments and the filter.
write_config_keys() {
    if ! command -v jq &> /dev/null; then
        echo -e "${RED}ERROR: jq is required to update the config${NC}" >&2
        exit 1
    fi
    mkdir -p "$CONFIG_DIR"
    [ -f "$CONFIG_FILE" ] || echo '{}' > "$CONFIG_FILE"
    local tmp="${CONFIG_FILE}.tmp.$$"
    if jq "$@" "$CONFIG_FILE" > "$tmp" 2>/dev/null; then
        mv "$tmp" "$CONFIG_FILE"
    else
        rm -f "$tmp"
        echo -e "${RED}ERROR: could not update $CONFIG_FILE${NC}" >&2
        exit 1
    fi
}

# Set one scalar key, leaving every other key intact.
# Usage: set_key <key> <value>
set_key() {
    local key="${1:-}" value="${2:-}"

    if [ -z "$key" ]; then
        echo -e "${RED}ERROR: --set needs a key and a value${NC}" >&2
        exit 1
    fi

    # Keys with a closed value set are checked here, so a typo fails loudly at
    # the moment it is made rather than silently disabling a feature later.
    case "$key" in
        auto_recap)
            case "$value" in
                off|notify|on) ;;
                *)
                    echo -e "${RED}ERROR: auto_recap must be off, notify or on${NC}" >&2
                    exit 1
                    ;;
            esac
            ;;
    esac

    write_config_keys --arg k "$key" --arg v "$value" '.[$k] = $v'
    echo -e "${GREEN}✓ $key = $value${NC}"
}

# Map a working-directory prefix to a knowledge-bank domain.
# Usage: set_domain <path-prefix> <domain> [comma,separated,default,tags]
# A prefix ending in * matches any path beginning with the stem.
set_domain() {
    local prefix="${1:-}" domain="${2:-}" tags="${3:-}" kb_path tags_json

    if [ -z "$prefix" ] || [ -z "$domain" ]; then
        echo -e "${RED}ERROR: --set-domain needs a path prefix and a domain${NC}" >&2
        exit 1
    fi

    # The domain must already exist in the bank. A typo here would resolve to
    # empty at every read, which looks like an unmapped directory rather than a
    # mistake, so it is refused up front.
    kb_path=$(jq -r '.knowledge_bank_path // empty' "$CONFIG_FILE" 2>/dev/null || true)
    if [ -n "$kb_path" ] && [ -d "$kb_path/projects" ] && [ ! -d "$kb_path/projects/$domain" ]; then
        echo -e "${RED}ERROR: '$domain' is not a domain in $kb_path/projects${NC}" >&2
        echo "Domains: $(find "$kb_path/projects" -mindepth 1 -maxdepth 1 -type d \
            -exec basename {} \; 2>/dev/null | sort | paste -sd ' ' -)" >&2
        exit 1
    fi

    tags_json=$(printf '%s' "$tags" | jq -R 'split(",") | map(gsub("^ +| +$";"")) | map(select(length > 0))')

    write_config_keys --arg p "$prefix" --arg d "$domain" --argjson t "$tags_json" \
        '.project_domains = ((.project_domains // {}) + { ($p): ({domain: $d}
            + (if ($t | length) > 0 then {default_tags: $t} else {} end)) })'
    echo -e "${GREEN}✓ $prefix → $domain${NC}${tags:+ (tags: $tags)}"
}

# Show current configuration
show_config() {
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Second Brain - Knowledge Bank Configuration"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${RED}✗ Not configured${NC}"
        echo ""
        echo "Run: $0 --configure"
        echo ""
        return 1
    fi

    # Read config
    local kb_path=""
    if command -v jq &> /dev/null; then
        kb_path=$(jq -r '.knowledge_bank_path // empty' "$CONFIG_FILE" 2>/dev/null)
    else
        kb_path=$(grep -o '"knowledge_bank_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')
    fi

    if [ -z "$kb_path" ]; then
        echo -e "${RED}✗ Invalid config file${NC}"
        echo ""
        echo "Run: $0 --configure"
        return 1
    fi

    echo -e "${BLUE}Config file:${NC} $CONFIG_FILE"
    echo -e "${BLUE}Knowledge bank:${NC} $kb_path"

    if command -v jq &> /dev/null; then
        local domain_count
        domain_count=$(jq -r '.project_domains // {} | length' "$CONFIG_FILE" 2>/dev/null || echo 0)
        echo -e "${BLUE}Domain map:${NC} $domain_count entries"
        jq -r '.project_domains // {} | to_entries[] | "  \(.key) → \(.value.domain)"' \
            "$CONFIG_FILE" 2>/dev/null || true
    fi
    echo ""

    if [ -d "$kb_path" ]; then
        echo -e "${GREEN}✓ Path exists${NC}"

        # Show some stats
        if [ -d "$kb_path/projects" ]; then
            local project_count=$(find "$kb_path/projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
            echo "  Projects: $project_count"
        fi

        if [ -d "$kb_path/daily-log" ]; then
            local log_count=$(find "$kb_path/daily-log" -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
            echo "  Daily logs: $log_count"
        fi

        echo ""
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${GREEN}${BOLD}  ✅ Configuration valid${NC}"
        echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        return 0
    else
        echo -e "${RED}✗ Path does not exist${NC}"
        echo ""
        echo "Run: $0 --configure"
        return 1
    fi
}

# Configuration (interactive or non-interactive)
# Usage: configure [optional_path]
configure() {
    local provided_path="${1:-}"
    local user_path=""

    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  Second Brain - Knowledge Bank Setup"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""

    # Show current config if exists
    if [ -f "$CONFIG_FILE" ]; then
        local current_path=""
        if command -v jq &> /dev/null; then
            current_path=$(jq -r '.knowledge_bank_path // empty' "$CONFIG_FILE" 2>/dev/null)
        else
            current_path=$(grep -o '"knowledge_bank_path"[[:space:]]*:[[:space:]]*"[^"]*"' "$CONFIG_FILE" 2>/dev/null | sed 's/.*"\([^"]*\)"$/\1/')
        fi
        if [ -n "$current_path" ]; then
            echo -e "${YELLOW}Current configuration:${NC} $current_path"
            echo ""
        fi
    fi

    # Use provided path or prompt interactively
    if [ -n "$provided_path" ]; then
        user_path="$provided_path"
        echo "Using provided path: $user_path"
    else
        # Interactive mode - prompt for path
        read -p "Enter knowledge bank path: " user_path
    fi

    # Expand tilde
    user_path="${user_path/#\~/$HOME}"

    # Validate input
    if [ -z "$user_path" ]; then
        echo -e "${RED}ERROR: Path cannot be empty${NC}"
        exit 1
    fi

    # Check if path exists
    if [ ! -d "$user_path" ]; then
        echo ""
        echo -e "${YELLOW}Directory does not exist: $user_path${NC}"
        if [ -n "$provided_path" ]; then
            # Non-interactive mode - create automatically
            mkdir -p "$user_path"
            echo -e "${GREEN}✓ Created: $user_path${NC}"
        else
            # Interactive mode - ask
            read -p "Create it? [y/N]: " create_dir
            if [[ "$create_dir" =~ ^[Yy]$ ]]; then
                mkdir -p "$user_path"
                echo -e "${GREEN}✓ Created: $user_path${NC}"
            else
                echo -e "${RED}Aborted${NC}"
                exit 1
            fi
        fi
    fi

    # Create config directory
    mkdir -p "$CONFIG_DIR"

    # Merge rather than rewrite. Other keys live in this file — the recap switch
    # and the path-to-domain map — and rewriting it wholesale silently discarded
    # them, which is why every other write goes through --set.
    write_config_keys \
        --arg p "$user_path" \
        --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        '. + {version: "1.0", knowledge_bank_path: $p, configured_at: $t}'

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}${BOLD}  ✅ Configuration saved!${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  Path: $user_path"
    echo "  Config: $CONFIG_FILE"
    echo ""
    echo -e "${YELLOW}Note: Restart Claude Code to create session folder.${NC}"
    echo ""
}

# Main
case "${1:-}" in
    --configure|-c)
        # Pass optional second argument (path) to configure
        configure "${2:-}"
        ;;
    --set)
        set_key "${2:-}" "${3:-}"
        ;;
    --set-domain)
        set_domain "${2:-}" "${3:-}" "${4:-}"
        ;;
    --show|-s|"")
        show_config
        ;;
    --help|-h)
        echo "Usage: $0 [OPTION] [ARGS]"
        echo ""
        echo "Options:"
        echo "  --configure, -c [PATH]   Configure knowledge bank path"
        echo "                           If PATH provided: non-interactive"
        echo "                           If no PATH: interactive prompt"
        echo "  --set KEY VALUE          Set one config key, preserving the rest"
        echo "  --set-domain PREFIX DOMAIN [TAGS]"
        echo "                           Map a directory prefix to a knowledge-bank"
        echo "                           domain. A PREFIX ending in * matches any"
        echo "                           path beginning with the stem. TAGS is a"
        echo "                           comma-separated list of hints."
        echo "  --show, -s               Show current configuration (default)"
        echo "  --help, -h               Show this help"
        echo ""
        echo "Examples:"
        echo "  $0 --configure                           # Interactive"
        echo "  $0 --configure /path/to/knowledge-bank   # Non-interactive"
        echo "  $0 --set auto_recap notify               # One key, others intact"
        echo "  $0 --set-domain /work/svc* aax aax       # Prefix family → domain"
        echo "  $0 --show                                # Show config"
        ;;
    *)
        echo "Unknown option: $1"
        echo "Run: $0 --help"
        exit 1
        ;;
esac
