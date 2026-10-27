#!/bin/bash
# recap_exit_watch.sh - end a recap session once its recap is done.
#
#   recap_exit_watch.sh <subject_session_folder> <herdr_pane> <recap_child_pid>
#
# Started in the background by recap_child.sh, and only under Herdr, never by hand. A recap
# session is interactive so a person can watch it and step in, and ADR-0007's one question is
# answered there, so nothing ended it when the skill wrote `done`: a finished recap held its
# memory until someone closed the pane, once for 66 hours (ADR-0010).
#
# It ends the session the way the ticket dispatcher ends its own: /exit typed through Herdr,
# and only into a session Herdr shows visibly idle at a prompt box that is empty or holds only
# dim ghost text. Every check that fails leaves the session open, which is what happened
# before this existed, with the reason in the subject's recap.log.
#
# Exit: 0 always, once running; 2 usage.

SUBJECT="${1:-}"
PANE="${2:-}"
CHILD_PID="${3:-}"
if [ -z "$SUBJECT" ] || [ -z "$PANE" ] || [ -z "$CHILD_PID" ]; then
    echo "Usage: $0 <subject_folder> <herdr_pane> <recap_child_pid>" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PLUGIN_ROOT/skills/common/obsidian_helpers.sh"
LOG="$SUBJECT/recap.log"
HERDR_BIN=$(command -v herdr 2>/dev/null || echo "$HOME/.local/bin/herdr")

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
