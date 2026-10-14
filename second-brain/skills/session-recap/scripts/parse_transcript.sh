#!/bin/bash
# parse_transcript.sh - Extract structured data from Claude Code transcript.jsonl
# Usage: ./parse_transcript.sh <transcript.jsonl> <command>
#
# Commands:
#   stats       - Show session statistics
#   users       - Extract user messages
#   files-read  - Extract files read (Read tool)
#   files-mod   - Extract files modified (Edit/Write tools, and Bash writes: redirects, tee, sed -i, python open/Path.write_text)
#   commands    - Extract bash commands executed
#   errors      - Extract errors and failures from tool results
#   subagents   - Extract subagent (Agent tool, formerly Task) invocations
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

# Extract user messages: one line per human prompt, truncated per message rather than
# per output, so one expanded skill body cannot hide every prompt after it. Messages
# from other sessions are isMeta records the prompt filter drops, so they get their
# own section.
extract_users() {
    echo "=== User Messages ==="
    jq -r 'select(.type == "user" and (.isMeta | not)) |
      (.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end) as $t |
      select(($t | length) > 0) |
      "[" + (.timestamp // "unknown") + "] " + ($t | gsub("\\s+"; " ") | .[0:300])' \
      "$TRANSCRIPT" 2>/dev/null
    echo ""
    echo "=== Inbound Session Messages ==="
    jq -r 'select(.type == "user" and .isMeta and ((.message.content | type) == "string")
             and (.message.content | contains("<cross-session-message"))) |
      "[" + (.timestamp // "unknown") + "] " +
      ((.message.content | capture("from-name=\"(?<n>[^\"]*)\"") | .n) // "?") + ": " +
      (.message.content | sub("(?s)^.*?<cross-session-message[^>]*>"; "") | gsub("\\s+"; " ") | .[0:300])' \
      "$TRANSCRIPT" 2>/dev/null
}

# Extract files read
extract_files_read() {
    echo "=== Files Read ==="
    jq -r 'select(.message.content[]?.type == "tool_use" and .message.content[]?.name == "Read") |
      .message.content[] | select(.type == "tool_use" and .name == "Read") |
      .input.file_path' "$TRANSCRIPT" 2>/dev/null | sort -u
}

# Files a Bash command writes. Under auto mode the harness asks for file changes through Bash, so
# a change made with `cat > f <<'EOF'`, `tee f`, `sed -i … f` or a `python3 - <<'EOF'` heredoc that
# calls open(f, "w") never shows up as an Edit or Write call: a six-file change on a real transcript
# read "Files modified: 0". Redirect targets must look like paths (a `/`, a `./`, a `$`, or an
# extension) and hold no `<`, `>`, quote or `*`, so `>` inside awk, sed or python scripts or a markdown
# blockquote in a heredoc body is skipped;
# explicit write APIs (tee, sed -i, open, Path.write_text) are taken as written. A `$VAR` or `${VAR}`
# in a target is expanded from a `VAR=value` assignment in the same command. `sed -i` takes any number
# of scripts, each after its own options (`-e`), before its file. A target that starts with `-` is an
# option, and one that holds a `$(` was cut inside a command substitution (the assignment scan ends a
# value at its first space), so neither is listed.
PT_JQ_DEFS=$(cat <<'JQ'
def pt_unquote: if length >= 2 and ((startswith("\"") and endswith("\"")) or (startswith("'") and endswith("'"))) then .[1:-1] else . end;
def pt_pathlike: test("^(\\$|/|~|\\.{1,2}/|[A-Za-z0-9_.-]+/|[A-Za-z0-9_.-]+\\.[A-Za-z0-9]{1,6}$)");
def pt_bash_write_targets:
  . as $c
  | ([ $c | scan("(?:^|[\\s;&|(])([A-Za-z_][A-Za-z0-9_]*)=(\"[^\"]*\"|'[^']*'|[^\\s;&|)]+)") | {k: .[0], v: (.[1] | pt_unquote)} ]) as $vars
  | def pt_expand: reduce $vars[] as $kv (.; gsub("\\$\\{" + $kv.k + "\\}|\\$" + $kv.k + "(?![A-Za-z0-9_])"; $kv.v));
    ( [ $c | scan("(?<![0-9=<>-])>{1,2}\\s*(\"[^\"]+\"|'[^']+'|[^\\s;&|)]+)") | .[0] | pt_unquote | pt_expand | select(pt_pathlike) ]
    + [ $c | scan("\\btee\\s+(?:-a\\s+)?(\"[^\"]+\"|'[^']+'|[^\\s;&|)]+)") | .[0] | pt_unquote | pt_expand ]
    + [ $c | scan("\\bsed\\s+(?:-[A-Za-z]+\\s+)*-i\\S*\\s+(?:(?:-[A-Za-z]+\\s+)*(?:'[^']*'|\"[^\"]*\")\\s+)+([^\\s;&|]+)") | .[0] | pt_expand ]
    + [ $c | scan("\\bopen\\(\\s*([\"'])([^\"']+)\\1\\s*,\\s*[\"'][wa]") | .[1] ]
    + [ $c | scan("Path\\(\\s*([\"'])([^\"']+)\\1\\s*\\)\\.write_(?:text|bytes)") | .[1] ]
    + [ $c | scan("\\bopen\\(\\s*([A-Za-z_][A-Za-z0-9_]*)\\s*,\\s*[\"'][wa]") | .[0] as $v
        | ($c | [scan("\\b" + $v + "\\s*=\\s*([\"'])([^\"']+)\\1")] | if length > 0 then .[0][1] else empty end) ]
    )
  | map(select(. != "/dev/null" and (startswith("&") | not) and (startswith("-") | not) and (contains("$(") | not) and (test("[<>'\"*]") | not)))
  | unique;
JQ
)

# Extract files modified: Edit and Write calls, plus the files Bash commands write ("Bash: <path>")
extract_files_modified() {
    echo "=== Files Modified ==="
    jq -r "${PT_JQ_DEFS}"'
      select(.message.content[]?.type == "tool_use") |
      .message.content[] | select(.type == "tool_use") |
      if (.name == "Edit" or .name == "Write") then "\(.name): \(.input.file_path)"
      elif .name == "Bash" then ((.input.command // "") | pt_bash_write_targets[] | "Bash: \(.)")
      else empty end' "$TRANSCRIPT" 2>/dev/null | sort -u
}

# Extract bash commands
extract_commands() {
    echo "=== Bash Commands ==="
    jq -r 'select(.message.content[]?.type == "tool_use" and .message.content[]?.name == "Bash") |
      .message.content[] | select(.type == "tool_use" and .name == "Bash") |
      .input.command' "$TRANSCRIPT" 2>/dev/null | head -50
}

# Failed tool results, by is_error. The old word match (error, fail, exception) listed
# successful results that quoted one, so on a long session ticket text filled the 30
# lines, and it missed failed results that named none: a cat of a missing file, a check
# that exited 1 after printing "syntax ok", a Write refused as modified since read.
extract_errors() {
    echo "=== Errors & Failures ==="
    jq -r 'select(.type == "user") | .message.content[]? |
      select(.type == "tool_result" and .is_error == true) |
      (if (.content | type) == "array" then [.content[] | select(.type == "text") | .text] | join(" ")
       else (.content // "" | tostring) end) |
      gsub("\\s+"; " ") | .[0:200]' "$TRANSCRIPT" 2>/dev/null | head -30
}

# Extract subagent invocations. The tool is Agent (Task is its old name), so a Task-only
# match left this section empty for every recap that had sub-agents. Matched per block:
# the record-level `select(A and B)` form prints a record with two calls four times each.
extract_subagents() {
    echo "=== Subagent Invocations ==="
    jq -r '.message.content[]? | select(.type == "tool_use" and (.name == "Agent" or .name == "Task")) |
      "[\(.input.subagent_type)] \(.input.description)"' "$TRANSCRIPT" 2>/dev/null
}

# Extract educational insights (★ Insight blocks from assistant messages)
extract_insights() {
    echo "=== Educational Insights ==="
    jq -r 'select(.type == "assistant") |
      .message.content[] | select(.type == "text") |
      .text' "$TRANSCRIPT" 2>/dev/null | \
    awk '/★ Insight/,/─────────────────────────────────────────────────$/' | \
    grep -v '^$' || true  # no insight block is not a failure; under set -e it ended `all` with exit 1
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
    # Messages from other sessions arrive in five envelopes, and a recap that reads "0"
    # here on an orchestrated session understates it. An idle session stores a peer
    # message, or a subagent hand-back prefixed "Another Claude session sent a message:",
    # as an isMeta user record; a busy session queues either as a queued_command
    # attachment instead; and agent-team reports are plain user records that can hold
    # several <teammate-message> blocks each (eight in one record on a real transcript),
    # so those are counted per block.
    echo "Inbound session messages: $(jq -s '
      ([.[] | select(.type == "user") |
         (.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join(" ")) end) as $t |
         (if .isMeta and (($t | contains("<cross-session-message")) or
                          (($t | startswith("Another Claude session sent a message:")) and ($t | contains("<agent-message"))))
          then 1 else 0 end)
         + ($t | [scan("<teammate-message")] | length)] | add // 0)
      + ([.[] | select(.type == "attachment" and .attachment.type == "queued_command"
                       and ((.attachment.prompt // "") | (startswith("<cross-session-message") or startswith("<agent-message"))))] | length)' \
      "$TRANSCRIPT" 2>/dev/null)"
    echo "Assistant messages: $(jq -s '[.[] | select(.type == "assistant")] | length' "$TRANSCRIPT" 2>/dev/null)"
    echo "Tool uses: $(jq -s '[.[] | .message.content[]? | select(.type == "tool_use")] | length' "$TRANSCRIPT" 2>/dev/null)"
    echo "Summaries: $(jq -s '[.[] | select(.type == "summary")] | length' "$TRANSCRIPT" 2>/dev/null)"
    echo ""
    echo "Files read: $(jq -r 'select(.message.content[]?.name == "Read") | .message.content[] | select(.name == "Read") | .input.file_path' "$TRANSCRIPT" 2>/dev/null | sort -u | wc -l | tr -d ' ')"
    echo "Files modified: $(jq -r "${PT_JQ_DEFS}"'.message.content[]? | select(.type == "tool_use") | if (.name == "Edit" or .name == "Write") then .input.file_path elif .name == "Bash" then ((.input.command // "") | pt_bash_write_targets[]) else empty end' "$TRANSCRIPT" 2>/dev/null | sort -u | wc -l | tr -d ' ')"
    echo "Files modified via Bash: $(jq -r "${PT_JQ_DEFS}"'.message.content[]? | select(.type == "tool_use" and .name == "Bash") | ((.input.command // "") | pt_bash_write_targets[])' "$TRANSCRIPT" 2>/dev/null | sort -u | wc -l | tr -d ' ')"
    # Counted as tool_use blocks. The old Bash line piped every record that held a call
    # through wc -l, so it counted pretty-printed lines (2061 for 31 calls on a real
    # transcript), and the subagent tool is Agent: Task never matched, so this read 0.
    echo "Bash commands: $(jq -s '[.[] | .message.content[]? | select(.type == "tool_use" and .name == "Bash")] | length' "$TRANSCRIPT" 2>/dev/null)"
    echo "Subagents spawned: $(jq -s '[.[] | .message.content[]? | select(.type == "tool_use" and (.name == "Agent" or .name == "Task"))] | length' "$TRANSCRIPT" 2>/dev/null)"
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
