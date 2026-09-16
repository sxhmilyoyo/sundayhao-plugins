#!/bin/bash
# parse_transcript.sh - Extract structured data from Claude Code transcript.jsonl
# Usage: ./parse_transcript.sh <transcript.jsonl> <command>
#
# Commands:
#   stats       - Show session statistics
#   users       - Extract user messages
#   files-read  - Extract files read (Read tool)
#   files-mod   - Extract files modified (Edit/Write tools)
#   commands    - Extract bash commands executed
#   errors      - Extract errors and failures from tool results
#   subagents   - Extract subagent (Task tool) invocations
#   insights    - Extract educational insights (★ Insight blocks)
#   project     - Auto-detect project from cwd
#   all         - Run all extractions

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <transcript.jsonl> <command>"
    echo ""
    echo "Commands:"
    echo "  stats       - Show session statistics"
    echo "  users       - Extract user messages"
    echo "  files-read  - Extract files read"
    echo "  files-mod   - Extract files modified"
    echo "  commands    - Extract bash commands"
    echo "  errors      - Extract errors from tool results"
    echo "  subagents   - Extract subagent invocations"
    echo "  insights    - Extract educational insights (★ Insight blocks)"
    echo "  project     - Auto-detect project from cwd"
    echo "  all         - Run all extractions"
    exit 1
fi

TRANSCRIPT="$1"
COMMAND="$2"

if [ ! -f "$TRANSCRIPT" ]; then
    echo "Error: Transcript file not found: $TRANSCRIPT"
    exit 1
fi

