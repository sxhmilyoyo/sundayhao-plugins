#!/bin/bash
# launch_delegate.sh - start a session that records which session launched it.
#
#   launch_delegate.sh <role> <prompt>
#
# Delegation is declared, not detected (ADR-0005). This script names the
# launching session on the launched command; the delegate's own SessionStart hook
# reads that and records the relationship. Nothing infers it afterwards, so a
# session started any other way simply has no lineage, which is the same outcome
# as before and is why it is acceptable.
#
# The marker travels inline on the command and never through the pane's
# environment. A terminal manager's --env option adds the variable to the pane's
# root shell, so every later session opened in that pane would inherit a launcher
# that never launched it.

set -uo pipefail

ROLE="${1:-}"
PROMPT="${2:-}"

if [ -z "$ROLE" ] || [ -z "$PROMPT" ]; then
    echo "Usage: $0 <role> <prompt>" >&2
    echo "" >&2
    echo "  role    what the delegate is for, e.g. review, research, port" >&2
    echo "  prompt  the delegate's first instruction" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/get_kb_path.sh"
source "$SCRIPT_DIR/obsidian_helpers.sh"

# In a hook subprocess this variable is always the hook's own session, which is
# exactly what makes it usable here: this script runs inside the launcher.
LAUNCHER_ID="${CLAUDE_CODE_SESSION_ID:-}"
if [ -z "$LAUNCHER_ID" ]; then
    echo "ERROR: CLAUDE_CODE_SESSION_ID is unset; run this from inside a session" >&2
    exit 1
fi

LAUNCHER_NAME=""
KB_PATH=$(get_kb_path 2>/dev/null) || KB_PATH=""
if [ -n "$KB_PATH" ]; then
    LAUNCHER_FOLDER=$(resolve_session_folder "$KB_PATH" "$LAUNCHER_ID")
    [ -n "$LAUNCHER_FOLDER" ] && LAUNCHER_NAME=$(read_frontmatter_prop \
        "$LAUNCHER_FOLDER/session.md" "session_name")
fi

# The role leads, so that when the 32-character agent-name limit truncates the
# result it is the launcher's name that is cut and not the part distinguishing
# this delegate from its siblings.
DELEGATE_NAME=$(printf '%s-%s' "$ROLE" "${LAUNCHER_NAME:-${LAUNCHER_ID:0:8}}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9_-]+/-/g; s/^[^a-z]+//' \
    | cut -c1-32 | sed -E 's/-+$//')
[ -n "$DELEGATE_NAME" ] || DELEGATE_NAME="delegate-${LAUNCHER_ID:0:8}"

# Every value is quoted for the shell that will run it, because a prompt is free
# text and a session name is chosen by a person.
CMD=$(printf 'SECOND_BRAIN_DELEGATED_BY=%q SECOND_BRAIN_DELEGATED_BY_NAME=%q claude -n %q %q' \
    "$LAUNCHER_ID" "$LAUNCHER_NAME" "$DELEGATE_NAME" "$PROMPT")

HERDR_BIN=$(herdr_bin)
HOST=$(terminal_host)

# Without a terminal host there is no pane to open, so hand the command over instead of
# guessing at a terminal. The delegate is identical either way.
if [ "$HOST" = "none" ]; then
    echo "Not running under the Herdr TUI or the Herdr app. Run this in a new terminal:"
    echo ""
    echo "  cd $(printf '%q' "$PWD") && $CMD"
    exit 0
fi

# The Herdr app (ADR-0011): the delegate is an hc worker, a terminal with no pane, listed
# in the app's agents sidebar, and an hc child of this session's own terminal. hc's notes
# stay on, so this session hears when the delegate blocks, errors or ends, and the prompt
# gains hc's own reach line, so the delegate knows how to report; both are what a session
# that works on another's behalf should have. --outlive-parent, because the parent's
# program is this pane's shell and closing the pane must not end a delegate mid-work.
# The command travels as one string the shell runs, so the marker stays inline and the
# worker gets the core's environment, not this session's. A name is unique among live
# terminals; a taken one is retried once with a suffix.
if [ "$HOST" = "herdr-app" ]; then
    HC_BIN=$(hc_bin)
    APP_PROMPT="$PROMPT

Report with hc send $HC_TERMINAL_ID when done or stuck."
    APP_CMD=$(printf 'SECOND_BRAIN_DELEGATED_BY=%q SECOND_BRAIN_DELEGATED_BY_NAME=%q claude -n %q %q' \
        "$LAUNCHER_ID" "$LAUNCHER_NAME" "$DELEGATE_NAME" "$APP_PROMPT")
    WORKER=""
    RUN_JSON=""
    RUN_ERR="${TMPDIR:-/tmp}/launch-delegate-$$.err"
    for TRY in "$DELEGATE_NAME" "$(printf '%s' "$DELEGATE_NAME" | cut -c1-30)-2"; do
        APP_CMD=$(printf 'SECOND_BRAIN_DELEGATED_BY=%q SECOND_BRAIN_DELEGATED_BY_NAME=%q claude -n %q %q' \
            "$LAUNCHER_ID" "$LAUNCHER_NAME" "$TRY" "$APP_PROMPT")
        RUN_JSON=$("$HC_BIN" run --json --bg --outlive-parent --name "$TRY" --cwd "$PWD" \
            -- "$APP_CMD" 2>"$RUN_ERR")
        WORKER=$(printf '%s' "$RUN_JSON" | jq -r '.address // empty' 2>/dev/null)
        [ -n "$WORKER" ] && { DELEGATE_NAME="$TRY"; break; }
        printf '%s %s' "$RUN_JSON" "$(cat "$RUN_ERR" 2>/dev/null)" | grep -q name_taken || break
    done
    if [ -z "$WORKER" ]; then
        echo "ERROR: could not start a worker; hc said: $RUN_JSON $(cat "$RUN_ERR" 2>/dev/null)" >&2
        rm -f "$RUN_ERR"
        echo "Run this in a new terminal instead:" >&2
        echo "  cd $(printf '%q' "$PWD") && $CMD" >&2
        exit 1
    fi
    rm -f "$RUN_ERR"
    echo "Launched $DELEGATE_NAME in hc terminal $WORKER (no pane: open it from the Herdr app's agents sidebar)"
    echo "  launched by: ${LAUNCHER_NAME:-$LAUNCHER_ID}"
    echo "  reachable as: hc send|wait|read $DELEGATE_NAME; it reports back with hc send $HC_TERMINAL_ID"
    exit 0
fi

PANE_JSON=$("$HERDR_BIN" pane split --pane "$HERDR_PANE_ID" --direction right \
    --no-focus --cwd "$PWD" 2>&1)
NEW_PANE=$(printf '%s' "$PANE_JSON" \
    | jq -r '.result.pane.pane_id // .result.pane_id // empty' 2>/dev/null)

if [ -z "$NEW_PANE" ]; then
    echo "ERROR: could not open a pane; herdr said: $PANE_JSON" >&2
    echo "Run this in a new terminal instead:" >&2
    echo "  cd $(printf '%q' "$PWD") && $CMD" >&2
    exit 1
fi

"$HERDR_BIN" pane run "$NEW_PANE" "$CMD" >/dev/null 2>&1

echo "Launched $DELEGATE_NAME in pane $NEW_PANE"
echo "  launched by: ${LAUNCHER_NAME:-$LAUNCHER_ID}"
echo "  reachable as: herdr agent prompt|wait|read $DELEGATE_NAME"
