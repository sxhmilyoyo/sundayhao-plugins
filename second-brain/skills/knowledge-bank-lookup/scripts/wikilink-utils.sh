#!/bin/bash
# wikilink-utils.sh - WikiLink extraction and DFS traversal utilities
#
# Functions for following Obsidian WikiLinks in knowledge bank documentation
# using Depth-First Search (DFS) to ensure comprehensive coverage of related docs
#
# Usage:
#   source wikilink-utils.sh
#   extract_wikilinks "path/to/doc.md"
#   resolve_wikilink "Document Name" "$KB_PATH"
#   dfs_traverse "starting_doc.md" 0 2 "$KB_PATH" 10

# Global variable for visited tracking file (temp file)
VISITED_TRACKING_FILE=""

# Initialize visited tracking (creates temp file)
_init_visited_tracking() {
    if [ -z "$VISITED_TRACKING_FILE" ]; then
        VISITED_TRACKING_FILE=$(mktemp /tmp/wikilink_visited.XXXXXX)
    fi
}

# Extract all WikiLinks from a markdown file
# WikiLink formats supported:
#   [[Document Name]]
#   [[Document Name|Display Text]]
#   [[Document Name#Section]]
#
# Args:
#   $1: Path to markdown file
# Returns:
#   List of WikiLink names (one per line), sorted and unique
extract_wikilinks() {
    local file="$1"

    if [ ! -f "$file" ]; then
        echo "ERROR: File not found: $file" >&2
        return 1
    fi

    # Extract WikiLinks, remove [[]], handle aliases and sections
    # `|| true` ensures zero exit when file has no WikiLinks
    # (grep returns 1 on no match, which breaks callers using set -e)
    grep -o '\[\[[^]]*\]\]' "$file" 2>/dev/null | \
        sed 's/\[\[\([^]|#]*\).*/\1/' | \
        grep -v '^[[:space:]]*$' | \
        sort -u || true
}

