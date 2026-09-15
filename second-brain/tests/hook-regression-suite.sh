#!/bin/bash
# Regression suite for the second-brain session hooks.
#
# Runs entirely against a scratch knowledge bank in a temp directory; it never
# reads or writes the real vault. Usage:
#
#   ./tests/hook-regression-suite.sh            # test this working tree
#   PLUGIN=/path/to/second-brain ./tests/...    # test an installed plugin copy
#
# Two environment notes that are easy to trip over. HOME is redirected only for
# the hook processes, because get_kb_path builds its config path from ${HOME} by
# plain assignment and offers no override; redirecting it for the whole script
# would also hit any tool that resolves through a version-manager shim. File
# edits use awk and sed for the same reason. HERDR_PANE_ID and TMUX_PANE are
# cleared per invocation so the terminal rename helper cannot touch a real pane.
PLUGIN="${PLUGIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROOT=$(mktemp -d /tmp/sb-test.XXXXXX)
H="$ROOT/home"; KB="$ROOT/kb"
mkdir -p "$H/.claude/plugins/config/second-brain" "$KB/_sessions" "$H/.claude/projects/proj"
printf '{"knowledge_bank_path":"%s"}\n' "$KB" > "$H/.claude/plugins/config/second-brain/config.json"
TODAY=$(date +%Y-%m-%d)
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
chk(){ [ "$2" = "$3" ] && ok "$1" || no "$1 (expected '$3', got '$2')"; }
prop(){ sed -n '/^---$/,/^---$/p' "$1" 2>/dev/null | grep "^$2:" | head -1 | sed "s/^$2: *//; s/^\"//; s/\"$//"; }
# HERDR_PANE_ID/TMUX_PANE cleared so the rename helper cannot touch the real terminal
run(){ local s="$1"; shift; printf '%s' "$1" | env HOME="$H" HERDR_PANE_ID= TMUX_PANE= "$PLUGIN/hooks/scripts/$s" >/dev/null 2>&1; }
ins_after(){ awk -v p="$2" '{print} $0==p{print "  - kepttag"}' "$1" > "$1.t" && mv "$1.t" "$1"; }

echo "== 1. startup registers a session =="
S1=11111111-1111-1111-1111-111111111111
T1="$H/.claude/projects/proj/$S1.jsonl"; echo '{"type":"user","cwd":"/tmp/work"}' > "$T1"
run session_start.sh "{\"session_id\":\"$S1\",\"cwd\":\"/tmp/work\",\"transcript_path\":\"$T1\",\"source\":\"startup\"}"
F1="$KB/_sessions/$TODAY/$S1"; M1="$F1/session.md"
[ -f "$M1" ] && ok "note created" || no "note created"
chk "date is today" "$(prop "$M1" date)" "$TODAY"
chk "project from cwd" "$(prop "$M1" project)" "work"
chk "forked_from empty for a new session" "$(prop "$M1" forked_from)" ""
[ -z "$(find /tmp -maxdepth 1 -name 'second-brain-startup-*' -print -quit)" ] && ok "no rendezvous key written" || no "no rendezvous key written"

echo "== 2. /clear does not discard user metadata =="
sed -i '' 's/^summary:$/summary: "kept summary"/' "$M1"
ins_after "$M1" "tags:"
run session_start.sh "{\"session_id\":\"$S1\",\"cwd\":\"/tmp/work\",\"transcript_path\":\"$T1\",\"source\":\"clear\"}"
chk "summary survives /clear" "$(prop "$M1" summary)" "kept summary"
grep -q 'kepttag' "$M1" && ok "tags survive /clear" || no "tags survive /clear"

echo "== 3. resume rebuilds a LOST note without refiling the date =="
OLD=2026-01-05; S3=33333333-3333-3333-3333-333333333333
mkdir -p "$KB/_sessions/$OLD/$S3/docs"; echo leftover > "$KB/_sessions/$OLD/$S3/docs/note.md"
T3="$H/.claude/projects/proj/$S3.jsonl"
printf '%s\n' '{"type":"user","cwd":"/tmp/work3","timestamp":"2026-01-05T10:00:00Z"}' '{"type":"custom-title","customTitle":"recovered-name"}' > "$T3"
run session_resume.sh "{\"session_id\":\"$S3\",\"cwd\":\"/tmp/work3\",\"transcript_path\":\"$T3\",\"source\":\"resume\"}"
M3="$KB/_sessions/$OLD/$S3/session.md"
[ -f "$M3" ] && ok "lost note rebuilt at resume" || no "lost note rebuilt at resume"
chk "date kept from folder, not today" "$(prop "$M3" date)" "$OLD"
chk "name recovered from transcript" "$(prop "$M3" session_name)" "recovered-name"
[ ! -d "$KB/_sessions/$TODAY/$S3" ] && ok "not refiled under today" || no "not refiled under today"

