#!/bin/bash
# recap_group.sh - recap a recap group: every session declared at launch to belong to it, in one session.
#
#   recap-group <key> --complete-at <UTC time> [--label k=v]... [--here]
#
# Reached through the stable path ~/.claude/plugins/config/second-brain/bin/recap-group, which the
# start hook keeps pointing at this file (ADR-0013). The caller is whatever declared the group at
# launch, with SECOND_BRAIN_RECAP_GROUP=<key> on each session it started, and now says the group is
# complete. It calls again until the answer is 0.
#
#   exit 0   settled: no member waits and none is alive. Stop calling.
#   exit 1   in progress, or waiting for members that are still alive. Call again later.
#   exit 2   needs a person. The line says why. Keep calling; a later 0 resolves it.
#
# One line on stdout, the first and the only one, says why it answered as it did. Anything else it has
# to say goes to the group's log, recap.log in the group's state folder. It reads this plugin's session
# notes, Claude Code's session registry and the terminal host, and nothing of the caller's.
#
# The call itself returns within about a second. What takes time is the run it starts, the same script
# with --run, detached: it writes one digest per member, claims the members, starts one recap session,
# waits for that session to end, and settles what the session left unsettled.
#
# What the first caller does at each call shapes both halves (its package's notes of 2026-11-11,
# verified there in its code). It is a tick in a crontab: stdin is closed, stdout and stderr are files
# the next call replaces, the working folder is the caller's own state folder, and the call has 30
# seconds. When the call returns, the caller sends SIGKILL to the call's whole process group. So the
# run leaves that group and its session before the call returns, keeps a log of its own, and leaves
# the caller's folder.
#
# Everything below is a function, and the last line calls main and exits. Bash reads a script as it
# goes, and a run lives as long as a recap does: read whole before anything runs, the script cannot be
# changed under a run that is waiting.
set -uo pipefail

# A caller may close stdin. A closed descriptor 0 is handed to the next file anything here opens, and
# a tool that falls back to reading stdin then fails on it, so it is opened on nothing instead.
{ : <&0; } 2>/dev/null || exec 0</dev/null

# The stable path is a link to this file, so the plugin copy is found through the link. Resolved by
# hand: `readlink -f` is GNU, and a macOS before 12.3 has no such option.
SELF="${BASH_SOURCE[0]:-$0}"
while [ -L "$SELF" ]; do
    LINK=$(readlink "$SELF")
    case "$LINK" in /*) SELF="$LINK" ;; *) SELF="$(dirname "$SELF")/$LINK" ;; esac
done
SCRIPT_DIR="$(cd "$(dirname "$SELF")" && pwd)"
SELF="$SCRIPT_DIR/$(basename "$SELF")"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$PLUGIN_ROOT/skills/common/get_kb_path.sh"
source "$PLUGIN_ROOT/skills/common/obsidian_helpers.sh"

STATUS="$PLUGIN_ROOT/skills/common/recap_status.sh"
CHILD="$PLUGIN_ROOT/hooks/scripts/recap_child.sh"
PARSE="$PLUGIN_ROOT/skills/session-recap/scripts/parse_transcript.sh"
STABLE="${PLUGIN_CONFIG_FILE%/*}/bin/recap-group"

# A run in progress longer than this needs a person: the recap's one question may be waiting for an
# answer with nobody there (ADR-0007), or the session hangs. The first run waits this long after
# --complete-at for members still alive, so that it can take the launcher's own session with it.
RUN_LIMIT_S=10800
ALIVE_WAIT_S=3600

usage_text() {
    cat <<'USAGE'
Usage: recap-group <key> --complete-at <UTC time> [--label k=v]... [--here]

Recaps the recap group <key>: the sessions declared at launch to belong to it, in one
recap session. Call it again until it exits 0.

  <key>              the group's key: letters, digits, . _ -, at most 64 characters
  --complete-at T    when the group was declared complete, in UTC, as `date -u +%FT%TZ`
                     prints it. Members still alive are waited for until an hour after it.
  --label k=v        a label for the terminal the recap session starts in (repeatable).
                     From outside a terminal, the labels are what names a place for the
                     session on the Herdr app's core; without one, nothing starts.
  --here             run the recap in this terminal, for a person: where no terminal
                     host can start a session, or after three runs that got nowhere

  exit 0  settled: no member waits and none is alive
  exit 1  in progress, or waiting for members still alive: call again
  exit 2  needs a person; the line printed says why
USAGE
}

# A call that cannot be understood needs a person. The reason comes first and on stdout, because the
# caller reads the first line; the usage follows on stderr.
# Args: $1=what is wrong
bad_call() {
    printf 'needs a person: %s\n' "$1"
    usage_text >&2
    exit 2
}

now_utc() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { printf '%s %s\n' "$(now_utc)" "$*" >> "$LOG" 2>/dev/null || true; }

# A UTC time as the caller's `date -u +%FT%TZ` prints one, a fraction of a second allowed, to seconds
# since the epoch. Branched on the platform like every date call here: GNU reads -d, BSD reads -j -f.
# Args: $1=time
# Returns: the epoch on stdout; non-zero when it is not such a time
utc_epoch() {
    local t="${1%Z}"
    t="${t%%.*}"
    case "$t" in
        [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]) ;;
        *) return 1 ;;
    esac
    if [[ "$OSTYPE" == darwin* ]]; then date -j -u -f "%Y-%m-%dT%H:%M:%S" "$t" +%s 2>/dev/null
    else date -u -d "$t" +%s 2>/dev/null; fi
}

# The reverse, for a line a person reads.
# Args: $1=epoch
epoch_utc() {
    if [[ "$OSTYPE" == darwin* ]]; then date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ
    else date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ; fi
}

# The local day of an instant, which is how the vault dates a daily log.
# Args: $1=epoch
epoch_day() {
    if [[ "$OSTYPE" == darwin* ]]; then date -r "$1" +%Y-%m-%d
    else date -d "@$1" +%Y-%m-%d; fi
}

# ── The call ─────────────────────────────────────────────────────────────────────

# The one line and the exit code. The line is also logged, once: a caller repeats the call every few
# minutes for as long as a member is alive, and the same answer a hundred times over says nothing.
# Args: $1=exit code, $2=line
answer() {
    if [ "$(cat "$STATE/answer" 2>/dev/null)" != "$1 $2" ]; then
        printf '%s %s\n' "$1" "$2" > "$STATE/answer" 2>/dev/null
        log "group answer $1: $2"
    fi
    printf '%s\n' "$2"
    exit "$1"
}

# Step 2. The members: every note whose recap_group is the key, in every date folder. The notice
# scans fourteen folders for speed, and a group can span weeks. grep narrows three thousand notes to
# the group's, which awk then reads: 0.25 s for the pair against 0.5 s for awk alone, measured on a
# vault of 3000 notes with 200 members. The key is compared whole by awk; grep's pattern only has to
# let every member through, and a dot in a key is escaped so that it lets nothing else through.
# Returns: one line per member, `<status>US<session id>US<name>US<folder>`, US the unit separator, so
#          that an empty status or name stays a field of its own
scan_members() {
    local key_re="${KEY//./\\.}"
    find "$KB_PATH/_sessions" -mindepth 3 -maxdepth 3 -name session.md -print0 2>/dev/null \
        | xargs -0 grep -l --null -E "^recap_group:[[:space:]]*\"?${key_re}\"?[[:space:]]*\$" 2>/dev/null \
        | xargs -0 awk -v key="$KEY" '
            # Quoted or bare: every writer here quotes, and Obsidian drops the quotes it does not
            # need whenever a person saves a note.
            function val(s) { sub(/^[a-z_]+:[[:space:]]*/, "", s); gsub(/^"|"$/, "", s); return s }
            function emit() {
                if (f == "" || g != key) return
                sub(/\/session\.md$/, "", f)
                printf "%s\037%s\037%s\037%s\n", st, id, nm, f
            }
            FNR == 1 { emit(); fm = 0; st = ""; g = ""; id = ""; nm = ""; f = FILENAME }
            /^---$/  { fm++; next }
            fm != 1  { next }
            /^recap_group:/  { g = val($0); next }
            /^recap_status:/ { st = val($0); next }
            /^session_id:/   { id = val($0); next }
            /^session_name:/ { nm = val($0); next }
            END { emit() }
        ' 2>/dev/null
}

