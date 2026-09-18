#!/bin/bash
# SessionStart hook - registers the session folder and note, and seeds the
# metadata a session can be recognised by later: its name, its knowledge-bank
# domain, and for a fork or a delegate the lineage and tags it inherits.
#
# Ownership reads by stage (ADR-0002 as amended by ADR-0006). This hook seeds what
# registration can see and never overwrites a value that is already there. The
# session-manager skill is the only writer while the session runs. The recap writes the
# session's description — its project, tags and summary — once the session has ended,
# reading the whole conversation rather than guessing from a name at launch.

INPUT=$(cat)
# One jq pass for all five fields. `source` distinguishes a genuine launch from a
# resume, a fork, a /clear or a compaction, and every decision below turns on it.
# `session_title` carries the name from --name or /rename, which removes the old
# race against a transcript that is documented to lag.
{
    IFS= read -r SESSION_ID
    IFS= read -r CWD
    IFS= read -r TRANSCRIPT_PATH
    IFS= read -r SOURCE
    IFS= read -r SESSION_TITLE
} < <(echo "$INPUT" | jq -r '.session_id // "", .cwd // "", .transcript_path // "",
                             .source // "", .session_title // ""')

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/../../skills/common/get_kb_path.sh"
source "$SCRIPT_DIR/../../skills/common/resolve_project.sh"
source "$SCRIPT_DIR/../../skills/common/obsidian_helpers.sh"

DOCS_GUIDANCE="When generating working documents (designs, plans, reviews, SOPs, issues, handoffs), write them to the session docs path above. Use subdirectories by type:
- docs/designs/    — architecture and design documents
- docs/plans/      — implementation plans
- docs/reviews/    — code/design review notes
- docs/issues/     — issue investigation and resolution
- docs/sops/       — standard operating procedures
- docs/            — anything else (handoffs, quick-start guides, etc.)"

# Emit the hook payload. Built with jq rather than a heredoc because three of the
# strings it carries are chosen by a person or read off a note: one quote in a session
# name would otherwise produce invalid JSON and silence this hook for every consumer.
#
# systemMessage sits beside hookSpecificOutput because it is a universal field, and it
# carries anything meant for the user rather than for Claude: additionalContext is
# delivered to Claude as a system reminder, so a retry command placed there would be
# read by the one party that cannot run it.
# Args: $1=additionalContext, $2=sessionTitle (optional), $3=systemMessage (optional)
emit_output() {
    local ctx="$1" title="${2:-}" note="${3:-}"
    jq -n --arg ctx "$ctx" --arg title "$title" --arg note "$note" '
        {hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $ctx}}
        | if $title != "" then .hookSpecificOutput.sessionTitle = $title else . end
        | if $note  != "" then .systemMessage = $note else . end'
}