echo "== 4. a fork records its parent =="
S4=44444444-4444-4444-4444-444444444444
T4="$H/.claude/projects/proj/$S4.jsonl"
printf '%s\n' "{\"type\":\"hook_success\",\"content\":\"Session folder created: $KB/_sessions/$OLD/$S3\"}" '{"type":"user","cwd":"/tmp/work"}' > "$T4"
run session_start.sh "{\"session_id\":\"$S4\",\"cwd\":\"/tmp/work\",\"transcript_path\":\"$T4\",\"source\":\"fork\"}"
chk "forked_from names the parent" "$(prop "$KB/_sessions/$TODAY/$S4/session.md" forked_from)" "$S3"

echo "== 5. a peer's resume does NOT delete another session's folder =="
S5=55555555-5555-5555-5555-555555555555
T5="$H/.claude/projects/proj/$S5.jsonl"; echo '{"type":"user","cwd":"/tmp/work"}' > "$T5"
run session_start.sh "{\"session_id\":\"$S5\",\"cwd\":\"/tmp/work\",\"transcript_path\":\"$T5\",\"source\":\"startup\"}"
run session_resume.sh "{\"session_id\":\"$S5\",\"cwd\":\"/tmp/work\",\"transcript_path\":\"$T5\",\"source\":\"compact\"}"
[ -f "$M1" ] && ok "peer folder in the same cwd survived" || no "peer folder in the same cwd survived"
[ -f "$KB/_sessions/$TODAY/$S4/session.md" ] && ok "fork folder in the same cwd survived" || no "fork folder in the same cwd survived"

echo "== 6. end hook reconstructs instead of writing a blank stub =="
S6=66666666-6666-6666-6666-666666666666
T6="$H/.claude/projects/proj/$S6.jsonl"
printf '%s\n' '{"type":"user","cwd":"/tmp/work6","timestamp":"2026-09-14T01:02:03Z"}' '{"type":"custom-title","customTitle":"ended-name"}' > "$T6"
run session_end.sh "{\"transcript_path\":\"$T6\",\"cwd\":\"/tmp/work6\",\"reason\":\"other\"}"
M6="$KB/_sessions/$TODAY/$S6/session.md"
[ -f "$M6" ] && ok "note created at end" || no "note created at end"
chk "cwd recovered"     "$(prop "$M6" cwd)"     "/tmp/work6"
chk "project recovered" "$(prop "$M6" project)" "work6"
chk "name recovered"    "$(prop "$M6" session_name)" "ended-name"
[ -n "$(prop "$M6" started_at)" ] && ok "started_at recovered, not blank" || no "started_at recovered, not blank"
[ -n "$(prop "$M6" ended_at)"   ] && ok "ended_at set" || no "ended_at set"

echo "== 7. unknown properties survive the end rewrite =="
awk '$0=="tags:"{print "recap_status: requested"} {print}' "$M1" > "$M1.t" && mv "$M1.t" "$M1"
run session_end.sh "{\"transcript_path\":\"$T1\",\"cwd\":\"/tmp/work\",\"reason\":\"other\"}"
chk "recap_status preserved" "$(prop "$M1" recap_status)" "requested"
chk "summary still preserved" "$(prop "$M1" summary)" "kept summary"
grep -q 'kepttag' "$M1" && ok "tags still preserved" || no "tags still preserved"

echo "== 8. pre_compact records into the true dated folder =="
run pre_compact.sh "{\"transcript_path\":\"$T3\"}"
[ -f "$KB/_sessions/$OLD/$S3/compaction-points.txt" ] && ok "boundary recorded in the true dated folder" || no "boundary recorded in the true dated folder"
[ ! -d "$KB/_sessions/$TODAY/$S3" ] && ok "pre_compact did not create a today folder" || no "pre_compact did not create a today folder"

echo
echo "RESULT: $PASS passed, $FAIL failed"
rm -rf "$ROOT"
[ "$FAIL" -eq 0 ]
