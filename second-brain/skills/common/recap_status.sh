#!/bin/bash
# recap_status.sh - the one writer of a subject session's recap status, and of the
# description a recap decides for it.
#
#   recap_status.sh <session_folder> <state> [recap_session_folder] \
#                   [--project P] [--tags "a, b"] [--summary S] [--force]
#
# state is one of: requested running done failed exempt
#
# Compare-and-set, not a blind setter (ADR-0002). Every caller comes through here, so
# a transition the table below does not allow changes nothing and exits 3. That is
# what makes `requested -> running` succeed exactly once when a launched recap and a
# hand-run retry race for the same subject, and what stops a stale child's post-check
# from writing `failed` over a `done` that landed after it started waiting.
#
# The per-folder lock is the transaction, not the number of writes. Four property
# writes under one lock are indivisible to every other writer that honours it, and
# every writer does: session_end.sh takes this same lock around its whole
# read-rebuild-write, so a `done` written here cannot vanish under a later exit.
#
# It also writes the subject's description — project, tags, summary — because after a
# session ends the recap is the only thing that knows what the work was
# (ADR-0006). Those values overwrite unconditionally: by then the recap has read the
# whole conversation, so what is already on the note was an input to its decision,
# not a limit on it. The one exception is an empty tag list, which set_frontmatter_list
# refuses to write, since matching no canonical tag is not a decision to erase one.
#
# Exit: 0 written, 2 usage or no note, 3 transition refused.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
source "$SCRIPT_DIR/obsidian_helpers.sh"

usage() {
    cat >&2 <<'USAGE'
Usage: recap_status.sh <session_folder> <state> [recap_session_folder]
                       [--project P] [--tags "a, b"] [--summary S] [--force]

  state                requested | running | done | failed | exempt
  --project/--tags/--summary   the description; accepted on done and failed only
  --force              with state `requested`, reopen a subject already done
USAGE
    exit 2
}

FOLDER=""; STATE=""; RECAP_SESSION=""; FORCE=""
PROJECT=""; TAGS=""; SUMMARY=""
HAVE_PROJECT=0; HAVE_TAGS=0; HAVE_SUMMARY=0

# Presence is tracked separately from value, because writing an empty project is a
# real instruction: it is how a legacy directory basename gets cleared off a note
# that the recap could not place in any domain.
while [ $# -gt 0 ]; do
    case "$1" in
        --force)   FORCE=1 ;;
        --project) [ $# -ge 2 ] || usage; HAVE_PROJECT=1; PROJECT="$2"; shift ;;
        --tags)    [ $# -ge 2 ] || usage; HAVE_TAGS=1;    TAGS="$2";    shift ;;
        --summary) [ $# -ge 2 ] || usage; HAVE_SUMMARY=1; SUMMARY="$2"; shift ;;
        -*)        printf 'recap_status.sh: unknown option: %s\n' "$1" >&2; usage ;;
        *)
            if   [ -z "$FOLDER" ];        then FOLDER="$1"
            elif [ -z "$STATE" ];         then STATE="$1"
            elif [ -z "$RECAP_SESSION" ]; then RECAP_SESSION="$1"
            else printf 'recap_status.sh: unexpected argument: %s\n' "$1" >&2; usage
            fi ;;
    esac
    shift
done

[ -n "$FOLDER" ] && [ -n "$STATE" ] || usage

# The notice and the launcher both print folder paths with a trailing slash, and a
# person pasting one should not get a different lock than the hook took.
while [ "${FOLDER%/}" != "$FOLDER" ] && [ "$FOLDER" != "/" ]; do FOLDER="${FOLDER%/}"; done

case "$STATE" in
    requested|running|done|failed|exempt) ;;
    *) printf 'recap_status.sh: not a state: %s\n' "$STATE" >&2; usage ;;
esac

