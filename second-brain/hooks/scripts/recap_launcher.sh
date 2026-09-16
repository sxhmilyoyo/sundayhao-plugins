#!/bin/bash
# recap_launcher.sh - start a recap in a session of its own.
#
#   recap_launcher.sh --manual <subject_session_folder>
#
# A recap must run in a dedicated recap session that carries SECOND_BRAIN_RECAP_OF
# from its very first process, so SessionStart registers it and SessionEnd exempts it
# whether or not the recap finishes (ADR-0003). Typing the slash command into a working
# session cannot give it that: either the working session stays unmarked and is itself
# recapped afterwards, or the skill marks the note it is running in and that session's
# real work is written off as exempt. Hence a launcher.
#
# Stage 1 ships --manual only, for retries a person asks for. Stage 2 adds --auto,
# called from the end hook, which is why the Herdr path below is written once.
#
# There is deliberately no project precondition. The recap is where the domain for
# work in an unmapped directory is decided, so refusing to launch without one would
# block the value on the only thing that can supply it (ADR-0006). A recap that still
# cannot place the work marks the subject failed and the notice asks a person.
#
# Exit: 0 launched or command printed, 2 usage or no such subject.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PLUGIN_ROOT/skills/common/get_kb_path.sh"
source "$PLUGIN_ROOT/skills/common/obsidian_helpers.sh"

usage() {
    cat >&2 <<'USAGE'
Usage: recap_launcher.sh --manual <subject_session_folder>

Starts a recap of that session in a session of its own. Inside Herdr it opens a
pane; anywhere else it prints the command to paste into a terminal.
USAGE
    exit 2
}

MODE=""
SUBJECT=""
# Only --auto has a parent worth waiting for: it runs from the ending session's own hook,
# so CLAUDE_PID is that session. Under --manual the invoking shell is not the subject.
PARENT_PID=""
while [ $# -gt 0 ]; do
    case "$1" in
        --manual) MODE="manual" ;;
        --auto)   MODE="auto" ;;
        -*)       printf 'recap_launcher.sh: unknown option: %s\n' "$1" >&2; usage ;;
        *)        [ -z "$SUBJECT" ] && SUBJECT="$1" || usage ;;
    esac
    shift
done

[ -n "$MODE" ] && [ -n "$SUBJECT" ] || usage
if [ "$MODE" = "auto" ]; then
    # Stage 2 owns this path. Failing loudly now is better than a hook silently
    # launching something this version has not tested.
    printf 'recap_launcher.sh: --auto is not implemented in this version\n' >&2
    exit 2
fi

# The notice prints folder paths with a trailing slash and a person may paste one.
while [ "${SUBJECT%/}" != "$SUBJECT" ] && [ "$SUBJECT" != "/" ]; do SUBJECT="${SUBJECT%/}"; done

if [ ! -f "$SUBJECT/session.md" ]; then
    printf 'recap_launcher.sh: no session note at %s/session.md\n' "$SUBJECT" >&2
    exit 2
fi

# One name for the pane, the Herdr agent, the session and its note, computed here so
# every one of them agrees. An unnamed subject still yields something identifiable.
SUBJECT_NAME=$(read_frontmatter_prop "$SUBJECT/session.md" "session_name")
if [ -n "$SUBJECT_NAME" ]; then
    NAME="recap-$SUBJECT_NAME"
else
    NAME="recap-$(basename "$SUBJECT" | cut -c1-8)"
fi
# Herdr's agent rule: lowercase, invalid runs collapsed, 32 characters. Applied here
# too so the -n name, the pane label and the agent name are the same string.
NAME=$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9_-]+/-/g; s/^[^a-z]+//' | cut -c1-32 | sed -E 's/-+$//')
[ -n "$NAME" ] || NAME="recap-session"

CHILD="$PLUGIN_ROOT/hooks/scripts/recap_child.sh"