# Claude Code's session registry: one JSON file per live session under ~/.claude/sessions, naming its
# conversation (`sessionId`), its process (`pid`) and when that process started (`procStart`). It is
# not documented. So an entry that does not parse, or that names no conversation, means the format is
# not the one known here, and the registry counts as unreadable, which means alive (ADR-0013).
# Sets: REGISTRY, one `<session id>|<pid>|<start>` line per entry
# Returns: 0 when it was read, 1 when it cannot be
read_registry() {
    local dir="$HOME/.claude/sessions" files
    REGISTRY=""
    [ -d "$dir" ] || return 1
    files=("$dir"/*.json)
    [ -e "${files[0]}" ] || return 0      # no session is alive at all
    REGISTRY=$(jq -r 'if (.sessionId | type) == "string"
                      then "\(.sessionId)|\(.pid // "")|\(.procStart // "")"
                      else error("an entry that names no conversation") end' "${files[@]}" 2>/dev/null) || return 1
    return 0
}

# Does the registry show a live process for this session? An entry that names no pid cannot be
# checked, and counts as alive for the same reason an unreadable registry does.
# Args: $1=session id
session_alive() {
    local id pid start
    case "$REGISTRY" in *"$1"*) ;; *) return 1 ;; esac
    while IFS='|' read -r id pid start; do
        [ "$id" = "$1" ] || continue
        case "$pid" in ''|*[!0-9]*) return 0 ;; esac
        process_runs "$pid" "$start" && return 0
    done <<< "$REGISTRY"
    return 1
}

# Step 3, for a member with no status and no live process: it ended without its end hook, killed or
# cut off at the hook's budget. Stamp it on the hook's behalf by the hook's own measure, `deferred`
# at five assistant records and `exempt` under five or with no transcript, with the reason in its
# recap.log. The hook would also have written the transcript pointer, which the digest and the recap
# need, so the transcript is found from the note's cwd and id and the pointer written. A transcript
# that is there and cannot be read is deferred: the run then reports it, which a silent skip would not.
# Args: $1=folder, $2=session id, $3=name
# Returns: the status the note carries afterwards, on stdout
stamp_on_behalf() {
    local md="$1/session.md" transcript cwd turns to=deferred why="it ended without its end hook"
    transcript=$(read_frontmatter_prop "$md" transcript_source)
    if [ -z "$transcript" ]; then
        cwd=$(read_frontmatter_prop "$md" cwd)
        transcript=$(session_transcript_path "$cwd" "$2")
        # Under the note's lock, and only while the pointer is still empty: a hook that ran after
        # all has written the real one.
        if [ -n "$transcript" ] && recap_lock_acquire "$1" 10; then
            [ -n "$(read_frontmatter_prop "$md" transcript_source)" ] \
                || set_frontmatter_prop "$md" transcript_source "$transcript"
            recap_lock_release "$1"
        fi
    fi
    if [ -z "$transcript" ] || [ ! -f "$transcript" ]; then
        to=exempt; why="it ended without its end hook and left no transcript"
    else
        turns=$(grep -c -m5 '"type":"assistant"' "$transcript" 2>/dev/null)
        case "$turns" in
            ''|*[!0-9]*) ;;
            *) [ "$turns" -ge 5 ] || { to=exempt; why="it ended without its end hook, with fewer than five assistant records"; } ;;
        esac
    fi
    if "$STATUS" "$1" "$to" >/dev/null 2>&1; then
        printf '%s %s: %s; stamped for recap group %s by the group command\n' \
            "$(now_utc)" "$to" "$why" "$KEY" >> "$1/recap.log" 2>/dev/null
        log "group stamped $3 $to on its end hook's behalf"
    fi
    read_frontmatter_prop "$md" recap_status
}

# Where a member's transcript should be: the note's pointer, and for a note with none, what its cwd
# and id lead to. Nothing here says the file is there.
# Args: $1=folder, $2=session id (optional)
# Returns: the path on stdout; empty when the note names none and none is found
member_transcript_pointer() {
    local md="$1/session.md" id="${2:-}" t
    t=$(read_frontmatter_prop "$md" transcript_source)
    if [ -z "$t" ]; then
        [ -n "$id" ] || id=$(read_frontmatter_prop "$md" session_id)
        [ -n "$id" ] || id="${1##*/}"
        t=$(session_transcript_path "$(read_frontmatter_prop "$md" cwd)" "$id")
    fi
    printf '%s' "$t"
}