# ── Recap notice — shown to the user, never handed to Claude ─────────────────
# What needs a person's attention: a recap that failed, and, once the hook launches
# them itself, one that should have started and did not. Nothing here lists a recap
# that is done, one that is exempt, a session never requested, or a recap session,
# because a nudge is for work that stalled and the never-requested backlog is a batch
# job for another day.
#
# One awk pass over a bounded window rather than read_frontmatter_prop per note:
# measured at 0.25 s for the pass against 2.8 s for the helper over 54 notes, and this
# hook shares its budget with registration. End to end the notice costs 0.09 s on a
# vault of 525 notes across 158 date directories. The scan accepts a status with or
# without quotes, because the setter writes them quoted and Obsidian strips quotes it
# does not need whenever a person saves a note, which has already happened to a fifth of
# the values in this vault.
# Args: $1=mode (notify|on)
# Returns: the notice on stdout; empty when nothing needs attention
recap_notice() {
    local mode="$1" launcher status_writer now cands st nm folder q_folder label date_dir line
    local mtime age reason body="" count=0
    [ -d "$KB_PATH/_sessions" ] || return 0
    launcher="$PLUGIN_ROOT/hooks/scripts/recap_launcher.sh"
    status_writer="$PLUGIN_ROOT/skills/common/recap_status.sh"
    now=$(date +%s)

    # Fourteen date directories, newest first, so the ordering inside each kind below
    # is already newest-first and needs no second sort. They are collected into an array
    # and handed to a single find: a find per date directory measured 0.87 s against
    # 0.06 s for one call over all fourteen roots on a vault of 525 notes, and the whole
    # notice has to stay a rounding error on a hook that runs before every session.
    local -a dirs=()
    while IFS= read -r line; do dirs+=("$line"); done < <(
        find "$KB_PATH/_sessions" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r | head -14)
    [ "${#dirs[@]}" -gt 0 ] || return 0
    cands=$(find "${dirs[@]}" -mindepth 2 -maxdepth 2 -name session.md 2>/dev/null \
        | tr '\n' '\0' \
        | xargs -0 awk '
            function val(s) { sub(/^[a-z_]+:[[:space:]]*/, "", s); gsub(/^"|"$/, "", s); return s }
            # The folder comes before the name because the name may be empty, and a
            # run of tabs collapses into one separator when IFS is a tab: an unnamed
            # session emitted as status, name, folder arrived as two fields and its
            # folder read as its name, so the whole row was dropped. The only field
            # allowed to be empty is the last one.
            function emit() {
                if (f == "" || ro != "") return
                if (st == "failed" || st == "requested" || st == "running")
                    print st "\t" f "\t" nm
            }
            FNR == 1 { emit(); fm = 0; st = ""; ro = ""; nm = ""; f = FILENAME }
            /^---$/  { fm++; next }
            fm != 1  { next }
            /^recap_status:/ { st = val($0); next }
            /^recap_of:/     { ro = val($0); next }
            /^session_name:/ { nm = val($0); next }
            END { emit() }
        ' 2>/dev/null)
    [ -n "$cands" ] || return 0

    # A duration a person reads, not a number of seconds.
    _ago() {
        local s="$1"
        if   [ "$s" -ge 86400 ]; then printf '%dd' $(( s / 86400 ))
        elif [ "$s" -ge 3600 ];  then printf '%dh' $(( s / 3600 ))
        else printf '%dm' $(( s / 60 )); fi
    }

    while IFS="$(printf '\t')" read -r st folder nm; do
        [ -n "$folder" ] || continue
        [ "$count" -lt 5 ] || break
        folder="${folder%/session.md}"
        # Never advertise the session this hook is running for. A /clear fires this hook
        # with the same session id, so a session stamped `requested` by an earlier exit
        # and then resumed would be offered as a recap candidate to itself: recapping a
        # live session reads a transcript still being written and marks it `done`, after
        # which its real exit sees a settled status and never requests the real recap.
        [ "$folder" != "$SESSION_FOLDER" ] || continue
        date_dir=$(basename "$(dirname "$folder")")
        # An unnamed session is still identifiable, and the first eight characters of
        # the id are what the rest of this plugin shows for one.
        label="${nm:-$(basename "$folder" | cut -c1-8)}"
        # Branch on the platform; chaining the two forms does not work. `-f` means
        # --file-system on GNU, so `stat -f %m` prints a filesystem block on *stdout* and
        # exits 1, and the fallback appended the real epoch to that block. The arithmetic
        # below then errored and left `age` empty, so no staleness threshold could fire.
        if [[ "$OSTYPE" == darwin* ]]; then
            mtime=$(stat -f %m "$folder/session.md" 2>/dev/null || echo "$now")
        else
            mtime=$(stat -c %Y "$folder/session.md" 2>/dev/null || echo "$now")
        fi
        age=$(( now - mtime ))
        # A path is data: a vault directory may contain a space, and an unquoted one
        # turns the printed command into three arguments the launcher rejects.
        q_folder=$(printf '%q' "$folder")
        case "$st" in
            failed)
                # The reason is the recap's, written to recap.log as `reason=<text>`
                # before it marked the subject failed.
                reason=$(grep 'reason=' "$folder/recap.log" 2>/dev/null | tail -1 | sed 's/.*reason=//')
                body="$body
- $date_dir $label — failed${reason:+: $reason} (see recap.log) — retry: $launcher --manual $q_folder"
                count=$(( count + 1 )) ;;
            requested)
                # In notify mode nothing ever starts a recap, so a request is a pending
                # to-do rather than a stall and needs no clock on it.
                if [ "$mode" = "notify" ]; then
                    body="$body
- $date_dir $label — requested, not started — run: $launcher --manual $q_folder"
                    count=$(( count + 1 ))
                elif [ "$age" -ge 600 ]; then
                    body="$body
