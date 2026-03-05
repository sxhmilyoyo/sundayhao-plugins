#!/bin/bash
# detect_project.sh - Detect project name from working directory
#
# Usage:
#   source detect_project.sh
#   PROJECT=$(detect_project "/path/to/cwd")

detect_project() {
    local cwd="$1"
    basename "$cwd"
}

export -f detect_project
