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
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
# `source` distinguishes a genuine launch from a resume, a fork, a /clear or a
# compaction, and every decision below turns on it. `session_title` carries the
# name from --name or /rename, which removes the old race against a transcript
# that is documented to lag.
SOURCE=$(echo "$INPUT" | jq -r '.source // empty')
SESSION_TITLE=$(echo "$INPUT" | jq -r '.session_title // empty')

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

# Session folder setup
TODAY=$(date +%Y-%m-%d)
SESSION_FOLDER="$KB_PATH/_sessions/$TODAY/$SESSION_ID"
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
    FORKED_FROM_NAME=""
    INHERIT_FROM=""
    if [ -n "$FORKED_FROM" ]; then
        INHERIT_FROM=$(resolve_session_folder "$KB_PATH" "$FORKED_FROM")
        [ -n "$INHERIT_FROM" ] && FORKED_FROM_NAME=$(read_frontmatter_prop \
            "$INHERIT_FROM/session.md" "session_name")
    elif [ -n "$DELEGATED_BY" ]; then
        INHERIT_FROM=$(resolve_session_folder "$KB_PATH" "$DELEGATED_BY")
        if [ -n "$INHERIT_FROM" ] && [ -z "$DELEGATED_BY_NAME" ]; then
            DELEGATED_BY_NAME=$(read_frontmatter_prop \
                "$INHERIT_FROM/session.md" "session_name")
        fi
    fi

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
    FRONTMATTER="schema_version: \"2.0\"
session_id: \"$SESSION_ID\"
date: $TODAY
project: \"$(yaml_escape "$PROJECT")\"
cwd: \"$(yaml_escape "$CWD")\"
git_branch: \"$(yaml_escape "$GIT_BRANCH")\"
started_at: $STARTED_AT
docs_path: \"_sessions/$TODAY/$SESSION_ID/docs\"
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

# A delegate whose launcher passed no name is named here, which is its only
# chance: no later event carries a name for a session that never had one.
EMIT_TITLE=""
if [ -z "$SESSION_TITLE" ] && [ -n "$DELEGATED_BY" ] \
   && [ -z "$(read_frontmatter_prop "$SESSION_MD" "session_name")" ]; then
    EMIT_TITLE="delegate-${DELEGATED_BY_NAME:-${DELEGATED_BY:0:8}}"
    set_frontmatter_prop "$SESSION_MD" "session_name" "$EMIT_TITLE"
fi

# Name the enclosing terminal container as soon as the name is known. The name
# is on stdin at startup, so waiting for a resume or a hand-run skill left a
# freshly launched session sitting in an unlabelled pane for its whole first life.
rename_terminal_window "$(read_frontmatter_prop "$SESSION_MD" "session_name")"

# ── Ask the model for what cannot be derived mechanically ─────────────────────
# Tags describe the work, which the name only hints at, so they are the model's
# to choose. The gate is narrow on purpose: a genuine launch, no declared
# launcher, no parent, a name to reason from, and no stamp from a previous start.
INSTRUCTION=""
if [ "$SOURCE" = "startup" ] \
   && [ -z "$DELEGATED_BY" ] \
   && [ -z "$(read_frontmatter_prop "$SESSION_MD" "forked_from")" ] \
   && [ -n "$(read_frontmatter_prop "$SESSION_MD" "session_name")" ] \
   && [ -z "$(read_frontmatter_prop "$SESSION_MD" "metadata_requested_at")" ]; then
    # Stamped at the moment the request is made, not when it is carried out, so a
    # session whose model never ran the skill is asked once and not again.
    set_frontmatter_prop "$SESSION_MD" "metadata_requested_at" \
        "$(date -u +%Y-%m-%dT%H:%M:%S)"

    SESSION_NAME=$(read_frontmatter_prop "$SESSION_MD" "session_name")
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
