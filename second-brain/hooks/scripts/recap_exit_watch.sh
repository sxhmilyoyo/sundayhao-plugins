#!/bin/bash
# recap_exit_watch.sh - end a recap session once its recap is done.
#
#   recap_exit_watch.sh <subject_session_folder> <terminal> <recap_child_pid>
#
# <terminal> is the Herdr TUI pane id or the Herdr app's hc terminal id, whichever host
# owns the recap's terminal; the host is read from the environment (terminal_host).
# Started in the background by recap_child.sh, and only under a terminal host, never by hand. A recap
# session is interactive so a person can watch it and step in, and ADR-0007's one question is
# answered there, so nothing ended it when the skill wrote `done`: a finished recap held its
# memory until someone closed the pane, once for 66 hours (ADR-0010).
#
# It ends the session the way the ticket dispatcher ends its own: /exit typed through the
# host, and only into a session the host shows idle at a prompt box that is empty or holds only
# dim ghost text. Every check that fails leaves the session open, which is what happened
# before this existed, with the reason in the subject's recap.log.
#
# Under the Herdr app (ADR-0011) the same five steps run through hc, with two differences
# that are hc's. `hc read` is plain text, so dim ghost text and a typed line look the same:
# only a box that is exactly empty takes /exit, and any text leaves the session open, with
# the reason saying so. And /exit is typed as key presses with `hc keys`, never `hc send`:
# send wraps what it pastes in hc's <hc> tag for a program that reports status, so the
# session would receive a prompt, not a command (measured 2026-11-03).
#
# Exit: 0 always, once running; 2 usage.

SUBJECT="${1:-}"
PANE="${2:-}"
CHILD_PID="${3:-}"
if [ -z "$SUBJECT" ] || [ -z "$PANE" ] || [ -z "$CHILD_PID" ]; then
    echo "Usage: $0 <subject_folder> <terminal> <recap_child_pid>" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PLUGIN_ROOT/skills/common/obsidian_helpers.sh"
LOG="$SUBJECT/recap.log"
HERDR_BIN=$(herdr_bin)
HC_BIN=$(hc_bin)
HOST=$(terminal_host)

log() {
    printf '%s exit-watch %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG" 2>/dev/null || true
}

# Validated, not trusted: an unusable value would make `sleep` or Herdr's --timeout fail at
# once, and a wait that fails at once reads as "nobody stepped in".
num() { case "$1" in ''|*[!0-9]*) printf '%s' "$2" ;; *) printf '%s' "$1" ;; esac; }
POLL_S=$(num "${SECOND_BRAIN_RECAP_EXIT_POLL_S:-}" 15)
IDLE_MS=$(num "${SECOND_BRAIN_RECAP_EXIT_IDLE_MS:-}" 900000)
GRACE_MS=$(num "${SECOND_BRAIN_RECAP_EXIT_GRACE_MS:-}" 120000)

OUT=$(mktemp "${TMPDIR:-/tmp}/recap-exit-watch.XXXXXX") || exit 0
SCREEN=$(mktemp "${TMPDIR:-/tmp}/recap-exit-screen.XXXXXX") || { rm -f "$OUT"; exit 0; }
trap 'rm -f "$OUT" "$SCREEN"' EXIT

# recap_child.sh stops this process from its exit check. Whatever it is waiting on goes with
# it, so a sleep or a fifteen-minute Herdr wait does not outlive the recap it was watching:
# each wait runs in the background and is waited for, which is what lets the signal land.
WAITING=""
trap '[ -n "$WAITING" ] && kill "$WAITING" 2>/dev/null; exit 0' TERM INT HUP
bg() {
    "$@" &
    WAITING=$!
    wait "$WAITING"
    local rc=$?
    WAITING=""
    return "$rc"
}
child_alive() { kill -0 "$CHILD_PID" 2>/dev/null; }
status() { read_frontmatter_prop "$SUBJECT/session.md" recap_status; }
herdr_error() { jq -r '.error.code // "no answer"' "$OUT" 2>/dev/null || echo "no answer"; }
hc_error() { jq -r '.error.kind // .error.message // "no answer"' "$OUT" 2>/dev/null || echo "no answer"; }
hc_state() { "$HC_BIN" get "$PANE" --json 2>/dev/null | jq -r '.status.state // "none"' 2>/dev/null || echo none; }

