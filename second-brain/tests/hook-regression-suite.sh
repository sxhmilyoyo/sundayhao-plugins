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
CFGF="$H/.claude/plugins/config/second-brain/config.json"
# The domain set is the vault's projects/ folders; the map keys are path prefixes
# matched on a path boundary, and a trailing * matches any deeper path (ADR-0004).
mkdir -p "$KB/projects/a2x" "$KB/projects/aax" "$KB/projects/cc"
cat > "$CFGF" << CFG
{
  "version": "1.0",
  "knowledge_bank_path": "$KB",
  "project_domains": {
    "/tmp/mapped": { "domain": "cc" },
    "/tmp/mapped/deeper": { "domain": "a2x" },
    "/tmp/pkg*": { "domain": "aax", "default_tags": ["pkg-hint"] },
    "/tmp/bogus": { "domain": "not-a-domain" }
  }
}
CFG
TODAY=$(date +%Y-%m-%d)
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
chk(){ [ "$2" = "$3" ] && ok "$1" || no "$1 (expected '$3', got '$2')"; }
prop(){ sed -n '/^---$/,/^---$/p' "$1" 2>/dev/null | grep "^$2:" | head -1 | sed "s/^$2: *//; s/^\"//; s/\"$//"; }
has(){ [ -n "$1" ] && echo yes || echo no; }
# HERDR_PANE_ID/TMUX_PANE cleared so the rename helper cannot touch the real terminal
run(){ local s="$1"; shift; printf '%s' "$1" | env HOME="$H" HERDR_PANE_ID= TMUX_PANE= "$PLUGIN/hooks/scripts/$s" >/dev/null 2>&1; }
ins_after(){ awk -v p="$2" '{print} $0==p{print "  - kepttag"}' "$1" > "$1.t" && mv "$1.t" "$1"; }
# Start a session through the real hook and return its stdout, so the injected
# instruction can be asserted on. Trailing args are extra environment pairs.
start(){
    local id="$1" src="$2" title="$3" cwd="$4"; shift 4
    local t="$H/.claude/projects/proj/$id.jsonl"
    [ -f "$t" ] || printf '{"type":"user","cwd":"%s"}\n' "$cwd" > "$t"
    printf '{"session_id":"%s","cwd":"%s","transcript_path":"%s","source":"%s","session_title":"%s"}' \
        "$id" "$cwd" "$t" "$src" "$title" \
      | env HOME="$H" HERDR_PANE_ID= TMUX_PANE= "$@" "$PLUGIN/hooks/scripts/session_start.sh" 2>/dev/null
}
# Did the hook ask the model to derive metadata?
inj(){ case "$1" in *"Automatic session-metadata derivation"*) echo yes ;; *) echo no ;; esac; }
# Write a fork transcript whose replayed parent marker sits in an attachment
# record, which is the only shape that counts as lineage.
fork_transcript(){
    printf '{"type":"attachment","attachment":{"type":"hook_success","content":"Session folder created: %s"}}\n{"type":"user","cwd":"/tmp/mapped"}\n' \
        "$2" > "$H/.claude/projects/proj/$1.jsonl"
}

echo "== 1. startup registers a session =="
S1=11111111-1111-1111-1111-111111111111
T1="$H/.claude/projects/proj/$S1.jsonl"; echo '{"type":"user","cwd":"/tmp/work"}' > "$T1"
run session_start.sh "{\"session_id\":\"$S1\",\"cwd\":\"/tmp/work\",\"transcript_path\":\"$T1\",\"source\":\"startup\"}"
F1="$KB/_sessions/$TODAY/$S1"; M1="$F1/session.md"
[ -f "$M1" ] && ok "note created" || no "note created"
chk "date is today" "$(prop "$M1" date)" "$TODAY"
chk "unmapped cwd leaves project empty" "$(prop "$M1" project)" ""
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
# The replayed marker's real shape: an attachment record wrapping the hook's
# output, verified against four fork transcripts in the corpus.
printf '%s\n' "{\"type\":\"attachment\",\"attachment\":{\"type\":\"hook_success\",\"content\":\"Session folder created: $KB/_sessions/$OLD/$S3\"}}" '{"type":"user","cwd":"/tmp/work"}' > "$T4"
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
chk "project not invented from basename" "$(prop "$M6" project)" ""
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