# Resolve a WikiLink name to its actual file path in the knowledge bank
# Search priority order:
#   1. concepts/ subdirectories
#   2. components/ subdirectories
#   3. best-practices/ subdirectories
#   4. _index/ directory (MOCs)
#   5. reflections/ directory
#   6. Any other location
#
# Args:
#   $1: WikiLink name (without [[]])
#   $2: Knowledge bank base path
# Returns:
#   Absolute path to the markdown file, or empty if not found
resolve_wikilink() {
    local link_name="$1"
    local kb_path="$2"

    if [ -z "$link_name" ] || [ -z "$kb_path" ]; then
        return 1
    fi

    # Clean up link name (trim whitespace)
    link_name=$(echo "$link_name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    local filename="${link_name}.md"

    # Priority 1: Search in concepts/ directories
    local found=$(find "$kb_path/projects" -type f -path "*/concepts/$filename" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi

    # Priority 2: Search in components/ directories
    found=$(find "$kb_path/projects" -type f -path "*/components/$filename" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi

    # Priority 3: Search in best-practices/ directories
    found=$(find "$kb_path/projects" -type f -path "*/best-practices/$filename" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi

    # Priority 4: Search in _index/ (MOCs)
    found=$(find "$kb_path/_index" -type f -name "$filename" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi

    # Priority 5: Search in reflections/
    found=$(find "$kb_path/reflections" -type f -name "$filename" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi

    # Priority 6: Search anywhere in knowledge bank
    found=$(find "$kb_path" -type f -name "$filename" 2>/dev/null | head -1)
    if [ -n "$found" ]; then
        echo "$found"
        return 0
    fi

    # Not found
    return 1
}

# Calculate relevance score for a WikiLink based on query context
# Higher scores indicate more relevant links to follow
#
# Args:
#   $1: WikiLink name
#   $2: Query keywords (space-separated)
# Returns:
#   Numeric score (higher = more relevant)
score_wikilink_relevance() {
    local link="$1"
    local keywords="$2"
    local score=0
    local link_lower=$(echo "$link" | tr '[:upper:]' '[:lower:]')

    # Exact keyword match: +10
    for keyword in $keywords; do
        local keyword_lower=$(echo "$keyword" | tr '[:upper:]' '[:lower:]')
        if [[ "$link_lower" == *"$keyword_lower"* ]]; then
            score=$((score + 10))
        fi
    done

    # Pattern/Principle docs: +5
    if [[ "$link_lower" == *"pattern"* ]] || [[ "$link_lower" == *"principle"* ]]; then
        score=$((score + 5))
    fi

    # Component docs: +3
    if [[ "$link_lower" == *"plugin"* ]] || [[ "$link_lower" == *"provider"* ]] || \
       [[ "$link_lower" == *"builder"* ]] || [[ "$link_lower" == *"extractor"* ]]; then
        score=$((score + 3))
    fi

    # Best practice docs: +4
    if [[ "$link_lower" == *"best practice"* ]] || [[ "$link_lower" == *"guideline"* ]]; then
        score=$((score + 4))
    fi

    echo "$score"
}

# Prioritize WikiLinks by relevance to query
# Returns links sorted by relevance score (highest first)
#
# Args:
#   $1: Newline-separated list of WikiLink names
#   $2: Query keywords (space-separated)
# Returns:
#   Sorted list of WikiLinks (one per line)
prioritize_wikilinks() {
    local links="$1"
    local keywords="$2"
    local scored_links=""

    while IFS= read -r link; do
        [ -z "$link" ] && continue
        local score=$(score_wikilink_relevance "$link" "$keywords")
        scored_links="${scored_links}${score}|${link}\n"
    done <<< "$links"

    # Sort by score (descending), then extract link names
    echo -e "$scored_links" | grep -v '^$' | sort -t'|' -k1 -rn | cut -d'|' -f2
}

# Depth-First Search traversal of WikiLink graph
# Follows WikiLinks recursively up to max_depth, tracking visited documents
#
# Args:
#   $1: Starting document path
#   $2: Current depth (start with 0)
#   $3: Maximum depth to traverse
#   $4: Knowledge bank base path
#   $5: Maximum total documents to visit (optional, default 50)
#   $6: Query keywords for prioritization (optional)
# Returns:
#   Prints traversal results to stdout in format: DEPTH:PATH
#   Updates visited tracking file
dfs_traverse() {
    local doc_path="$1"
    local depth="$2"
    local max_depth="$3"
    local kb_path="$4"
    local max_docs="${5:-50}"
    local keywords="${6:-}"

    # Initialize visited tracking
    _init_visited_tracking

    # Check if we've reached depth limit
    if [ "$depth" -gt "$max_depth" ]; then
        return 0
    fi

    # Check if we've reached document limit
    local visited_count=$(wc -l < "$VISITED_TRACKING_FILE" 2>/dev/null || echo 0)
    if [ "$visited_count" -ge "$max_docs" ]; then
        return 0
    fi

    # Check if already visited (prevent cycles)
    if grep -Fxq "$doc_path" "$VISITED_TRACKING_FILE" 2>/dev/null; then
        return 0
    fi

    # Check if file exists
    if [ ! -f "$doc_path" ]; then
        return 1
    fi

    # Mark as visited
    echo "$doc_path" >> "$VISITED_TRACKING_FILE"

    # Record this visit
    echo "${depth}:${doc_path}"

    # Extract WikiLinks from current document
    local links=$(extract_wikilinks "$doc_path")

    # If no links found, return
    if [ -z "$links" ]; then
        return 0
    fi

    # Prioritize links if keywords provided
    if [ -n "$keywords" ]; then
        links=$(prioritize_wikilinks "$links" "$keywords")
    fi

    # Recursively traverse each link
    local next_depth=$((depth + 1))
    while IFS= read -r link; do
        [ -z "$link" ] && continue

        # Resolve WikiLink to file path
        local resolved_path=$(resolve_wikilink "$link" "$kb_path")

        if [ -n "$resolved_path" ]; then
            # Recursive DFS call
            dfs_traverse "$resolved_path" "$next_depth" "$max_depth" "$kb_path" "$max_docs" "$keywords"
        fi
    done <<< "$links"
}

# Reset the global visited tracking
# Call this before starting a new DFS traversal
reset_visited() {
    _init_visited_tracking
    > "$VISITED_TRACKING_FILE"  # Truncate file
}

# Get count of visited documents
get_visited_count() {
    _init_visited_tracking
    wc -l < "$VISITED_TRACKING_FILE" 2>/dev/null || echo 0
}

# Check if a document has been visited
# Args:
#   $1: Document path
# Returns:
#   0 if visited, 1 if not visited
is_visited() {
    local doc_path="$1"
    _init_visited_tracking
    grep -Fxq "$doc_path" "$VISITED_TRACKING_FILE" 2>/dev/null
}

# Cleanup visited tracking file
# Call this when done with WikiLink operations
cleanup_visited() {
    if [ -n "$VISITED_TRACKING_FILE" ] && [ -f "$VISITED_TRACKING_FILE" ]; then
        rm -f "$VISITED_TRACKING_FILE"
        VISITED_TRACKING_FILE=""
    fi
}

# Extract WikiLinks and show their resolved paths
# Useful for debugging and understanding link structure
#
# Args:
#   $1: Document path
#   $2: Knowledge bank base path
# Returns:
#   List of "LINK_NAME -> RESOLVED_PATH" (or "NOT_FOUND")
show_wikilink_paths() {
    local doc_path="$1"
    local kb_path="$2"

    local links=$(extract_wikilinks "$doc_path")

    while IFS= read -r link; do
        [ -z "$link" ] && continue
        local resolved=$(resolve_wikilink "$link" "$kb_path")
        if [ -n "$resolved" ]; then
            echo "$link -> $resolved"
        else
            echo "$link -> NOT_FOUND"
        fi
    done <<< "$links"
}

# Export functions for use in other scripts
export -f extract_wikilinks
export -f resolve_wikilink
export -f score_wikilink_relevance
export -f prioritize_wikilinks
export -f dfs_traverse
export -f reset_visited
export -f get_visited_count
export -f is_visited
export -f cleanup_visited
export -f show_wikilink_paths
