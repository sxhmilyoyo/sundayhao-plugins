#!/bin/bash
# SessionEnd hook - updates session.md with final metadata (reference-only architecture)
# No segment copies — stores transcript_source path in frontmatter.
# Reads compaction-points.txt (written by pre_compact.sh) for segment boundaries.

shopt -s nullglob

INPUT=$(cat)
# One jq pass for all three fields, as session_start.sh does: three separate calls cost
# three processes, and this hook shares a 1.5-second budget with a memory copy, two
# transcript scans and a full rewrite of the note.
#
# `reason` says why the session ended. `clear` and `resume` are not endings: /clear keeps
# the same session id and resume switches away from a conversation that stays resumable,
# so neither may stamp a recap request (1.3 of the recap plan).
{
    IFS= read -r TRANSCRIPT_PATH
    IFS= read -r CWD_INPUT
    IFS= read -r REASON_INPUT
} < <(echo "$INPUT" | jq -r '.transcript_path // "", .cwd // "", .reason // ""')
SESSION_ID=$(basename "$TRANSCRIPT_PATH" .jsonl)

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../skills/common/get_kb_path.sh"
source "$SCRIPT_DIR/../../skills/common/obsidian_helpers.sh"

KB_PATH=$(get_kb_path 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$KB_PATH" ]; then
    cat << 'EOF'
{
  "continue": true,
  "systemMessage": "Session ended. Knowledge bank not configured - session not saved."
}
EOF
    exit 0
fi

# Resolve the folder, and reconstruct the note when it is missing instead of
# writing a blank one under today's date. The rebuild takes the date from the
# existing folder and the timing, cwd, project and lineage from the transcript,
# so the properties read below survive a note that was lost mid-session.
SESSION_FOLDER=$(resolve_session_folder "$KB_PATH" "$SESSION_ID")
if [ -z "$SESSION_FOLDER" ] || [ ! -f "$SESSION_FOLDER/session.md" ]; then
    SESSION_FOLDER=$(rebuild_session_md "$KB_PATH" "$SESSION_ID" "$TRANSCRIPT_PATH" "$CWD_INPUT")
fi

# Everything from the property reads to the rewrite below is one transaction, because
# a recap marking this subject `done` in between would have its write read, discarded
# and overwritten. Two deliberate limits on that.
#
# It is best-effort: if the lock cannot be taken the note is still written, since losing
# one concurrent property is a smaller failure than losing the whole note. And it spins
# briefly rather than for the helper's default, because this hook's entire budget is
# about 1.5 s: waiting the default would let a contended lock consume the budget and get
# the hook killed here, before ended_at, the duration, the transcript pointer or the
# rebuilt body were written.
#
# The trap matters as much as the acquire. Without it a hook killed mid-rewrite — the
# budget, a slow git call, a large memory directory to copy — would leave .recap.lock
# behind and every recap of this session would be refused until the lock aged past a
# minute.
LOCKED=""
if recap_lock_acquire "$SESSION_FOLDER" 3; then
    LOCKED=1
    trap 'recap_lock_release "$SESSION_FOLDER"' EXIT HUP INT TERM
fi

# ── 1. Read properties to preserve across overwrite ───────────────────
# One pass for all thirteen scalars, in the order listed. Read one at a time this cost
# three processes each, about 0.28 s of fork overhead, on a hook that shares a
# 1.5-second budget with a memory copy, two transcript scans and a rewrite — enough on a
# real session to have the whole hook cancelled after doing its work.
SESSION_MD="$SESSION_FOLDER/session.md"
{
    IFS= read -r SCHEMA_VERSION
    IFS= read -r STARTED_AT
    IFS= read -r PROJECT
    IFS= read -r CWD
    IFS= read -r GIT_BRANCH
    IFS= read -r DOCS_PATH_PROP
    IFS= read -r DATE_PROP
    # Set mid-session by the user through the session-manager skill, and after the
    # session ends by the recap, so they are preserved rather than recomputed.
    IFS= read -r SUMMARY
    IFS= read -r SESSION_NAME
    IFS= read -r FORKED_FROM
    IFS= read -r FORKED_FROM_NAME
    IFS= read -r DELEGATED_BY
    IFS= read -r DELEGATED_BY_NAME
    # The two the predicate needs, read here with the rest rather than separately after
    # the rewrite. Same values either way, since the rewrite preserves both through the
    # unknown-property loop, and reading them under the lock with everything else is one
    # fewer process and one fewer chance to see a half-written note.
    IFS= read -r RECAP_STATUS
    IFS= read -r RECAP_OF
} < <(read_frontmatter_props "$SESSION_MD" \
        schema_version started_at project cwd git_branch docs_path date \
        summary session_name forked_from forked_from_name delegated_by delegated_by_name \
        recap_status recap_of)

# tags is a list, so it needs the list reader rather than the scalar batch.
TAGS=$(read_frontmatter_list "$SESSION_MD" "tags")

# Lineage: the transcript is complete by now, so backfill what the fork-time scan
# may have missed while the file was still being written asynchronously.
[ -n "$FORKED_FROM" ] || FORKED_FROM=$(transcript_forked_from "$TRANSCRIPT_PATH" "$SESSION_ID")

# A fork detected only now has an id but no name, so resolve the name here too.
# Tags are deliberately not backfilled: inheritance belongs at registration,
# where the fork had not yet done any work of its own to describe.
if [ -n "$FORKED_FROM" ] && [ -z "$FORKED_FROM_NAME" ]; then
    PARENT_FOLDER=$(resolve_session_folder "$KB_PATH" "$FORKED_FROM")
    [ -n "$PARENT_FOLDER" ] && FORKED_FROM_NAME=$(read_frontmatter_prop \
        "$PARENT_FOLDER/session.md" "session_name")
fi

# Preserve every property this hook does not manage, verbatim, so properties
# written by skills (recap_* and anything added later) survive the rewrite.
KNOWN_PROPS="schema_version session_id date project cwd git_branch started_at docs_path forked_from forked_from_name delegated_by delegated_by_name transcript_source session_name ended_at duration_seconds summary tags"
# Continuation lines are carried with the key above them. Filtering to key lines
# alone kept an unknown list property as a bare null key and silently deleted
# every one of its items, which is exactly the preservation ADR-0002 promises.
EXTRA_YAML=""
if [ -f "$SESSION_MD" ]; then
    EXTRA_YAML=$(SB_KNOWN=" $KNOWN_PROPS " awk '
        BEGIN { fm = 0; keep = 0; known = ENVIRON["SB_KNOWN"] }
        /^---$/ { fm++; if (fm == 2) exit; next }
        fm != 1 { next }
        /^[a-z_][a-z0-9_]*:/ {
            key = $0; sub(/:.*/, "", key)
            keep = (index(known, " " key " ") == 0)
            if (keep) print
            next
        }
        keep { print }
    ' "$SESSION_MD")
    [ -n "$EXTRA_YAML" ] && EXTRA_YAML="$EXTRA_YAML
"
fi

# ── 2. Compute end-time metadata ─────────────────────────────────────
ENDED_AT=$(date -u +%Y-%m-%dT%H:%M:%S)

DURATION=""
if [ -n "$STARTED_AT" ]; then
    START_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$STARTED_AT" +%s 2>/dev/null)
    END_EPOCH=$(date -j -f "%Y-%m-%dT%H:%M:%S" "$ENDED_AT" +%s 2>/dev/null)
    if [ -n "$START_EPOCH" ] && [ -n "$END_EPOCH" ]; then
        DURATION=$(( END_EPOCH - START_EPOCH ))
    fi
fi

# Read customTitle from transcript (reverse-scan — fast on large files)
if [ -f "$TRANSCRIPT_PATH" ]; then
    CUSTOM_TITLE=$(tail -r "$TRANSCRIPT_PATH" 2>/dev/null \
        | grep -m1 '"type":"custom-title"' \
        | jq -r '.customTitle // empty' 2>/dev/null)
    [ -n "$CUSTOM_TITLE" ] && SESSION_NAME="$CUSTOM_TITLE"
fi

# ── 3. Copy auto memory snapshot ─────────────────────────────────────
if [ -n "$CWD" ]; then
    REPO_ROOT=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)
    MEMORY_ROOT="${REPO_ROOT:-$CWD}"
    MEMORY_HASH=$(echo "$MEMORY_ROOT" | sed 's|[/.]|-|g')
    MEMORY_SRC="$HOME/.claude/projects/$MEMORY_HASH/memory"
    if [ -d "$MEMORY_SRC" ]; then
        cp -r "$MEMORY_SRC" "$SESSION_FOLDER/memory"
    fi
fi

# ── 4. Build hub body ────────────────────────────────────────────────
BODY=""

# Lineage is regenerated from the properties rather than preserved, because this
# hook rebuilds the whole body: a link written at registration would otherwise be
# deleted here, and a fork whose parent was detected late would never get one.
# It is kept out of BODY because BODY is expanded with printf %b below, and a
# person-chosen name carrying a backslash escape would be interpreted there: a
# `\c` truncates the body and takes the ## Transcript pointer with it, which under
# the reference-only architecture is the only pointer to the conversation.
LINEAGE=$(session_lineage_body "$KB_PATH" "$FORKED_FROM" "$FORKED_FROM_NAME" \
    "$DELEGATED_BY" "$DELEGATED_BY_NAME")

# Generated Artifacts (docs/*.md)
DOCS_DIR="$SESSION_FOLDER/docs"
if [ -d "$DOCS_DIR" ]; then
    ARTIFACTS=""
    while IFS= read -r doc_file; do
        doc_name=$(basename "$doc_file" .md)
        ARTIFACTS="${ARTIFACTS}\n- [[${doc_name}]]"
    done < <(find "$DOCS_DIR" -name "*.md" -type f 2>/dev/null | sort)
    [ -n "$ARTIFACTS" ] && BODY="$BODY\n\n## Generated Artifacts${ARTIFACTS}"
fi

# Transcript source reference
BODY="$BODY\n\n## Transcript\n- Source: \`$TRANSCRIPT_PATH\`"

# Compaction Points (from pre_compact.sh sidecar)
CP_FILE="$SESSION_FOLDER/compaction-points.txt"
if [ -f "$CP_FILE" ]; then
    CP_LINES=""
    SEG_NUM=0
    while IFS=' ' read -r line_count timestamp; do
        CP_LINES="${CP_LINES}\n- Segment $SEG_NUM: $line_count lines ($timestamp)"
        SEG_NUM=$((SEG_NUM + 1))
    done < "$CP_FILE"
    [ -n "$CP_LINES" ] && BODY="$BODY\n\n## Compaction Points${CP_LINES}"
fi

# Memory Snapshot (memory/*.md)
MEMORY_DIR="$SESSION_FOLDER/memory"
if [ -d "$MEMORY_DIR" ]; then
    MEMORY_FILES=""
    for mem_file in "$MEMORY_DIR"/*.md; do
        [ -f "$mem_file" ] || continue
        mem_name=$(basename "$mem_file" .md)
        MEMORY_FILES="${MEMORY_FILES}\n- [[${mem_name}]]"
    done
    [ -n "$MEMORY_FILES" ] && BODY="$BODY\n\n## Memory Snapshot${MEMORY_FILES}"
fi

# ── 5. Write session.md atomically (frontmatter + body) ───────────────
TAGS_YAML=""
if [ -n "$TAGS" ]; then
    TAGS_YAML=$(echo "$TAGS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' | while read -r tag; do
        [ -n "$tag" ] && echo "  - $tag"
    done)
fi

FRONTMATTER="schema_version: \"${SCHEMA_VERSION:-2.0}\"
session_id: \"$SESSION_ID\"
date: ${DATE_PROP:-}
project: \"$(yaml_escape "${PROJECT:-}")\"
cwd: \"$(yaml_escape "${CWD:-}")\"
git_branch: \"$(yaml_escape "${GIT_BRANCH:-}")\"
started_at: ${STARTED_AT:-}
docs_path: \"$(yaml_escape "${DOCS_PATH_PROP:-}")\"
forked_from: \"$(yaml_escape "${FORKED_FROM:-}")\"
forked_from_name: \"$(yaml_escape "${FORKED_FROM_NAME:-}")\"
delegated_by: \"$(yaml_escape "${DELEGATED_BY:-}")\"
delegated_by_name: \"$(yaml_escape "${DELEGATED_BY_NAME:-}")\"
transcript_source: \"$(yaml_escape "$TRANSCRIPT_PATH")\"
session_name: \"$(yaml_escape "${SESSION_NAME:-}")\"
ended_at: $ENDED_AT
duration_seconds: ${DURATION:-}
summary: \"$(yaml_escape "${SUMMARY:-}")\"
${EXTRA_YAML}tags:
${TAGS_YAML}"

RESOLVED_BODY="# Session: $SESSION_ID"
[ -n "$LINEAGE" ] && RESOLVED_BODY="$RESOLVED_BODY

$LINEAGE"
RESOLVED_BODY="$RESOLVED_BODY$(printf '%b' "$BODY")"
write_session_md "$SESSION_FOLDER/session.md" "$FRONTMATTER" "$RESOLVED_BODY"

# Released before the predicate runs: recap_status.sh takes this same lock, so
# stamping while holding it would deadlock the hook against itself. Each half is
# atomic on its own, and the transition table refuses whatever a writer slipped into
# the gap, which is why splitting the transaction here is safe.
if [ -n "$LOCKED" ]; then
    recap_lock_release "$SESSION_FOLDER"
    trap - EXIT HUP INT TERM
    LOCKED=""
fi

# ── 6. Request a recap, or record that this session never needs one ────
# Every stamp goes through recap_status.sh, so each is compare-and-set: this hook can
# only move a note from no status, or from `exempt`, and can never disturb a recap in
# flight (ADR-0002). Output is discarded because a hook's stdout carries the protocol.
MODE=$(get_plugin_config_value auto_recap off)
case "$REASON_INPUT" in clear|resume) ENDING="" ;; *) ENDING=1 ;; esac
if [ "$MODE" != "off" ] && [ -n "$ENDING" ]; then
    STATUS="$SCRIPT_DIR/../../skills/common/recap_status.sh"
    # The stamp waits on the same lock this hook just released, and this hook is on a
    # 1.5 s clock. Two attempts, so the ordinary case succeeds on the first mkdir with no
    # wait at all, and a contended one gives up in 0.1 s rather than queueing behind a
    # recap mid-write for a stamp the transition table would refuse anyway.
    export SECOND_BRAIN_LOCK_ATTEMPTS=2
    # Both came off the note in the batch read above, so this costs no processes.
    CURRENT="$RECAP_STATUS"
    if [ -z "$CURRENT" ] || [ "$CURRENT" = "exempt" ]; then
        # RECAP_OF is what decides whether this is a recap session, never
        # SECOND_BRAIN_RECAP_OF. The marker's job ends at registration; at exit the
        # note is the record. If registration ever failed to write it, one redundant
        # recap is wasted, whereas trusting a marker here would let any process that
        # inherited one stamp a working session `exempt` and lose its knowledge. The
        # cheaper failure wins.
        if [ -n "$RECAP_OF" ]; then
            # A recap session: exempt for good, so a recap never recaps itself.
            [ -z "$CURRENT" ] && "$STATUS" "$SESSION_FOLDER" exempt >/dev/null 2>&1
        elif [ ! -f "$TRANSCRIPT_PATH" ]; then
            # Nothing to recap, ever. A permanent `requested` would nag forever.
            [ -z "$CURRENT" ] && "$STATUS" "$SESSION_FOLDER" exempt >/dev/null 2>&1
        else
            # Assistant records, not messages typed and not lines. Measured over every
            # vault session with a live transcript, they separate trivial from real
            # with an empty band from five to nine, while a prompt count exempted a
            # third of real sessions here (long autonomous runs driven by one slash
            # command) and a line count loses a 35-line session with fourteen model
            # turns while being fooled by a 15-line launch carrying 34 KB of injected
            # context and no reply at all. The bounded grep stops at the fifth match,
            # so it reads the head of the file and stays robust to the documented
            # transcript lag. An unreadable transcript yields no number and stamps
            # nothing, which is the safe answer whenever the evidence is missing.
            #
            # Two things to know before anyone makes this precise. It counts matching
            # lines, so a session that reads or quotes a transcript can match on
            # content rather than on its own model turns; that biases towards
            # recapping, which is the safe direction, and a recap session is already
            # excluded by recap_of above. And no match is an answer of zero, not a
            # failure: grep exits 1 there, so this must never be wrapped in `|| echo 0`
            # (which appends a second line and breaks the numeric test) nor guarded by
            # `|| exit`, which would abort on exactly the sessions that need `exempt`.
            TURNS=$(grep -c -m5 '"type":"assistant"' "$TRANSCRIPT_PATH" 2>/dev/null)
            case "$TURNS" in
                ''|*[!0-9]*) : ;;
                *) if [ "$TURNS" -ge 5 ]; then
                       # empty→requested, or exempt→requested for a session that was
                       # resumed after a small start and then did real work.
                       "$STATUS" "$SESSION_FOLDER" requested >/dev/null 2>&1
                       # Stage 2 launches the recap here, guarded by MODE = on.
                   elif [ -z "$CURRENT" ]; then
                       "$STATUS" "$SESSION_FOLDER" exempt >/dev/null 2>&1
                   fi ;;
            esac
        fi
    fi
fi

# ── Output ──────────────────────────────────────────────────────────────

cat << EOF
{
  "continue": true,
  "systemMessage": "Session complete: $SESSION_FOLDER"
}
EOF
