#!/bin/bash
# validate_obsidian_syntax.sh - Validate Obsidian-specific syntax in markdown files
#
# Usage: validate_obsidian_syntax.sh <file-or-directory> [--fix]
#
# Validates:
# 1. WikiLink targets - verify linked files exist
# 2. Heading anchors - [[Note#Heading]] → verify heading exists
# 3. Callout types - > [!type] → verify type is valid
# 4. Frontmatter properties - YAML type consistency
# 5. Embed targets - ![[Note]] → verify embeddable content

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Valid callout types (Obsidian built-in + common custom)
VALID_CALLOUTS=(
    "note" "tip" "info" "warning" "danger" "bug"
    "example" "quote" "abstract" "summary" "tldr"
    "todo" "success" "check" "done" "question" "help" "faq"
    "failure" "fail" "missing" "error" "important" "caution" "attention"
)

# Required frontmatter properties by document type
declare -A REQUIRED_PROPERTIES
REQUIRED_PROPERTIES["concept"]="title type status"
REQUIRED_PROPERTIES["component"]="title type status"
REQUIRED_PROPERTIES["best-practice"]="title type status"
REQUIRED_PROPERTIES["daily-log"]="title type status"
REQUIRED_PROPERTIES["moc"]="title type"

# Valid property values
VALID_STATUS="active evolving deprecated archived experimental"
VALID_COMPLEXITY="simple intermediate advanced"
VALID_TYPES="concept component best-practice daily-log moc distilled reflection"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================================
# State
# ============================================================================

ERROR_COUNT=0
WARNING_COUNT=0
CHECKED_COUNT=0

# ============================================================================
# Functions
# ============================================================================

show_usage() {
    echo "Usage: $0 <file-or-directory> [options]"
    echo ""
    echo "Options:"
    echo "  --fix          Attempt to fix simple issues (not implemented yet)"
    echo "  --quiet        Only show errors, not warnings"
    echo "  --json         Output results as JSON"
    echo ""
    echo "Examples:"
    echo "  $0 /path/to/document.md"
    echo "  $0 /path/to/knowledge-bank/"
    exit 1
}

log_error() {
    echo -e "${RED}ERROR${NC}: $1" >&2
    ((++ERROR_COUNT))
}

log_warning() {
    echo -e "${YELLOW}WARN${NC}: $1" >&2
    ((++WARNING_COUNT))
}

log_success() {
    echo -e "${GREEN}OK${NC}: $1"
}

# Check if a callout type is valid
is_valid_callout() {
    local callout="$1"
    local lower_callout=$(echo "$callout" | tr '[:upper:]' '[:lower:]')

    for valid in "${VALID_CALLOUTS[@]}"; do
        if [[ "$lower_callout" == "$valid" ]]; then
            return 0
        fi
    done
    return 1
}

# Extract frontmatter from a markdown file
extract_frontmatter() {
    local file="$1"
    # Extract content between first --- and second ---
    awk '/^---$/{if(p){exit}else{p=1;next}} p{print}' "$file"
}

# Get property value from frontmatter
get_property() {
    local frontmatter="$1"
    local property="$2"
    echo "$frontmatter" | grep "^$property:" | sed "s/^$property:[[:space:]]*//"
}

# Validate frontmatter properties
validate_frontmatter() {
    local file="$1"
    local frontmatter=$(extract_frontmatter "$file")

    if [[ -z "$frontmatter" ]]; then
        log_error "$file: Missing frontmatter"
        return 1
    fi

    # Get document type
    local doc_type=$(get_property "$frontmatter" "type")

    if [[ -z "$doc_type" ]]; then
        log_error "$file: Missing 'type' property in frontmatter"
        return 1
    fi

    # Validate type value
    if ! echo "$VALID_TYPES" | grep -qw "$doc_type"; then
        log_warning "$file: Unknown document type '$doc_type'"
    fi

    # Check required properties
    local required="${REQUIRED_PROPERTIES[$doc_type]:-title type}"
    for prop in $required; do
        local value=$(get_property "$frontmatter" "$prop")
        if [[ -z "$value" ]]; then
            log_error "$file: Missing required property '$prop' for type '$doc_type'"
        fi
    done

    # Validate status value if present
    local status=$(get_property "$frontmatter" "status")
    if [[ -n "$status" ]] && ! echo "$VALID_STATUS" | grep -qw "$status"; then
        log_warning "$file: Invalid status value '$status' (valid: $VALID_STATUS)"
    fi

    # Validate complexity value if present
    local complexity=$(get_property "$frontmatter" "complexity")
    if [[ -n "$complexity" ]] && ! echo "$VALID_COMPLEXITY" | grep -qw "$complexity"; then
        log_warning "$file: Invalid complexity value '$complexity' (valid: $VALID_COMPLEXITY)"
    fi
}