# Extract user messages
extract_users() {
    echo "=== User Messages ==="
    jq -r 'select(.type == "user") |
      "[" + (.timestamp // "unknown") + "] " +
      (.message.content | if type == "string" then . else (.[0].text // "[tool_result]") end)' \
      "$TRANSCRIPT" 2>/dev/null | head -100
}

# Extract files read
extract_files_read() {
    echo "=== Files Read ==="
    jq -r 'select(.message.content[]?.type == "tool_use" and .message.content[]?.name == "Read") |
      .message.content[] | select(.type == "tool_use" and .name == "Read") |
      .input.file_path' "$TRANSCRIPT" 2>/dev/null | sort -u
}

# Extract files modified
extract_files_modified() {
    echo "=== Files Modified ==="
    jq -r 'select(.message.content[]?.type == "tool_use") |
      .message.content[] | select(.type == "tool_use") |
      select(.name == "Edit" or .name == "Write") |
      "\(.name): \(.input.file_path)"' "$TRANSCRIPT" 2>/dev/null | sort -u
}

# Extract bash commands
extract_commands() {
    echo "=== Bash Commands ==="
    jq -r 'select(.message.content[]?.type == "tool_use" and .message.content[]?.name == "Bash") |
      .message.content[] | select(.type == "tool_use" and .name == "Bash") |
      .input.command' "$TRANSCRIPT" 2>/dev/null | head -50
}

# Extract errors from tool results
extract_errors() {
    echo "=== Errors & Failures ==="
    jq -r 'select(.message.content[]?.type == "tool_result") |
      .message.content[] | select(.type == "tool_result") |
      if .content | type == "array" then
        .content[] | select(.type == "text") | .text
      elif .content | type == "string" then
        .content
      else
        empty
      end' "$TRANSCRIPT" 2>/dev/null | grep -i -E "(error|fail|exception|Error:|FAILED)" | head -30
}

# Extract subagent invocations
extract_subagents() {
    echo "=== Subagent Invocations ==="
    jq -r 'select(.message.content[]?.type == "tool_use" and .message.content[]?.name == "Task") |
      .message.content[] | select(.type == "tool_use" and .name == "Task") |
      "[\(.input.subagent_type)] \(.input.description)"' "$TRANSCRIPT" 2>/dev/null
}

# Extract educational insights (★ Insight blocks from assistant messages)
extract_insights() {
    echo "=== Educational Insights ==="
    jq -r 'select(.type == "assistant") |
      .message.content[] | select(.type == "text") |
      .text' "$TRANSCRIPT" 2>/dev/null | \
    awk '/★ Insight/,/─────────────────────────────────────────────────$/' | \
    grep -v '^$'
}

# Report the working directory and the domain it maps to. This is information, never a
# decision: `project` names a knowledge-bank domain (ADR-0004) and the recap decides it
# from three sources in SKILL.md Phase 1.2. The old helper here matched the cwd against
# project directory names and printed `unknown` when nothing matched, which is exactly
# the invented domain ADR-0004 exists to keep visibly missing.
extract_project() {
    CWD=$(jq -r 'select(.type == "user") | .cwd' "$TRANSCRIPT" 2>/dev/null | head -1)
    if [ -z "$CWD" ]; then
        echo "Could not extract cwd from transcript"
        return 0
    fi
    echo "CWD: $CWD"
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ -f "$SCRIPT_DIR/../../common/resolve_project.sh" ]; then
        source "$SCRIPT_DIR/../../common/resolve_project.sh"
        RESOLVED=$(resolve_project "$CWD")
        echo "Project: ${RESOLVED:-(this directory maps to no domain; see SKILL.md Phase 1.2)}"
    else
        echo "Project: (resolver unavailable)"
    fi
}

# Session statistics
extract_stats() {
    echo "=== Session Statistics ==="
    # Two numbers, because they are two different things and the old single line said
    # "User messages" while counting both. Tool results carry `"type":"user"` too, so on
    # a real transcript the raw count runs an order of magnitude high: 1080 records
    # against 42 actual prompts on the session that found this.
    #
    # The prompt figure is approximate on purpose and labelled so. It counts a typed
    # slash command as the input it is, and it also counts messages from other sessions
    # and the compaction preamble, which is fine for a sense of scale and would be wrong
    # to present as "messages the human typed".
    STATS_DIR="$(cd "$(dirname "$0")" && pwd)"
    if [ -f "$STATS_DIR/../../common/obsidian_helpers.sh" ]; then
        source "$STATS_DIR/../../common/obsidian_helpers.sh" >/dev/null 2>&1
        echo "User prompts (approx.): $(count_user_messages "$TRANSCRIPT")"
    fi
    echo "User records (incl. tool results): $(jq -s '[.[] | select(.type == "user")] | length' "$TRANSCRIPT" 2>/dev/null)"
    echo "Assistant messages: $(jq -s '[.[] | select(.type == "assistant")] | length' "$TRANSCRIPT" 2>/dev/null)"
    echo "Tool uses: $(jq -s '[.[] | .message.content[]? | select(.type == "tool_use")] | length' "$TRANSCRIPT" 2>/dev/null)"
    echo "Summaries: $(jq -s '[.[] | select(.type == "summary")] | length' "$TRANSCRIPT" 2>/dev/null)"
    echo ""
    echo "Files read: $(jq -r 'select(.message.content[]?.name == "Read") | .message.content[] | select(.name == "Read") | .input.file_path' "$TRANSCRIPT" 2>/dev/null | sort -u | wc -l | tr -d ' ')"
    echo "Files modified: $(jq -r 'select(.message.content[]?.name == "Edit" or .message.content[]?.name == "Write") | .message.content[] | select(.name == "Edit" or .name == "Write") | .input.file_path' "$TRANSCRIPT" 2>/dev/null | sort -u | wc -l | tr -d ' ')"
    echo "Bash commands: $(jq -r 'select(.message.content[]?.name == "Bash")' "$TRANSCRIPT" 2>/dev/null | wc -l | tr -d ' ')"
    echo "Subagents spawned: $(jq -r 'select(.message.content[]?.name == "Task")' "$TRANSCRIPT" 2>/dev/null | wc -l | tr -d ' ')"
}

# Run based on command
case "$COMMAND" in
    stats)
        extract_stats
        ;;
    users)
        extract_users
        ;;
    files-read)
        extract_files_read
        ;;
    files-mod)
        extract_files_modified
        ;;
    commands)
        extract_commands
        ;;
    errors)
        extract_errors
        ;;
    subagents)
        extract_subagents
        ;;
    insights)
        extract_insights
        ;;
    project)
        extract_project
        ;;
    all)
        extract_stats
        echo ""
        extract_project
        echo ""
        extract_users
        echo ""
        extract_files_read
        echo ""
        extract_files_modified
        echo ""
        extract_commands
        echo ""
        extract_errors
        echo ""
        extract_subagents
        echo ""
        extract_insights
        ;;
    *)
        echo "Unknown command: $COMMAND"
        echo "Run without arguments for usage."
        exit 1
        ;;
esac
