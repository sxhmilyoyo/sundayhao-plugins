#!/bin/bash
# recap_child.sh - the process that runs one recap, inside its own session.
#
#   SECOND_BRAIN_RECAP_OF=<subject> SECOND_BRAIN_RECAP_NAME=<name> \
#   SECOND_BRAIN_PLUGIN_ROOT=<root> bash recap_child.sh <subject_session_folder>
#
# Started by recap_launcher.sh, never by hand: the markers above have to be on this
# command for the recap session's own hooks to register it (ADR-0003), and the launcher
# is what puts them there.
#
# Its job is to claim the subject, run the recap, and make sure the subject never sits
# in `running` after this process is gone. It marks `failed` on the way out if the
# recap did not reach `done`, so a closed pane or a crashed model surfaces in the
# start-of-session notice instead of looking like a recap still in flight.

SUBJECT="${1:-}"
if [ -z "$SUBJECT" ] || [ -z "${SECOND_BRAIN_PLUGIN_ROOT:-}" ]; then
    echo "Usage: SECOND_BRAIN_RECAP_OF=... SECOND_BRAIN_PLUGIN_ROOT=... $0 <subject_folder>" >&2
    exit 2
fi
while [ "${SUBJECT%/}" != "$SUBJECT" ] && [ "$SUBJECT" != "/" ]; do SUBJECT="${SUBJECT%/}"; done

# Exported functions do not survive into this shell: it was started by a terminal
# multiplexer, not forked from the launcher. Checked rather than assumed, because the
# plugin cache holds several version directories and the one this command names may have
# been retired since the notice printed the command.
if [ ! -f "$SECOND_BRAIN_PLUGIN_ROOT/skills/common/obsidian_helpers.sh" ]; then
    echo "recap_child.sh: no plugin at $SECOND_BRAIN_PLUGIN_ROOT" >&2
    exit 2
fi
source "$SECOND_BRAIN_PLUGIN_ROOT/skills/common/obsidian_helpers.sh"
STATUS="$SECOND_BRAIN_PLUGIN_ROOT/skills/common/recap_status.sh"
LOG="$SUBJECT/recap.log"

if [ ! -f "$SUBJECT/session.md" ]; then
    echo "recap_child.sh: no session note at $SUBJECT/session.md" >&2
    exit 2
fi

# Anything other than `done` when this process ends is a failure a person should see.
# An exit 3 here is harmless: it means the subject already reached a terminal state,
# which is exactly the case that needs no correction.
post_check() {
    if [ "$(read_frontmatter_prop "$SUBJECT/session.md" recap_status)" != "done" ]; then
        "$STATUS" "$SUBJECT" failed >/dev/null 2>&1
    fi
    printf '%s exit status=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$(read_frontmatter_prop "$SUBJECT/session.md" recap_status)" >> "$LOG" 2>/dev/null || true
}
# EXIT alone. Adding HUP, TERM or INT runs post_check twice when a pane is closed,
# because the signal handler returns and the shell then exits.
trap 'post_check' EXIT

# The transcript is written asynchronously, so a recap that starts the moment the
# subject exits can read a file the subject is still finishing. Wait for the parent to
# be gone (empty under a hand-run launch), then require the file itself to be quiet:
# a PID that has exited is not proof that its last write landed.
i=0
while [ -n "${SECOND_BRAIN_PARENT_PID:-}" ] \
      && kill -0 "$SECOND_BRAIN_PARENT_PID" 2>/dev/null && [ "$i" -lt 240 ]; do
    sleep 0.5
    i=$(( i + 1 ))
done

T=$(read_frontmatter_prop "$SUBJECT/session.md" transcript_source)
if [ -n "$T" ] && [ -f "$T" ]; then
    last=-1; same=0; j=0
    while [ "$j" -lt 120 ] && [ "$same" -lt 5 ]; do
        sz=$(stat -f %z "$T" 2>/dev/null || echo 0)
        if [ "$sz" = "$last" ]; then same=$(( same + 1 )); else same=0; fi
        last="$sz"
        sleep 1
        j=$(( j + 1 ))
    done
fi

# Compare-and-set, so a second child for the same subject, or a hand-run recap that
# already holds the claim, is refused here and leaves without marking anything failed.
#
# Only exit 3 means that, though. The writer also exits 2 for a missing note or bad
# usage, and the shell exits 127 when the script is not where this process was told it
# would be — realistic, since the plugin cache holds several version directories and an
# orphaned one can still be referenced. Reporting those as "another recap holds the
# claim" would send someone looking for a process that never existed, and clearing the
# trap on them would leave the subject `requested` with nothing recording why.
"$STATUS" "$SUBJECT" running >/dev/null 2>&1
CLAIM=$?
if [ "$CLAIM" -eq 3 ]; then
    printf '%s claim refused status=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        "$(read_frontmatter_prop "$SUBJECT/session.md" recap_status)" >> "$LOG" 2>/dev/null || true
    # This process changed nothing and owns no outcome, so it must not mark failed.
    trap - EXIT
    echo "Another recap holds the claim on $(basename "$SUBJECT"); nothing to do."
    echo "  why: $LOG"
    exit 0
elif [ "$CLAIM" -ne 0 ]; then
    printf '%s claim error exit=%s status=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$CLAIM" \
        "$(read_frontmatter_prop "$SUBJECT/session.md" recap_status)" >> "$LOG" 2>/dev/null || true
    trap - EXIT
    echo "Could not claim $(basename "$SUBJECT"): $STATUS exited $CLAIM." >&2
    echo "Check that SECOND_BRAIN_PLUGIN_ROOT points at a plugin copy that still exists." >&2
    exit 1
fi

printf '%s start pane=%s name=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "${HERDR_PANE_ID:-none}" "${SECOND_BRAIN_RECAP_NAME:-unnamed}" >> "$LOG" 2>/dev/null || true

# Interactive and in the foreground, on this pane's TTY, so a person can watch it and
# step in. The trap runs when it exits, or when the pane is closed under it.
# No --settings: ADR-0003 keeps this session's hooks on, which is what registers it.
if [ -n "${SECOND_BRAIN_RECAP_NAME:-}" ]; then
    claude -n "$SECOND_BRAIN_RECAP_NAME" "/second-brain:session-recap $SUBJECT"
else
    claude "/second-brain:session-recap $SUBJECT"
fi