# Restricted to the two terminal-ish states the recap actually reaches, so a stray
# description on a `requested` stamp is a caught mistake rather than a silent write.
if [ "$HAVE_PROJECT$HAVE_TAGS$HAVE_SUMMARY" != "000" ]; then
    case "$STATE" in
        done|failed) ;;
        *) printf 'recap_status.sh: --project/--tags/--summary are for done or failed, not %s\n' \
               "$STATE" >&2; usage ;;
    esac
fi

# --force exists for one case: reopening a subject whose recap is done. Allowing it
# to force any state would give every other transition a way around the table.
if [ -n "$FORCE" ] && [ "$STATE" != "requested" ]; then
    printf 'recap_status.sh: --force applies to requested only\n' >&2
    usage
fi

MD="$FOLDER/session.md"
if [ ! -f "$MD" ]; then
    printf 'recap_status.sh: no session note at %s\n' "$MD" >&2
    exit 2
fi

LOG="$FOLDER/recap.log"

log_line() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >> "$LOG" 2>/dev/null || true; }

# The lock protocol lives in obsidian_helpers.sh, because session_end.sh takes the
# same lock around its read-rebuild-write and two copies of a spin-and-break-stale
# loop would drift apart. Unlike that hook, this script will not write without it:
# every guarantee here rests on reading the current state under the lock.
#
# The wait defaults to 2 s, which is right for a person or a recap that can afford to
# queue. A caller on a clock lowers it: SessionEnd has about 1.5 s for the whole hook and
# pays this wait twice, once for its own rewrite and once for this stamp, so it asks for
# a fraction of the default rather than risk being killed before the note is written.
if ! recap_lock_acquire "$FOLDER" "${SECOND_BRAIN_LOCK_ATTEMPTS:-40}"; then
    log_line "lock timeout pid=$$ wanted=$STATE"
    printf 'recap_status.sh: could not take the lock on %s\n' "$FOLDER" >&2
    exit 3
fi
# Only now, so a failed acquisition can never remove the holder's lock.
trap 'recap_lock_release "$FOLDER"' EXIT

# Read the current state under the lock. Reading it before would be a race with
# exactly the writer this lock exists to serialise against.
FROM=$(read_frontmatter_prop "$MD" recap_status)

allowed() {
    case "$1|$2" in
        "|requested"|"|exempt")            return 0 ;;
        "exempt|requested"|"exempt|running") return 0 ;;
        "requested|running"|"requested|failed") return 0 ;;
        "running|done"|"running|failed")   return 0 ;;
        "failed|running")                  return 0 ;;
    esac
    return 1
}

if ! allowed "$FROM" "$STATE"; then
    if [ -n "$FORCE" ]; then
        log_line "forced ${FROM:-empty}->$STATE pid=$$"
    else
        log_line "refused ${FROM:-empty}->$STATE pid=$$"
        printf 'recap_status.sh: %s -> %s is not allowed\n' "${FROM:-empty}" "$STATE" >&2
        exit 3
    fi
fi

# Description first, status last, all inside the one lock: a reader that sees `done`
# is then guaranteed to see the description that goes with it. Refused tag items land
# in recap.log as proposals, which is where the recap skill is told to look for them.
[ "$HAVE_PROJECT" -eq 1 ] && set_frontmatter_prop "$MD" project  "$PROJECT"
[ "$HAVE_TAGS"    -eq 1 ] && set_frontmatter_list "$MD" tags     "$TAGS" 2>>"$LOG"
[ "$HAVE_SUMMARY" -eq 1 ] && set_frontmatter_prop "$MD" summary  "$SUMMARY"

set_frontmatter_prop "$MD" recap_status "$STATE"
if [ "$STATE" = "done" ]; then
    set_frontmatter_prop "$MD" recapped_at "$(date -u +%Y-%m-%dT%H:%M:%S)"
    [ -n "$RECAP_SESSION" ] && set_frontmatter_prop "$MD" recap_session "$RECAP_SESSION"
fi

log_line "set ${FROM:-empty}->$STATE pid=$$"
exit 0
