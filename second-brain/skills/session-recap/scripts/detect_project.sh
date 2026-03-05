#!/bin/bash
# Detect which project based on modified files
# Returns the project name if found, or "unknown" if not detected
#
# Uses dynamic discovery from knowledge bank - no hardcoded project names

# Get script directory for relative path resolution
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COMMON_DIR="$SCRIPT_DIR/../common"

# Source common utilities
if [ -f "$COMMON_DIR/get_kb_path.sh" ]; then
    source "$COMMON_DIR/get_kb_path.sh"
fi

show_usage() {
    echo "Usage: $0 <file-path> [file-path...]" >&2
    echo "Detects project from file paths using dynamic discovery" >&2
    echo "" >&2
    echo "Projects are auto-discovered from your knowledge bank." >&2
    echo "The script matches file paths against project directory patterns." >&2
    echo "" >&2
    echo "Returns:" >&2
    echo "  <project-name>   if a matching project is found" >&2
    echo "  unknown          if project cannot be determined" >&2
    echo "" >&2

    # Show available projects if knowledge bank is configured
    if type discover_projects &>/dev/null; then
        local projects=$(discover_projects 2>/dev/null)
        if [ -n "$projects" ]; then
            echo "Available projects in your knowledge bank:" >&2
            echo "$projects" | sed 's/^/  - /' >&2
        fi
    fi

    exit 1
}

if [ $# -eq 0 ]; then
    show_usage
fi

# Try to discover projects from knowledge bank
AVAILABLE_PROJECTS=""
if type discover_projects &>/dev/null; then
    AVAILABLE_PROJECTS=$(discover_projects 2>/dev/null)
fi

# Check each file path for project indicators
for FILE in "$@"; do
    # Normalize the file path for matching
    NORMALIZED_FILE="$FILE"

    # If we have discovered projects, try to match against them
    if [ -n "$AVAILABLE_PROJECTS" ]; then
        while IFS= read -r project; do
            [ -z "$project" ] && continue

            # Match project name in the file path
            # This handles various path patterns like:
            #   /path/to/project-name/...
            #   /path/to/Project-Name/...
            #   /home/user/workspace/ProjectName/...
            if [[ "$NORMALIZED_FILE" == *"/$project/"* ]] || \
               [[ "$NORMALIZED_FILE" == *"/$project" ]] || \
               [[ "$NORMALIZED_FILE" =~ (^|/)$project(/|$) ]]; then
                echo "$project"
                exit 0
            fi

            # Also try case-insensitive match
            local lower_file=$(echo "$NORMALIZED_FILE" | tr '[:upper:]' '[:lower:]')
            local lower_project=$(echo "$project" | tr '[:upper:]' '[:lower:]')
            if [[ "$lower_file" == *"/$lower_project/"* ]] || \
               [[ "$lower_file" == *"/$lower_project" ]]; then
                echo "$project"
                exit 0
            fi
        done <<< "$AVAILABLE_PROJECTS"
    fi

    # Fallback: Common patterns for project detection
    # These are generic patterns that work without knowledge bank config

    # Check for .claude directory (Claude Code work)
    if [[ "$FILE" == *"/.claude/"* ]] || [[ "$FILE" == *"/claude-code/"* ]]; then
        # Check if "cc" is a valid project
        if [ -n "$AVAILABLE_PROJECTS" ] && echo "$AVAILABLE_PROJECTS" | grep -q "^cc$"; then
            echo "cc"
            exit 0
        fi
    fi
done

# If no match found
echo "unknown"
exit 1