- $date_dir $label — requested $(_ago "$age") ago, never started — run: $launcher --manual $q_folder"
                    count=$(( count + 1 ))
                fi ;;
            running)
                # Listed in both modes, not only in `on`. A manual launch can die
                # without its wrapper running — kill -9, a closed pane shell, a reboot —
                # and `running` is then a dead end that nothing else reports, so leaving
                # it out of `notify` means the one mode this version actually ships
                # cannot surface the state it can reach. The clock is the note's mtime,
                # since the writer rewrites the file on every transition: an untouched
                # note means nothing has advanced. Stalled is a judgement from elapsed
                # time, never a stored state.
                #
                # The command has to be the reopen, not `--manual`. A recap claims its
                # subject by moving `requested` to `running`, and there is deliberately
                # no `running` to `running` transition, so `--manual` against a stuck
                # subject is refused as "another recap holds the claim" — which is true
                # of a process that no longer exists. Reopening it is the only way back.
                if [ "$age" -ge 7200 ]; then
                    body="$body
- $date_dir $label — running $(_ago "$age") with no change — check its pane; if nothing is running: $status_writer $q_folder requested --force"
                    count=$(( count + 1 ))
                fi ;;
        esac
    done < <(
        printf '%s\n' "$cands" | grep '^failed	'    || true
        printf '%s\n' "$cands" | grep '^requested	' || true
        printf '%s\n' "$cands" | grep '^running	'   || true
    )

    [ "$count" -gt 0 ] || return 0
    if [ "$count" -eq 1 ]; then
        printf 'Second Brain: 1 recap needs attention%s' "$body"
    else
        printf 'Second Brain: %d recaps need attention%s' "$count" "$body"
    fi
}

# Try to get KB path (will fail if not configured)
KB_PATH=$(get_kb_path 2>/dev/null)

if [ $? -ne 0 ] || [ -z "$KB_PATH" ]; then
    SETUP_SCRIPT="$SCRIPT_DIR/../../skills/common/setup_kb_path.sh"
    emit_output "Second Brain Plugin: Knowledge bank not configured!

Run this command to configure:
  $SETUP_SCRIPT --configure"
    exit 0
fi

# An existing folder is authoritative about which day the session belongs to.
# Assuming today instead meant a /clear after midnight, or a reused --session-id,
# checked a path that was not the session's folder: the "write only when absent"
# guard below saw nothing, a second blank note appeared under today, and the note
# holding the real metadata was orphaned. The other three hooks already resolve.
SESSION_FOLDER=$(resolve_session_folder "$KB_PATH" "$SESSION_ID")
if [ -z "$SESSION_FOLDER" ]; then
    SESSION_FOLDER="$KB_PATH/_sessions/$(date +%Y-%m-%d)/$SESSION_ID"
fi
DATE_DIR=$(basename "$(dirname "$SESSION_FOLDER")")
DOCS_PATH="$SESSION_FOLDER/docs"
SESSION_MD="$SESSION_FOLDER/session.md"
mkdir -p "$DOCS_PATH"

# Cache folder path so SessionEnd/PreCompact can skip folder search
echo "$SESSION_FOLDER" > "/tmp/second-brain-folder-$SESSION_ID"

# A launcher declares delegation on the launched command and nothing infers it
# (ADR-0005). The marker is read only for a genuine startup: a variable that
# leaked into a shell would otherwise make every later session in it look
# delegated by one that never launched it.
DELEGATED_BY=""
DELEGATED_BY_NAME=""
if [ "$SOURCE" = "startup" ]; then
    DELEGATED_BY="${SECOND_BRAIN_DELEGATED_BY:-}"
    DELEGATED_BY_NAME="${SECOND_BRAIN_DELEGATED_BY_NAME:-}"
fi

# A recap session carries its subject the same way, inline on the launched command
# (ADR-0003), and for the same reason: a marker in a pane's environment would make
# every later session opened there register as a recap of something it never read.
# The marker's job ends here. At exit, session_end.sh reads `recap_of` off the note
# and never looks at this variable, so a stray one cannot exempt real work.
RECAP_OF=""
if [ "$SOURCE" = "startup" ]; then
    RECAP_OF="${SECOND_BRAIN_RECAP_OF:-}"
    while [ "${RECAP_OF%/}" != "$RECAP_OF" ] && [ "$RECAP_OF" != "/" ]; do RECAP_OF="${RECAP_OF%/}"; done
fi

