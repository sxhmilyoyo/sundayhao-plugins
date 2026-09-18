#!/bin/bash
# validate_cross_references.sh - Validate cross-references in knowledge bank documents
# Usage: ./validate_cross_references.sh <document.md> [knowledge-bank-path]

set -euo pipefail

# Get script directory for relative path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$SCRIPT_DIR/../../common"

# Require common utilities - no fallback
if [ ! -f "$COMMON_DIR/get_kb_path.sh" ]; then
    echo "ERROR: Common utilities not found at $COMMON_DIR/get_kb_path.sh" >&2
    echo "Please ensure the session-recap skill is properly installed with common utilities." >&2
    exit 1
fi

source "$COMMON_DIR/get_kb_path.sh"

# Configuration
# Allow KB_PATH override via second argument, otherwise use discovery
if [ -n "${2:-}" ]; then
    KB_PATH="$2"
else
    KB_PATH=$(get_kb_path)
    # Validate KB_PATH exists
    if ! validate_kb_path "$KB_PATH"; then
        exit 1
    fi
fi

DOCUMENT="${1:-}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
TOTAL_LINKS=0
BROKEN_LINKS=0
VALID_LINKS=0

# Help message
if [ "$#" -lt 1 ] || [ "$DOCUMENT" = "--help" ] || [ "$DOCUMENT" = "-h" ]; then
    echo "Usage: $0 <document.md> [knowledge-bank-path]"
    echo ""
    echo "Validates WikiLinks in knowledge bank documents:"
    echo "  - Checks all [[WikiLink]] references resolve to actual files"
    echo "  - Reports broken links with suggestions"
    echo "  - Verifies bidirectional linking (if applicable)"
    echo ""
    echo "Arguments:"
    echo "  document.md         Path to document to validate"
    echo "  knowledge-bank-path Optional path to knowledge bank (default: $KB_PATH)"
    echo ""
    echo "Exit codes:"
    echo "  0 - All WikiLinks valid"
    echo "  1 - Broken WikiLinks found"
    echo ""
    echo "Examples:"
    echo "  $0 /path/to/document.md"
    echo "  $0 document.md /custom/knowledge-bank/path"
    exit 0
fi

# Validate inputs
if [ ! -f "$DOCUMENT" ]; then
    echo -e "${RED}❌ ERROR: Document not found: $DOCUMENT${NC}"
    exit 1
fi

if [ ! -d "$KB_PATH" ]; then
    echo -e "${RED}❌ ERROR: Knowledge bank not found: $KB_PATH${NC}"
    exit 1
fi

echo "🔍 Validating cross-references in: $(basename "$DOCUMENT")"
echo "📚 Knowledge bank: $KB_PATH"
echo ""

# Extract all WikiLinks from document
WIKILINKS=$(sed '/^```/,/^```/d' "$DOCUMENT" | sed 's/`[^`]*`//g' | grep -o '\[\[[^]]*\]\]' | sed 's/\[\[\(.*\)\]\]/\1/' | sort -u || true)

if [ -z "$WIKILINKS" ]; then
    echo -e "${YELLOW}⚠️  WARNING: No WikiLinks found in document${NC}"
    exit 0
fi

# Count total links
TOTAL_LINKS=$(echo "$WIKILINKS" | wc -l | tr -d ' ')
echo "Found $TOTAL_LINKS unique WikiLinks to validate"
echo ""

# Function to find file by title
find_file_by_title() {
    local title="$1"
    local search_results

    # Search for markdown files with matching title in frontmatter
    search_results=$(find "$KB_PATH" -type f -name "*.md" -exec grep -l "^title: $title$" {} \; 2>/dev/null || true)

    if [ -n "$search_results" ]; then
        echo "$search_results"
        return 0
    fi

    # Fallback: search for files with matching name
    search_results=$(find "$KB_PATH" -type f -name "$title.md" 2>/dev/null || true)

    if [ -n "$search_results" ]; then
        echo "$search_results"
        return 0
    fi

    return 1
}

# Validate each WikiLink
while IFS= read -r link; do
    if [ -z "$link" ]; then
        continue
    fi

    # Try to find the referenced file
    if target_file=$(find_file_by_title "$link"); then
        echo -e "${GREEN}✅ VALID:${NC} [[$link]] → $(basename "$target_file")"
        ((++VALID_LINKS))
    else
        echo -e "${RED}❌ BROKEN:${NC} [[$link]] - File not found"
        ((++BROKEN_LINKS))

        # Try to suggest similar files
        suggestions=$(find "$KB_PATH" -type f -name "*.md" -exec basename {} .md \; | grep -i "$(echo "$link" | sed 's/ /-/g')" | head -3 || true)
        if [ -n "$suggestions" ]; then
            echo -e "${YELLOW}   💡 Suggestions:${NC}"
            echo "$suggestions" | while read -r suggestion; do
                echo "      - [[$suggestion]]"
            done
        fi
    fi
done <<< "$WIKILINKS"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📊 Validation Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total WikiLinks:  $TOTAL_LINKS"
echo -e "Valid Links:      ${GREEN}$VALID_LINKS${NC}"

if [ "$BROKEN_LINKS" -gt 0 ]; then
    echo -e "Broken Links:     ${RED}$BROKEN_LINKS${NC}"
    echo ""
    echo -e "${RED}❌ VALIDATION FAILED${NC}: Fix broken WikiLinks before proceeding"
    exit 1
else
    echo -e "Broken Links:     ${GREEN}0${NC}"
    echo ""
    echo -e "${GREEN}✅ VALIDATION PASSED${NC}: All WikiLinks resolve correctly"
    exit 0
fi
