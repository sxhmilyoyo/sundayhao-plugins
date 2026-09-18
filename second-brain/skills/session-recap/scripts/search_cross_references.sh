#!/bin/bash
# Search for related documentation across all knowledge bank categories
# This helps discover cross-references before writing documentation
# Uses dynamic project and category discovery - no hardcoded project names

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
KNOWLEDGE_BASE=$(get_kb_path)

# Validate KB_PATH exists
if ! validate_kb_path "$KNOWLEDGE_BASE"; then
    exit 1
fi

show_usage() {
    echo "Usage: $0 <search-keyword> [project]"
    echo "Searches for related documentation across all categories"
    echo ""
    echo "Arguments:"
    echo "  search-keyword  Keyword to search for"
    echo "  project         Optional: Specific project to search"
    echo "                  If omitted, searches all projects"
    echo ""

    # Show available projects dynamically
    local available_projects=$(discover_projects "$KNOWLEDGE_BASE" 2>/dev/null)
    if [ -n "$available_projects" ]; then
        echo "Available projects:"
        echo "$available_projects" | sed 's/^/  - /'
    else
        echo "No projects found in knowledge bank."
        echo "Create project directories under: $KNOWLEDGE_BASE/projects/"
    fi

    exit 1
}

if [ $# -eq 0 ]; then
    show_usage
fi

KEYWORD="$1"
SPECIFIC_PROJECT="$2"

# Function to search and format results
search_category() {
    local project=$1
    local category=$2
    local emoji=$3
    local path="$KNOWLEDGE_BASE/projects/$project/$category"

    if [ -d "$path" ]; then
        local results=$(grep -rl "$KEYWORD" "$path/" 2>/dev/null | sed 's|.*/||' | head -5 | sed 's/^/  - [[/' | sed 's/\.md$/]]/')
        if [ -n "$results" ]; then
            echo "$emoji $category (projects/$project/$category/):"
            echo "$results"
            echo ""
            return 0
        fi
    fi
    return 1
}

# Track if we found anything
TOTAL_FOUND=0

# Discover projects dynamically
if [ -z "$SPECIFIC_PROJECT" ]; then
    mapfile -t PROJECTS < <(discover_projects "$KNOWLEDGE_BASE")
    if [ ${#PROJECTS[@]} -eq 0 ]; then
        echo "No projects found in knowledge bank." >&2
        echo "Create project directories under: $KNOWLEDGE_BASE/projects/" >&2
        exit 1
    fi
    echo "=== Cross-Reference Discovery (All Projects) for: '$KEYWORD' ==="
else
    # Validate the specified project exists
    if ! project_exists "$SPECIFIC_PROJECT" "$KNOWLEDGE_BASE"; then
        echo "ERROR: Project not found: $SPECIFIC_PROJECT" >&2
        echo "" >&2
        echo "Available projects:" >&2
        discover_projects "$KNOWLEDGE_BASE" | sed 's/^/  - /' >&2
        exit 1
    fi
    PROJECTS=("$SPECIFIC_PROJECT")
    echo "=== Cross-Reference Discovery ($SPECIFIC_PROJECT) for: '$KEYWORD' ==="
fi
echo ""

# Category emoji mapping for common categories
declare -A CATEGORY_EMOJIS=(
    ["concepts"]="📚"
    ["components"]="⚙️"
    ["best-practices"]="✨"
    ["daily"]="📅"
    ["performance"]="⚡"
    ["operation"]="🔧"
    ["plugins"]="🔌"
    ["rules"]="📋"
    ["reflections"]="💭"
    ["architecture"]="🏗️"
    ["debugging"]="🐛"
    ["testing"]="🧪"
)

# Default emoji for unknown categories
DEFAULT_EMOJI="📁"

# Get emoji for a category (with fallback)
get_category_emoji() {
    local category="$1"
    echo "${CATEGORY_EMOJIS[$category]:-$DEFAULT_EMOJI}"
}

# Search each project
for PROJECT in "${PROJECTS[@]}"; do
    PROJECT_FOUND=0
    PROJECT_PATH="$KNOWLEDGE_BASE/projects/$PROJECT"

    # Only show project header if searching multiple projects
    if [ ${#PROJECTS[@]} -gt 1 ]; then
        echo "━━━ Project: $PROJECT ━━━"
    fi

    # Discover categories dynamically for this project
    while IFS= read -r category; do
        [ -z "$category" ] && continue

        emoji=$(get_category_emoji "$category")

        if search_category "$PROJECT" "$category" "$emoji"; then
            ((PROJECT_FOUND++))
            ((TOTAL_FOUND++))
        fi
    done < <(discover_categories "$PROJECT_PATH")

    if [ $PROJECT_FOUND -eq 0 ] && [ ${#PROJECTS[@]} -gt 1 ]; then
        echo "  (No matches found in $PROJECT)"
        echo ""
    fi
done

if [ $TOTAL_FOUND -eq 0 ]; then
    echo "❌ No matches found across any projects"
    echo ""
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "💡 Tip: Use these WikiLinks in your documentation to ensure rich cross-referencing"
echo "   Target: 10-15 total cross-references distributed across categories"
echo ""

# Show available projects dynamically
available=$(discover_projects "$KNOWLEDGE_BASE" 2>/dev/null | tr '\n' ', ' | sed 's/,$//')
if [ -n "$available" ]; then
    echo "📖 Projects in knowledge bank: $available"
fi
