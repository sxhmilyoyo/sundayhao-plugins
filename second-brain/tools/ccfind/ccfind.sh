#!/usr/bin/env bash
# ccfind.sh - Find and resume Claude Code sessions
#
# Usage:
#   ccfind                  # Flat search across all sessions
#   ccfind --by-name        # Show only named sessions
#   ccfind --by-tag         # Two-step: pick tag first, then session
#   ccfind --not-recapped  # Sessions still waiting on a recap, or whose recap failed
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
    --by-name)     MODE="by_name" ;;
    --by-tag)      MODE="by_tag" ;;
    --not-recapped) MODE="not_recapped" ;;
    --tags)        MODE="list_tags" ;;
    --refresh)     MODE="refresh" ;;
    --refresh-and-search) MODE="refresh_and_search" ;;
    -h|--help)
        cat <<'EOF'
ccfind - Claude Code Session Finder

Usage: ccfind [option]

Options:
  (none)          Search all sessions interactively
  --by-name       Show only named sessions (have session_name)
  --by-tag        Pick a tag, then browse matching sessions
  --not-recapped  Sessions with no recap yet, or whose recap failed
  --tags          List all unique tags
  --refresh       Force cache refresh
  -h, --help      Show this help

Keybindings (in fzf):
  Enter           Resume session alongside (herdr pane right / tmux window)
  Ctrl-O          Open session folder in nvim, alongside
  Ctrl-Y          Copy session folder path to clipboard
  Ctrl-A          Switch to all sessions
  Ctrl-N          Switch to by-name mode (named sessions only)
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
# Fields parse_sessions.sh emits. A cache with a different count was written by another
# version and is refreshed synchronously rather than served to filters that read by index.
CACHE_FIELDS=7

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
    # Branch on the platform rather than chaining the two forms with ||, the way
    # kb-lint already does. A chain relies on the wrong-platform binary failing
    # silently, and GNU stat given -f does the opposite: -f means --file-system there,
    # so it prints a filesystem block on stdout *and* exits 1, the fallback appends the
    # real epoch to that, and the arithmetic below dies on `File` under set -u.
    if [[ "$OSTYPE" == darwin* ]]; then
        file_mtime=$(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0)
    else
        file_mtime=$(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)
    fi
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

    # A cache written by an older version has fewer fields than the filters now read,
    # and there is no version stamp in the file to check. The field count is the check:
    # refresh synchronously rather than serving a row shape the filters cannot match.
    # Without this the first --not-recapped after an upgrade tests a seventh field that
    # is not there, matches nothing, and reports an empty backlog as though every
    # session had been recapped. Stale-while-revalidate is the wrong trade when the
    # staleness is structural rather than just old.
    if [ -f "$CACHE_FILE" ] \
       && [ "$(head -1 "$CACHE_FILE" 2>/dev/null | awk -F'\t' '{print NF}')" != "$CACHE_FIELDS" ]; then
        refresh_cache
    elif [ "$age" -ge "$CACHE_TTL" ] && [ -f "$CACHE_FILE" ]; then
        refresh_cache &
    elif [ ! -f "$CACHE_FILE" ]; then
        refresh_cache
    fi

    _SESSIONS_CACHE=$(cat "$CACHE_FILE")
    printf '%s\n' "$_SESSIONS_CACHE"
}

# Filter cached data using raw fields (tab field 5=tags, 6=session_name, 7=recap_status)
get_unique_tags() {
    get_sessions | awk -F'\t' '$5 != "-" { split($5, a, ","); for (i in a) { gsub(/^ +| +$/, "", a[i]); if (a[i] != "") print a[i] } }' | sort -u
}

filter_by_tag() {
    local tag="$1"
    get_sessions | awk -F'\t' -v tag="$tag" '{
        split($5, a, ","); for (i in a) { gsub(/^ +| +$/, "", a[i]); if (a[i] == tag) { print; next } }
    }'
}

# Sessions whose knowledge has not been distilled yet: never requested, waiting, or
# failed. Deliberately excludes `exempt` (decided too small to recap), `done`, and
# `running` (someone holds it), and excludes recap sessions themselves, which have a
# status of their own but nothing to distil. This is the full backlog the
# start-of-session notice deliberately does not show, since a nudge is for what stalled.
filter_not_recapped() {
    get_sessions | awk -F'\t' '$7 == "-" || $7 == "requested" || $7 == "failed"'
}

filter_named() {
    get_sessions | awk -F'\t' '$6 != "-"'
}

# --- Actions ---