# A member's transcript, when it is there and can be read. The call and the run both ask here, so that
# what the call takes for unreadable is exactly what the run fails as unreadable.
# Args: $1=folder, $2=session id (optional)
# Returns: the path on stdout; 1 when the transcript is missing or cannot be read
member_transcript() {
    local t
    t=$(member_transcript_pointer "$1" "${2:-}")
    [ -n "$t" ] && [ -f "$t" ] && [ -r "$t" ] || return 1
    printf '%s' "$t"
}

# Why a member's transcript cannot be had, in the words the group's daily log entry gives a reader:
# which of the three it is, and the file it is about.
# Args: $1=folder, $2=session id (optional)
member_unreadable_why() {
    local t
    t=$(member_transcript_pointer "$1" "${2:-}")
    if [ -z "$t" ]; then printf 'its note names no transcript, and none was found for its session id'
    elif [ ! -f "$t" ]; then printf 'its transcript is missing: %s' "$t"
    else printf 'its transcript cannot be read: %s' "$t"
    fi
}

# Up to three names and how many more, for a line a person reads.
# Args: $1=names joined by ", ", $2=how many there are
some_names() {
    local shown rest
    shown=$(printf '%s' "$1" | awk -F', ' '{ n = (NF < 3) ? NF : 3; for (i = 1; i <= n; i++) printf "%s%s", (i > 1 ? ", " : ""), $i }')
    rest=$(( $2 - 3 ))
    if [ "$rest" -gt 0 ]; then printf '%s and %d more' "$shown" "$rest"; else printf '%s' "$shown"; fi
}

# The count of runs in a row that ended with no member done. Three of them and the command stops
# starting runs and says it needs a person.
failures() {
    local n
    n=$(cat "$STATE/failures" 2>/dev/null)
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
    printf '%s' "$n"
}

