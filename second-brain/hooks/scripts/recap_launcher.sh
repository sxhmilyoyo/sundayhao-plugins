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
# Two ways in, one Herdr path:
#
#   --manual <folder>   a person asking for a recap or a retry. Talks to the terminal:
#                       opens a pane under Herdr, prints a paste-able command elsewhere.
#   --auto <folder>     the SessionEnd hook, when auto_recap is `on`. Has no terminal to
#                       talk to, so everything it would say goes to the subject's
#                       recap.log, and outside Herdr it does nothing at all: the subject
#                       stays `requested` and the start-of-session notice covers it.
#
# There is deliberately no project precondition. The recap is where the domain for
# work in an unmapped directory is decided, so refusing to launch without one would
# block the value on the only thing that can supply it (ADR-0006). A recap that still
# cannot place the work marks the subject failed and the notice asks a person.
#
# Exit: 0 launched, command printed, or deliberately did nothing; 2 usage or no subject.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PLUGIN_ROOT/skills/common/get_kb_path.sh"
source "$PLUGIN_ROOT/skills/common/obsidian_helpers.sh"

usage() {
    cat >&2 <<'USAGE'
Usage: recap_launcher.sh --manual <subject_session_folder>
       recap_launcher.sh --auto   <subject_session_folder>

Starts a recap of that session in a session of its own. Inside Herdr it opens a
pane; anywhere else --manual prints the command to paste into a terminal and
--auto does nothing, leaving the start-of-session notice to ask.
USAGE
    exit 2
}

MODE=""
SUBJECT=""
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

