#!/usr/bin/env bash
# ccfind.sh - Find and resume Claude Code sessions
#
# Usage:
#   ccfind                  # Flat search across all sessions
#   ccfind --by-tag         # Two-step: pick tag first, then session
#   ccfind --tags           # List unique tags (non-interactive)
#   ccfind --refresh        # Force cache refresh

set -euo pipefail

# Resolve paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF="$SCRIPT_DIR/ccfind.sh"
PARSE_SCRIPT="$SCRIPT_DIR/parse_sessions.sh"
PREVIEW_SCRIPT="$SCRIPT_DIR/preview.sh"

# Parse args early so --help doesn't pay KB path cost
MODE="search"
case "${1:-}" in
    --by-tag)      MODE="by_tag" ;;
    --tags)        MODE="list_tags" ;;
    --refresh)     MODE="refresh" ;;
    -h|--help)
        cat <<'EOF'
ccfind - Claude Code Session Finder

Usage: ccfind [option]

Options:
  (none)          Search all sessions interactively
  --by-tag        Pick a tag, then browse matching sessions
  --tags          List all unique tags
  --refresh       Force cache refresh
  -h, --help      Show this help

Keybindings (in fzf):
  Enter           Resume session in new tmux tab
  Ctrl-O          Open session folder in nvim (new tmux tab)
  Ctrl-Y          Copy session folder path to clipboard
  Ctrl-A          Switch to all sessions
  Ctrl-T          Switch to by-tag mode
EOF
        exit 0
        ;;
    "") ;;
    *)
        echo "Unknown option: $1" >&2
        exit 1
        ;;
esac

# Source get_kb_path
source "$SCRIPT_DIR/../../skills/common/get_kb_path.sh"
KB_PATH=$(get_kb_path) || exit 1
SESSIONS_DIR="$KB_PATH/_sessions"

if [ ! -d "$SESSIONS_DIR" ]; then
    echo "Error: Sessions directory not found: $SESSIONS_DIR" >&2
    exit 1
fi

# --- Cache ---
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/ccfind"
CACHE_FILE="$CACHE_DIR/sessions.tsv"
CACHE_TTL=300  # 5 minutes before background refresh

mkdir -p "$CACHE_DIR"

refresh_cache() {
    local tmp="$CACHE_FILE.tmp.$$"
    "$PARSE_SCRIPT" "$SESSIONS_DIR" > "$tmp" 2>/dev/null
    mv "$tmp" "$CACHE_FILE"
}

cache_age() {
    if [ ! -f "$CACHE_FILE" ]; then
        echo 999999
        return
    fi
    local now file_mtime
    now=$(date +%s)
    file_mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
    echo $(( now - file_mtime ))
}

# Stale-while-revalidate; memoized in _SESSIONS_CACHE
_SESSIONS_CACHE=""
get_sessions() {
    if [ -n "$_SESSIONS_CACHE" ]; then
        printf '%s\n' "$_SESSIONS_CACHE"
        return
    fi

    local age
    age=$(cache_age)

    if [ "$age" -ge "$CACHE_TTL" ] && [ -f "$CACHE_FILE" ]; then
        refresh_cache &
    elif [ ! -f "$CACHE_FILE" ]; then
        refresh_cache
    fi

    _SESSIONS_CACHE=$(cat "$CACHE_FILE")
    printf '%s\n' "$_SESSIONS_CACHE"
}

# Filter cached data using raw fields (tab field 5=tags)
get_unique_tags() {
    get_sessions | awk -F'\t' '$5 != "-" { split($5, a, ","); for (i in a) { gsub(/^ +| +$/, "", a[i]); if (a[i] != "") print a[i] } }' | sort -u
}

filter_by_tag() {
    local tag="$1"
    get_sessions | awk -F'\t' -v tag="$tag" '{
        split($5, a, ","); for (i in a) { gsub(/^ +| +$/, "", a[i]); if (a[i] == tag) { print; next } }
    }'
}

# --- Actions ---

resume_session() {
    local selected="$1"
    local session_id cwd
    session_id=$(printf '%s' "$selected" | cut -f2)
    cwd=$(printf '%s' "$selected" | cut -f3)

    if [ -z "$cwd" ] || [ "$cwd" = "-" ] || [ ! -d "$cwd" ]; then
        echo "Error: Working directory no longer exists: $cwd" >&2
        exit 1
    fi

    tmux new-window -c "$cwd" "claude -r '$session_id'"
}

open_session_folder() {
    local selected="$1"
    local session_path session_dir
    session_path=$(printf '%s' "$selected" | cut -f4)
    session_dir="$(dirname "$session_path")"

    if [ -d "$session_dir" ]; then
        tmux new-window -c "$session_dir" "nvim ."
    else
        echo "Session directory not found: $session_dir" >&2
        exit 1
    fi
}

copy_session_path() {
    local selected="$1"
    local session_path session_dir
    session_path=$(printf '%s' "$selected" | cut -f4)
    session_dir="$(dirname "$session_path")"
    printf '%s' "$session_dir" | pbcopy
    echo "Copied: $session_dir"
}

# --- Shared fzf navigation binds ---
FZF_NAV_BINDS=(
    --bind "ctrl-a:become($SELF)"
    --bind "ctrl-t:become($SELF --by-tag)"
)
FZF_NAV_HEADER=' ^a all  ^t by tag'

# --- Session picker via fzf ---

pick_session_from() {
    local label="${1:- ccfind }"
    local fzf_output
    fzf_output=$(fzf --ansi \
        --delimiter=$'\t' \
        --with-nth=1 \
        --preview "$PREVIEW_SCRIPT {}" \
        --preview-window='right:50%:wrap' \
        --border-label="$label" \
        --prompt='> ' \
        --header="$FZF_NAV_HEADER  Enter: resume  ^o nvim  ^y copy path" \
        "${FZF_NAV_BINDS[@]}" \
        --expect=ctrl-o,ctrl-y) || exit 0

    local key selected
    key=$(printf '%s' "$fzf_output" | head -1)
    selected=$(printf '%s' "$fzf_output" | sed -n '2p')

    [ -z "$selected" ] && exit 0

    case "$key" in
        ctrl-o) open_session_folder "$selected" ;;
        ctrl-y) copy_session_path "$selected" ;;
        *)      resume_session "$selected" ;;
    esac
}

# --- Dispatch ---

case "$MODE" in
    search)
        get_sessions | pick_session_from
        ;;
    by_tag)
        tag=$(get_unique_tags | fzf \
            --border-label=' ccfind: select tag ' \
            --prompt='tag> ' \
            --header="$FZF_NAV_HEADER" \
            "${FZF_NAV_BINDS[@]}") || exit 0
        [ -z "$tag" ] && exit 0
        filter_by_tag "$tag" | pick_session_from " ccfind: tag=$tag "
        ;;
    list_tags)
        get_unique_tags
        ;;
    refresh)
        refresh_cache
        echo "Cache refreshed."
        ;;
esac