call_main() {
    local mode now complete_epoch run_pid run_start run_at run_term run_alive="" run_dead=""
    local claimed="" st id nm folder label ours alive
    local n=0 n_done=0 n_exempt=0 n_foreign=0 n_alive=0 n_wait=0 n_unreadable=0 ours_n=0 ours_done=0 ours_open=0
    local wait_list="" alive_names="" unreadable_names="" where since byhand fails host line i l
    local -a run_args

    recap_group_key_valid "$KEY" \
        || bad_call "$KEY is not a recap group key (letters, digits, . _ -, at most 64 characters)"
    complete_epoch=$(utc_epoch "$COMPLETE_AT") && [ -n "$complete_epoch" ] \
        || bad_call "--complete-at $COMPLETE_AT is not a UTC time such as 2026-11-11T06:28:11Z"

    # Step 1. The command acts under auto_recap `on` only. Anything else: settled, and nothing changes.
    mode=$(get_plugin_config_value auto_recap off)
    if [ "$mode" != "on" ]; then
        printf 'settled: auto_recap is %s, not on, so no group recap runs here\n' "$mode"
        exit 0
    fi
    KB_PATH=$(get_kb_path 2>/dev/null) || {
        printf 'needs a person: the knowledge bank is not configured, or its folder is gone\n'
        exit 2; }

    # One call at a time for a key, so two callers cannot start two runs. The lock is the notes' own,
    # on the group's state folder: held for this call, about a second, and broken when a minute old.
    # A key that turns out to have no member leaves no state folder behind.
    mkdir -p "$STATE" 2>/dev/null || { printf 'needs a person: cannot create %s\n' "$STATE"; exit 2; }
    if ! recap_lock_acquire "$STATE" 10; then
        printf 'in progress: another call for recap group %s is deciding\n' "$KEY"
        exit 1
    fi
    trap 'recap_lock_release "$STATE"; rmdir "$STATE" 2>/dev/null' EXIT
    now=$(date +%s)

    # Steps 4 and 5 need one fact before the members are sorted: whether the run on record is alive.
    # The record names the run's own process and, once it has started one, its recap session's; either
    # one alive is a run alive. Only while a record exists is members.tsv the list of what that run
    # claimed: once a run has been settled the file is history, and a member that reads running again
    # is somebody else's.
    if [ -f "$STATE/run" ]; then
        run_pid=$(state_value "$STATE/run" pid);  run_start=$(state_value "$STATE/run" start)
        run_at=$(state_value "$STATE/run" at);    run_term=$(state_value "$STATE/run" terminal)
        case "$run_at" in ''|*[!0-9]*) run_at="$now" ;; esac
        if process_runs "$run_pid" "$run_start" \
           || process_runs "$(state_value "$STATE/child" pid)" "$(state_value "$STATE/child" start)"; then
            run_alive=1
        else
            run_dead=1
        fi
        claimed=$'\n'"$(cut -f1 "$STATE/members.tsv" 2>/dev/null)"$'\n'
    fi

    # Step 3. Sort each member.
    REG_OK=""; read_registry && REG_OK=1
    while IFS=$'\037' read -r st id nm folder; do
        [ -n "$folder" ] || continue
        n=$((n + 1))
        [ -n "$id" ] || id="${folder##*/}"      # a session folder is named by its id
        label="${nm:-${id:0:8}}"
        ours=""; case "$claimed" in *$'\n'"$folder"$'\n'*) ours=1 ;; esac

        # Alive by the registry, whatever its status: a session stamped at an earlier exit and since
        # resumed is writing its transcript again. With no registry to read, a member its end hook
        # stamped has ended by that stamp, and one with no status counts as alive.
        alive=""
        if [ -n "$REG_OK" ]; then session_alive "$id" && alive=1
        elif [ -z "$st" ]; then alive=1
        fi
        if [ -z "$alive" ] && [ -z "$st" ]; then
            st=$(stamp_on_behalf "$folder" "$id" "$label")
            [ -n "$st" ] || alive=1        # the stamp did not land: still ending, look again next call
        fi

        # Step 5. The run on record is dead and this member still reads running: the run died
        # without its exit check, so nothing will ever mark it. Failed, with the reason the notice shows.
        if [ -n "$ours" ]; then
            ours_n=$((ours_n + 1))
            if [ "$st" = "running" ] && [ -n "$run_dead" ]; then
                printf '%s failed reason=%s\n' "$(now_utc)" \
                    "its group recap ($KEY) ended before it was marked done" >> "$folder/recap.log" 2>/dev/null
                "$STATUS" "$folder" failed >/dev/null 2>&1 && st=failed
            fi
            if [ "$st" = "done" ]; then ours_done=$((ours_done + 1)); else ours_open=$((ours_open + 1)); fi
        fi

        if [ -n "$alive" ]; then
            n_alive=$((n_alive + 1)); alive_names="${alive_names:+$alive_names, }$label"
            continue
        fi
        case "$st" in
            done)   n_done=$((n_done + 1)) ;;
            exempt) n_exempt=$((n_exempt + 1)) ;;
            deferred|requested)
                    n_wait=$((n_wait + 1)); wait_list="$wait_list$folder"$'\n' ;;
            failed)
                    # Failed, with a transcript to read: its run died, or its recap gave up, and it
                    # waits for the next run. Failed, and its transcript is missing or cannot be read:
                    # no run can do anything for it, so it does not wait, and the group settles
                    # without it. Asked at every call and recorded nowhere, so a transcript that can
                    # be read again puts its member back in line.
                    if member_transcript "$folder" "$id" >/dev/null; then
                        n_wait=$((n_wait + 1)); wait_list="$wait_list$folder"$'\n'
                    else
                        n_unreadable=$((n_unreadable + 1))
                        unreadable_names="${unreadable_names:+$unreadable_names, }$label"
                    fi ;;
            running)
                    # Claimed. By the live run on record, which the next step answers for; else by
                    # another recap session, one a person started for this member alone.
                    [ -n "$ours" ] || n_foreign=$((n_foreign + 1)) ;;
            *)      n_foreign=$((n_foreign + 1)) ;;
        esac
    done < <(scan_members)

    if [ "$n" -eq 0 ]; then
        printf 'settled: no session belongs to recap group %s\n' "$KEY"
        exit 0
    fi
    # From here on the group has state to keep, so its folder stays.
    trap 'recap_lock_release "$STATE"' EXIT

    # Step 5, the rest: the dead run is settled. A run that got a member done made progress.
    if [ -n "$run_dead" ]; then
        if [ "$ours_done" -gt 0 ]; then echo 0 > "$STATE/failures"
        else echo $(( $(failures) + 1 )) > "$STATE/failures"; fi
        rm -f "$STATE/run" "$STATE/child"
        log "group settled a run that died without its exit check: $ours_done of $ours_n members done"
    fi

    # Step 4. A run for this key is alive, and has members it has not got done, or has claimed none
    # yet: in progress. A run whose every member is done is over; its session is closing, or a person
    # keeps it, and neither is a reason to hold back members that ended since.
    if [ -n "$run_alive" ] && { [ "$ours_open" -gt 0 ] || [ "$ours_n" -eq 0 ]; }; then
        where="${run_term:+ in hc terminal $run_term}"
        since=$(epoch_utc "$run_at")
        if [ $(( now - run_at )) -gt "$RUN_LIMIT_S" ]; then
            answer 2 "needs a person: the recap of group $KEY, started $since$where, has been in progress over 3 hours ($ours_done of $ours_n members done); its one question may be waiting for an answer, or it hangs"
        fi
        answer 1 "in progress: the recap of group $KEY, started $since$where, has $ours_done of $ours_n members done"
    fi

    # Steps 6 and 7. Nothing waits.
    if [ "$n_wait" -eq 0 ]; then
        if [ "$n_alive" -gt 0 ]; then
            answer 1 "waiting: $n_alive of $n members $([ "$n_alive" -eq 1 ] && echo is || echo are) still alive ($(some_names "$alive_names" "$n_alive")); nothing waits to be recapped"
        fi
        if [ "$n_foreign" -gt 0 ]; then
            answer 1 "in progress: $n_foreign $([ "$n_foreign" -eq 1 ] && echo "member is" || echo "members are") being recapped by another recap session"
        fi
        line="settled: $n $([ "$n" -eq 1 ] && echo member || echo members), $n_done done and $n_exempt exempt"
        if [ "$n_unreadable" -gt 0 ]; then
            line="$line; $n_unreadable failed because $([ "$n_unreadable" -eq 1 ] && echo its || echo their) transcript is missing or cannot be read ($(some_names "$unreadable_names" "$n_unreadable"))"
        fi
        answer 0 "$line"
    fi

    # Step 8. Members wait, a member is alive, and the hour after --complete-at has not passed.
    if [ "$n_alive" -gt 0 ] && [ "$now" -lt $(( complete_epoch + ALIVE_WAIT_S )) ]; then
        answer 1 "waiting: $n_alive $([ "$n_alive" -eq 1 ] && echo "member is" || echo "members are") still alive ($(some_names "$alive_names" "$n_alive")) and $n_wait $([ "$n_wait" -eq 1 ] && echo waits || echo wait) to be recapped; a run starts once they have ended, or at $(epoch_utc $(( complete_epoch + ALIVE_WAIT_S )))"
    fi

    # Step 9. Start a run over the members that wait. Each thing that stops it needs a person, who can
    # run the recap in a terminal of their own with --here.
    #
    # Where no terminal host can start a session from outside a terminal, nothing starts. The Herdr
    # app's core can, through hc; the Herdr TUI splits a pane it is given and cannot. Which of them
    # this call may use is read from the call, not from which binaries are installed: this machine
    # has both (ADR-0011). In a Herdr app pane, the core that owns the pane starts the session. From
    # outside any terminal, a tick in a crontab, the labels are the fact: a caller on the core passes
    # the labels of the tab the session is to open in, and one whose loop runs on the TUI passes none,
    # so a call with no label has named no place where a person would find the session.
    byhand=$(printf '%q %q --complete-at %q --here' \
        "$([ -e "$STABLE" ] && printf '%s' "$STABLE" || printf '%s' "$SELF")" "$KEY" "$COMPLETE_AT")
    if [ -z "$HERE" ]; then
        host=$(terminal_host)
        if [ "$host" = "herdr-tui" ] || [ ! -x "$(hc_bin)" ] \
           || { [ "$host" = "none" ] && [ "${#LABELS[@]}" -eq 0 ]; }; then
            answer 2 "needs a person: no terminal host here can start a session from outside a terminal, and $n_wait $([ "$n_wait" -eq 1 ] && echo "member waits" || echo "members wait") to be recapped; in a terminal of your own, run: $byhand"
        fi
        # The run has to leave this call's process group and session: the caller kills the group the
        # moment the call returns. Only the double fork does that, and it needs perl; the fallback
        # without perl stays in the group and would die with the call.
        command -v perl >/dev/null 2>&1 \
            || answer 2 "needs a person: perl is not on this caller's PATH, and without it a run cannot outlive the call that starts it; in a terminal of your own, run: $byhand"
    fi
    # The session is given this caller's PATH as it is, so claude has to be on it.
    command -v claude >/dev/null 2>&1 \
        || answer 2 "needs a person: claude is not on this caller's PATH, so a recap session could not start"
    # Three runs in a row that got no member done: a recap that keeps dying is not retried for ever.
    fails=$(failures)
    if [ -z "$HERE" ] && [ "$fails" -ge 3 ]; then
        answer 2 "needs a person: three runs in a row ended with no member of group $KEY done (see $LOG); to run it by hand, in a terminal of your own: $byhand"
    fi

    printf '%s' "$wait_list" > "$STATE/waiting"
    rm -f "$STATE/run" "$STATE/started"
    run_args=("$KEY" --complete-at "$COMPLETE_AT" --run)
    for l in ${LABELS[@]+"${LABELS[@]}"}; do run_args+=(--label "$l"); done

    if [ -n "$HERE" ]; then
        # In this terminal, for the person at it. The run replaces this process, so the record it
        # will write names the same pid: written here first, under the lock, it leaves no moment in
        # which another caller finds members waiting and no run.
        printf 'pid=%s\nstart=%s\nat=%s\n' "$$" "$(proc_start_time $$)" "$now" > "$STATE/run"
        log "group starting a run over $n_wait members in the caller's terminal"
        recap_lock_release "$STATE"
        trap - EXIT
        exec "$SELF" "${run_args[@]}" --here
    fi

    # Detached, and waited for until it has put itself on record: the lock is held until then, so the
    # next caller finds the run and not just the members it has yet to claim.
    spawn_detached "$SELF" "${run_args[@]}"
    i=0
    while [ ! -f "$STATE/started" ] && [ "$i" -lt 100 ]; do sleep 0.05; i=$((i + 1)); done
    if [ ! -f "$STATE/started" ]; then
        # Counted as a run that got nowhere, or a run that can never start would be retried for ever
        # without a word.
        echo $(( fails + 1 )) > "$STATE/failures"
        answer 1 "started: a recap of $n_wait $([ "$n_wait" -eq 1 ] && echo member || echo members) of group $KEY, which has not reported in yet"
    fi
    answer 1 "started: a recap of $n_wait $([ "$n_wait" -eq 1 ] && echo member || echo members) of group $KEY"
}