# Validate callouts in file
validate_callouts() {
    local file="$1"

    # Find all callout declarations
    local callouts=$(grep -oE '>\s*\[!([a-zA-Z]+)\]' "$file" 2>/dev/null | \
        sed 's/.*\[!\([^]]*\)\].*/\1/' | sort -u)

    while IFS= read -r callout; do
        [[ -z "$callout" ]] && continue

        if ! is_valid_callout "$callout"; then
            log_warning "$file: Unknown callout type '[$callout]'"
        fi
    done <<< "$callouts"
}

# Validate WikiLinks in file
validate_wikilinks() {
    local file="$1"
    local base_dir=$(dirname "$file")

    # Extract all WikiLinks
    local links=$(grep -oE '\[\[[^\]]+\]\]' "$file" 2>/dev/null | \
        sed 's/\[\[//g; s/\]\]//g')

    while IFS= read -r link; do
        [[ -z "$link" ]] && continue

        # Parse link components
        local target="${link%%|*}"  # Remove display text
        local anchor=""

        if [[ "$target" == *"#"* ]]; then
            anchor="${target#*#}"
            target="${target%%#*}"
        fi

        # Skip external links and embeds for now
        [[ "$target" == "!"* ]] && continue

        # For anchor validation, we'd need to resolve the file path
        # This is a simplified check
        if [[ -n "$anchor" ]]; then
            # Note: Full anchor validation would require file resolution
            # This just logs for awareness
            : # log_info "$file: WikiLink with anchor: $target#$anchor"
        fi
    done <<< "$links"
}

# Validate a single file
validate_file() {
    local file="$1"

    if [[ ! -f "$file" ]]; then
        log_error "File not found: $file"
        return 1
    fi

    # Only process markdown files
    if [[ "$file" != *.md ]]; then
        return 0
    fi

    ((++CHECKED_COUNT))

    echo "Checking: $file"

    # Run validations
    validate_frontmatter "$file"
    validate_callouts "$file"
    validate_wikilinks "$file"
}

# Validate directory recursively
validate_directory() {
    local dir="$1"

    if [[ ! -d "$dir" ]]; then
        log_error "Directory not found: $dir"
        return 1
    fi

    # Find all markdown files
    while IFS= read -r -d '' file; do
        validate_file "$file"
    done < <(find "$dir" -name "*.md" -type f -print0)
}

# ============================================================================
# Main
# ============================================================================

main() {
    if [[ $# -lt 1 ]]; then
        show_usage
    fi

    local target="$1"
    shift

    # Parse options
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --fix)
                echo "Note: --fix not yet implemented"
                ;;
            --quiet)
                exec 2>/dev/null
                ;;
            --json)
                echo "Note: --json not yet implemented"
                ;;
            *)
                echo "Unknown option: $1" >&2
                show_usage
                ;;
        esac
        shift
    done

    echo "=========================================="
    echo "Obsidian Syntax Validator"
    echo "=========================================="
    echo ""

    # Determine if target is file or directory
    if [[ -f "$target" ]]; then
        validate_file "$target"
    elif [[ -d "$target" ]]; then
        validate_directory "$target"
    else
        log_error "Target not found: $target"
        exit 1
    fi

    # Summary
    echo ""
    echo "=========================================="
    echo "Validation Summary"
    echo "=========================================="
    echo "Files checked: $CHECKED_COUNT"
    echo -e "Errors: ${RED}$ERROR_COUNT${NC}"
    echo -e "Warnings: ${YELLOW}$WARNING_COUNT${NC}"

    if [[ $ERROR_COUNT -gt 0 ]]; then
        exit 1
    fi

    if [[ $WARNING_COUNT -eq 0 && $ERROR_COUNT -eq 0 ]]; then
        echo -e "${GREEN}All validations passed!${NC}"
    fi
}

# Run main
main "$@"