# Resolved here rather than inside the note-creation branch below, because the
# marker exists only for this one process: if the note already exists, nothing
# later can recover the launcher's name, and the end hook has no marker to read.
LAUNCHER_FOLDER=""
if [ -n "$DELEGATED_BY" ]; then
    LAUNCHER_FOLDER=$(resolve_session_folder "$KB_PATH" "$DELEGATED_BY")
    if [ -n "$LAUNCHER_FOLDER" ] && [ -z "$DELEGATED_BY_NAME" ]; then
        DELEGATED_BY_NAME=$(read_frontmatter_prop "$LAUNCHER_FOLDER/session.md" "session_name")
    fi
fi

# Write the note only when it is absent. This hook also fires for /clear and for
# a fork, and a /clear keeps the same session id, so rewriting here would discard
# the tags, summary and name set earlier in the very same session.
if [ ! -f "$SESSION_MD" ]; then
    # Detect git branch
    GIT_BRANCH=""
    if [ -d "$CWD/.git" ] || git -C "$CWD" rev-parse --git-dir >/dev/null 2>&1; then
        GIT_BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
    fi

    # The knowledge-bank domain this work belongs to, from the shared resolver.
    # Empty when the directory maps to no domain, which is the intended signal
    # rather than a directory name standing in for one (ADR-0004).
    PROJECT=$(resolve_project "$CWD" "$KB_PATH")

    # Timestamps
    STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%S)

    # A forked session continues another conversation under a new id, and replays
    # its parent's history, so the parent is recoverable from this transcript.
    FORKED_FROM=$(transcript_forked_from "$TRANSCRIPT_PATH" "$SESSION_ID")

    # A fork continues a conversation and a delegate carries out work for one, so
    # both begin from the metadata of the session they came from. An untagged source
    # leaves them untagged: nothing here invents a description, and the recap writes
    # one for the source and for this session after each has ended (ADR-0006).
    # A session can be both forked and declared-delegated, so both names are
    # resolved; the fork's parent is the one metadata is inherited from, being the
    # conversation this one continues.
    FORKED_FROM_NAME=""
    INHERIT_FROM=""
    if [ -n "$FORKED_FROM" ]; then
        INHERIT_FROM=$(resolve_session_folder "$KB_PATH" "$FORKED_FROM")
        [ -n "$INHERIT_FROM" ] && FORKED_FROM_NAME=$(read_frontmatter_prop \
            "$INHERIT_FROM/session.md" "session_name")
    fi
    [ -n "$INHERIT_FROM" ] || INHERIT_FROM="$LAUNCHER_FOLDER"

    INHERITED_TAGS=""
    if [ -n "$INHERIT_FROM" ] && [ -f "$INHERIT_FROM/session.md" ]; then
        INHERITED_TAGS=$(read_frontmatter_list "$INHERIT_FROM/session.md" "tags")
        # The source's domain wins over this directory's, because a delegate can
        # be launched anywhere while the work still belongs where the launcher
        # filed it. Validated, so a legacy basename is not carried forward.
        INHERITED_PROJECT=$(validate_project "$(read_frontmatter_prop \
            "$INHERIT_FROM/session.md" "project")" "$KB_PATH")
        [ -n "$INHERITED_PROJECT" ] && PROJECT="$INHERITED_PROJECT"
    fi

    # A recap session takes its subject's domain, or its emptiness, and never the
    # bank's own name: it runs with the vault as its working directory, which maps to
    # no domain, while the work being described belongs wherever the subject filed it
    # (ADR-0004). Validated, so a subject holding a legacy basename yields empty here
    # rather than passing one on.
    if [ -n "$RECAP_OF" ]; then
        PROJECT=$(validate_project "$(read_frontmatter_prop \
            "$RECAP_OF/session.md" "project")" "$KB_PATH")
    fi

    TAGS_YAML=""
    if [ -n "$INHERITED_TAGS" ]; then
        TAGS_YAML=$(echo "$INHERITED_TAGS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' \
            | while read -r tag; do [ -n "$tag" ] && echo "  - $tag"; done)
    fi
    # The one tag a hook writes, and the canonical spelling in this vault. A recap
    # session is recognisable as one from its tags as well as from `recap_of`.
    if [ -n "$RECAP_OF" ]; then
        if [ -n "$TAGS_YAML" ]; then TAGS_YAML="$TAGS_YAML
  - session-recap"; else TAGS_YAML="  - session-recap"; fi
    fi

    # Written only for a recap session, so an ordinary note gains no empty property.
    # It is what makes a recap session identifiable after its marker is gone: the
    # notice never lists one, and the end hook stamps it exempt for good.
    RECAP_YAML=""
    [ -n "$RECAP_OF" ] && RECAP_YAML="recap_of: \"$(yaml_escape "$RECAP_OF")\"
"

    # Create session.md with full frontmatter in one atomic filesystem write.
    # Bypasses Obsidian CLI for reliability — CLI create can fail silently.
    FRONTMATTER="schema_version: \"2.1\"
session_id: \"$SESSION_ID\"
date: $DATE_DIR
project: \"$(yaml_escape "$PROJECT")\"
cwd: \"$(yaml_escape "$CWD")\"
git_branch: \"$(yaml_escape "$GIT_BRANCH")\"
started_at: $STARTED_AT
docs_path: \"_sessions/$DATE_DIR/$SESSION_ID/docs\"
forked_from: \"$(yaml_escape "$FORKED_FROM")\"
forked_from_name: \"$(yaml_escape "$FORKED_FROM_NAME")\"
delegated_by: \"$(yaml_escape "$DELEGATED_BY")\"
delegated_by_name: \"$(yaml_escape "$DELEGATED_BY_NAME")\"
${RECAP_YAML}transcript_source:
session_name: \"$(yaml_escape "$SESSION_TITLE")\"
ended_at:
duration_seconds:
summary:
tags:"
    [ -n "$TAGS_YAML" ] && FRONTMATTER="$FRONTMATTER
$TAGS_YAML"

    BODY="# Session: $SESSION_ID"
    LINEAGE=$(session_lineage_body "$KB_PATH" "$FORKED_FROM" "$FORKED_FROM_NAME" \
        "$DELEGATED_BY" "$DELEGATED_BY_NAME")
    [ -n "$LINEAGE" ] && BODY="$BODY

$LINEAGE"

    write_session_md "$SESSION_MD" "$FRONTMATTER" "$BODY"
fi

# Declared lineage is recorded even when the note already existed, because the
# marker lives for this process only. A note rebuilt at an earlier resume, or a
# session restarted under the same id, would otherwise lose the relationship for
# good: nothing downstream can rediscover it and the end hook has no marker.
if [ -n "$DELEGATED_BY" ] \
   && [ -z "$(read_frontmatter_prop "$SESSION_MD" "delegated_by")" ]; then
    set_frontmatter_prop "$SESSION_MD" "delegated_by" "$DELEGATED_BY"
    set_frontmatter_prop "$SESSION_MD" "delegated_by_name" "$DELEGATED_BY_NAME"
fi

# A delegate or a recap whose launcher passed no name is named here, which is its only
# chance: no later event carries a name for a session that never had one. The launcher
# normally passes one with -n; this covers the hand-run case.
EMIT_TITLE=""
if [ -z "$SESSION_TITLE" ] \
   && [ -z "$(read_frontmatter_prop "$SESSION_MD" "session_name")" ]; then
    if [ -n "$DELEGATED_BY" ]; then
        EMIT_TITLE="delegate-${DELEGATED_BY_NAME:-${DELEGATED_BY:0:8}}"
    elif [ -n "$RECAP_OF" ]; then
        EMIT_TITLE="recap-$(basename "$RECAP_OF" | cut -c1-8)"
    fi
    [ -n "$EMIT_TITLE" ] && set_frontmatter_prop "$SESSION_MD" "session_name" "$EMIT_TITLE"
fi

SESSION_NAME=$(read_frontmatter_prop "$SESSION_MD" "session_name")

# Name the enclosing terminal container as soon as the name is known, which is
# what a launch now provides. Only on a genuine startup: a fork arrives carrying
# its parent's title, and renaming there would take the parent's Herdr agent name
# away from the session still using it.
[ "$SOURCE" = "startup" ] && rename_terminal_window "$SESSION_NAME"

# The notice is built only when the feature is on, so a switched-off plugin pays
# nothing for it, and a broken config reads as off rather than as on.
NOTICE=""
RECAP_MODE=$(get_plugin_config_value auto_recap off)
[ "$RECAP_MODE" != "off" ] && NOTICE=$(recap_notice "$RECAP_MODE")

# Inject system prompt with docs path
emit_output "Session folder created: $SESSION_FOLDER

Session docs path: $DOCS_PATH

$DOCS_GUIDANCE" "$EMIT_TITLE" "$NOTICE"