# ── The run ──────────────────────────────────────────────────────────────────────

# To the group's log, and to the terminal as well when a person runs it there.
say() {
    log "run $*"
    [ -z "$HERE" ] || printf '%s\n' "$*"
}

# One member's digest, for the recap session to read in place of its transcript: a header, what
# parse_transcript.sh extracts from the transcript, and the member's own Debrief blocks. The digest is
# code-made on purpose: a transcript is megabytes, its digest a few kilobytes in a second or two, so
# the step that is paid once for each member costs no model at all (ADR-0013).
# Args: $1=folder
# Sets: D_NAME, for the caller's messages
# Returns: 0 with one row appended to ready.tsv; 1 when the member's transcript is missing or cannot
#          be read; 2 when it is there and no digest could be made of it, which is a fault here and
#          not the member's
digest_member() {
    local folder="$1" md="$1/session.md" id name cwd transcript started ended project records body out
    { IFS= read -r id; IFS= read -r name; IFS= read -r cwd
      IFS= read -r started; IFS= read -r ended; IFS= read -r project; } \
        < <(read_frontmatter_props "$md" session_id session_name cwd started_at ended_at project)
    [ -n "$id" ] || id=$(basename "$folder")
    D_NAME="${name:-${id:0:8}}"
    transcript=$(member_transcript "$folder" "$id") || return 1
    body=$("$PARSE" "$transcript" all 2>/dev/null) || return 2
    [ -n "$body" ] || return 2
    records=$(grep -c '"type":"assistant"' "$transcript" 2>/dev/null)
    case "$records" in ''|*[!0-9]*) records=0 ;; esac
    # The domain the member resolves to: what its note says when that is a domain, else what its
    # directory maps to. The group's documents go under the one most members resolve to.
    project=$(validate_project "$project" "$KB_PATH")
    [ -n "$project" ] || project=$(resolve_project "$cwd" "$KB_PATH")
    out="$STATE/digests/$id.md"
    {
        printf '# Digest of %s\n\n' "$D_NAME"
        printf -- '- recap group: %s\n- session id: %s\n- session folder: %s\n- transcript: %s\n' \
            "$KEY" "$id" "$folder" "$transcript"
        printf -- '- started: %s\n- ended: %s\n- assistant records: %s\n- project: %s\n\n' \
            "${started:-unknown}" "${ended:-unknown}" "$records" "${project:-none}"
        printf '%s\n\n' "$body"
        "$PARSE" "$transcript" debriefs 2>/dev/null
    } > "$out.tmp" && mv -f "$out.tmp" "$out" || return 2
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$folder" "$id" "${name:--}" "${project:--}" "$records" "$out" >> "$STATE/ready.tsv"
    return 0
}