# Reads the text to copy on stdin. Local clipboard tools first, then OSC 52: on a
# headless host the terminal at the far end of the SSH session owns the real clipboard,
# and herdr relays a pane's OSC 52 write to its attached client. tmux's paste buffer is
# last because it is the only tier that does not reach a system clipboard.
copy_to_clipboard() {
    if command -v pbcopy >/dev/null 2>&1; then pbcopy
    elif command -v wl-copy >/dev/null 2>&1; then wl-copy
    elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard
    elif command -v base64 >/dev/null 2>&1 && [ -w /dev/tty ]; then
        printf '\033]52;c;%s\007' "$(base64 | tr -d '\n')" > /dev/tty
    elif [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
        tmux load-buffer -
    else
        return 1
    fi
}

# Opens $@ next to the caller, at cwd $1: a right-hand split under herdr, a new window
# under tmux. Each multiplexer is detected by the variable it owns, not by which binaries
# exist: a host can have tmux installed with no server running (herdr is not tmux and
# sets no $TMUX). Neither herdr verb takes a command, so the pane is made first and the
# id is read from the reply — ids must never be predicted. --focus is explicit because
# herdr places new panes in the background, while tmux switches to the new window:
# without it the editor really does open, somewhere you never see.
open_alongside() {
    local cwd="$1"; shift
    if [ -n "${TMUX:-}" ] && command -v tmux >/dev/null 2>&1; then
        tmux new-window -c "$cwd" "$*"
        return
    fi
    if [ "${HERDR_ENV:-}" != 1 ]; then
        echo "Not inside tmux or herdr; cannot open a new pane." >&2
        return 1
    fi

    # herdr launches a keybinding's command directly, not through a login shell, so
    # $PATH there is not the one ~/.zshrc builds and `command -v herdr` finds nothing.
    # $HERDR_BIN_PATH is injected into every pane for exactly this; the last fallback
    # is the idiom recap_launcher.sh already uses.
    local herdr_bin
    herdr_bin=$(command -v herdr 2>/dev/null) \
        || herdr_bin="${HERDR_BIN_PATH:-$HOME/.local/bin/herdr}"
    if [ ! -x "$herdr_bin" ]; then
        echo "herdr not found at $herdr_bin; cannot open a new pane." >&2
        return 1
    fi

    # Which pane to split. A popup launcher has its pane identity deliberately removed
    # (herdr's app/popup.rs drops HERDR_PANE_ID), so there is no own pane to split and
    # the workspace's focused pane — the one the popup is covering — is what the user
    # means by "beside this".
    local target
    target="${HERDR_PANE_ID:-}"
    [ -n "$target" ] || target=$("$herdr_bin" api snapshot 2>/dev/null \
        | sed -n 's/.*"focused_pane_id":"\([^"]*\)".*/\1/p')
    if [ -z "$target" ]; then
        echo "Could not determine which herdr pane to split." >&2
        return 1
    fi

    local created pane
    created=$("$herdr_bin" pane split --pane "$target" --direction right --cwd "$cwd" --focus) || return 1
    pane=$(printf '%s' "$created" | sed -n 's/.*"pane":{[^}]*"pane_id":"\([^"]*\)".*/\1/p')
    [ -n "$pane" ] || return 1
    "$herdr_bin" pane run "$pane" "$@"
}

resume_session() {
    local selected="$1"
    local session_id cwd
    session_id=$(printf '%s' "$selected" | cut -f2)
    cwd=$(printf '%s' "$selected" | cut -f3)

    if [ -z "$cwd" ] || [ "$cwd" = "-" ] || [ ! -d "$cwd" ]; then
        echo "Error: Working directory no longer exists: $cwd" >&2
        exit 1
    fi

    open_alongside "$cwd" claude -r "$session_id"
}

open_session_folder() {
    local selected="$1"
    local session_path session_dir
    session_path=$(printf '%s' "$selected" | cut -f4)
    session_dir="$(dirname "$session_path")"

    if [ -d "$session_dir" ]; then
        open_alongside "$session_dir" nvim .
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
    if printf '%s' "$session_dir" | copy_to_clipboard; then
        echo "Copied: $session_dir"
    else
        echo "No clipboard available; path: $session_dir" >&2
    fi
}

# --- Shared fzf navigation binds ---
FZF_NAV_BINDS=(
    --bind "ctrl-a:become($SELF)"
    --bind "ctrl-n:become($SELF --by-name)"
    --bind "ctrl-t:become($SELF --by-tag)"
    --bind "ctrl-r:become($SELF --refresh-and-search)"
)
FZF_NAV_HEADER=' ^a all  ^n named  ^t by tag  ^r refresh'

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
    by_name)
        filter_named | pick_session_from " ccfind: named sessions "
        ;;
    not_recapped)
        filter_not_recapped | pick_session_from " ccfind: not recapped "
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
    refresh_and_search)
        refresh_cache
        _SESSIONS_CACHE=""
        get_sessions | pick_session_from
        ;;
esac