echo "== 9. project resolves to a knowledge-bank domain, never a basename =="
RP="$PLUGIN/skills/common/resolve_project.sh"
rp(){ env HOME="$H" bash -c 'source "$1"; resolve_project "$2"' _ "$RP" "$1"; }
vp(){ env HOME="$H" bash -c 'source "$1"; validate_project "$2"' _ "$RP" "$1"; }
chk "unmapped cwd resolves to empty"       "$(rp /tmp/work)"          ""
chk "mapped cwd resolves to its domain"    "$(rp /tmp/mapped)"        "cc"
chk "longest prefix wins"                  "$(rp /tmp/mapped/deeper)" "a2x"
chk "a child of a mapped dir inherits"     "$(rp /tmp/mapped/other)"  "cc"
chk "match stops at a path boundary"       "$(rp /tmp/mappedother)"   ""
chk "a trailing * matches deeper paths"    "$(rp /tmp/pkgFoo/src)"    "aax"
chk "a domain outside the set is refused"  "$(rp /tmp/bogus)"         ""
chk "a legacy basename is unresolved"      "$(vp second-brain)"       ""
chk "a real domain validates"              "$(vp a2x)"                "a2x"
chk "one source of truth for the set" \
    "$(env HOME="$H" bash -c 'source "$1"; list_project_domains' _ "$RP" | paste -sd, -)" "a2x,aax,cc"
chk "default tags are readable as hints" \
    "$(env HOME="$H" bash -c 'source "$1"; project_default_tags "$2"' _ "$RP" /tmp/pkgFoo)" "pkg-hint"

echo "== 10. config --set preserves keys it does not own =="
SK="$PLUGIN/skills/common/setup_kb_path.sh"
GK="$PLUGIN/skills/common/get_kb_path.sh"
gv(){ env HOME="$H" bash -c 'source "$1"; get_plugin_config_value "$2" "$3"' _ "$GK" "$1" "$2"; }
env HOME="$H" "$SK" --set auto_recap notify >/dev/null 2>&1
chk "--set writes the key"               "$(jq -r '.auto_recap' "$CFGF")" "notify"
chk "--set keeps the knowledge bank"     "$(jq -r '.knowledge_bank_path' "$CFGF")" "$KB"
chk "--set keeps the domain map"         "$(jq -r '.project_domains["/tmp/mapped"].domain' "$CFGF")" "cc"
env HOME="$H" "$SK" --set auto_recap sideways >/dev/null 2>&1 \
    && no "--set rejects an invalid auto_recap" || ok "--set rejects an invalid auto_recap"
chk "a rejected value is not written"    "$(jq -r '.auto_recap' "$CFGF")" "notify"
env HOME="$H" "$SK" --configure "$KB" >/dev/null 2>&1
chk "--configure preserves auto_recap"  "$(jq -r '.auto_recap' "$CFGF")" "notify"
chk "--configure preserves the map"     "$(jq -r '.project_domains["/tmp/mapped"].domain' "$CFGF")" "cc"
chk "config reader returns a value"     "$(gv auto_recap off)" "notify"
chk "config reader falls back"           "$(gv nonesuch off)"   "off"

echo "== 11. the injection gate: only a named, unstamped, lineage-free startup =="
S9=99999999-9999-9999-9999-999999999991
O=$(start $S9 startup named-one /tmp/mapped); M9="$KB/_sessions/$TODAY/$S9/session.md"
chk "a named startup is asked to derive"     "$(inj "$O")" yes
chk "the request is stamped on the note"     "$(has "$(prop "$M9" metadata_requested_at)")" yes
chk "session_name comes from stdin"          "$(prop "$M9" session_name)" "named-one"
chk "project comes from the map"             "$(prop "$M9" project)" "cc"
chk "the instruction names the domain hint"  "$(case "$O" in *"cc"*) echo yes ;; *) echo no ;; esac)" yes
O=$(start $S9 startup named-one /tmp/mapped)
chk "a stamped session is not re-asked"      "$(inj "$O")" no
SA=99999999-9999-9999-9999-999999999992
O=$(start $SA clear named-two /tmp/mapped)
chk "/clear is never asked"                  "$(inj "$O")" no
SB=99999999-9999-9999-9999-999999999993
O=$(start $SB startup "" /tmp/mapped)
chk "an unnamed session is not asked"        "$(inj "$O")" no
chk "but its project is still resolved"      "$(prop "$KB/_sessions/$TODAY/$SB/session.md" project)" "cc"