# The members that the group has left out because their transcripts are missing or cannot be read,
# for the group's daily log entry: one row each, `<folder><TAB><session id><TAB><name><TAB><reason>`,
# a member with no name going by the first eight characters of its id. The start-of-session notice
# shows a failed recap only from the fourteen newest date folders, and a group spans weeks, so the
# entry is where a person finds these members (the owner's decision of 2026-11-11). The whole list as
# it stands now, not only the members this run tried: it is the same question the call asks of every
# failed member, asked here of the group, so a member an earlier run left out is on it still, and one
# that can be read again, and that this run has therefore claimed, is not. Written by every run, the
# one that starts no session included. An empty file says that the group has left nobody out.
# Sets: LEFT_OUT, how many there are
write_left_out() {
    local st id nm folder tmp="$STATE/left-out.tsv.$$"
    LEFT_OUT=0
    : > "$tmp"
    while IFS=$'\037' read -r st id nm folder; do
        [ -n "$folder" ] && [ "$st" = "failed" ] || continue
        [ -n "$id" ] || id="${folder##*/}"
        member_transcript "$folder" "$id" >/dev/null && continue
        printf '%s\t%s\t%s\t%s\n' "$folder" "$id" "${nm:-${id:0:8}}" "$(member_unreadable_why "$folder" "$id")" >> "$tmp"
        LEFT_OUT=$((LEFT_OUT + 1))
    done < <(scan_members)
    mv -f "$tmp" "$STATE/left-out.tsv"
}

# What the run leaves behind when its session has ended, or never started: a member it claimed that
# still reads running is failed, with the reason the notice shows; a run that got a member done made
# progress, and one that tried and got none done counts towards the three; and the terminal of a run
# that got every member done is removed, which closes its tab. A terminal with a member short of done
# stays, so that a person can read why. A run that had nothing to try, every member it was given
# unreadable or claimed by another recap, counts for nothing: it attempted no recap. The record and the
# count are touched only while the record still names this run: a later run for members that ended
# since may have taken its place.
# Args: $1=hc terminal address, empty when the run started none
# Sets: RUN_DONE, RUN_TOTAL
finish_run() {
    local addr="${1:-}" st folder i=0
    RUN_DONE=0; RUN_TOTAL=0
    while IFS=$'\t' read -r st folder; do
        [ -n "$folder" ] || continue
        RUN_TOTAL=$((RUN_TOTAL + 1))
        case "$st" in
            done) RUN_DONE=$((RUN_DONE + 1)) ;;
            running)
                printf '%s failed reason=%s\n' "$(now_utc)" \
                    "its group recap ($KEY) ended before it was marked done" >> "$folder/recap.log" 2>/dev/null
                "$STATUS" "$folder" failed >/dev/null 2>&1 ;;
        esac
    done < <(printf '%s' "$RUN_MEMBERS" | recap_member_statuses)
    if [ "$(state_value "$STATE/run" pid)" = "$$" ]; then
        if [ "$RUN_DONE" -gt 0 ]; then echo 0 > "$STATE/failures"
        elif [ $(( RUN_TOTAL + RUN_UNDIGESTED )) -gt 0 ]; then echo $(( $(failures) + 1 )) > "$STATE/failures"
        fi
        rm -f "$STATE/run" "$STATE/child"
    fi
    say "ended: $RUN_DONE of $RUN_TOTAL members done"
    if [ -n "$addr" ] && [ "$RUN_TOTAL" -gt 0 ] && [ "$RUN_DONE" -eq "$RUN_TOTAL" ]; then
        # The terminal is finished a moment after its program is gone, and hc removes only a
        # finished one, so the removal is tried for a few seconds.
        while [ "$i" -lt 10 ]; do
            if "$(hc_bin)" rm "$addr" >/dev/null 2>&1; then say "removed the finished terminal $addr"; return 0; fi
            sleep 1; i=$((i + 1))
        done
        say "could not remove the finished terminal $addr; hc rm $addr closes its tab"
    fi
    return 0
}