# The notice prints folder paths with a trailing slash and a person may paste one.
while [ "${SUBJECT%/}" != "$SUBJECT" ] && [ "$SUBJECT" != "/" ]; do SUBJECT="${SUBJECT%/}"; done
# Absolute from here on, because this string outlives the directory it was typed in. The
# child changes into the vault before it uses it, and every path built from it afterwards —
# recap.log, the note it reads, the folder it hands the status writer — would then resolve
# against the vault instead. A relative path that happens to exist under the vault too is
# the bad case: no error, just a different session's note being written.
case "$SUBJECT" in /*) ;; *) SUBJECT="$PWD/$SUBJECT" ;; esac

if [ ! -f "$SUBJECT/session.md" ]; then
    printf 'recap_launcher.sh: no session note at %s/session.md\n' "$SUBJECT" >&2
    exit 2
fi

# Under --auto there is no terminal to talk to. The hook that started this is already
# gone, and this process is detached with its stdio closed, so anything printed would
# vanish. The subject's recap.log is the record instead, and it is the same file the
# child and the status writer append to, so one file tells the whole story of a recap.
LOG="$SUBJECT/recap.log"
say() {
    if [ "$MODE" = "auto" ]; then
        printf '%s launcher %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG" 2>/dev/null || true
    else
        printf '%s\n' "$*"
    fi
}
# A failure a person needs to see. Under --manual it goes to stderr with the paste-able
# command; under --auto it is logged and the subject simply stays `requested`, which the
# notice already lists, so a failed automatic launch degrades to the manual flow.
fail() {
    if [ "$MODE" = "auto" ]; then
        printf '%s launcher failed: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG" 2>/dev/null || true
        exit 0
    fi
    printf 'recap_launcher.sh: %s\n' "$*" >&2
    exit 2
}

# Only --auto has a parent worth waiting for: it runs from the ending session's own hook,
# where CLAUDE_PID is that session's process (verified present in the hook environment).
# Under --manual the invoking shell is not the subject, so there is nothing to wait for.
PARENT_PID=""
[ "$MODE" = "auto" ] && PARENT_PID="${CLAUDE_PID:-}"

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

# Outside Herdr there is no pane to open. A person gets the command to run; the hook gets
# nothing at all, deliberately, because `on` degrading to `notify` is the documented
# behaviour and a half-started recap would be worse than none. The subject is already
# stamped `requested` by this point, so the notice covers it either way.
if [ "${HERDR_ENV:-}" != "1" ] || [ -z "${HERDR_PANE_ID:-}" ] || [ ! -x "$HERDR_BIN" ]; then
    if [ "$MODE" = "auto" ]; then
        say "not under Herdr, leaving the subject requested for the notice"
        exit 0
    fi
    KB_PATH=$(get_kb_path 2>/dev/null) || KB_PATH=""
    echo "Not running under Herdr. Run this in a new terminal:"
    echo ""
    [ -n "$KB_PATH" ] && echo "  cd $(printf '%q' "$KB_PATH") && $CMD" || echo "  $CMD"
    exit 0
fi

KB_PATH=$(get_kb_path 2>/dev/null)
[ -n "$KB_PATH" ] || fail "knowledge bank not configured"

# ── Where to run it: in this pane, or beside it ──────────────────────────────────
# One rule for both modes: run where the shell is free, otherwise beside it. A person
# leaves a pane sitting at its prompt after exiting a session, so that pane is the natural
# home for that session's recap, and a new pane per recap is clutter reuse removes.
#
# "Free" is Herdr's own definition of an available shell pane, read from `pane
# process-info` rather than guessed from a prompt pattern: `foreground_process_group_id` is
# the process group that currently owns the pane's terminal, `shell_pid` its root shell.
# `agent start` decides availability from the same fact, but cannot be used here because it
# has no way to carry the child's inline markers, so reuse is a `pane run` after the check.
#
# What that group is compared against differs by mode, because our own position differs:
#
#   --auto   is detached in a session of its own, so nothing of ours is in that pane. Free
#            means the foreground group is the pane's own shell: nothing running, at a
#            prompt. Measured: an idle pane reports fg group == shell_pid and exactly one
#            foreground process, zsh.
#   --manual is running IN that pane, so the shell's own group is exactly what a free pane
#            does NOT report — we are holding the foreground ourselves. Free means the
#            foreground group is ours. Measured: a script typed at a zsh prompt is the
#            tty's foreground group leader (pgid == tpgid), while the same script run
#            through a Claude session's Bash tool sits in its own group beneath claude, and
#            claude's group holds the foreground. Comparing against shell_pid here would
#            call every manual launch busy and leave the inline path unreachable.
pane_state() {   # free | busy | gone
    local pane="$1" fg shell nproc want
    { IFS= read -r fg; IFS= read -r shell; IFS= read -r nproc; } \
        < <("$HERDR_BIN" pane process-info --pane "$pane" 2>/dev/null \
        | jq -r '.result.process_info.foreground_process_group_id // "",
                 .result.process_info.shell_pid // "",
                 (.result.process_info.foreground_processes | length)' 2>/dev/null)
    # A closed pane answers nothing. Distinguished from busy because there is no point
    # waiting for a pane that no longer exists, and because the split below will fail
    # against it too, which is what leaves the subject `requested` for the notice.
    [ -n "$fg" ] || { printf 'gone\n'; return; }
    # Whose group has to hold the pane for it to count as free: the pane's own shell when
    # we are outside it, our own group when we are the thing standing in it.
    if [ "$MODE" = "auto" ]; then
        want="$shell"
        # Second half of the rule, and it only means anything on this side. A shell hands
        # each job its own process group, so a shell that owns the foreground normally owns
        # it alone; a second process in there is something running without a group of its
        # own, and the pane is busy however the group ids compare. Under --manual the group
        # is ours and holds us, so counting would only be counting ourselves.
        # `-le 1` rather than `-eq 1`: a build that does not report the list at all answers
        # zero, and a missing field should not quietly switch reuse off.
        case "$nproc" in
            ''|*[!0-9]*) : ;;
            *) [ "$nproc" -le 1 ] || { printf 'busy\n'; return; } ;;
        esac
    else
        want=$(ps -o pgid= -p $$ 2>/dev/null | tr -d ' ')
    fi
    if [ -n "$want" ] && [ "$fg" = "$want" ]; then printf 'free\n'; else printf 'busy\n'; fi
}

# Under --auto the pane is certain to be busy at this instant, and waiting is not
# optional. This process was spawned by the ending session's own SessionEnd hook, so it is
# a descendant of that session's claude, so claude is still alive, so claude's process
# group still owns the pane's terminal. Measured directly: CLAUDE_PID in the hook
# environment is the very number `pane process-info` reports as
# foreground_process_group_id, and shell_pid is its parent. A single check here would
# therefore read `busy` every time and reuse would never once engage — the plan's
# assumption that this process already waits for the parent was wrong, the child is what
# waits. So wait for the pane itself to come free, which is the condition the decision
# actually needs and is true only once claude has released the terminal.
#
# Bounded, because a person who exits a session and immediately starts something else in
# that pane must not hold the recap up: when the window closes on a still-busy pane the
# split below runs, exactly as before reuse existed. Off the hook's clock either way —
# this process is detached and nothing is waiting on it.
#
# The child keeps its own parent-exit wait, and it is still load-bearing: that timeout is
# reached precisely when the pane never came free, which is when claude may still be alive
# and the transcript still being written.
STATE=$(pane_state "$HERDR_PANE_ID")
if [ "$MODE" = "auto" ]; then
    # Validated, not trusted, and for a specific reason: an unusable value makes `-lt` fail
    # with "integer expression expected", the body never runs, and the wait silently
    # collapses to the single check this whole passage exists to avoid — with the complaint
    # going to the /dev/null this process was detached onto, so nothing would record it.
    ATTEMPTS="${SECOND_BRAIN_PANE_WAIT_ATTEMPTS:-20}"
    case "$ATTEMPTS" in ''|*[!0-9]*) ATTEMPTS=20 ;; esac
    i=0
    while [ "$STATE" = "busy" ] && [ "$i" -lt "$ATTEMPTS" ]; do
        sleep 0.5
        i=$(( i + 1 ))
        STATE=$(pane_state "$HERDR_PANE_ID")
    done
fi

if [ "$STATE" = "free" ]; then
    if [ "$MODE" = "auto" ]; then
        # Nothing is renamed here. The pane still carries the subject's name, and the recap
        # session's own SessionStart renames pane and agent to the recap name just as it
        # does in a split; claiming the label before anything ran would tell a watcher the
        # wrong thing if the hand-off failed.
        #
        # One risk reuse adds that a fresh pane did not have: `pane run` submits text to
        # that shell, and several things a person would call busy read as free here, because
        # `process-info` reads processes and not the line editor or the job table. A prompt
        # with something typed at it but not yet entered looks exactly like an empty one. So
        # does a suspended job: Ctrl-Z hands the terminal back, so the foreground group is
        # the shell again and holds only the shell. So does anything the shell runs inside
        # its own group rather than a job of its own — a shell function, a compound command,
        # a `read` prompt. In each case the text lands somewhere it does nothing.
        # Left alone deliberately: the shell reports a command it cannot find, the subject
        # stays `requested` and the next notice offers it, so the failure is visible and
        # costs a recap rather than any data. Clearing the line first would start the recap
        # by throwing away what they were typing, which is worse than the notice.
        if ! "$HERDR_BIN" pane run "$HERDR_PANE_ID" "$CMD" >/dev/null 2>&1; then
            fail "could not start the recap in pane $HERDR_PANE_ID"
        fi
        say "reusing pane $HERDR_PANE_ID for $NAME"
        exit 0
    fi
    # --manual at a prompt: become the recap. No Herdr call at all, so there is no pane
    # hand-off left to fail, and the pane returns to its prompt when the recap ends.
    # Exported rather than quoted onto a command line: there is no shell in between to
    # quote for, which removes the only place a vault path with a space could break.
    echo "Recapping $(basename "$SUBJECT") as $NAME in this pane"
    export SECOND_BRAIN_RECAP_OF="$SUBJECT"
    export SECOND_BRAIN_RECAP_NAME="$NAME"
    export SECOND_BRAIN_PARENT_PID="$PARENT_PID"
    export SECOND_BRAIN_PLUGIN_ROOT="$PLUGIN_ROOT"
    exec bash "$CHILD" "$SUBJECT"
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
    PANE_STDERR=$(cat "$PANE_ERR" 2>/dev/null)
    rm -f "$PANE_ERR"
    if [ "$MODE" = "auto" ]; then
        fail "could not open a pane; herdr said: $PANE_JSON $PANE_STDERR"
    fi
    printf 'recap_launcher.sh: could not open a pane; herdr said: %s %s\n' \
        "$PANE_JSON" "$PANE_STDERR" >&2
    echo "Run this in a new terminal instead:" >&2
    echo "  cd $(printf '%q' "$KB_PATH") && $CMD" >&2
    exit 2
fi
rm -f "$PANE_ERR"

# The split returns as soon as the pane exists, which is before its shell can accept
# text: `pane run` submits text plus Enter to that shell, and text sent too early is
# simply lost, leaving a correctly labelled pane sitting at an empty prompt. Under --auto
# nobody is watching to notice. `pane process-info` reports a shell_pid once the shell is
# up, which is a fact about the pane rather than a guess at what a prompt looks like, so
# it works whatever shell and theme the user has.
#
# This is off the hook's clock: the launcher is detached by now, so waiting costs nothing
# that anyone is waiting on.
READY=""
i=0
while [ "$i" -lt 60 ]; do
    if [ -n "$("$HERDR_BIN" pane process-info --pane "$NEW_PANE" 2>/dev/null \
                | jq -r '.result.process_info.shell_pid // empty' 2>/dev/null)" ]; then
        READY=1
        break
    fi
    sleep 0.1
    i=$(( i + 1 ))
done
[ -n "$READY" ] || say "pane $NEW_PANE never reported a shell after 6 s, sending anyway"

# Label the pane before anything runs in it, so a person watching sees what it is.
# Never rename_terminal_window: under --auto this runs in the dying parent's
# environment, where that helper would rename the parent's own pane.
"$HERDR_BIN" pane rename "$NEW_PANE" "$NAME" >/dev/null 2>&1 || true

# Checked, like the split above. Reporting a recap as started when the hand-off failed
# leaves an empty pane open and the subject sitting at `requested`, with the notice
# repeating the same row every session and nothing saying why.
if ! "$HERDR_BIN" pane run "$NEW_PANE" "$CMD" >/dev/null 2>&1; then
    if [ "$MODE" = "auto" ]; then
        fail "opened pane $NEW_PANE but could not start the recap in it"
    fi
    printf 'recap_launcher.sh: opened pane %s but could not start the recap in it\n' "$NEW_PANE" >&2
    echo "Run this in that pane, or in a new terminal:" >&2
    echo "  cd $(printf '%q' "$KB_PATH") && $CMD" >&2
    exit 2
fi

if [ "$MODE" = "auto" ]; then
    say "started $NAME in pane $NEW_PANE"
else
    echo "Recapping $(basename "$SUBJECT") as $NAME in pane $NEW_PANE"
fi
exit 0