# The prompt box, read the way the ticket dispatcher reads it before it types /exit. Herdr's
# `live_prompt_box` rule gives the box as text, so a dim placeholder reads exactly like a
# person's half-typed line: Claude's own suggestion, or the debrief mod's `go ahead: ...`
# ghost. The styled screen tells them apart, and this is the dispatcher's own check, ported:
# the box's lines are found on the screen from the bottom, and every character drawn after
# the pointer, past an inverse cursor, must be dim (SGR 2).
# Answers one word: busy, nobox, empty, ghost or text.
BOX_JQ='
def styled_lines:
  reduce match("\u001b\\[([0-9;:]*)m|\r|\n|[\\s\\S]"; "g") as $m
    ({lines: [[]], dim: false, inv: false};
     if $m.captures[0].string != null then
       ($m.captures[0].string | split(";") | map(if . == "" then 0 else (tonumber? // -1) end)) as $ps
       | reduce range(0; $ps | length) as $i (. + {skip: 0};
           if .skip > 0 then .skip -= 1
           elif $ps[$i] == 0 then .dim = false | .inv = false
           elif $ps[$i] == 2 then .dim = true
           elif $ps[$i] == 22 then .dim = false
           elif $ps[$i] == 7 then .inv = true
           elif $ps[$i] == 27 then .inv = false
           elif ($ps[$i] == 38 or $ps[$i] == 48 or $ps[$i] == 58) then
             .skip = (if $ps[$i + 1] == 5 then 2 elif $ps[$i + 1] == 2 then 4 else 0 end)
           else . end)
       | del(.skip)
     elif $m.string == "\n" then .lines += [[]]
     elif $m.string == "\r" then .
     else .lines[-1] += [{ch: $m.string, dim: .dim, inv: .inv}]
     end)
  | .lines;
def text_of: map(.ch) | join("") | sub("\\s+$"; "");
def only_ghost($screen):
  (sub("\n$"; "") | split("\n") | map(sub("\\s+$"; ""))) as $bl
  | ($bl | length) as $n
  | ($screen | styled_lines) as $lines
  | ([range(($lines | length) - $n; -1; -1)
      | . as $t | select(all(range(0; $n); ($lines[$t + .] | text_of) == $bl[.]))] | first) as $top
  | if $top == null then false
    else
      ($lines[$top:($top + $n)] | add // []) as $drawn
      | (($drawn | map(.ch) | index("❯")) // -1) as $p
      | [$drawn[($p + 1):][] | select(.ch | test("\\S"))] as $after
      | (if ($after[0].inv // false) then $after[1:] else $after end) as $ghost
      | ($ghost | length) > 0 and ($ghost | all(.dim))
    end;
if .visible_idle != true then "busy"
else
  ([.evaluated_rules[]? | select(.id == "live_prompt_box" and .matched)][0].evidence.region_preview) as $box
  | if $box == null then "nobox"
    elif ($box | test("^[ \t]*❯[ \t]*\n?$")) then "empty"
    elif ($box | only_ghost($screen)) then "ghost"
    else "text" end
end'

# 1. The recap is done. The skill's final phase writes it (ADR-0002), and nothing else
# here may act before it does: the domain question of ADR-0007 is asked while the status is
# still `running`, so a recap waiting on a person is never ended.
while [ "$(status)" != "done" ]; do
    child_alive || exit 0
    bg sleep "$POLL_S"
done
log "recap done; waiting for the session to go idle"

if [ "$HOST" = "herdr-app" ]; then
    # 2. The session has finished its turn. `done` lands mid-turn, so the turn is waited out
    # within the TUI's bound, and the session's state is always read back from `hc get`, never
    # taken from the wait: on a live recap (2026-11-04) `hc wait` came back at once while the
    # turn was still running. A wait that comes back early is repeated a poll later.
    DEADLINE=$(( $(date +%s) + IDLE_MS / 1000 ))
    S=$(hc_state)
    while { [ "$S" = working ] || [ "$S" = blocked ]; } && [ "$(date +%s)" -lt "$DEADLINE" ]; do
        LEFT=$(( DEADLINE - $(date +%s) )); [ "$LEFT" -ge 1 ] || LEFT=1
        bg "$HC_BIN" wait "$PANE" --timeout "$LEFT" > "$OUT" 2>&1
        child_alive || exit 0
        S=$(hc_state)
        if [ "$S" = working ] || [ "$S" = blocked ]; then
            [ -n "${EARLY:-}" ] || { EARLY=1
                log "hc wait came back with the session still $S ($(jq -r '.reason // .error.kind // "no answer"' "$OUT" 2>/dev/null || echo "no answer")); waiting again"; }
            bg sleep "$POLL_S"
            child_alive || exit 0
        fi
    done
    case "$S" in
        idle|done) ;;
        *) log "left open: the session did not go idle after done (hc shows $S)"; exit 0 ;;
    esac
    # 3. Nobody steps in. hc has no wait for "working", so the grace is polled: a turn
    # started in it makes the session a person's, exactly as under the TUI.
    END=$(( $(date +%s) + GRACE_MS / 1000 ))
    while [ "$(date +%s)" -lt "$END" ]; do
        bg sleep "$POLL_S"
        child_alive || exit 0
        S=$(hc_state)
        case "$S" in
            idle|done) ;;
            working|blocked) log "left open: the session went back to work within the grace, so a person stepped in"; exit 0 ;;
            *) log "left open: hc stopped showing the session ($S)"; exit 0 ;;
        esac
    done
    # 4. The box is exactly empty. The box line is the last line that starts with the prompt
    # pointer at column one; the command menu Claude Code draws above it indents its own
    # pointer. Empty is the pointer alone, or the pointer and the no-break space Claude Code
    # draws after it, which is how hc reads an empty box back (measured 2026-11-04 on a done
    # recap: bytes e2 9d af c2 a0); the comparison is exact. hc returns text without
    # attributes, so a dim ghost and a typed line read the same here, and both keep the session
    # open: typed into either, /exit would be sent as part of a prompt.
    EMPTY_BOX="❯$(printf '\302\240')"
    BOXLINE=$("$HC_BIN" read "$PANE" 2>/dev/null | sed 's/[[:space:]]*$//' | grep '^❯' | tail -1)
    case "$BOXLINE" in
        '')  log "left open: hc shows no prompt box"; exit 0 ;;
        '❯'|"$EMPTY_BOX") ;;
        *)   log "left open: the prompt box holds text, typed or ghost text hc cannot tell apart"; exit 0 ;;
    esac
    if [ "$(status)" != "done" ]; then
        log "left open: the subject is $(status) now, not done"
        exit 0
    fi
    # 5. /exit as key presses, never `hc send` (see the header). Logged before typing, for
    # the reason the TUI path gives. `hc keys` waits for a person to pause before it types.
    log "typing /exit into $PANE as key presses: done, idle through the grace, prompt box empty"
    if ! bg "$HC_BIN" keys "$PANE" / e x i t enter > "$OUT" 2>&1; then
        log "left open: hc refused the /exit ($(hc_error))"
    fi
    exit 0
