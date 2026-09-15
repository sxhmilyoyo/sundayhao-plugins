#!/bin/bash
# SessionStart hook - registers the session folder and note, and seeds the
# metadata a session can be recognised by later: its name, its knowledge-bank
# domain, and for a fork or a delegate the lineage and tags it inherits.
#
# Ownership. This hook seeds a note at registration; the session-manager skill is
# the only mid-session writer; nothing here overwrites a non-empty value. What
# cannot be derived mechanically — the tags of an ordinary named session — is not
# guessed: the hook asks the model to run the skill and stamps the note, so the
# request is made once rather than on every later start.

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

# Emit the hook payload. Built with jq rather than a heredoc because two of the
# strings it carries are chosen by a person: one quote in a session name would
# otherwise produce invalid JSON and silence this hook for every consumer of it.
# Args: $1=additionalContext, $2=sessionTitle (optional)
emit_output() {
    local ctx="$1" title="${2:-}"
    if [ -n "$title" ]; then
        jq -n --arg ctx "$ctx" --arg title "$title" \
            '{hookSpecificOutput: {hookEventName: "SessionStart",
                                   additionalContext: $ctx,
                                   sessionTitle: $title}}'
    else
        jq -n --arg ctx "$ctx" \
            '{hookSpecificOutput: {hookEventName: "SessionStart",
                                   additionalContext: $ctx}}'
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
    # both begin from the metadata of the session they came from. An untagged
    # source leaves them untagged rather than falling through to the model: a
    # derivation request would land in the middle of a fork's conversation or on
    # top of a delegate's first instruction.
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

    TAGS_YAML=""
    if [ -n "$INHERITED_TAGS" ]; then
        TAGS_YAML=$(echo "$INHERITED_TAGS" | tr ',' '\n' | sed 's/^ *//;s/ *$//' \
            | while read -r tag; do [ -n "$tag" ] && echo "  - $tag"; done)
    fi

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
transcript_source:
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

# A delegate whose launcher passed no name is named here, which is its only
# chance: no later event carries a name for a session that never had one.
EMIT_TITLE=""
if [ -z "$SESSION_TITLE" ] && [ -n "$DELEGATED_BY" ] \
   && [ -z "$(read_frontmatter_prop "$SESSION_MD" "session_name")" ]; then
    EMIT_TITLE="delegate-${DELEGATED_BY_NAME:-${DELEGATED_BY:0:8}}"
    set_frontmatter_prop "$SESSION_MD" "session_name" "$EMIT_TITLE"
fi

SESSION_NAME=$(read_frontmatter_prop "$SESSION_MD" "session_name")

# Name the enclosing terminal container as soon as the name is known, which is
# what a launch now provides. Only on a genuine startup: a fork arrives carrying
# its parent's title, and renaming there would take the parent's Herdr agent name
# away from the session still using it.
[ "$SOURCE" = "startup" ] && rename_terminal_window "$SESSION_NAME"

# ââ Ask the model for what cannot be derived mechanically âââââââââââââââââââââ
# Tags describe the work, which the name only hints at, so they are the model's to
# choose. The gate is narrow on purpose: a genuine launch, no declared launcher, no
# parent, a name to reason from, no tags already, and no stamp from a previous
# start. The tags check matters for a session restarted under its own id, whose
# note already carries inherited tags the instruction would otherwise contradict.
INSTRUCTION=""
STAMP_NOW=no
if [ "$SOURCE" = "startup" ] \
   && [ -z "$DELEGATED_BY" ] \
   && [ -z "$(read_frontmatter_prop "$SESSION_MD" "forked_from")" ] \
   && [ -n "$SESSION_NAME" ] \
   && [ -z "$(read_frontmatter_list "$SESSION_MD" "tags")" ] \
   && [ -z "$(read_frontmatter_prop "$SESSION_MD" "metadata_requested_at")" ]; then
    STAMP_NOW=yes
    PROJECT_NOW=$(read_frontmatter_prop "$SESSION_MD" "project")
    TAG_HINTS=$(project_default_tags "$CWD")

    INSTRUCTION="

Automatic session-metadata derivation: this session's note carries a name but no tags. Once you have answered the first request, run the second-brain:session-manager skill in automatic mode to set them.
- Session name: $SESSION_NAME
- Resolved project: ${PROJECT_NOW:-none, leave it empty unless the work clearly belongs to one domain}
- Tag hints for this directory: ${TAG_HINTS:-none}
Automatic mode writes tags that already have a canonical form in the vault without asking, reports any tag it could not match to an existing one, and never interrupts with a prompt."
fi

# Inject system prompt with docs path
emit_output "Session folder created: $SESSION_FOLDER

Session docs path: $DOCS_PATH

$DOCS_GUIDANCE$INSTRUCTION" "$EMIT_TITLE"

# Stamped only after the request has been written out. Stamping first spent the
# one-shot on any later failure — a timeout, a jq error, a full disk — and since
# startup fires once per session id, the request could then never be made again.
if [ "$STAMP_NOW" = "yes" ]; then
    set_frontmatter_prop "$SESSION_MD" "metadata_requested_at" \
        "$(date -u +%Y-%m-%dT%H:%M:%S)"
fi