run_main() {
    local folder row total i=0 why project cmd try addr="" run_json run_err child_pid child_start claimed
    local complete_epoch poll start_wait
    local -a label_args

    KB_PATH=$(get_kb_path 2>/dev/null) || { log "run stopped: no knowledge bank"; return 2; }
    complete_epoch=$(utc_epoch "$COMPLETE_AT") || complete_epoch=$(date +%s)
    # Validated, not trusted: an unusable value would make sleep fail at once and the waits spin.
    poll="${SECOND_BRAIN_GROUP_POLL_S:-5}";        case "$poll" in ''|*[!0-9]*) poll=5 ;; esac
    start_wait="${SECOND_BRAIN_GROUP_START_S:-60}"; case "$start_wait" in ''|*[!0-9]*) start_wait=60 ;; esac

    # Out of the caller's working folder, which is the caller's own state folder: this process lives
    # as long as a recap does, and nothing of it belongs there. Every path below is absolute.
    [ -n "$HERE" ] || cd "$STATE" 2>/dev/null || cd / 2>/dev/null

    # On record before anything else, so that a caller that asks finds a run alive; `started` is what
    # the call that began this run waits for. The members file starts empty: it lists what this run
    # claims, and the last run's list is history.
    mkdir -p "$STATE/digests"
    printf 'pid=%s\nstart=%s\nat=%s\n' "$$" "$(proc_start_time $$)" "$(date +%s)" > "$STATE/run.$$" \
        && mv -f "$STATE/run.$$" "$STATE/run"
    rm -f "$STATE/child" "$STATE/ready.tsv"
    : > "$STATE/members.tsv"
    : > "$STATE/started"
    RUN_MEMBERS=""; RUN_UNDIGESTED=0

    # 1 and 2. One digest per member. A member whose transcript is missing or cannot be read is failed
    # with its reason and left out; the rest of the group goes on, and from then on that member does
    # not wait (the call asks the same question of it). The claim comes first there because the only
    # way from deferred to failed is through running, which keeps the table as it is. A transcript that
    # is there and cannot be digested is not the same thing: that is a fault here, a parser that broke,
    # so its member is failed with that reason, waits, and counts as a member this run tried. A broken
    # parser then ends at a person after three runs, never at a group settled with every member failed.
    total=$(grep -c '' "$STATE/waiting" 2>/dev/null); case "$total" in ''|*[!0-9]*) total=0 ;; esac
    say "began for $total $([ "$total" -eq 1 ] && echo member || echo members) of group $KEY"
    while IFS= read -r folder; do
        [ -n "$folder" ] || continue
        i=$((i + 1))
        digest_member "$folder"
        case $? in
            0)  [ -z "$HERE" ] || printf '  digest %d of %d: %s\n' "$i" "$total" "$D_NAME"
                continue ;;
            1)  why="its transcript is missing or cannot be read" ;;
            *)  why="its transcript could not be digested"; RUN_UNDIGESTED=$((RUN_UNDIGESTED + 1)) ;;
        esac
        if "$STATUS" "$folder" running >/dev/null 2>&1; then
            printf '%s failed reason=%s\n' "$(now_utc)" \
                "$why, so the recap of group $KEY left it out" >> "$folder/recap.log" 2>/dev/null
            "$STATUS" "$folder" failed >/dev/null 2>&1
            say "left out $D_NAME: $why"
        else
            say "left out $D_NAME: $why, and its claim was refused"
        fi
    done < "$STATE/waiting"

    # 3. Claim each member, compare-and-set. A refused claim leaves that member out: another recap
    # holds it, or it settled since the call.
    if [ -f "$STATE/ready.tsv" ]; then
        while IFS= read -r row; do
            folder="${row%%$'\t'*}"
            [ -n "$folder" ] || continue
            if "$STATUS" "$folder" running >/dev/null 2>&1; then
                printf '%s\n' "$row" >> "$STATE/members.tsv"
                RUN_MEMBERS="$RUN_MEMBERS$folder"$'\n'
            else
                say "left out $(printf '%s' "$row" | cut -f3): its claim was refused"
            fi
        done < "$STATE/ready.tsv"
        rm -f "$STATE/ready.tsv"
    fi

    # The members the group has left out for want of a transcript, as the group stands now. After the
    # claims, so that every member of this run has the status this run gave it.
    write_left_out
    [ "$LEFT_OUT" -eq 0 ] || say "the group has left out $LEFT_OUT $([ "$LEFT_OUT" -eq 1 ] && echo member || echo members) whose transcript is missing or cannot be read; left-out.tsv lists them"

    if [ -z "$RUN_MEMBERS" ]; then
        say "claimed no member, so no session starts"
        finish_run ""
        return 1
    fi

    # What the recap session needs to know of the group, beside the members: when it was completed,
    # which dates the daily log, the domain most members resolve to, and where the list of the
    # members the group has left out is. A domain an earlier run recorded is kept, so a later run
    # files where the group's documents already are.
    project=$(state_value "$STATE/manifest" project)
    [ -n "$project" ] || project=$(cut -f4 "$STATE/members.tsv" | grep -v '^-$' | sort | uniq -c | sort -k1,1nr -k2 | awk 'NR == 1 { print $2 }')
    {
        printf 'key=%s\ncomplete_at=%s\nlog_date=%s\nproject=%s\n' "$KEY" "$COMPLETE_AT" "$(epoch_day "$complete_epoch")" "$project"
        printf 'members=%s\nmembers_file=%s\ndigests=%s\n' "$(grep -c '' "$STATE/members.tsv")" "$STATE/members.tsv" "$STATE/digests"
        printf 'left_out_file=%s\n' "$STATE/left-out.tsv"
    } > "$STATE/manifest.$$" && mv -f "$STATE/manifest.$$" "$STATE/manifest"

    # 4. One recap session. In the caller's terminal for a person, who then watches it there.
    claimed="$(grep -c '' "$STATE/members.tsv") members"; [ "$claimed" != "1 members" ] || claimed="1 member"
    if [ -n "$HERE" ]; then
        say "claimed $claimed; starting the recap session here"
        SECOND_BRAIN_RECAP_OF="group:$KEY" SECOND_BRAIN_RECAP_NAME="$NAME" SECOND_BRAIN_PLUGIN_ROOT="$PLUGIN_ROOT" \
            bash "$CHILD" --group "$KEY"
        finish_run ""
        [ "$RUN_DONE" -eq "$RUN_TOTAL" ]
        return
    fi

    # Else on the core, from outside any terminal: `hc run --bg --no-parent`, with the labels the
    # caller passed, which is what puts the session in a tab of the caller's choosing. The markers
    # travel inline on the command, never through a terminal's environment (ADR-0003). So does this
    # caller's PATH: a program the core starts gets the core's environment, and on 2026-11-11 the
    # core's PATH on this host held no claude. A name is unique among live terminals; a taken one, the
    # session of an earlier run that a person has kept, is retried once with a suffix.
    cmd=$(printf 'PATH=%q SECOND_BRAIN_RECAP_OF=%q SECOND_BRAIN_RECAP_NAME=%q SECOND_BRAIN_PLUGIN_ROOT=%q bash %q --group %q' \
        "$PATH" "group:$KEY" "$NAME" "$PLUGIN_ROOT" "$CHILD" "$KEY")
    label_args=()
    for try in ${LABELS[@]+"${LABELS[@]}"}; do label_args+=(--label "$try"); done
    run_err="$STATE/hc-run.err"
    for try in "$NAME" "$(printf '%s' "$NAME" | cut -c1-30)-2"; do
        run_json=$("$(hc_bin)" run --json --bg --no-parent --name "$try" --cwd "$KB_PATH" \
            ${label_args[@]+"${label_args[@]}"} -- "$cmd" 2>"$run_err")
        addr=$(printf '%s' "$run_json" | jq -r '.address // empty' 2>/dev/null)
        [ -n "$addr" ] && break
        printf '%s %s' "$run_json" "$(cat "$run_err" 2>/dev/null)" | grep -q name_taken || break
    done
    if [ -z "$addr" ]; then
        say "could not start a session; hc said: $run_json $(cat "$run_err" 2>/dev/null)"
        rm -f "$run_err"
        finish_run ""
        return 1
    fi
    rm -f "$run_err"
    printf 'terminal=%s\n' "$addr" >> "$STATE/run"
    say "claimed $claimed; started $NAME in hc terminal $addr"

    # 5 and 6. The session is the child's from here: it starts the exit watcher, runs the recap, and
    # fails what did not get done on its way out. This run waits for it by its process, a local fact
    # that needs no answer from the core, and then settles the rest.
    i=0
    while [ ! -s "$STATE/child" ] && [ "$i" -lt "$start_wait" ]; do sleep 1; i=$((i + 1)); done
    child_pid=$(state_value "$STATE/child" pid); child_start=$(state_value "$STATE/child" start)
    if [ -z "$child_pid" ]; then
        say "the session in $addr did not start the recap within $start_wait s; its terminal is left for a person to read"
        finish_run ""
        return 1
    fi
    while process_runs "$child_pid" "$child_start"; do sleep "$poll"; done
    finish_run "$addr"
    [ "$RUN_DONE" -eq "$RUN_TOTAL" ]
}

