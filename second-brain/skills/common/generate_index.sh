#!/bin/bash
# generate_index.sh - Auto-generate _meta/index.md content catalog
#
# Walks KB directories, reads frontmatter from each .md file,
# and generates a unified index organized by project and type.
#
# Usage:
#   ./generate_index.sh                  # Uses KB path from config
#   ./generate_index.sh /path/to/kb      # Explicit KB path
#
# Can also be sourced for the generate_index function:
#   source generate_index.sh
#   generate_index "$KB_PATH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get_kb_path.sh"
source "$SCRIPT_DIR/obsidian_helpers.sh"

generate_index() {
    local kb_path="${1:-}"
    if [ -z "$kb_path" ]; then
        kb_path=$(get_kb_path) || return 1
    fi

    local meta_dir="$kb_path/_meta"
    local index_file="$meta_dir/index.md"
    mkdir -p "$meta_dir"

    local total=0
    local output=""

    # --- Projects ---
    local projects_dir="$kb_path/projects"
    local project_stats=""
    if [ -d "$projects_dir" ]; then
        for project_dir in "$projects_dir"/*/; do
            [ -d "$project_dir" ] || continue
            local project_name
            project_name=$(basename "$project_dir")
            local project_output=""
            local project_count=0

            for category_dir in "$project_dir"*/; do
                [ -d "$category_dir" ] || continue
                local category
                category=$(basename "$category_dir")
                local category_entries=""

                while IFS= read -r -d '' file; do
                    local title
                    title=$(read_frontmatter_prop "$file" "title")
                    [ -z "$title" ] && title=$(basename "$file" .md)
                    category_entries+="- [[${title}]]"$'\n'
                    project_count=$((project_count + 1))
                done < <(find "$category_dir" -maxdepth 1 -name "*.md" -print0 | sort -z)

                if [ -n "$category_entries" ]; then
                    project_output+="### ${category}"$'\n\n'
                    project_output+="$category_entries"$'\n'
                fi
            done

            if [ "$project_count" -gt 0 ]; then
                output+="## ${project_name} (${project_count})"$'\n\n'
                output+="$project_output"
                total=$((total + project_count))
                project_stats+="| ${project_name} | ${project_count} |"$'\n'
            fi
        done
    fi

    # --- Reflections ---
    local reflections_dir="$kb_path/reflections"
    if [ -d "$reflections_dir" ]; then
        local ref_output=""
        local ref_count=0

        for category_dir in "$reflections_dir"/*/; do
            [ -d "$category_dir" ] || continue
            local category
            category=$(basename "$category_dir")
            local category_entries=""

            while IFS= read -r -d '' file; do
                local title
                title=$(read_frontmatter_prop "$file" "title")
                [ -z "$title" ] && title=$(basename "$file" .md)
                category_entries+="- [[${title}]]"$'\n'
                ref_count=$((ref_count + 1))
            done < <(find "$category_dir" -maxdepth 1 -name "*.md" -print0 | sort -z)

            if [ -n "$category_entries" ]; then
                ref_output+="### ${category}"$'\n\n'
                ref_output+="$category_entries"$'\n'
            fi
        done

        if [ "$ref_count" -gt 0 ]; then
            output+="## Reflections (${ref_count})"$'\n\n'
            output+="$ref_output"
            total=$((total + ref_count))
        fi
    fi

    # --- Top-level directories: rules, manual, best-practices ---
    for dir_name in rules manual best-practices; do
        local dir="$kb_path/$dir_name"
        [ -d "$dir" ] || continue
        local dir_entries=""
        local dir_count=0

        while IFS= read -r -d '' file; do
            local title
            title=$(read_frontmatter_prop "$file" "title")
            [ -z "$title" ] && title=$(basename "$file" .md)
            dir_entries+="- [[${title}]]"$'\n'
            dir_count=$((dir_count + 1))
        done < <(find "$dir" -name "*.md" -not -path "*/archive/*" -print0 | sort -z)

        if [ "$dir_count" -gt 0 ]; then
            output+="## ${dir_name} (${dir_count})"$'\n\n'
            output+="$dir_entries"$'\n'
            total=$((total + dir_count))
        fi
    done

    # project_stats was accumulated during the Projects loop above

    # --- Write index file ---
    local timestamp
    timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S')

    cat > "$index_file" << EOF
---
title: Knowledge Bank Index
type: index
generated: ${timestamp}
total_documents: ${total}
---

# Knowledge Bank Index

> Auto-generated catalog of all knowledge bank documents.
> Last updated: ${timestamp} | Total: ${total} documents

| Project | Documents |
|---------|-----------|
${project_stats}

${output}
EOF

    echo "Generated $index_file (${total} documents)" >&2
    return 0
}

export -f generate_index

# Direct execution
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    generate_index "$@"
fi