echo "== 12. a delegation marker is honoured only at startup =="
ins_after "$M9" "tags:"
SC=99999999-9999-9999-9999-999999999994
O=$(start $SC startup named-four /tmp/work SECOND_BRAIN_DELEGATED_BY=$S9 SECOND_BRAIN_DELEGATED_BY_NAME=named-one)
MC="$KB/_sessions/$TODAY/$SC/session.md"
chk "delegated_by is recorded"           "$(prop "$MC" delegated_by)" "$S9"
chk "delegated_by_name is recorded"      "$(prop "$MC" delegated_by_name)" "named-one"
chk "a delegate is never asked to derive" "$(inj "$O")" no
chk "a delegate copies the launcher tags" "$(grep -c 'kepttag' "$MC")" "1"
chk "a delegate inherits the domain"     "$(prop "$MC" project)" "cc"
chk "the body carries a Lineage section" "$(grep -c '^## Lineage' "$MC")" "1"
chk "lineage links the full folder path" "$(grep -c '_sessions/'"$TODAY"'/'"$S9"'/session|named-one' "$MC")" "1"
SD=99999999-9999-9999-9999-999999999995
start $SD resume named-five /tmp/mapped SECOND_BRAIN_DELEGATED_BY=$S9 >/dev/null
chk "a stray marker on resume is ignored" "$(prop "$KB/_sessions/$TODAY/$SD/session.md" delegated_by)" ""

echo "== 13. forks inherit, and an untagged source stays untagged =="
SE=99999999-9999-9999-9999-999999999996
fork_transcript $SE "$KB/_sessions/$TODAY/$S9"
O=$(start $SE fork "" /tmp/mapped); ME="$KB/_sessions/$TODAY/$SE/session.md"
chk "forked_from names the parent"       "$(prop "$ME" forked_from)" "$S9"
chk "forked_from_name is recorded"       "$(prop "$ME" forked_from_name)" "named-one"
chk "a fork copies the parent's tags"    "$(grep -c 'kepttag' "$ME")" "1"
chk "a fork is never asked to derive"    "$(inj "$O")" no
SF=99999999-9999-9999-9999-999999999997
fork_transcript $SF "$KB/_sessions/$TODAY/$SB"
O=$(start $SF fork "" /tmp/mapped); MF="$KB/_sessions/$TODAY/$SF/session.md"
chk "an untagged parent yields no tags"  "$(grep -c 'kepttag' "$MF")" "0"
chk "and still no derivation request"    "$(inj "$O")" no

echo "== 14. only an attachment record counts as a replayed parent marker =="
SG=99999999-9999-9999-9999-999999999998
printf '{"type":"user","message":{"content":"quoting Session folder created: %s from a tool result"}}\n' \
    "$KB/_sessions/$TODAY/$S9" > "$H/.claude/projects/proj/$SG.jsonl"
start $SG startup quoter /tmp/mapped >/dev/null
chk "a quoted marker is not lineage"     "$(prop "$KB/_sessions/$TODAY/$SG/session.md" forked_from)" ""

echo "== 15. the end hook backfills the lineage name, never the tags =="
SH=99999999-9999-9999-9999-999999999999
fork_transcript $SH "$KB/_sessions/$TODAY/$S9"
start $SH fork "" /tmp/mapped >/dev/null
MH="$KB/_sessions/$TODAY/$SH/session.md"
sed -i '' 's/^forked_from_name: .*/forked_from_name: ""/' "$MH"
run session_end.sh "{\"transcript_path\":\"$H/.claude/projects/proj/$SH.jsonl\",\"cwd\":\"/tmp/mapped\",\"reason\":\"other\"}"
chk "forked_from_name backfilled at exit" "$(prop "$MH" forked_from_name)" "named-one"
chk "Lineage regenerated at exit"         "$(grep -c '^## Lineage' "$MH")" "1"
STAMP9=$(prop "$M9" metadata_requested_at)
run session_end.sh "{\"transcript_path\":\"$H/.claude/projects/proj/$S9.jsonl\",\"cwd\":\"/tmp/mapped\",\"reason\":\"other\"}"
chk "the stamp survives the end rewrite"  "$(prop "$M9" metadata_requested_at)" "$STAMP9"
run session_end.sh "{\"transcript_path\":\"$H/.claude/projects/proj/$SC.jsonl\",\"cwd\":\"/tmp/work\",\"reason\":\"other\"}"
chk "delegated_by survives the end rewrite"      "$(prop "$MC" delegated_by)" "$S9"
chk "delegated_by_name survives the end rewrite" "$(prop "$MC" delegated_by_name)" "named-one"

echo
echo "RESULT: $PASS passed, $FAIL failed"
rm -rf "$ROOT"
[ "$FAIL" -eq 0 ]