fi

# 2. The session has finished its turn. `done` lands in the middle of the final turn, with
# the closing message still to stream, so the turn is waited out rather than cut off.
if ! bg "$HERDR_BIN" agent wait "$PANE" --until idle --until done --timeout "$IDLE_MS" > "$OUT" 2>&1; then
    log "left open: the session did not go idle after done ($(herdr_error))"
    exit 0
fi
child_alive || exit 0

# 3. Nobody steps in. The grace is a wait for the session to start working again: a person
# who types in the pane starts a turn, and from then on the session is theirs. A timeout is
# the answer this step hopes for; any other failure is Herdr not knowing the pane.
if bg "$HERDR_BIN" agent wait "$PANE" --until working --until blocked --timeout "$GRACE_MS" > "$OUT" 2>&1; then
    log "left open: the session went back to work within the grace, so a person stepped in"
    exit 0
fi
if [ "$(herdr_error)" != "timeout" ]; then
    log "left open: Herdr did not answer the grace wait ($(herdr_error))"
    exit 0
fi
child_alive || exit 0

# 4. The box takes /exit cleanly: visibly idle, and empty or holding only dim ghost text.
# Typed into anything else, /exit would be appended to what a person wrote and sent as their
# prompt, so a box with text in it keeps the session open.
bg "$HERDR_BIN" agent explain "$PANE" --json > "$OUT" 2>/dev/null
bg "$HERDR_BIN" agent read "$PANE" --source visible --format ansi > "$SCREEN" 2>/dev/null
BOX=$(jq -r --rawfile screen "$SCREEN" "$BOX_JQ" "$OUT" 2>/dev/null)
case "$BOX" in
    empty|ghost) ;;
    text)  log "left open: the prompt box holds text a person may have typed"; exit 0 ;;
    busy)  log "left open: Herdr does not show the session visibly idle"; exit 0 ;;
    *)     log "left open: Herdr shows no prompt box (${BOX:-no answer})"; exit 0 ;;
esac
# Read once more: a person may have re-requested the recap during the grace.
if [ "$(status)" != "done" ]; then
    log "left open: the subject is $(status) now, not done"
    exit 0
fi

# 5. The dispatcher's own end path. Logged before typing, because the exit it causes is what
# makes recap_child.sh stop this process, and the record must not depend on winning that race.
log "typing /exit into $PANE: done, idle through the grace, prompt box $BOX"
if ! bg "$HERDR_BIN" agent prompt "$PANE" "/exit" > "$OUT" 2>&1; then
    log "left open: Herdr refused the /exit ($(herdr_error))"
fi
exit 0