main() {
    KEY=""; COMPLETE_AT=""; HERE=""; RUN=""
    LABELS=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --complete-at) [ $# -ge 2 ] || bad_call "--complete-at needs a UTC time"
                           COMPLETE_AT="$2"; shift ;;
            --label)       [ $# -ge 2 ] || bad_call "--label needs k=v"
                           case "$2" in ?*=*) ;; *) bad_call "a label is k=v, and $2 is not" ;; esac
                           LABELS+=("$2"); shift ;;
            --here)        HERE=1 ;;
            --run)         RUN=1 ;;      # the run, started by this script and by nothing else
            -h|--help)     usage_text; exit 0 ;;
            -*)            bad_call "recap-group does not know the option $1" ;;
            *)             [ -z "$KEY" ] || bad_call "recap-group takes one key, and got $KEY and $1"
                           KEY="$1" ;;
        esac
        shift
    done
    [ -n "$KEY" ] && [ -n "$COMPLETE_AT" ] || bad_call "recap-group needs a key and --complete-at <UTC time>"

    STATE=$(recap_group_state_dir "$KEY")
    LOG="$STATE/recap.log"
    NAME=$(recap_group_session_name "$KEY")
    if [ -n "$RUN" ]; then run_main; else call_main; fi
}

main "$@"; exit $?