# The markers travel inline on the command, never through the pane's environment.
# Herdr's --env "adds or replaces that variable in the new root shell", so a marker
# passed that way outlives this recap: every later claude started in that pane would
# register as a recap session and be stamped exempt at its own exit, losing its work.
# %q throughout, because a vault path may contain a space or a quote.
# SECOND_BRAIN_PARENT_PID travels too, and is empty under --manual because there is no
# dying session to wait for. It is what the child's parent-exit wait reads, and Stage 2's
# --auto is where that matters: launched from the end hook, the subject's process is
# still flushing its transcript, and without this the child would start reading a file
# that is still being written.
CMD=$(printf 'SECOND_BRAIN_RECAP_OF=%q SECOND_BRAIN_RECAP_NAME=%q SECOND_BRAIN_PARENT_PID=%q SECOND_BRAIN_PLUGIN_ROOT=%q bash %q %q' \
    "$SUBJECT" "$NAME" "${PARENT_PID:-}" "$PLUGIN_ROOT" "$CHILD" "$SUBJECT")

HERDR_BIN=$(command -v herdr 2>/dev/null || echo "$HOME/.local/bin/herdr")

# Outside Herdr there is no pane to open, so hand the command over rather than guess at
# a terminal. The recap is identical either way; only who starts it differs.
if [ "${HERDR_ENV:-}" != "1" ] || [ -z "${HERDR_PANE_ID:-}" ] || [ ! -x "$HERDR_BIN" ]; then
    KB_PATH=$(get_kb_path 2>/dev/null) || KB_PATH=""
    echo "Not running under Herdr. Run this in a new terminal:"
    echo ""
    [ -n "$KB_PATH" ] && echo "  cd $(printf '%q' "$KB_PATH") && $CMD" || echo "  $CMD"
    exit 0
fi

KB_PATH=$(get_kb_path 2>/dev/null)
if [ -z "$KB_PATH" ]; then
    printf 'recap_launcher.sh: knowledge bank not configured\n' >&2
    exit 2
fi

# stdout and stderr are kept apart: the response is parsed as JSON, and one deprecation
# notice or auth warning on stderr would otherwise prefix the document, make jq fail, and
# send this down the error path below — after the pane had already been created, leaving
# an orphan behind.
PANE_ERR="${TMPDIR:-/tmp}/recap-launcher-$$.err"
PANE_JSON=$("$HERDR_BIN" pane split --pane "$HERDR_PANE_ID" --direction right \
    --no-focus --cwd "$KB_PATH" 2>"$PANE_ERR")
NEW_PANE=$(printf '%s' "$PANE_JSON" \
    | jq -r '.result.pane.pane_id // .result.pane_id // empty' 2>/dev/null)

if [ -z "$NEW_PANE" ]; then
    printf 'recap_launcher.sh: could not open a pane; herdr said: %s %s\n' \
        "$PANE_JSON" "$(cat "$PANE_ERR" 2>/dev/null)" >&2
    rm -f "$PANE_ERR"
    echo "Run this in a new terminal instead:" >&2
    echo "  cd $(printf '%q' "$KB_PATH") && $CMD" >&2
    exit 2
fi
rm -f "$PANE_ERR"

# Label the pane before anything runs in it, so a person watching sees what it is.
# Never rename_terminal_window: under --auto this runs in the dying parent's
# environment, where that helper would rename the parent's own pane.
"$HERDR_BIN" pane rename "$NEW_PANE" "$NAME" >/dev/null 2>&1 || true

# Checked, like the split above. Reporting a recap as started when the hand-off failed
# leaves an empty pane open and the subject sitting at `requested`, with the notice
# repeating the same row every session and nothing saying why.
if ! "$HERDR_BIN" pane run "$NEW_PANE" "$CMD" >/dev/null 2>&1; then
    printf 'recap_launcher.sh: opened pane %s but could not start the recap in it\n' "$NEW_PANE" >&2
    echo "Run this in that pane, or in a new terminal:" >&2
    echo "  cd $(printf '%q' "$KB_PATH") && $CMD" >&2
    exit 2
fi

echo "Recapping $(basename "$SUBJECT") as $NAME in pane $NEW_PANE"
exit 0
