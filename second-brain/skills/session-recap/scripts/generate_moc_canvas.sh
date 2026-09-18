#!/bin/bash
# generate_moc_canvas.sh - Generate JSON Canvas from MOC WikiLinks
#
# Usage: generate_moc_canvas.sh <moc-file.md> [output.canvas]
#
# Parses WikiLinks from a Map of Content (MOC) file and generates
# a JSON Canvas file for visual knowledge navigation in Obsidian.
#
# Node colors:
#   - Concepts: Cyan (5)
#   - Components: Green (4)
#   - Best Practices: Purple (6)
#   - Daily Logs: Orange (2)
#   - Default: Gray (0)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Node dimensions
NODE_WIDTH=300
NODE_HEIGHT=80
GROUP_PADDING=50

# Grid spacing
HORIZONTAL_SPACING=350
VERTICAL_SPACING=120

# Color mapping (Obsidian canvas color codes)
declare -A COLORS=(
    ["concept"]="5"      # Cyan
    ["component"]="4"    # Green
    ["best-practice"]="6" # Purple
    ["daily-log"]="2"    # Orange
    ["moc"]="1"          # Red (central hub)
    ["default"]="0"      # Gray
)

# ============================================================================
# Functions
# ============================================================================

show_usage() {
    echo "Usage: $0 <moc-file.md> [output.canvas]"
    echo ""
    echo "Arguments:"
    echo "  moc-file.md    Path to the Map of Content markdown file"
    echo "  output.canvas  Output canvas file (default: <moc-name>.canvas)"
    echo ""
    echo "Example:"
    echo "  $0 /path/to/MyProject-MOC.md"
    echo "  $0 /path/to/MyProject-MOC.md /tmp/MyProject-knowledge.canvas"
    exit 1
}

# Extract WikiLinks from a markdown file
# Returns: list of link targets (one per line)
extract_wikilinks() {
    local file="$1"
    grep -oE '\[\[[^]]+\]\]' "$file" 2>/dev/null | \
        sed 's/\[\[//g; s/\]\]//g' | \
        sed 's/|.*//g' | \
        sed 's/#.*//g' | \
        sort -u
}

# Determine document type from path or content
get_doc_type() {
    local link="$1"
    local base_path="${2:-}"

    # Check path patterns
    if [[ "$link" =~ concept ]]; then
        echo "concept"
    elif [[ "$link" =~ component ]]; then
        echo "component"
    elif [[ "$link" =~ best-practice ]]; then
        echo "best-practice"
    elif [[ "$link" =~ daily-log ]]; then
        echo "daily-log"
    elif [[ "$link" =~ MOC ]]; then
        echo "moc"
    else
        echo "default"
    fi
}

# Generate a unique ID
generate_id() {
    echo "node-$(date +%s%N)-$RANDOM"
}

# JSON escape a string
json_escape() {
    local str="$1"
    str="${str//\\/\\\\}"
    str="${str//\"/\\\"}"
    str="${str//$'\n'/\\n}"
    str="${str//$'\t'/\\t}"
    echo "$str"
}

# ============================================================================
# Main
# ============================================================================

main() {
    # Validate arguments
    if [[ $# -lt 1 ]]; then
        show_usage
    fi

    local moc_file="$1"
    local output_file="${2:-}"

    # Validate MOC file exists
    if [[ ! -f "$moc_file" ]]; then
        echo "Error: MOC file not found: $moc_file" >&2
        exit 1
    fi

    # Default output filename
    if [[ -z "$output_file" ]]; then
        local basename=$(basename "$moc_file" .md)
        output_file="${moc_file%/*}/${basename}.canvas"
    fi

    # Get MOC directory for relative path resolution
    local moc_dir=$(dirname "$moc_file")
    local moc_name=$(basename "$moc_file" .md)

    echo "Generating canvas from: $moc_file"
    echo "Output: $output_file"

    # Extract WikiLinks
    local links=$(extract_wikilinks "$moc_file")
    local link_count=$(echo "$links" | grep -c . || echo 0)
    echo "Found $link_count WikiLinks"

    # Group links by type
    declare -A grouped_links
    while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        local doc_type=$(get_doc_type "$link" "$moc_dir")
        grouped_links["$doc_type"]+="$link"$'\n'
    done <<< "$links"

    # Calculate layout
    local nodes_json=""
    local edges_json=""
    local groups_json=""
    local node_ids=()

    # Central MOC node
    local moc_id=$(generate_id)
    local moc_x=0
    local moc_y=0
    nodes_json+="{\"id\":\"$moc_id\",\"type\":\"text\",\"x\":$moc_x,\"y\":$moc_y,\"width\":$NODE_WIDTH,\"height\":$NODE_HEIGHT,\"color\":\"${COLORS[moc]}\",\"text\":\"# $(json_escape "$moc_name")\"}"

    # Layout each group
    local group_index=0
    local current_y=$((moc_y + VERTICAL_SPACING * 2))

    for doc_type in "concept" "component" "best-practice" "daily-log" "default"; do
        local type_links="${grouped_links[$doc_type]:-}"
        [[ -z "$type_links" ]] && continue

        local group_id="group-$doc_type"
        local group_x=$((group_index * (NODE_WIDTH + HORIZONTAL_SPACING) - (NODE_WIDTH / 2)))
        local group_y=$current_y
        local node_index=0
        local group_nodes=""

        echo "Processing $doc_type links..."

        while IFS= read -r link; do
            [[ -z "$link" ]] && continue

            local node_id=$(generate_id)
            local node_x=$group_x
            local node_y=$((group_y + GROUP_PADDING + (node_index * VERTICAL_SPACING)))
            local color="${COLORS[$doc_type]:-${COLORS[default]}}"

            # Add comma separator
            [[ -n "$nodes_json" ]] && nodes_json+=","

            # Create file node
            nodes_json+="{\"id\":\"$node_id\",\"type\":\"text\",\"x\":$node_x,\"y\":$node_y,\"width\":$NODE_WIDTH,\"height\":$NODE_HEIGHT,\"color\":\"$color\",\"text\":\"$(json_escape "$link")\"}"

            # Create edge from MOC to node
            [[ -n "$edges_json" ]] && edges_json+=","
            edges_json+="{\"id\":\"edge-$node_id\",\"fromNode\":\"$moc_id\",\"toNode\":\"$node_id\",\"fromSide\":\"bottom\",\"toSide\":\"top\"}"

            node_ids+=("$node_id")
            group_nodes+="\"$node_id\","
            ((++node_index))
        done <<< "$type_links"

        # Create group
        if [[ $node_index -gt 0 ]]; then
            local group_height=$((GROUP_PADDING * 2 + (node_index * VERTICAL_SPACING)))
            local group_label="${doc_type^}s"  # Capitalize first letter + 's'

            [[ -n "$groups_json" ]] && groups_json+=","
            groups_json+="{\"id\":\"$group_id\",\"type\":\"group\",\"x\":$((group_x - GROUP_PADDING)),\"y\":$((group_y)),\"width\":$((NODE_WIDTH + GROUP_PADDING * 2)),\"height\":$group_height,\"label\":\"$group_label\"}"
        fi

        ((++group_index))
    done

    # Build final JSON
    local canvas_json=$(cat <<EOF
{
  "nodes": [$nodes_json],
  "edges": [$edges_json]
}
EOF
)

    # Write output
    echo "$canvas_json" > "$output_file"
    echo "Canvas generated successfully: $output_file"
    echo "  - Nodes: $((${#node_ids[@]} + 1))"
    echo "  - Edges: ${#node_ids[@]}"
}

# Run main
main "$@"
