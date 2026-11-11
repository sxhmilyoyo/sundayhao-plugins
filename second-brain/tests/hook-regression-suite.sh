#!/bin/bash
# Regression suite for the second-brain session hooks.
#
# Runs entirely against a scratch knowledge bank in a temp directory; it never
# reads or writes the real vault. Usage:
#
#   ./tests/hook-regression-suite.sh            # test this working tree
#   PLUGIN=/path/to/second-brain ./tests/...    # test an installed plugin copy
#
# Three environment notes that are easy to trip over. HOME is redirected only for
# the hook processes, because get_kb_path builds its config path from ${HOME} by
# plain assignment and offers no override; redirecting it for the whole script
# would also hit any tool that resolves through a version-manager shim. File
# edits use awk and sed for the same reason. HERDR_PANE_ID and TMUX_PANE are
# cleared per invocation so the terminal rename helper cannot touch a real pane.
#
# Third: the suite inherits its caller's environment, and two kinds of inherited
# state make it lie rather than fail. The SECOND_BRAIN_* recap markers are now
# unset below -- run from inside a recap session before that, this reported 8 false
# failures silently. And it is not re-entrant: fixture session ids are fixed, so two
# copies at once corrupt each other's results, and an interrupted run leaks
# /tmp/second-brain-folder-<id> files that outlive it. Run one at a time, from an
# ordinary shell.
PLUGIN="${PLUGIN:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
ROOT=$(mktemp -d /tmp/sb-test.XXXXXX)
# The real temp directory: /private/tmp on macOS, where /tmp is a symlink that find
# does not descend, and plain /tmp on Linux, which has no /private/tmp at all.
TMPREAL=$(cd /tmp && pwd -P)
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
# ── The real Herdr is out of reach for the whole run ─────────────────────────────
# This suite opened two real panes in the user's workspace before this guard existed,
# splitting the pane of the session that ran the tests and pointing the new ones at a
# scratch vault that the suite then deleted. Two panes, both dead on arrival.
#
# Clearing HERDR_PANE_ID per invocation was not enough, because the launcher resolves the
# binary itself: `command -v herdr`, falling back to $HOME/.local/bin/herdr. Any case that
# forgot to clear the variables, or that reached the launcher through an `eval` of a
# printed command, got the real binary and a real pane id from the ambient environment.
#
# So the environment is made hostile once, here, rather than per call site:
#   - a tripwire `herdr` first on PATH, which records the attempt and fails, so
#     `command -v herdr` can never resolve to the real binary and the fallback is dead;
#   - the Herdr detection variables cleared for every child, so the launcher's gate is
#     shut unless a case deliberately opens it with a stub of its own.
# A case that wants the Herdr path puts its own stub earlier on PATH (see case 34).
# The tripwire log is asserted empty at the end: reaching the real Herdr is a test
# failure, not a surprise in someone's terminal.
#
# The Herdr app is guarded the same way, and needs it more: ccfind drives the app's window
# from any hc terminal that can find `herdr-app`, and this suite is usually run from one. So
# `herdr-app` and `hc` get tripwires too, and $HC_TERMINAL_ID, the app's gate, is cleared
# with the others below (cases 40b, 40c and 48 open it with stubs of their own).
mkdir -p "$ROOT/bin"
TRIPWIRE="$ROOT/herdr-tripwire.log"
for bin in herdr herdr-app hc; do
cat > "$ROOT/bin/$bin" << TRIP
#!/bin/bash
printf 'REAL %s REACHED: %s\n' "$bin" "\$*" >> "$TRIPWIRE"
echo "$bin: the regression suite must never call the real binary" >&2
exit 1
TRIP
chmod +x "$ROOT/bin/$bin"
done
export PATH="$ROOT/bin:$PATH"
# Six variables, not four. HERDR_SOCKET_PATH is the channel to the running daemon, so the
# real binary reaches the live workspace through it whatever pane id it was handed, which
# is how a split lands in someone's terminal rather than failing. HERDR_BIN_PATH is an
# absolute path to the real binary and would bypass PATH order entirely, so the tripwire
# above cannot cover it; nothing in the plugin reads that one today, which makes it latent
# rather than live, and exactly the kind of thing to clear before it becomes live.
export HERDR_ENV= HERDR_PANE_ID= HERDR_TAB_ID= HERDR_WORKSPACE_ID= \
       HERDR_SOCKET_PATH= HERDR_BIN_PATH= TMUX_PANE=
# The Herdr app's gate is $HC_TERMINAL_ID. CCFIND_REPORT=labels would turn a pick into an hc
# label on the caller's own terminal instead (case 40c).
export HC_TERMINAL_ID= CCFIND_REPORT=
# ── The recap markers are cleared for the same reason ────────────────────────────
# Run from inside a recap session, this suite reported 8 false failures and said
# nothing about why: 266 passed / 12 failed against 274 / 4 from an ordinary shell.
# The recap launcher exports SECOND_BRAIN_RECAP_OF (plus _PLUGIN_ROOT, _RECAP_NAME and
# _PARENT_PID) into the pane it starts, every child inherits them, and RECAP_OF alone
# marks the process as a recap — so the end hook stamps `exempt` instead of
# `requested`, which is the whole exempt cluster, and the notice and launcher rows
# follow from it. Reproduced both ways: clearing all four gives 274/4, restoring only
# RECAP_OF gives back all 12.
#
# Cases that want the marker pass it per invocation through `env`, so clearing it here
# takes nothing away from them. Unset rather than set empty: absent is what a normal
# session's environment looks like.
#
# The irony is worth recording. ADR-0003 exists because this marker must be read from
# the persisted note and never from the inherited environment, and the vault states the
# same rule as "Trust the Persisted Fact Not the Inherited Environment". The suite that
# guards that decision was itself caught by the hazard the decision is about.
#
# The other launch markers are cleared with them, for a suite run from a session that
# something launched: a delegate carries the two delegation markers, and a session of the
# ticket dispatcher those, the exemption and its recap group. Run from a delegate on
# 2026-11-11, the suite reported 519 passed and 2 failed against 521 and 0: the first
# startup inherited the launcher's domain, and an unnamed recap took a delegate's name.
unset SECOND_BRAIN_RECAP_OF SECOND_BRAIN_PLUGIN_ROOT SECOND_BRAIN_RECAP_NAME \
      SECOND_BRAIN_PARENT_PID \
      SECOND_BRAIN_DELEGATED_BY SECOND_BRAIN_DELEGATED_BY_NAME \
      SECOND_BRAIN_RECAP_EXEMPT SECOND_BRAIN_RECAP_GROUP

TODAY=$(date +%Y-%m-%d)
PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); echo "  PASS  $1"; }
no(){ FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
chk(){ [ "$2" = "$3" ] && ok "$1" || no "$1 (expected '$3', got '$2')"; }
prop(){ sed -n '/^---$/,/^---$/p' "$1" 2>/dev/null | grep "^$2:" | head -1 | sed "s/^$2: *//; s/^\"//; s/\"$//"; }
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
# The real temp directory, not /tmp: searched through the macOS symlink, or at a
# hardcoded /private/tmp on Linux, this assertion passed no matter what the hook wrote.
[ -z "$(find "$TMPREAL" -maxdepth 1 -name 'second-brain-startup-*' -print -quit 2>/dev/null)" ] && ok "no rendezvous key written" || no "no rendezvous key written"

echo "== 2. /clear does not discard user metadata =="
sed 's/^summary:$/summary: "kept summary"/' "$M1" > "$M1.t" && mv "$M1.t" "$M1"
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

echo "== 11. registration writes what it can see and asks for nothing =="
# A name and a domain are facts at launch; a description is not. The start hook no
# longer asks the model for one and no longer stamps the note (ADR-0006), because the
# request was measured to be ignored. The inverted assertion is the guard: re-adding an
# injection fails here. The description is now written by the recap, after the session
# ends, which is prose in the recap skill rather than shell, so its coverage is the
# plan's acceptance run and not this suite.
S9=99999999-9999-9999-9999-999999999991
O=$(start $S9 startup named-one /tmp/mapped); M9="$KB/_sessions/$TODAY/$S9/session.md"
chk "a named startup is asked for nothing"   "$(inj "$O")" no
chk "session_name comes from stdin"          "$(prop "$M9" session_name)" "named-one"
chk "project comes from the map"             "$(prop "$M9" project)" "cc"
SB=99999999-9999-9999-9999-999999999993
O=$(start $SB startup "" /tmp/mapped)
chk "but its project is still resolved"      "$(prop "$KB/_sessions/$TODAY/$SB/session.md" project)" "cc"

echo "== 12. a delegation marker is honoured only at startup =="
ins_after "$M9" "tags:"
SC=99999999-9999-9999-9999-999999999994
O=$(start $SC startup named-four /tmp/work SECOND_BRAIN_DELEGATED_BY=$S9 SECOND_BRAIN_DELEGATED_BY_NAME=named-one)
MC="$KB/_sessions/$TODAY/$SC/session.md"
chk "delegated_by is recorded"           "$(prop "$MC" delegated_by)" "$S9"
chk "delegated_by_name is recorded"      "$(prop "$MC" delegated_by_name)" "named-one"
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

echo "== 14b. the recap notice in a session's own registration record is not lineage =="
# The start hook's whole stdout is stored as one attachment record, so the record that
# carries this session's marker also carries the recap notice, which names other
# sessions by their folder path. Only the marker's own path may name a parent.
SI=99999999-9999-9999-9999-99999999999a
printf '{"type":"attachment","attachment":{"type":"hook_success","content":"Session folder created: %s/_sessions/%s/%s\\n\\nSecond Brain: 1 recap needs attention\\n- %s named-one — requested, not started — run: recap --manual %s/_sessions/%s/%s"}}\n{"type":"user","cwd":"/tmp/mapped"}\n' \
    "$KB" "$TODAY" "$SI" "$TODAY" "$KB" "$TODAY" "$S9" > "$H/.claude/projects/proj/$SI.jsonl"
start $SI startup noticed /tmp/mapped >/dev/null
MI="$KB/_sessions/$TODAY/$SI/session.md"
chk "a notice path is not lineage"               "$(prop "$MI" forked_from)" ""
chk "and nothing is inherited from it"           "$(grep -c 'kepttag' "$MI")" "0"
SJ=99999999-9999-9999-9999-99999999999b
{ printf '{"type":"attachment","attachment":{"type":"hook_success","content":"Session folder created: %s"}}\n' "$KB/_sessions/$TODAY/$S9"
  printf '{"type":"attachment","attachment":{"type":"hook_success","content":"Session folder created: %s/_sessions/%s/%s\\n- %s untagged — requested, not started — run: recap --manual %s/_sessions/%s/%s"}}\n{"type":"user","cwd":"/tmp/mapped"}\n' \
    "$KB" "$TODAY" "$SJ" "$TODAY" "$KB" "$TODAY" "$SB"
} > "$H/.claude/projects/proj/$SJ.jsonl"
start $SJ fork "" /tmp/mapped >/dev/null
chk "a fork with a notice still names its parent" "$(prop "$KB/_sessions/$TODAY/$SJ/session.md" forked_from)" "$S9"

echo "== 15. the end hook backfills the lineage name, never the tags =="
SH=99999999-9999-9999-9999-999999999999
fork_transcript $SH "$KB/_sessions/$TODAY/$S9"
start $SH fork "" /tmp/mapped >/dev/null
MH="$KB/_sessions/$TODAY/$SH/session.md"
sed 's/^forked_from_name: .*/forked_from_name: ""/' "$MH" > "$MH.t" && mv "$MH.t" "$MH"
run session_end.sh "{\"transcript_path\":\"$H/.claude/projects/proj/$SH.jsonl\",\"cwd\":\"/tmp/mapped\",\"reason\":\"other\"}"
chk "forked_from_name backfilled at exit" "$(prop "$MH" forked_from_name)" "named-one"
chk "Lineage regenerated at exit"         "$(grep -c '^## Lineage' "$MH")" "1"
# The property is planted rather than written: nothing stamps it since ADR-0006 removed
# the start-time request. The assertion stays because it is load-bearing for recap_status,
# which reaches the note through the same unknown-property preserve loop, and because the
# notes already carrying a stamp must keep it.
awk '$0=="tags:"{print "metadata_requested_at: \"2026-09-15T00:00:00\""} {print}' "$M9" > "$M9.t" && mv "$M9.t" "$M9"
run session_end.sh "{\"transcript_path\":\"$H/.claude/projects/proj/$S9.jsonl\",\"cwd\":\"/tmp/mapped\",\"reason\":\"other\"}"
chk "a planted stamp survives the end rewrite" "$(prop "$M9" metadata_requested_at)" "2026-09-15T00:00:00"
run session_end.sh "{\"transcript_path\":\"$H/.claude/projects/proj/$SC.jsonl\",\"cwd\":\"/tmp/work\",\"reason\":\"other\"}"
chk "delegated_by survives the end rewrite"      "$(prop "$MC" delegated_by)" "$S9"
chk "delegated_by_name survives the end rewrite" "$(prop "$MC" delegated_by_name)" "named-one"

echo "== 16. a person-chosen name survives every writer, escaped exactly once =="
HELP="$PLUGIN/skills/common/obsidian_helpers.sh"
NASTY='fix the "auth" bug'
# The round trip is the property that matters: whatever a reader returns must be
# what a writer can store again without changing it.
chk "escape then unescape is the identity" \
    "$(bash -c 'source "$1" >/dev/null 2>&1; yaml_unescape "$(yaml_escape "$2")"' _ "$HELP" "$NASTY")" "$NASTY"
T16="$ROOT/nasty.md"
printf -- '---\nsession_name: "%s"\nsummary: ""\ntags:\n---\n\n# body\n' "$(printf '%s' "$NASTY" | sed 's/"/\\"/g')" > "$T16"
chk "reading a quoted scalar returns the plain value" \
    "$(bash -c 'source "$1" >/dev/null 2>&1; read_frontmatter_prop "$2" session_name' _ "$HELP" "$T16")" "$NASTY"
# A plain scalar is not escaped in YAML, so its backslashes are literal. Reading
# one must not unescape, or a value nothing wrote as an escape gets rewritten.
T16B="$ROOT/plain.md"
{ printf -- '---\n'; printf 'plain_prop: C:\\\\srv\\new\n'; printf 'quoted_prop: "C:\\\\\\\\srv"\n'; printf 'unquoted: requested\n---\n'; } > "$T16B"
rfp(){ bash -c 'source "$1" >/dev/null 2>&1; read_frontmatter_prop "$2" "$3"' _ "$HELP" "$T16B" "$1"; }
chk "a plain scalar keeps its backslashes" "$(rfp plain_prop)" 'C:\\srv\new'
chk "a quoted scalar is unescaped once"    "$(rfp quoted_prop)" 'C:\\srv'
chk "a bare word is untouched"             "$(rfp unquoted)"    "requested"
# set_frontmatter_prop must not let awk re-interpret the value it is given.
bash -c 'source "$1" >/dev/null 2>&1; set_frontmatter_prop "$2" summary "$3"' _ "$HELP" "$T16" "$NASTY"
chk "set_frontmatter_prop round-trips a quote" \
    "$(bash -c 'source "$1" >/dev/null 2>&1; read_frontmatter_prop "$2" summary' _ "$HELP" "$T16")" "$NASTY"
# The round trip alone cannot tell escaping from doing nothing at all, so assert
# the stored form too: the quote must be backslashed on disk.
chk "and stores it escaped on disk" "$(grep -c '^summary: "fix the \\"auth\\" bug"$' "$T16")" "1"
INJ='evil
summary: pwned'
bash -c 'source "$1" >/dev/null 2>&1; set_frontmatter_prop "$2" session_name "$3"' _ "$HELP" "$T16" "$INJ"
chk "a newline in a value cannot inject a second key" \
    "$(sed -n '/^---$/,/^---$/p' "$T16" | grep -c '^summary: pwned$')" "0"
chk "frontmatter is still one block" "$(grep -c '^---$' "$T16")" "2"

echo "== 17. the helpers load under zsh, which is what the skill documents =="
if command -v zsh >/dev/null 2>&1; then
    chk "sourcing from an unrelated cwd defines the resolver" \
        "$(cd /tmp && zsh -c "source '$HELP' >/dev/null 2>&1; type resolve_project >/dev/null 2>&1 && echo yes || echo no")" "yes"
    chk "and does not error on the relative source" \
        "$(cd /tmp && zsh -c "source '$HELP' 2>&1 >/dev/null" | grep -c 'no such file')" "0"
else
    ok "zsh absent, skipped"; ok "zsh absent, skipped"
fi

echo "== 18. a more specific mapping beats a wildcard that also matches =="
mkdir -p "$KB/projects/broad" "$KB/projects/narrow"
CFG18="$ROOT/cfg18"; mkdir -p "$CFG18/.claude/plugins/config/second-brain"
jq -n --arg kb "$KB" '{knowledge_bank_path:$kb,project_domains:{"/w/a*":{domain:"broad"},"/w/ab":{domain:"narrow"}}}' \
    > "$CFG18/.claude/plugins/config/second-brain/config.json"
rp18(){ env HOME="$CFG18" bash -c 'source "$1"; resolve_project "$2"' _ "$RP" "$1"; }
chk "exact key beats a wildcard"          "$(rp18 /w/ab)"      "narrow"
chk "child of the exact key beats it too" "$(rp18 /w/ab/deep)" "narrow"
chk "the wildcard still covers siblings"  "$(rp18 /w/az)"      "broad"

echo "== 19. a mapping the tool accepts is a mapping that resolves =="
SK19(){ env HOME="$CFG18" "$SK" "$@" >/dev/null 2>&1; }
SK19 --set-domain /tmp/notags broad && ok "--set-domain works without tags" || no "--set-domain works without tags"
chk "and the tagless entry resolves"      "$(rp18 /tmp/notags)" "broad"
SK19 --set-domain /tmp/slash/ broad t && ok "a tab-completed trailing slash is accepted" || no "a tab-completed trailing slash is accepted"
chk "a trailing slash still resolves"     "$(rp18 /tmp/slash)"     "broad"
chk "and so do its children"              "$(rp18 /tmp/slash/sub)" "broad"
SK19 --set-domain '/tmp/mid*dle' broad && no "a non-final * is refused" || ok "a non-final * is refused"
chk "a regex-ish value does not validate as a domain" \
    "$(env HOME="$CFG18" bash -c 'source "$1"; validate_project "b.oad"' _ "$RP")" ""

echo "== 20. --set cannot clobber keys that have their own writer =="
SK20(){ env HOME="$CFG18" "$SK" "$@" >/dev/null 2>&1; }
C20="$CFG18/.claude/plugins/config/second-brain/config.json"
SK20 --set knowledge_bank_path /nonexistent && no "--set refuses the kb path" || ok "--set refuses the kb path"
chk "the kb path is untouched"   "$(jq -r '.knowledge_bank_path' "$C20")" "$KB"
SK20 --set project_domains oops && no "--set refuses the domain map" || ok "--set refuses the domain map"
chk "the domain map is still an object" "$(jq -r '.project_domains|type' "$C20")" "object"

echo "== 22. a named session is still collectable as a ghost =="
GL="$PLUGIN/skills/kb-lint/scripts/lint_ghost_folders.sh"
GKB="$ROOT/ghostkb"; mkdir -p "$GKB/_sessions/2026-01-01/g1111111-1111-1111-1111-111111111111"
printf -- '---\nsession_id: "g1111111-1111-1111-1111-111111111111"\ndate: 2026-01-01\nsession_name: "refactor-auth"\nended_at:\nsummary:\ntranscript_source:\ntags:\n---\n\n# Session\n' \
    > "$GKB/_sessions/2026-01-01/g1111111-1111-1111-1111-111111111111/session.md"
# The script reports its count on stderr and the findings on stdout.
chk "a named but empty folder is reported" \
    "$(env HOME="$H" bash "$GL" "$GKB" 0 2>&1 >/dev/null | sed -n 's/^TOTAL_GHOSTS=//p')" "1"
chk "and it is named in the findings" \
    "$(env HOME="$H" bash "$GL" "$GKB" 0 2>/dev/null | grep -c 'g1111111')" "1"

echo "== 23. the terminal is named on a launch, never on a fork =="
# A stub herdr on PATH records what would have been renamed. A fork arrives
# carrying its parent's title, so renaming there would take the parent's agent
# name away from the session still using it.
mkdir -p "$H/.local/bin"
cat > "$H/.local/bin/herdr" << 'STUB'
#!/bin/bash
echo "$*" >> "$HOME/herdr-calls.log"
exit 0
STUB
chmod +x "$H/.local/bin/herdr"
hstart(){ # $1=id $2=source $3=title
    local t="$H/.claude/projects/proj/$1.jsonl"
    [ -f "$t" ] || printf '{"type":"user","cwd":"/tmp/mapped"}\n' > "$t"
    printf '{"session_id":"%s","cwd":"/tmp/mapped","transcript_path":"%s","source":"%s","session_title":"%s"}' \
        "$1" "$t" "$2" "$3" \
      | env HOME="$H" PATH="$H/.local/bin:$PATH" HERDR_PANE_ID=stub:p1 TMUX_PANE= \
        "$PLUGIN/hooks/scripts/session_start.sh" >/dev/null 2>&1
}
: > "$H/herdr-calls.log"
hstart 66666666-6666-6666-6666-66666666aaa1 startup launch-named
chk "a launch renames the pane"  "$(grep -c 'pane rename stub:p1 launch-named' "$H/herdr-calls.log")" "1"
: > "$H/herdr-calls.log"
FK=66666666-6666-6666-6666-66666666aaa2
fork_transcript $FK "$KB/_sessions/$TODAY/$S9"
hstart $FK fork inherited-parent-title
chk "a fork renames nothing"     "$(grep -c 'rename' "$H/herdr-calls.log")" "0"
: > "$H/herdr-calls.log"
hstart 66666666-6666-6666-6666-66666666aaa1 clear launch-named
chk "a /clear renames nothing"   "$(grep -c 'rename' "$H/herdr-calls.log")" "0"

echo "== 24. the list setter writes a block, or deliberately nothing =="
# The tags block is the one list the hooks and the recap both touch, and every rule
# here is a shape this vault really produces.
HELPL="$PLUGIN/skills/common/obsidian_helpers.sh"
sfl(){ bash -c 'source "$1" >/dev/null 2>&1; set_frontmatter_list "$2" "$3" "$4"' _ "$HELPL" "$@"; }
rfl(){ bash -c 'source "$1" >/dev/null 2>&1; read_frontmatter_list "$2" "$3"' _ "$HELPL" "$@"; }
L1="$ROOT/list-a.md"
# `tags:` then a blank line then the delimiter is exactly what session_end.sh writes.
printf -- '---\nsession_name: "n"\nsummary: ""\ntags:\n\n---\n\n# body\nkeepline\n' > "$L1"
sfl "$L1" tags "alpha, beta, gamma"
# Three items, not two: a missing terminator on the last field used to drop it, which
# for a one-tag list meant the write was skipped and the note looked untouched.
chk "every item is written"            "$(rfl "$L1" tags)" "alpha, beta, gamma"
chk "the body is untouched"            "$(grep -c '^keepline$' "$L1")" "1"
sfl "$L1" tags "solo"
chk "a populated block is replaced"    "$(rfl "$L1" tags)" "solo"
chk "and leaves one item behind"       "$(grep -c '^  - ' "$L1")" "1"
cp "$L1" "$L1.snap"
sfl "$L1" tags ""
sfl "$L1" tags "  ,  , "
chk "empty input writes nothing"       "$(cmp -s "$L1.snap" "$L1" && echo same || echo changed)" "same"
L2="$ROOT/list-b.md"
printf -- '---\nn: "x"\ntags:\n  - old\n---\n\n# body\n' > "$L2"
REFUSED=$(sfl "$L2" tags 'good-one, bad: colon, has space, -leading, nested/ok' 2>&1 >/dev/null)
chk "non-slug items are refused"       "$(printf '%s' "$REFUSED" | grep -c 'refused')" "3"
chk "the slugs are still written"      "$(rfl "$L2" tags)" "good-one, nested/ok"
chk "the frontmatter stays one block"  "$(grep -c '^---$' "$L2")" "2"
# tags has to stay last, because the scalar setter inserts above it and this setter
# ends a block by scanning to the end of its items. Delimiter, n, aliases, two items,
# then tags on line 6.
chk "a non-tags list goes above tags" \
    "$(printf -- '---\nn: "x"\ntags:\n  - t\n---\n\n# b\n' > "$L2"; sfl "$L2" aliases "one, two"; \
       sed -n '/^---$/,/^---$/p' "$L2" | grep -n '^tags:$' | cut -d: -f1)" "6"

echo "== 25. recap status is compare-and-set, and single-flight =="
ST="$PLUGIN/skills/common/recap_status.sh"
SUBJ="$ROOT/subject"; mkdir -p "$SUBJ"
subjnote(){ printf -- '---\nsession_id: "s"\nproject: "data"\nsummary: ""\ntags:\n  - inherited\n---\n\n# body\nkeepline\n' > "$SUBJ/session.md"; }
st(){ env HOME="$H" "$ST" "$@" >/dev/null 2>&1; }
subjnote
st "$SUBJ" requested
chk "empty to requested lands"         "$(prop "$SUBJ/session.md" recap_status)" "requested"
st "$SUBJ" done
chk "requested to done is refused"     "$(prop "$SUBJ/session.md" recap_status)" "requested"
st "$SUBJ" running
st "$SUBJ" done "$ROOT/recapsess" --project cc --tags "plugin-second-brain, session-hooks" --summary "did the thing"
chk "running to done lands"            "$(prop "$SUBJ/session.md" recap_status)" "done"
# ADR-0006: the recap owns the description once the session has ended, and overwrites.
chk "the recap replaces a basename"    "$(prop "$SUBJ/session.md" project)" "cc"
chk "the recap writes the summary"     "$(prop "$SUBJ/session.md" summary)" "did the thing"
chk "the recap writes the tags"        "$(rfl "$SUBJ/session.md" tags)" "plugin-second-brain, session-hooks"
[ -n "$(prop "$SUBJ/session.md" recapped_at)" ] && ok "recapped_at is stamped" || no "recapped_at is stamped"
chk "recap_session points at the recap" "$(prop "$SUBJ/session.md" recap_session)" "$ROOT/recapsess"
chk "the body survives every write"    "$(grep -c '^keepline$' "$SUBJ/session.md")" "1"
cp "$SUBJ/session.md" "$SUBJ/snap"
st "$SUBJ" requested
chk "done is terminal"                 "$(cmp -s "$SUBJ/snap" "$SUBJ/session.md" && echo same || echo changed)" "same"
st "$SUBJ" requested --force
chk "and --force is its only exit"     "$(prop "$SUBJ/session.md" recap_status)" "requested"
# T14: twenty writers race for one claim. Exactly one may win, or two recaps run and
# the subject gets two daily logs. Refusals are counted as a delta, because the
# refused transition asserted above is already in this log.
REFUSED_BEFORE=$(grep -c 'refused' "$SUBJ/recap.log")
# $1 $2 $3, not $4: sh -c takes the word after the script as $0, so `_ A B C` puts C in
# $3. Reading $4 gave every racer an empty HOME, which escaped this suite's scratch HOME
# and would reach the real config the moment anything in that path reads one.
CLAIMS=$(seq 20 | xargs -P20 -I{} sh -c 'env HOME="$3" "$1" "$2" running >/dev/null 2>&1 && echo won' _ "$ST" "$SUBJ" "$H" | grep -c won)
chk "exactly one claim wins"           "$CLAIMS" "1"
chk "the nineteen losers are refused"  "$(( $(grep -c 'refused' "$SUBJ/recap.log") - REFUSED_BEFORE ))" "19"
chk "the note keeps one status line"   "$(grep -c '^recap_status:' "$SUBJ/session.md")" "1"
chk "no lock is left behind"           "$([ -d "$SUBJ/.recap.lock" ] && echo leaked || echo clean)" "clean"
mkdir -p "$SUBJ/.recap.lock"; touch -t 202601010000 "$SUBJ/.recap.lock"
st "$SUBJ" done
chk "a stale lock is broken"           "$(grep -c 'broke stale lock' "$SUBJ/recap.log")" "1"
chk "and the write goes through"       "$(prop "$SUBJ/session.md" recap_status)" "done"
# A description on any other state is a mistake, not a silent write.
st "$SUBJ" requested --force --summary "nope"
chk "a description needs done or failed" "$(prop "$SUBJ/session.md" summary)" "did the thing"

echo "== 26. the end hook requests a recap, or records that one is never needed =="
env HOME="$H" "$SK" --set auto_recap notify >/dev/null 2>&1
# Assistant records are the test, not prompts and not lines: a prompt count exempted a
# third of real sessions here, and a line count loses a short session with many turns.
turns(){ local f="$1" n="$2" i=0; : > "$f"
    printf '{"type":"user","cwd":"/tmp/mapped"}\n' >> "$f"
    while [ "$i" -lt "$n" ]; do printf '{"type":"assistant","message":{"content":[]}}\n' >> "$f"; i=$((i+1)); done; }
endrun(){ printf '{"transcript_path":"%s","cwd":"/tmp/mapped","reason":"%s"}' "$2" "$3" \
    | env HOME="$H" HERDR_PANE_ID= TMUX_PANE= "${@:4}" "$PLUGIN/hooks/scripts/session_end.sh" >/dev/null 2>&1; }
P1=aaaaaaaa-0000-0000-0000-000000000001; TP1="$H/.claude/projects/proj/$P1.jsonl"
turns "$TP1" 9; start $P1 startup real-work /tmp/mapped >/dev/null
MP1="$KB/_sessions/$TODAY/$P1/session.md"
endrun x "$TP1" prompt_input_exit
chk "a real session is requested"      "$(prop "$MP1" recap_status)" "requested"
endrun x "$TP1" prompt_input_exit
chk "a second exit changes nothing"    "$(prop "$MP1" recap_status)" "requested"
# T15: a small session that was resumed and then did real work is re-evaluated.
P2=aaaaaaaa-0000-0000-0000-000000000002; TP2="$H/.claude/projects/proj/$P2.jsonl"
turns "$TP2" 2; start $P2 startup small /tmp/mapped >/dev/null
MP2="$KB/_sessions/$TODAY/$P2/session.md"
endrun x "$TP2" prompt_input_exit
chk "two turns is exempt"              "$(prop "$MP2" recap_status)" "exempt"
turns "$TP2" 5
endrun x "$TP2" prompt_input_exit
chk "exempt is re-evaluated on growth" "$(prop "$MP2" recap_status)" "requested"
# clear and resume are not endings.
P3=aaaaaaaa-0000-0000-0000-000000000003; TP3="$H/.claude/projects/proj/$P3.jsonl"
turns "$TP3" 9; start $P3 startup cleared /tmp/mapped >/dev/null
MP3="$KB/_sessions/$TODAY/$P3/session.md"
endrun x "$TP3" clear
chk "/clear stamps nothing"            "$(prop "$MP3" recap_status)" ""
endrun x "$TP3" resume
chk "resume stamps nothing"            "$(prop "$MP3" recap_status)" ""
# T16: no evidence means no stamp, but a transcript with no reply at all is exempt.
P4=aaaaaaaa-0000-0000-0000-000000000004; TP4="$H/.claude/projects/proj/$P4.jsonl"
turns "$TP4" 9; start $P4 startup unreadable /tmp/mapped >/dev/null
MP4="$KB/_sessions/$TODAY/$P4/session.md"
chmod 000 "$TP4"
endrun x "$TP4" prompt_input_exit
chk "an unreadable transcript stamps nothing" "$(prop "$MP4" recap_status)" ""
chmod 644 "$TP4"
P5=aaaaaaaa-0000-0000-0000-000000000005; TP5="$H/.claude/projects/proj/$P5.jsonl"
turns "$TP5" 0; start $P5 startup noreply /tmp/mapped >/dev/null
endrun x "$TP5" prompt_input_exit
chk "a launch that got no reply is exempt" "$(prop "$KB/_sessions/$TODAY/$P5/session.md" recap_status)" "exempt"
# A recap session is exempt for good, decided by its note and never by the marker.
P6=aaaaaaaa-0000-0000-0000-000000000006; TP6="$H/.claude/projects/proj/$P6.jsonl"
turns "$TP6" 9; start $P6 startup a-recap /tmp/mapped >/dev/null
MP6="$KB/_sessions/$TODAY/$P6/session.md"
awk '$0=="tags:"{print "recap_of: \"/somewhere/subject\""} {print}' "$MP6" > "$MP6.t" && mv "$MP6.t" "$MP6"
endrun x "$TP6" prompt_input_exit
chk "a recap session is exempt"         "$(prop "$MP6" recap_status)" "exempt"
endrun x "$TP6" prompt_input_exit
chk "and stays exempt on a later exit"  "$(prop "$MP6" recap_status)" "exempt"
# T17: the stray marker. An inherited environment variable must not exempt real work.
P7=aaaaaaaa-0000-0000-0000-000000000007; TP7="$H/.claude/projects/proj/$P7.jsonl"
turns "$TP7" 9; start $P7 startup stray-marker /tmp/mapped >/dev/null
endrun x "$TP7" prompt_input_exit SECOND_BRAIN_RECAP_OF=/somewhere/subject
chk "a stray marker cannot exempt work" "$(prop "$KB/_sessions/$TODAY/$P7/session.md" recap_status)" "requested"
# The feature is off unless it is configured on, and a broken config reads as off.
CFG26="$ROOT/cfg26"; mkdir -p "$CFG26/.claude/plugins/config/second-brain"
jq -n --arg kb "$KB" '{knowledge_bank_path:$kb}' > "$CFG26/.claude/plugins/config/second-brain/config.json"
P8=aaaaaaaa-0000-0000-0000-000000000008; TP8="$H/.claude/projects/proj/$P8.jsonl"
turns "$TP8" 9; start $P8 startup unconfigured /tmp/mapped >/dev/null
printf '{"transcript_path":"%s","cwd":"/tmp/mapped","reason":"prompt_input_exit"}' "$TP8" \
    | env HOME="$CFG26" HERDR_PANE_ID= TMUX_PANE= "$PLUGIN/hooks/scripts/session_end.sh" >/dev/null 2>&1
chk "auto_recap absent stamps nothing" "$(prop "$KB/_sessions/$TODAY/$P8/session.md" recap_status)" ""
# The rewrite and the stamp must both survive a concurrent done (T14, hook side).
P9=aaaaaaaa-0000-0000-0000-000000000009; TP9="$H/.claude/projects/proj/$P9.jsonl"
turns "$TP9" 9; start $P9 startup racer /tmp/mapped >/dev/null
MP9="$KB/_sessions/$TODAY/$P9/session.md"
endrun x "$TP9" prompt_input_exit
env HOME="$H" "$ST" "$KB/_sessions/$TODAY/$P9" running >/dev/null 2>&1
( sleep 0.1; env HOME="$H" "$ST" "$KB/_sessions/$TODAY/$P9" done >/dev/null 2>&1 ) &
endrun x "$TP9" prompt_input_exit
wait
chk "a done written under the rewrite survives" "$(prop "$MP9" recap_status)" "done"

echo "== 26c. a done subject that keeps working is requested again =="
# fe3c98d2 was recapped done on 2026-10-13 and ran five more days with every exit reading done
# and stamping nothing. The done stamp now records the transcript's assistant records, and the
# end hook re-requests when the live count has grown by the trivial band, five.
P7=aaaaaaaa-0000-0000-0000-000000000007; TP7="$H/.claude/projects/proj/$P7.jsonl"
turns "$TP7" 10; start $P7 startup regrowth /tmp/mapped >/dev/null
MP7="$KB/_sessions/$TODAY/$P7/session.md"; FP7="$KB/_sessions/$TODAY/$P7"
endrun x "$TP7" prompt_input_exit
chk "requested on its first exit"            "$(prop "$MP7" recap_status)" "requested"
st "$FP7" running; st "$FP7" done --summary "recapped once"
chk "done stamps the assistant records"      "$(prop "$MP7" recap_assistant_records)" "10"
turns "$TP7" 14
endrun x "$TP7" prompt_input_exit
chk "four more records keep it done"         "$(prop "$MP7" recap_status)" "done"
chk "and the stamp survives the rewrite"     "$(prop "$MP7" recap_assistant_records)" "10"
turns "$TP7" 15
endrun x "$TP7" prompt_input_exit
chk "five more records re-request it"        "$(prop "$MP7" recap_status)" "requested"
chk "with the reason in recap.log"           "$(grep -c 'grew by 5 assistant records since the recap (10 -> 15), re-requesting' "$FP7/recap.log")" "1"
chk "the description is kept"                "$(prop "$MP7" summary)" "recapped once"
# A note recapped before the stamp existed carries no evidence, so it stays done however it grows.
P8=aaaaaaaa-0000-0000-0000-000000000008; TP8="$H/.claude/projects/proj/$P8.jsonl"
turns "$TP8" 10; start $P8 startup old-done /tmp/mapped >/dev/null
MP8="$KB/_sessions/$TODAY/$P8/session.md"; FP8="$KB/_sessions/$TODAY/$P8"
endrun x "$TP8" prompt_input_exit; st "$FP8" running; st "$FP8" done
sed -i '/^recap_assistant_records:/d' "$MP8"
turns "$TP8" 40
endrun x "$TP8" prompt_input_exit
chk "no stamp, no re-request"                "$(prop "$MP8" recap_status)" "done"

echo "== 26d. a launcher can declare the session it starts exempt (ADR-0009) =="
# The dispatcher ends its ticket sessions with /exit typed through Herdr, which the end hook
# cannot tell from the owner's own: both arrive as prompt_input_exit. So the launcher declares
# the exemption on the launch, the way a recap session carries its subject: SECOND_BRAIN_RECAP_EXEMPT
# on a genuine startup becomes `recap_exempt: launcher` on the note, and every exit reads the note.
PD1=aaaaaaaa-0000-0000-0000-0000000026d1; TPD1="$H/.claude/projects/proj/$PD1.jsonl"
turns "$TPD1" 10; start $PD1 startup declared-exempt /tmp/mapped SECOND_BRAIN_RECAP_EXEMPT=1 >/dev/null
MPD1="$KB/_sessions/$TODAY/$PD1/session.md"; FPD1="$KB/_sessions/$TODAY/$PD1"
chk "startup records who declared it"              "$(prop "$MPD1" recap_exempt)" "launcher"
endrun x "$TPD1" prompt_input_exit
chk "ten records are exempt, not requested"        "$(prop "$MPD1" recap_status)" "exempt"
chk "with the reason in recap.log"                 "$(grep -c 'exempt: declared by its launcher at launch (recap_exempt)' "$FPD1/recap.log")" "1"
turns "$TPD1" 20
endrun x "$TPD1" prompt_input_exit
chk "growth never promotes it"                     "$(prop "$MPD1" recap_status)" "exempt"
chk "and the reason is logged once"                "$(grep -c 'recap_exempt' "$FPD1/recap.log")" "1"
# Recapped by hand (exempt -> running is allowed), then kept working: a hand recap is final.
st "$FPD1" running; st "$FPD1" done --summary "by hand"
chk "done stamps the records it saw"               "$(prop "$MPD1" recap_assistant_records)" "20"
turns "$TPD1" 40
endrun x "$TPD1" prompt_input_exit
chk "a hand recap that grew stays done"            "$(prop "$MPD1" recap_status)" "done"
chk "with no re-request in recap.log"              "$(grep -c 'grew by' "$FPD1/recap.log")" "0"
chk "the property survives every rewrite"          "$(prop "$MPD1" recap_exempt)" "launcher"
# Undeclared, the same session is requested: the marker is what made the difference.
PD2=aaaaaaaa-0000-0000-0000-0000000026d2; TPD2="$H/.claude/projects/proj/$PD2.jsonl"
turns "$TPD2" 10; start $PD2 startup undeclared /tmp/mapped >/dev/null
endrun x "$TPD2" prompt_input_exit
chk "undeclared, the same session is requested"    "$(prop "$KB/_sessions/$TODAY/$PD2/session.md" recap_status)" "requested"
chk "and its note carries no property"             "$(grep -c '^recap_exempt:' "$KB/_sessions/$TODAY/$PD2/session.md")" "0"
# Honoured on a genuine startup only, like recap_of; and at exit only off the note (ADR-0005).
PD3=aaaaaaaa-0000-0000-0000-0000000026d3; TPD3="$H/.claude/projects/proj/$PD3.jsonl"
turns "$TPD3" 10; start $PD3 startup plain /tmp/mapped >/dev/null
start $PD3 resume plain /tmp/mapped SECOND_BRAIN_RECAP_EXEMPT=1 >/dev/null
chk "a marker on a resume is ignored"              "$(prop "$KB/_sessions/$TODAY/$PD3/session.md" recap_exempt)" ""
endrun x "$TPD3" prompt_input_exit SECOND_BRAIN_RECAP_EXEMPT=1
chk "a stray marker at exit exempts nothing"       "$(prop "$KB/_sessions/$TODAY/$PD3/session.md" recap_status)" "requested"
# A note that already exists at a declared startup, a restart under the same id, is stamped too.
PD4=aaaaaaaa-0000-0000-0000-0000000026d4; TPD4="$H/.claude/projects/proj/$PD4.jsonl"
turns "$TPD4" 10; start $PD4 startup restarted /tmp/mapped >/dev/null
start $PD4 startup restarted /tmp/mapped SECOND_BRAIN_RECAP_EXEMPT=1 >/dev/null
chk "a pre-existing note is stamped at a declared startup" "$(prop "$KB/_sessions/$TODAY/$PD4/session.md" recap_exempt)" "launcher"
# Global off still skips the whole block: the feature off means nothing is tracked.
env HOME="$H" "$SK" --set auto_recap off >/dev/null 2>&1
PD5=aaaaaaaa-0000-0000-0000-0000000026d5; TPD5="$H/.claude/projects/proj/$PD5.jsonl"
turns "$TPD5" 10; start $PD5 startup feature-off /tmp/mapped SECOND_BRAIN_RECAP_EXEMPT=1 >/dev/null
endrun x "$TPD5" prompt_input_exit
chk "with auto_recap off a declared session is stamped nothing" "$(prop "$KB/_sessions/$TODAY/$PD5/session.md" recap_status)" ""
env HOME="$H" "$SK" --set auto_recap notify >/dev/null 2>&1

echo "== 27. the notice reaches the user, and lists only what stalled =="
# Its own vault, so the notes the earlier cases stamped do not leak into the listing.
NKB="$ROOT/nkb"; NH="$ROOT/nhome"
mkdir -p "$NH/.claude/plugins/config/second-brain" "$NKB/_sessions" "$NH/.claude/projects/proj" "$NKB/projects/cc"
ncfg(){ jq -n --arg kb "$NKB" --arg m "$1" '{knowledge_bank_path:$kb,auto_recap:$m}' \
    > "$NH/.claude/plugins/config/second-brain/config.json"; }
nmk(){ # $1=date $2=id $3=name $4=status(quoted or bare, may be empty) $5=extra line
    mkdir -p "$NKB/_sessions/$1/$2"
    { printf -- '---\nsession_id: "%s"\nsession_name: "%s"\n' "$2" "$3"
      [ -n "$5" ] && printf '%s\n' "$5"
      [ -n "$4" ] && printf 'recap_status: %s\n' "$4"
      printf 'tags:\n---\n\n# body\n'; } > "$NKB/_sessions/$1/$2/session.md"; }
nstart(){ local id="$1"
    local t="$NH/.claude/projects/proj/$id.jsonl"
    printf '{"type":"user","cwd":"/tmp/mapped"}\n' > "$t"
    printf '{"session_id":"%s","cwd":"/tmp/mapped","transcript_path":"%s","source":"startup","session_title":"observer"}' "$id" "$t" \
      | env HOME="$NH" HERDR_PANE_ID= TMUX_PANE= "$PLUGIN/hooks/scripts/session_start.sh" 2>/dev/null; }
nmk 2026-09-13 f1111111-1111-1111-1111-111111111111 inv-recap-hook '"failed"'
printf 'x failed reason=no knowledge-bank domain fits\n' > "$NKB/_sessions/2026-09-13/f1111111-1111-1111-1111-111111111111/recap.log"
# Deliberately unnamed: an empty name used to collapse the scan's tab-separated fields
# and drop the whole row, so this asserts the row survives and falls back to the id.
nmk 2026-09-12 r2222222-2222-2222-2222-222222222222 "" 'requested'
nmk 2026-09-11 d3333333-3333-3333-3333-333333333333 done-one '"done"'
nmk 2026-09-11 e4444444-4444-4444-4444-444444444444 tiny '"exempt"'
nmk 2026-09-11 n5555555-5555-5555-5555-555555555555 never-asked ''
nmk 2026-09-10 c6666666-6666-6666-6666-666666666666 the-recap '"requested"' 'recap_of: "/somewhere/subj"'
ncfg notify
NOUT=$(nstart 12121212-1111-1111-1111-111111111111)
NMSG=$(printf '%s' "$NOUT" | jq -r '.systemMessage // ""')
NCTX=$(printf '%s' "$NOUT" | jq -r '.hookSpecificOutput.additionalContext // ""')
chk "the hook still emits valid JSON"   "$(printf '%s' "$NOUT" | jq -e . >/dev/null 2>&1 && echo yes || echo no)" "yes"
chk "the notice goes to the user"       "$(printf '%s' "$NMSG" | grep -c 'need attention')" "1"
chk "and never into Claude's context"   "$(printf '%s' "$NCTX" | grep -c 'need attention')" "0"
chk "it counts what it lists"           "$(printf '%s' "$NMSG" | grep -c '^- ')" "2"
chk "a failed recap is listed first"    "$(printf '%s' "$NMSG" | sed -n '2p' | grep -c 'failed')" "1"
chk "with the reason from recap.log"    "$(printf '%s' "$NMSG" | grep -c 'no knowledge-bank domain fits')" "1"
chk "an unnamed session is not dropped" "$(printf '%s' "$NMSG" | grep -c 'r2222222')" "1"
chk "the retry command is the launcher" "$(printf '%s' "$NMSG" | grep -c 'recap_launcher.sh --manual')" "2"
for pair in "done-one:a done recap" "tiny:an exempt session" "never-asked:a never-requested session" "the-recap:a recap session"; do
    chk "${pair#*:} is not listed" "$(printf '%s' "$NMSG" | grep -c "${pair%%:*}")" "0"
done
ncfg off
chk "off produces no notice at all" \
    "$(printf '%s' "$(nstart 12121212-2222-2222-2222-222222222222)" | jq -r '.systemMessage // "none"')" "none"

echo "== 27b. pending proposed improvements are counted into the notice =="
# Queue files are what a recap writes and a person drains; the start-of-session notice is
# their only surfacing (ADR-0008), so it must fire regardless of auto_recap — `off` was
# set just above and deliberately stays. One status bare and one quoted, because Obsidian
# normalises quotes whenever a person saves a note.
mkdir -p "$NKB/_proposals"
mkprop(){ printf -- '---\ntype: proposed-improvement\nseverity: high\ncategory: tool-reliability\ntarget: scripts/x\nclassification: mechanical\nsession-folder: _sessions/2026-09-13/f1\nstatus: %s\n---\nbody\n' \
    "$2" > "$NKB/_proposals/$1"; }
mkprop 2026-09-13-one.md 'pending'
mkprop 2026-09-13-two.md '"pending"'
POUT=$(nstart 12121212-3333-3333-3333-333333333333)
PMSG=$(printf '%s' "$POUT" | jq -r '.systemMessage // ""')
PCTX=$(printf '%s' "$POUT" | jq -r '.hookSpecificOutput.additionalContext // ""')
chk "pending proposals are noticed with auto_recap off" "$(printf '%s' "$PMSG" | grep -c 'proposed improvements pending')" "1"
chk "quoted and bare status both count"                 "$(printf '%s' "$PMSG" | grep -c '2 proposed improvements')" "1"
chk "the queue path is in the notice"                   "$(printf '%s' "$PMSG" | grep -c '_proposals')" "1"
chk "and never into Claude's context"                   "$(printf '%s' "$PCTX" | grep -c 'proposed improvement')" "0"
# A person's approval is what empties the queue, and one left is still a sentence.
mkprop 2026-09-13-two.md 'approved'
P1MSG=$(nstart 12121212-4444-4444-4444-444444444444 | jq -r '.systemMessage // ""')
chk "an approved proposal stops counting" "$(printf '%s' "$P1MSG" | grep -c '1 proposed improvement pending')" "1"
mkprop 2026-09-13-one.md 'rejected'
chk "an empty queue produces no notice" \
    "$(printf '%s' "$(nstart 12121212-5555-5555-5555-555555555555)" | jq -r '.systemMessage // "none"')" "none"
rm -rf "$NKB/_proposals"

echo "== 28. the launcher hands over a command that carries the markers inline =="
LSUBJ="$NKB/_sessions/2026-09-13/f1111111-1111-1111-1111-111111111111"
LOUT=$(env HOME="$NH" HERDR_ENV= HERDR_PANE_ID= "$PLUGIN/hooks/scripts/recap_launcher.sh" --manual "$LSUBJ/" 2>&1)
chk "the subject marker is inline"     "$(printf '%s' "$LOUT" | grep -c "SECOND_BRAIN_RECAP_OF=")" "1"
chk "the name travels with it"         "$(printf '%s' "$LOUT" | grep -c 'SECOND_BRAIN_RECAP_NAME=recap-inv-recap-hook')" "1"
chk "it runs the child, not claude"    "$(printf '%s' "$LOUT" | grep -c 'recap_child.sh')" "1"
# --env would put the marker in the pane's root shell, where every later session in that
# pane would inherit it, register as a recap and be stamped exempt at its own exit.
chk "never through the pane's env"     "$(printf '%s' "$LOUT" | grep -c -- '--env')" "0"
# A command a person pastes runs in their own shell, which has its own PATH; only a worker the core starts
# is given the launcher's (case 49).
chk "a pasted command names no PATH"   "$(printf '%s' "$LOUT" | grep -c 'PATH=')" "0"
chk "a trailing slash is normalised"   "$(printf '%s' "$LOUT" | grep -c 'f1111111-1111-1111-1111-111111111111 ')" "1"
env HOME="$NH" "$PLUGIN/hooks/scripts/recap_launcher.sh" --manual /nope/nothing >/dev/null 2>&1 \
    && no "a missing subject is refused" || ok "a missing subject is refused"
# --auto has no terminal to talk to, so outside Herdr it does nothing and says nothing:
# the subject is already `requested` and the notice covers it. `on` degrading to `notify`
# where there is no Herdr is the documented behaviour.
AOUT=$(env HOME="$NH" HERDR_ENV= HERDR_PANE_ID= "$PLUGIN/hooks/scripts/recap_launcher.sh" --auto "$LSUBJ" 2>&1)
chk "--auto outside Herdr exits 0"      "$?" "0"
chk "and prints nothing at all"         "${AOUT:-empty}" "empty"
chk "but records why in recap.log"      "$(grep -c 'no terminal host' "$LSUBJ/recap.log")" "1"

echo "== 29. a recap session registers as one, only at startup =="
# The marker is honoured on a genuine launch and nowhere else, and it decides three
# things on the new note: what it recaps, whose domain it belongs to, and its one tag.
RSUB="$KB/_sessions/$TODAY/aaaaaaaa-0000-0000-0000-000000000001"   # from case 26, project cc
RS1=bbbbbbbb-0000-0000-0000-000000000001
start $RS1 startup recap-real-work /tmp/work SECOND_BRAIN_RECAP_OF="$RSUB" >/dev/null
MR1="$KB/_sessions/$TODAY/$RS1/session.md"
chk "recap_of names the subject"        "$(prop "$MR1" recap_of)" "$RSUB"
# The vault is the recap's cwd and maps to no domain, so without this the note would
# either be empty or take the bank's own name; ADR-0004 says it takes the subject's.
chk "it takes the subject's domain"     "$(prop "$MR1" project)" "cc"
chk "and carries the one hook-written tag" "$(rfl "$MR1" tags)" "session-recap"
# Its own exit must leave it exempt for good, decided by the note, not the marker.
endrun x "$H/.claude/projects/proj/$RS1.jsonl" prompt_input_exit
chk "a recap session exempts itself"    "$(prop "$MR1" recap_status)" "exempt"
chk "and keeps recap_of through the rewrite" "$(prop "$MR1" recap_of)" "$RSUB"
# A subject holding a legacy basename yields no domain rather than passing one on.
RSUB2="$ROOT/legacy"; mkdir -p "$RSUB2"
printf -- '---\nsession_id: "l"\nproject: "data"\ntags:\n---\n\n# b\n' > "$RSUB2/session.md"
RS2=bbbbbbbb-0000-0000-0000-000000000002
start $RS2 startup recap-legacy /tmp/work SECOND_BRAIN_RECAP_OF="$RSUB2" >/dev/null
chk "a legacy basename is not inherited" "$(prop "$KB/_sessions/$TODAY/$RS2/session.md" project)" ""
# An unnamed hand-run recap gets its only chance at a name here.
RS3=bbbbbbbb-0000-0000-0000-000000000003
RO=$(start $RS3 startup "" /tmp/work SECOND_BRAIN_RECAP_OF="$RSUB")
chk "an unnamed recap is named for its subject" \
    "$(printf '%s' "$RO" | jq -r '.hookSpecificOutput.sessionTitle // ""')" "recap-aaaaaaaa"
# A stray marker on a resume must not turn an ordinary session into a recap session.
RS4=bbbbbbbb-0000-0000-0000-000000000004
start $RS4 resume stray /tmp/mapped SECOND_BRAIN_RECAP_OF="$RSUB" >/dev/null
chk "a marker on resume is ignored"     "$(prop "$KB/_sessions/$TODAY/$RS4/session.md" recap_of)" ""
chk "an ordinary note gains no empty recap_of" \
    "$(grep -c '^recap_of:' "$KB/_sessions/$TODAY/$RS4/session.md")" "0"

echo "== 30. the notice cannot send you to recap the session you are in =="
# A /clear fires the start hook with the same session id, so a session already stamped
# `requested` would be offered to itself. Recapping a live session reads a transcript
# still being written and marks it `done`, after which its real exit sees a settled
# status and the real recap never happens. Silent, and it loses the whole session.
ncfg notify
SELFID=13131313-1111-1111-1111-111111111111
nstart $SELFID >/dev/null
SELFMD="$NKB/_sessions/$TODAY/$SELFID/session.md"
awk '$0=="tags:"{print "recap_status: \"requested\""} {print}' "$SELFMD" > "$SELFMD.t" && mv "$SELFMD.t" "$SELFMD"
SOUT=$(printf '{"session_id":"%s","cwd":"/tmp/mapped","transcript_path":"%s","source":"clear","session_title":"mine"}' \
        "$SELFID" "$NH/.claude/projects/proj/$SELFID.jsonl" \
      | env HOME="$NH" HERDR_PANE_ID= TMUX_PANE= "$PLUGIN/hooks/scripts/session_start.sh" 2>/dev/null)
chk "the current session is never listed" \
    "$(printf '%s' "$SOUT" | jq -r '.systemMessage // ""' | grep -c "$SELFID")" "0"
chk "but another session still is" \
    "$(printf '%s' "$SOUT" | jq -r '.systemMessage // ""' | grep -c 'inv-recap-hook')" "1"

echo "== 31. a stuck running recap is recoverable, and says how =="
# A manual launch can die without its wrapper running, and `running` is then a dead end:
# there is no running-to-running transition, so the launcher would refuse it as claimed
# by a process that no longer exists. The notice has to offer the reopen instead, and it
# has to list the row in `notify` too, which is the only mode this version ships.
nmk 2026-09-08 h8888888-8888-8888-8888-888888888888 stuck-one '"running"'
touch -t "$(date -v-3H +%Y%m%d%H%M 2>/dev/null || date -d '3 hours ago' +%Y%m%d%H%M)" \
    "$NKB/_sessions/2026-09-08/h8888888-8888-8888-8888-888888888888/session.md"
ROUT=$(nstart 13131313-2222-2222-2222-222222222222 | jq -r '.systemMessage // ""')
chk "a stale running is listed in notify"  "$(printf '%s' "$ROUT" | grep -c 'stuck-one')" "1"
chk "and it offers the reopen, not --manual" \
    "$(printf '%s' "$ROUT" | grep 'stuck-one' | grep -c 'requested --force')" "1"
# The command the notice prints has to work as printed.
RCMD=$(printf '%s' "$ROUT" | sed -n 's/.*if nothing is running: //p' | head -1)
eval "env HOME=\"$NH\" $RCMD" >/dev/null 2>&1
chk "and the printed command reopens it" \
    "$(prop "$NKB/_sessions/2026-09-08/h8888888-8888-8888-8888-888888888888/session.md" recap_status)" "requested"

echo "== 32. ccfind refreshes a cache whose shape predates the recap column =="
# The cache carries no version, and get_sessions is stale-while-revalidate, so a cache
# written by an older version would be served to a filter reading a field that is not
# there: every session would read as recapped and the backlog would look empty.
CC="$ROOT/cchome"; mkdir -p "$CC/ccfind"
printf 'display\tid1\t/tmp/x\t/p/session.md\t-\t-\n' > "$CC/ccfind/sessions.tsv"
chk "an old cache has six fields" "$(awk -F'\t' '{print NF}' "$CC/ccfind/sessions.tsv")" "6"
XDG_CACHE_HOME="$CC" env HOME="$H" "$PLUGIN/tools/ccfind/ccfind.sh" --tags >/dev/null 2>&1 || true
chk "and is rewritten with seven"  "$(awk -F'\t' 'NR==1{print NF}' "$CC/ccfind/sessions.tsv")" "7"
# Against a six-field cache this filter matched nothing at all, which read as "every
# session has been recapped". The property is that it now matches, and that it still
# excludes the settled ones rather than matching everything.
chk "the backlog filter matches something" \
    "$(awk -F'\t' '$7 == "-" || $7 == "requested" || $7 == "failed"' "$CC/ccfind/sessions.tsv" \
       | grep -c . | awk '{print ($1 > 0) ? "yes" : "no"}')" "yes"
chk "and still excludes done, exempt and running" \
    "$(awk -F'\t' '$7 == "done" || $7 == "exempt" || $7 == "running"' "$CC/ccfind/sessions.tsv" \
       | awk -F'\t' '$7 == "-" || $7 == "requested" || $7 == "failed"' | grep -c .)" "0"

echo "== 33. the batched reader agrees with the single one, and the end hook uses it =="
# The end hook shares a 1.5-second SessionEnd budget with a memory copy, two transcript
# scans and a full rewrite. Read one at a time, its property reads cost three processes
# each and the hook was cancelled mid-exit on a real session. This guards both halves of
# the fix: that the batch reader returns exactly what the single reader would, and that
# the hook keeps using it.
B1="$ROOT/batch.md"
printf -- '---\nschema_version: "2.1"\nsession_name: "fix the \\"auth\\" bug"\nproject: cc\nwindows_path: C:\\\\srv\\new\nquoted_empty: ""\nbare_key:\nsummary: "did it"\ntags:\n  - a\n  - has:colon\n---\n\n# body\n' > "$B1"
BATCH_PROPS="schema_version session_name project windows_path quoted_empty bare_key summary absent_key"
# Every value, compared against the reader it replaces. A quoted scalar must come back
# unescaped exactly once; a plain one must keep its backslashes untouched.
MISMATCH=$(bash -c '
    source "$1" >/dev/null 2>&1
    n=0
    { for p in $3; do
        IFS= read -r batched
        single=$(read_frontmatter_prop "$2" "$p")
        [ "$batched" = "$single" ] || { printf "%s " "$p"; n=$((n+1)); }
      done; } < <(read_frontmatter_props "$2" $3)
    exit 0' _ "$HELPL" "$B1" "$BATCH_PROPS")
chk "every batched value matches the single reader" "${MISMATCH:-none}" "none"
chk "a quoted scalar is unescaped once" \
    "$(bash -c 'source "$1" >/dev/null 2>&1; read_frontmatter_props "$2" session_name' _ "$HELPL" "$B1")" \
    'fix the "auth" bug'
chk "a plain scalar keeps its backslashes" \
    "$(bash -c 'source "$1" >/dev/null 2>&1; read_frontmatter_props "$2" windows_path' _ "$HELPL" "$B1")" \
    'C:\\srv\new'
# Order and arity are the contract: callers read the values back positionally, so a
# missing or reordered line silently assigns one property's value to another.
chk "one line per property, in order, absent ones empty" \
    "$(bash -c 'source "$1" >/dev/null 2>&1; read_frontmatter_props "$2" absent_key project absent2 summary' _ "$HELPL" "$B1" | tr '\n' '|')" \
    "|cc||did it|"
chk "a missing file still yields one line per property" \
    "$(bash -c 'source "$1" >/dev/null 2>&1; read_frontmatter_props /nope/none a b c' _ "$HELPL" | wc -l | tr -d ' ')" "3"
# A list item carrying a colon must not be mistaken for a key of that name.
chk "a list item is not read as a property" \
    "$(bash -c 'source "$1" >/dev/null 2>&1; read_frontmatter_props "$2" has' _ "$HELPL" "$B1")" ""
# Structural, because a timing assertion would be flaky on a loaded machine while the
# thing that actually regressed is the number of processes the hook spawns.
# Two calls, and both are deliberate: the predicate reads its two properties before the
# lock, the rewrite reads its thirteen under it. Neither reads one property at a time.
chk "the end hook batches its property reads" \
    "$(grep -c 'read_frontmatter_props' "$PLUGIN/hooks/scripts/session_end.sh")" "2"
# The ordering is a correctness property, not tidiness. The hook costs about 1.58 s
# against a default 1.5 s budget, so it can be cancelled part-way. With the stamp last, a
# cancelled hook rewrote the note and never stamped: the note looked complete, the status
# stayed empty, and the notice skips an empty status, so the session left the recap
# pipeline permanently and silently. Stamping first inverts that into a visibly incomplete
# note for a session that will still be recapped.
chk "the recap stamp precedes the lock" \
    "$(awk '/recap_status.sh"$/{s=NR} /^if recap_lock_acquire/{l=NR} END{print (s>0 && l>0 && s<l) ? "yes" : "no"}' \
       "$PLUGIN/hooks/scripts/session_end.sh")" "yes"
chk "and precedes the note rewrite" \
    "$(awk '/^    STATUS=/{s=NR} /^write_session_md "\$SESSION_FOLDER/{w=NR} END{print (s>0 && w>0 && s<w) ? "yes" : "no"}' \
       "$PLUGIN/hooks/scripts/session_end.sh")" "yes"
# Bash runs a signal handler and then resumes, so a handler that only releases the lock
# leaves the rest of the read-rebuild-write running with nothing held — the exact
# lost-update window the lock exists to close. A signal trap here must exit.
chk "no bare handler on a signal" \
    "$(grep -c "trap 'recap_lock_release \"\$SESSION_FOLDER\"' EXIT HUP INT TERM" \
       "$PLUGIN/hooks/scripts/session_end.sh")" "0"
chk "every signal trap exits" \
    "$(awk '/^ *trap .*recap_lock_release/ && /TERM|INT|HUP/ { if ($0 !~ /exit /) bad++ } END{print bad+0}' \
       "$PLUGIN/hooks/scripts/session_end.sh")" "0"
chk "and EXIT still has one that returns" \
    "$(grep -c "trap 'recap_lock_release \"\$SESSION_FOLDER\"' EXIT$" \
       "$PLUGIN/hooks/scripts/session_end.sh")" "1"
chk "and reads the payload in one jq pass" \
    "$(grep -c 'echo "\$INPUT" | jq' "$PLUGIN/hooks/scripts/session_end.sh")" "1"
# Two are legitimate: the folder rebuild path and nothing else. This goes red if
# per-property reads creep back into the hook body.
chk "no per-property reads remain in the end hook" \
    "$(grep -c 'read_frontmatter_prop "' "$PLUGIN/hooks/scripts/session_end.sh")" "0"

echo "== 34. on mode launches the recap in a pane of its own =="
# A stub herdr records every call, so the Herdr flow is asserted without touching a real
# workspace. process-info answers with a shell_pid, which is what the launcher waits for.
#
# The old pane must answer as *busy*, not merely exist: this case is the ending session's
# own pane, and at that moment the session's claude still owns the pane's terminal. Omitting
# foreground_process_group_id made pane_state read `gone` instead, and the split assertions
# below went on passing through the closed-pane branch rather than the busy one they were
# written for — the split is the same either way, which is exactly what hid it.
mkdir -p "$NH/.local/bin"
cat > "$NH/.local/bin/herdr" << 'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$HOME/herdr-calls.log"
case "$*" in
    *"pane split"*)        echo '{"result":{"pane":{"pane_id":"w9:pNEW"}}}' ;;
    *"pane process-info --pane w9:pOLD"*)
        echo '{"result":{"process_info":{"shell_pid":4242,"foreground_process_group_id":31337,"foreground_processes":[{"name":"claude","pid":31337},{"name":"zsh","pid":4242}]}}}' ;;
    *"pane process-info"*) echo '{"result":{"process_info":{"shell_pid":4242}}}' ;;
esac
exit 0
STUB
chmod +x "$NH/.local/bin/herdr"
ASUBJ="$NKB/_sessions/2026-09-13/f1111111-1111-1111-1111-111111111111"
: > "$NH/herdr-calls.log"; : > "$ASUBJ/recap.log"
AOUT2=$(env HOME="$NH" PATH="$NH/.local/bin:$PATH" HERDR_ENV=1 HERDR_PANE_ID=w9:pOLD \
    SECOND_BRAIN_PANE_WAIT_ATTEMPTS=1 \
    CLAUDE_PID=31337 "$PLUGIN/hooks/scripts/recap_launcher.sh" --auto "$ASUBJ" 2>&1)
chk "--auto prints nothing even on success" "${AOUT2:-empty}" "empty"
chk "it splits the ending session's pane" \
    "$(grep -c 'pane split --pane w9:pOLD --direction right --no-focus --cwd' "$NH/herdr-calls.log")" "1"
# Two reads, not one: the split above has to be reached through the busy branch. A pane that
# answers nothing reads `gone`, takes one look and splits too, so the assertion above cannot
# tell the two apart on its own — and for a while it was silently taking the wrong one.
chk "and it got there by finding it busy" \
    "$(grep -c 'pane process-info --pane w9:pOLD' "$NH/herdr-calls.log")" "2"
# --env would put the marker in the pane's root shell, where every later claude in that
# pane inherits it, registers as a recap and is stamped exempt at its own exit.
chk "never through the pane environment"    "$(grep -c -- '--env' "$NH/herdr-calls.log")" "0"
chk "it waits for the pane's shell"         "$(grep -c 'pane process-info --pane w9:pNEW' "$NH/herdr-calls.log")" "1"
chk "it labels the pane before running"     "$(grep -c 'pane rename w9:pNEW recap-inv-recap-hook' "$NH/herdr-calls.log")" "1"
chk "it runs the child in the new pane"     "$(grep -c 'pane run w9:pNEW .*recap_child.sh' "$NH/herdr-calls.log")" "1"
chk "the subject marker is inline"          "$(grep -c 'SECOND_BRAIN_RECAP_OF=' "$NH/herdr-calls.log")" "1"
# The child waits for this pid to exit before reading a transcript that is still being
# flushed. Without it the wait loop is dead code and the recap can read a partial file.
chk "the ending session's pid travels too"  "$(grep -c 'SECOND_BRAIN_PARENT_PID=31337' "$NH/herdr-calls.log")" "1"
chk "and it logged the launch"              "$(grep -c 'launcher started recap-inv-recap-hook in pane w9:pNEW' "$ASUBJ/recap.log")" "1"
# A failed split must not look like a started recap, and must not exit non-zero into a
# hook that is already gone. The subject stays `requested` and the notice asks.
cat > "$NH/.local/bin/herdr" << 'STUB2'
#!/bin/bash
printf '%s\n' "$*" >> "$HOME/herdr-calls.log"
case "$*" in *"pane split"*) echo "herdr: pane is gone" >&2; exit 1 ;; esac
exit 0
STUB2
chmod +x "$NH/.local/bin/herdr"
: > "$ASUBJ/recap.log"
env HOME="$NH" PATH="$NH/.local/bin:$PATH" HERDR_ENV=1 HERDR_PANE_ID=w9:pOLD \
    SECOND_BRAIN_PANE_WAIT_ATTEMPTS=1 \
    "$PLUGIN/hooks/scripts/recap_launcher.sh" --auto "$ASUBJ" >/dev/null 2>&1
chk "a failed split exits 0 under --auto"   "$?" "0"
chk "and is logged as a failure"            "$(grep -c 'launcher failed: could not open a pane' "$ASUBJ/recap.log")" "1"
chk "the subject is left for the notice"    "$(prop "$ASUBJ/session.md" recap_status)" "failed"

echo "== 35. the end hook launches only in on mode, and only detached =="
# notify records and notifies; on also launches. A stub launcher records that it was
# called, so this asserts the hook's decision rather than Herdr's behaviour.
mkdir -p "$ROOT/stubplugin/hooks/scripts" "$ROOT/stubplugin/skills"
cp -R "$PLUGIN/skills" "$ROOT/stubplugin/" 2>/dev/null
cp "$PLUGIN/hooks/scripts/session_end.sh" "$ROOT/stubplugin/hooks/scripts/"
cat > "$ROOT/stubplugin/hooks/scripts/recap_launcher.sh" << 'STUB3'
#!/bin/bash
printf 'called %s\n' "$*" >> "${SB_LAUNCH_LOG:-/dev/null}"
STUB3
chmod +x "$ROOT/stubplugin/hooks/scripts/recap_launcher.sh"
LAUNCHLOG="$ROOT/launch.log"
mode_run(){ # $1=auto_recap value -> did the hook launch anything?
    jq -n --arg kb "$KB" --arg m "$1" '{knowledge_bank_path:$kb,auto_recap:$m}' > "$CFGF"
    local id="ababab$2-0000-0000-0000-00000000000$2" t
    t="$H/.claude/projects/proj/$id.jsonl"; turns "$t" 9
    start "$id" startup "launch-$1" /tmp/mapped >/dev/null
    : > "$LAUNCHLOG"
    printf '{"transcript_path":"%s","cwd":"/tmp/mapped","reason":"prompt_input_exit"}' "$t" \
      | env HOME="$H" HERDR_PANE_ID= TMUX_PANE= SB_LAUNCH_LOG="$LAUNCHLOG" \
        "$ROOT/stubplugin/hooks/scripts/session_end.sh" >/dev/null 2>&1
    # The launcher is detached, so it may land a moment after the hook returns.
    local i=0; while [ ! -s "$LAUNCHLOG" ] && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i+1)); done
    # No `|| echo 0`: grep -c already prints 0 on no match and exits 1, so the fallback
    # would append a second line and the comparison would see "0\n0". The plugin's own
    # predicate carries a comment about this trap; the harness fell into it anyway.
    local n; n=$(grep -c 'called' "$LAUNCHLOG" 2>/dev/null); printf '%s' "${n:-0}"; }
chk "notify launches nothing"          "$(mode_run notify 1)" "0"
chk "on launches the recap"            "$(mode_run on 2)" "1"
chk "with --auto and the subject"      "$(grep -c -- '--auto .*_sessions' "$LAUNCHLOG")" "1"
chk "off launches nothing"             "$(mode_run off 3)" "0"
# The detach is what makes the launch survive a hook that Claude cancels at its budget:
# measured, a plain background child and a bare setsid child are both killed with the
# hook's process tree, and only a double fork escapes it.
SDR="$ROOT/sd"; mkdir -p "$SDR"
cat > "$SDR/parent.sh" << PARENT
#!/bin/bash
source "$HELPL"
spawn_detached /bin/sh -c 'sleep 3; touch $SDR/survived'
touch $SDR/forked
sleep 30
PARENT
chmod +x "$SDR/parent.sh"
"$SDR/parent.sh" & SDP=$!
i=0; while [ ! -f "$SDR/forked" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
kill -9 $SDP 2>/dev/null; wait $SDP 2>/dev/null || true
sleep 5
chk "a detached child outlives a killed parent" "$([ -f "$SDR/survived" ] && echo survived || echo killed)" "survived"

echo "== 36. the suite never touches the real Herdr =="
# Load-bearing, not hygiene. Before this guard the suite split the pane of the session
# running it, twice, and pointed the new panes at a scratch vault it then deleted. Any
# entry here names a call site that resolved the real binary from the ambient environment.
if [ -s "$TRIPWIRE" ]; then
    no "no call site reached the real herdr"
    echo "         attempts:"; sed 's/^/           /' "$TRIPWIRE"
else
    ok "no call site reached the real herdr"
fi
# The gate the launcher itself checks, so a case that opens the Herdr path has to say so.
# `${VAR-x}` not `${VAR:-x}`: these are set-but-empty on purpose, and the colon form
# reports an empty value as unset, which made this assertion fail against itself.
chk "Herdr detection is off by default"  "${HERDR_ENV-MISSING}${HERDR_PANE_ID-MISSING}" ""
# The socket is the one that actually reaches the user's workspace, and the bin path is the
# one a PATH tripwire cannot defend against. Both must be cleared, not merely unset.
chk "the daemon socket is unreachable"   "${HERDR_SOCKET_PATH-MISSING}" ""
chk "and the binary path is not handed over" "${HERDR_BIN_PATH-MISSING}" ""
# The Herdr app's: from an hc terminal, ccfind would otherwise drive the real window.
chk "and the Herdr app's gate is shut too"   "${HC_TERMINAL_ID-MISSING}${CCFIND_REPORT-MISSING}" ""

echo "== 37. a person can re-request a subject, and nothing automatic can =="
# The status only moves forwards, so `requested`, `done` and `failed` are dead ends to the
# end hook. `clear` is the documented way back, and it needs --force because it is a
# decision rather than a transition. This is the operation whose absence forced a hand edit
# of a real note.
CSUBJ="$ROOT/clearsubj"; mkdir -p "$CSUBJ"
cnote(){ printf -- '---\nsession_id: "c"\nsummary: "kept"\nrecap_status: "%s"\ntags:\n  - kepttag\n---\n\n# body\nkeptline\n' "$1" > "$CSUBJ/session.md"; }
cst(){ env HOME="$H" "$ST" "$@" >/dev/null 2>&1; }
cnote requested
cst "$CSUBJ" clear && no "clear refuses without --force" || ok "clear refuses without --force"
chk "and changes nothing"              "$(prop "$CSUBJ/session.md" recap_status)" "requested"
for s in requested running done failed exempt; do
    cnote "$s"; cst "$CSUBJ" clear --force
    chk "clear works from $s"          "$(grep -c '^recap_status:' "$CSUBJ/session.md")" "0"
done
chk "the rest of the note survives"    "$(grep -c '^keptline$' "$CSUBJ/session.md")" "1"
chk "so do its tags"                   "$(rfl "$CSUBJ/session.md" tags)" "kepttag"
chk "and its summary"                  "$(prop "$CSUBJ/session.md" summary)" "kept"
chk "the frontmatter stays one block"  "$(grep -c '^---$' "$CSUBJ/session.md")" "2"
# Cleared means the end hook will request it again, which is the entire point.
cst "$CSUBJ" requested
chk "a cleared subject can be requested" "$(prop "$CSUBJ/session.md" recap_status)" "requested"
# Guard rails: a reset is not a back door to the description or to other states.
cnote done; cst "$CSUBJ" clear --force --summary "nope"
chk "clear takes no description"       "$(prop "$CSUBJ/session.md" recap_status)" "done"
cnote running
cst "$CSUBJ" done --force
chk "--force still only serves requested and clear" "$(prop "$CSUBJ/session.md" recap_status)" "running"
chk "and every reset is in the log"    "$(grep -c 'reset .*->empty' "$CSUBJ/recap.log")" "5"

echo "== 38. a recap reuses the pane it was launched from when that pane is free =="
# One sentence covers both paths — run where the shell is free, otherwise beside it — but
# "free" is a different comparison in each, and that difference is the whole subtlety.
# Herdr's `pane process-info` reports `foreground_process_group_id`, the process group that
# owns the pane's terminal right now, and `shell_pid`, the pane's root shell.
#
#   --auto   is detached, so nothing of ours is in that pane. Free means the foreground
#            group is the pane's own shell: nothing is running, the shell is at a prompt.
#   --manual runs IN that pane, so the shell's own group is precisely what a free pane does
#            NOT report — we are holding the foreground ourselves. Free means the
#            foreground group is ours.
#
# Measured on this machine before the rule was written: an idle pane reports
# fg group == shell_pid with one foreground process, zsh; a script typed at a zsh prompt is
# the tty's foreground group leader (pgid == tpgid); the same script run through a Claude
# session's Bash tool sits in its own group under claude, and claude holds the foreground.
# Comparing against shell_pid in both modes would leave the inline path unreachable, so
# these cases pin the two comparisons apart.
RH="$NH/.local/bin/herdr"
PINFO="$NH/paneinfo"
# One stub for every case below: it answers process-info for the old pane from a file, so a
# case sets the pane's state by writing a word.
#
#   settles  busy for two reads, then free — the real --auto sequence, because this launcher
#            is a descendant of the ending session's own claude and so cannot see a free
#            pane on its first read. A stub that answered `free` at once would pass whether
#            or not the launcher waits at all, which is the trap this state exists to close.
#   mine     reports the caller's own process group, which IS the launcher's (a command
#            substitution in a non-interactive shell keeps the group), so the manual
#            comparison is exercised for real rather than against a constant.
cat > "$RH" << 'STUB4'
#!/bin/bash
printf '%s\n' "$*" >> "$HOME/herdr-calls.log"
zsh='{"name":"zsh","pid":5555}'
busy="{\"result\":{\"process_info\":{\"shell_pid\":5555,\"foreground_process_group_id\":45612,\"foreground_processes\":[{\"name\":\"claude\",\"pid\":45612},$zsh]}}}"
free="{\"result\":{\"process_info\":{\"shell_pid\":5555,\"foreground_process_group_id\":5555,\"foreground_processes\":[$zsh]}}}"
# Group ids agree, but something is running in the shell's own group: busy all the same.
crowded="{\"result\":{\"process_info\":{\"shell_pid\":5555,\"foreground_process_group_id\":5555,\"foreground_processes\":[$zsh,{\"name\":\"sleep\",\"pid\":5556}]}}}"
case "$*" in
    *"pane process-info --pane w9:pOLD"*)
        case "$(cat "$HOME/paneinfo" 2>/dev/null)" in
            free|refuses) printf '%s\n' "$free" ;;
            busy) printf '%s\n' "$busy" ;;
            crowded) printf '%s\n' "$crowded" ;;
            settles)
                n=$(cat "$HOME/panecalls" 2>/dev/null); n=$(( ${n:-0} + 1 ))
                printf '%s' "$n" > "$HOME/panecalls"
                [ "$n" -ge 3 ] && printf '%s\n' "$free" || printf '%s\n' "$busy" ;;
            mine) printf '{"result":{"process_info":{"shell_pid":5555,"foreground_process_group_id":%s}}}\n' \
                      "$(ps -o pgid= -p $$ | tr -d ' ')" ;;
            *)    echo "herdr: no such pane" >&2; exit 1 ;;
        esac ;;
    *"pane process-info"*) printf '%s\n' '{"result":{"process_info":{"shell_pid":4242}}}' ;;
    *"pane run"*)
        # `refuses` reaches the one branch no other state can: the pane was free a moment ago
        # and the hand-off into it still failed.
        if [ "$(cat "$HOME/paneinfo" 2>/dev/null)" = refuses ]; then
            echo "herdr: pane went away" >&2; exit 1
        fi ;;
    *"pane split"*)
        if [ "$(cat "$HOME/paneinfo" 2>/dev/null)" = gone ]; then
            echo "herdr: no such pane" >&2; exit 1
        fi
        printf '%s\n' '{"result":{"pane":{"pane_id":"w9:pNEW"}}}' ;;
esac
exit 0
STUB4
chmod +x "$RH"
# A stub claude, so the inline path can be asserted end to end without a model: it records
# the working directory, which is the other half of reuse. A reused pane brings no
# `--cwd`, and a recap that runs in the work repo picks up that repo's settings and
# instructions instead of the vault's.
cat > "$NH/.local/bin/claude" << 'CSTUB'
#!/bin/bash
printf 'claude cwd=%s args=%s\n' "$PWD" "$*" >> "$HOME/claude-calls.log"
CSTUB
chmod +x "$NH/.local/bin/claude"
RSUBJ="$NKB/_sessions/2026-09-13/f1111111-1111-1111-1111-111111111111"
RST="$PLUGIN/skills/common/recap_status.sh"
rset(){ printf '%s' "$1" > "$PINFO"; printf '0' > "$NH/panecalls"
    env HOME="$NH" "$RST" "$RSUBJ" clear --force >/dev/null 2>&1
    env HOME="$NH" "$RST" "$RSUBJ" requested >/dev/null 2>&1
    : > "$NH/herdr-calls.log"; : > "$NH/claude-calls.log"; : > "$RSUBJ/recap.log"; }
rlaunch(){ env HOME="$NH" PATH="$NH/.local/bin:$PATH" HERDR_ENV=1 HERDR_PANE_ID=w9:pOLD \
    SECOND_BRAIN_PANE_WAIT_ATTEMPTS=2 "$@"; }
LAUNCH="$PLUGIN/hooks/scripts/recap_launcher.sh"
pireads(){ grep -c 'pane process-info --pane w9:pOLD' "$NH/herdr-calls.log"; }

rset settles
ROUT=$(rlaunch CLAUDE_PID=31337 "$LAUNCH" --auto "$RSUBJ" 2>&1)
chk "T18 an idle pane hosts the recap itself" "$(grep -c 'pane run w9:pOLD .*recap_child.sh' "$NH/herdr-calls.log")" "1"
chk "T18 and no new pane appears"             "$(grep -c 'pane split' "$NH/herdr-calls.log")" "0"
# The wait is the whole feature on this path: a hook-spawned launcher is a descendant of
# the session's own claude, so its first read of the pane always says busy. Without the
# wait, reuse would never once engage and every recap would still get a new pane.
chk "T18 it waits for claude to let go"       "$(pireads)" "3"
# The recap session's own SessionStart renames pane and agent; renaming here as well would
# claim the pane before anything ran in it and tell a watcher the wrong thing on a failure.
chk "T18 registration relabels it, not us"    "$(grep -c 'pane rename' "$NH/herdr-calls.log")" "0"
chk "T18 the markers still travel inline"     "$(grep -c 'SECOND_BRAIN_RECAP_OF=' "$NH/herdr-calls.log")" "1"
chk "T18 never through the pane environment"  "$(grep -c -- '--env' "$NH/herdr-calls.log")" "0"
chk "T18 --auto still prints nothing"         "${ROUT:-empty}" "empty"
chk "T18 and the reuse is logged"             "$(grep -c 'reusing pane w9:pOLD' "$RSUBJ/recap.log")" "1"
# The launcher hands a recap over; it never records the outcome of one. Only the status writer
# does, called by the end hook before this and by the child after it. A status write inserted
# into the reuse branch went unnoticed by every other assertion here, so this pins it: the
# subject was `requested` going in and nothing on this path may move it.
chk "T18 and the launcher records nothing"    "$(prop "$RSUBJ/session.md" recap_status)" "requested"

rset busy
rlaunch CLAUDE_PID=31337 "$LAUNCH" --auto "$RSUBJ" >/dev/null 2>&1
chk "T19 a busy pane gets a split beside it"  "$(grep -c 'pane split --pane w9:pOLD' "$NH/herdr-calls.log")" "1"
chk "T19 and the child runs in the new pane"  "$(grep -c 'pane run w9:pNEW .*recap_child.sh' "$NH/herdr-calls.log")" "1"
chk "T19 nothing is sent to the busy pane"    "$(grep -c 'pane run w9:pOLD' "$NH/herdr-calls.log")" "0"
chk "T19 and the launcher records nothing"    "$(prop "$RSUBJ/session.md" recap_status)" "requested"
# Bounded, so a pane the user claimed for something else cannot hold the recap up forever.
chk "T19 it gives up rather than queue"       "$(pireads)" "3"

# The rule has two halves and the group ids are only the first. A shell gives each job its
# own process group, so a shell holding the foreground normally holds it alone; a second
# process in that group is something running without a group of its own, and the pane is
# busy however the ids compare.
rset crowded
rlaunch CLAUDE_PID=31337 "$LAUNCH" --auto "$RSUBJ" >/dev/null 2>&1
chk "T19b a second process in the group is busy" "$(grep -c 'pane split --pane w9:pOLD' "$NH/herdr-calls.log")" "1"
chk "T19b and the pane is left alone"            "$(grep -c 'pane run w9:pOLD' "$NH/herdr-calls.log")" "0"

rset mine
rlaunch "$LAUNCH" --manual "$RSUBJ" >/dev/null 2>&1
chk "T20 a prompt runs the recap inline"      "$(grep -c '^claude cwd=' "$NH/claude-calls.log")" "1"
chk "T20 in the vault, not the work repo"     "$(sed -n '1s/^claude cwd=\([^ ]*\) .*/\1/p' "$NH/claude-calls.log")" "$NKB"
chk "T20 under the recap's own session name"  "$(grep -c -- '-n recap-inv-recap-hook' "$NH/claude-calls.log")" "1"
chk "T20 and Herdr is read, never told"       "$(grep -cE 'pane (split|run|rename)' "$NH/herdr-calls.log")" "0"

rset busy
rlaunch "$LAUNCH" --manual "$RSUBJ" >/dev/null 2>&1
chk "T21 a Claude session's Bash tool splits" "$(grep -c 'pane split --pane w9:pOLD' "$NH/herdr-calls.log")" "1"
chk "T21 and nothing runs inline"             "$(grep -c '^claude cwd=' "$NH/claude-calls.log")" "0"
# Asked once, not polled. This is the case that can tell the difference: a person is standing
# at that prompt and whatever holds it will not release it because we waited. Asserting the
# read count on a free pane proves nothing, since a free pane skips the loop either way.
chk "T21 and it does not wait on a person"    "$(pireads)" "1"

# A free pane whose hand-off fails anyway. Until this state existed the branch was dead code:
# the stub had no `pane run` case, so every reuse succeeded and the --auto contracts were
# pinned on the happy path alone.
rset refuses
RFOUT=$(rlaunch CLAUDE_PID=31337 "$LAUNCH" --auto "$RSUBJ" 2>&1); RFRC=$?
chk "T18b a refused hand-off exits 0"         "$RFRC" "0"
chk "T18b and stays silent"                   "${RFOUT:-empty}" "empty"
chk "T18b and says why in the log"            "$(grep -c 'launcher failed: could not start the recap' "$RSUBJ/recap.log")" "1"
chk "T18b and leaves the subject requested"   "$(prop "$RSUBJ/session.md" recap_status)" "requested"

rset gone
rlaunch CLAUDE_PID=31337 "$LAUNCH" --auto "$RSUBJ" >/dev/null 2>&1; RRC=$?
chk "T22 a closed pane exits 0 under --auto"  "$RRC" "0"
chk "T22 the subject is left for the notice"  "$(prop "$RSUBJ/session.md" recap_status)" "requested"
chk "T22 and the failure says why"            "$(grep -c 'launcher failed' "$RSUBJ/recap.log")" "1"
# Nothing to wait for: a pane that no longer exists will not come free.
chk "T22 and a gone pane is not waited on"    "$(pireads)" "1"

echo "== 39. ccfind survives its own warm cache on a GNU host =="
# GNU stat reads `-f` as --file-system, prints a filesystem block on stdout and exits 1,
# so a BSD-first || chain *appends* the real epoch to that garbage instead of replacing
# it, and cache_age's arithmetic reads the word `File` — fatal under set -u. The cold
# path returns early without calling stat, so the crash only fires once a cache exists:
# every run but the very first, and never on macOS, where the BSD form succeeds.
CC2="$ROOT/cchome2"; mkdir -p "$CC2/ccfind"
env XDG_CACHE_HOME="$CC2" HOME="$H" "$PLUGIN/tools/ccfind/ccfind.sh" --tags >/dev/null 2>&1 || true
chk "a cold run builds a cache"        "$([ -s "$CC2/ccfind/sessions.tsv" ] && echo yes || echo no)" "yes"
W39=$(env XDG_CACHE_HOME="$CC2" HOME="$H" "$PLUGIN/tools/ccfind/ccfind.sh" --tags 2>&1 >/dev/null); W39RC=$?
chk "a warm run exits zero"            "$W39RC" "0"
chk "and reads no poisoned mtime"      "$(printf '%s' "$W39" | grep -c 'unbound variable')" "0"

echo "== 40. ccfind's actions do not require pbcopy or tmux =="
# The three fzf actions assumed a Mac inside tmux: Ctrl-Y piped to pbcopy (a 127 that
# set -e turns into the whole UI dying), and Enter/Ctrl-O called tmux new-window with no
# guard — herdr is not tmux, sets no $TMUX and runs no tmux server, so both primary
# actions failed under it. The functions are extracted and driven with a PATH holding
# only what each tier needs, because the OSC 52 tier writes to /dev/tty and a test that
# let it fire would set the clipboard of whoever runs the suite.
CBIN="$ROOT/ccbin"; mkdir -p "$CBIN"
for t in bash cut dirname sed; do ln -sf "$(command -v "$t")" "$CBIN/$t"; done
CFNS=$(sed -n '/^copy_to_clipboard()/,/^}/p; /^copy_session_path()/,/^}/p; /^json_array()/,/^}/p;
    /^herdr_app_argv()/,/^}/p; /^open_alongside()/,/^}/p' "$PLUGIN/tools/ccfind/ccfind.sh")
CROW=$(printf 'disp\tid9\t/tmp/work\t%s/_sessions/2026-09-18/id9/session.md\t-\t-\t-' "$KB")
# pbcopy first when it exists: upstream macOS behaviour is unchanged.
cat > "$CBIN/pbcopy" << PB
#!/bin/bash
exec /bin/cat > "$ROOT/pb.out"
PB
chmod +x "$CBIN/pbcopy"
env PATH="$CBIN" TMUX= HERDR_ENV= CFNS="$CFNS" bash -c 'eval "$CFNS"; printf %s /kb/x | copy_to_clipboard' 2>/dev/null
chk "pbcopy is preferred when present" "$(cat "$ROOT/pb.out" 2>/dev/null)" "/kb/x"
rm -f "$CBIN/pbcopy" "$ROOT/pb.out"
# With no clipboard tool at all, the action must say where the path is and leave the
# UI alive, not die 127 before the confirmation line.
C40=$(env PATH="$CBIN" TMUX= HERDR_ENV= CFNS="$CFNS" CROW="$CROW" bash -c \
    'set -euo pipefail; eval "$CFNS"; copy_session_path "$CROW"' 2>&1); C40RC=$?
chk "no clipboard tool is not fatal"   "$C40RC" "0"
chk "and the path is still shown"      "$(printf '%s' "$C40" | grep -c '_sessions/2026-09-18/id9')" "1"
# Inside tmux the existing behaviour is kept, flags included.
cat > "$CBIN/tmux" << TM
#!/bin/bash
printf '%s\n' "\$*" >> "$ROOT/cc-mux.log"
TM
chmod +x "$CBIN/tmux"
: > "$ROOT/cc-mux.log"
env PATH="$CBIN" TMUX=/tmp/fake,1,0 HERDR_ENV= CFNS="$CFNS" bash -c \
    'eval "$CFNS"; open_alongside /tmp/work claude -r id9' 2>/dev/null
chk "inside tmux, tmux opens the window" \
    "$(grep -c 'new-window -c /tmp/work claude -r id9' "$ROOT/cc-mux.log")" "1"
rm -f "$CBIN/tmux"
# Under herdr the same action is a right-hand split of the caller's own pane, then pane
# run; the new pane's id must be read from the reply, never predicted. The stub answers
# with the real CLI's JSON shape, which nests the id under "pane", not "root_pane".
# It lives in a directory of its own so the PATH-less case below can hide it.
HBIN="$ROOT/hbin"; mkdir -p "$HBIN"
cat > "$HBIN/herdr" << HD
#!/bin/bash
printf '%s\n' "\$*" >> "$ROOT/cc-mux.log"
case "\$*" in
    "pane split"*)  printf '{"id":"cli:pane:split","result":{"pane":{"agent_status":"unknown","cwd":"/tmp/work","focused":true,"pane_id":"w9:p7","tab_id":"w9:t2"},"type":"pane_info"}}\n' ;;
    "pane current"*) printf '{"id":"cli:pane:current","result":{"pane":{"cwd":"/tmp","focused":true,"pane_id":"w9:pFOCUS","tab_id":"w9:t2","workspace_id":"w9"},"type":"pane_info"}}\n' ;;
esac
HD
chmod +x "$HBIN/herdr"
: > "$ROOT/cc-mux.log"
env PATH="$HBIN:$CBIN" TMUX= HERDR_ENV=1 HERDR_PANE_ID=w9:pOLD CFNS="$CFNS" bash -c \
    'eval "$CFNS"; open_alongside /tmp/work claude -r id9' 2>/dev/null
chk "under herdr, the caller's pane splits right" \
    "$(grep -c 'pane split --pane w9:pOLD --direction right --cwd /tmp/work' "$ROOT/cc-mux.log")" "1"
chk "and the command runs in the replied pane" "$(grep -c 'pane run w9:p7 claude -r id9' "$ROOT/cc-mux.log")" "1"
# herdr places new panes in the background; tmux switches to the new window. Without an
# explicit --focus the action looks like it did nothing at all: nvim really is running,
# in a pane the user never sees, and the only visible evidence is a stray process.
chk "and it is focused, as new-window would be" \
    "$(grep -c 'pane split .*--focus' "$ROOT/cc-mux.log")" "1"
# The launcher people actually use is a herdr keybinding of type "popup", and herdr runs
# a keybinding's command directly rather than through a login shell. Two things follow,
# and together they made every action fail while every test still passed: $PATH is not
# the one ~/.zshrc builds, so `command -v herdr` finds nothing; and popups have their
# pane identity deliberately removed (herdr's app/popup.rs calls without_pane_identity),
# so there is no own pane to split. The binary comes from $HERDR_BIN_PATH and the target
# from `pane current` — the focused pane, the one the popup is covering. Case 42 covers why
# that is asked for directly rather than read out of `api snapshot`.
: > "$ROOT/cc-mux.log"
P40=$(env PATH="$CBIN" TMUX= HERDR_ENV=1 HERDR_BIN_PATH="$HBIN/herdr" CFNS="$CFNS" \
    bash -c 'unset HERDR_PANE_ID; eval "$CFNS"; open_alongside /tmp/work nvim .' 2>&1); P40RC=$?
chk "a popup launcher still opens a pane"   "$P40RC" "0"
chk "it finds herdr off PATH via HERDR_BIN_PATH" \
    "$(grep -c 'pane split' "$ROOT/cc-mux.log")" "1"
chk "it asks which pane is focused"         "$(grep -c 'pane current' "$ROOT/cc-mux.log")" "1"
chk "and splits that one, not an empty id"  "$(grep -c 'pane split --pane w9:pFOCUS' "$ROOT/cc-mux.log")" "1"
# A missing binary must say so rather than dying on "command not found".
B40=$(env PATH="$CBIN" TMUX= HERDR_ENV=1 HERDR_BIN_PATH="$ROOT/nope/herdr" CFNS="$CFNS" \
    bash -c 'unset HERDR_PANE_ID; eval "$CFNS"; open_alongside /tmp/work nvim .' 2>&1); B40RC=$?
chk "an unusable herdr binary is reported"  "$B40RC" "1"
chk "and names the path it tried"           "$(printf '%s' "$B40" | grep -c 'herdr not found at')" "1"
# Neither multiplexer: a clear refusal with a message, not a hang or a bare tmux error.
M40=$(env PATH="$CBIN" TMUX= HERDR_ENV= CFNS="$CFNS" bash -c \
    'eval "$CFNS"; open_alongside /tmp/work claude -r id9' 2>&1); M40RC=$?
chk "no multiplexer is refused"        "$M40RC" "1"
chk "and the refusal names both"       "$(printf '%s' "$M40" | grep -c 'tmux or herdr')" "1"

echo "== 40b. in the Herdr app, Enter and Ctrl-O split the pane under the popup =="
# The Herdr app is neither tmux nor herdr: herdr-core gives every terminal $HC_TERMINAL_ID,
# and the herdr-app CLI drives the window. ccfind's popup there is not a pane, so the split
# names the pane underneath, which `status` reports as focused_pane, and the new pane's
# command changes into the folder itself, since pane.split takes none. A new tab is the
# fallback, and when that fails too, the reason is printed. The stub answers `status` in the
# real CLI's shape (pretty JSON, a space after the colon), fails where the real one does when
# asked to, and brackets each argument, so a folder with a space has to arrive as one. Run
# under set -euo pipefail, as ccfind runs: a failing `status` once ended ccfind silently.
ABIN="$ROOT/abin"; mkdir -p "$ABIN"
cat > "$ABIN/herdr-app" << HA
#!/bin/bash
{ printf herdr-app; printf ' [%s]' "\$@"; printf '\n'; } >> "$ROOT/cc-app.log"
case "\$1 \${2-}" in
    "status ")
        [ -z "\${APP_NO_WINDOW-}" ] || { echo "herdr-app: no Herdr window" >&2; exit 2; }
        printf '{\n  "focused_pane": %s,\n  "overlays": []\n}\n' "\${APP_PANE:-null}" ;;
    "do pane.split")
        [ -z "\${APP_SPLIT_FAILS-}" ] || { echo '{ "error": "no such pane" }'; exit 1; } ;;
    "do tab.new")
        [ -z "\${APP_NO_WINDOW-}" ] || { echo '{ "error": "no Herdr window" }'; exit 1; } ;;
esac
exit 0
HA
chmod +x "$ABIN/herdr-app"
# The new pane's command as herdr_app_argv prints it, up to the folder: cd, run, leave a shell.
WRAP40='"sh","-c","sleep 0.2; cd \"$1\" && shift && \"$@\"; exec \"${SHELL:-sh}\"","sh"'
app40() {
    : > "$ROOT/cc-app.log"
    env PATH="$ABIN:$CBIN" TMUX= HERDR_ENV= HC_TERMINAL_ID=t9 "$@" CFNS="$CFNS" \
        bash -c 'set -euo pipefail; eval "$CFNS"; open_alongside "/tmp/a b" claude -r id9' 2>&1
}
A40=$(app40 APP_PANE='"p5"'); A40RC=$?
chk "a pick in the Herdr app exits zero"   "$A40RC" "0"
chk "the pane under the popup splits right, into the folder" \
    "$(grep -cxF "herdr-app [do] [pane.split] [--pane] [p5] [--direction] [right] [--argv] [[$WRAP40,\"/tmp/a b\",\"claude\",\"-r\",\"id9\"]]" "$ROOT/cc-app.log")" "1"
chk "and no tab opens as well"             "$(grep -c '\[tab.new\]' "$ROOT/cc-app.log")" "0"
A40=$(app40 APP_PANE='"p5"' APP_SPLIT_FAILS=1)
chk "a split that fails falls back to a tab in the folder" \
    "$(grep -cxF 'herdr-app [do] [tab.new] [--folder] [/tmp/a b] [--argv] [["claude","-r","id9"]]' "$ROOT/cc-app.log")" "1"
A40=$(app40)
chk "with no focused pane, a tab opens"    "$(grep -c '\[tab.new\]' "$ROOT/cc-app.log")" "1"
A40=$(app40 APP_NO_WINDOW=1); A40RC=$?
chk "with no window at all, the pick fails" "$A40RC" "1"
chk "and says why"                         "$(printf '%s' "$A40" | grep -c 'no Herdr window')" "1"

echo "== 40c. a popup on another machine gets the pick as labels, and opens nothing =="
# The Herdr app's popup over a clouddesk space runs ccfind on the clouddesk, which has no
# herdr-app and no route back to the window. With CCFIND_REPORT=labels the pick is left as
# labels on ccfind's own hc terminal, for the popup to read after ccfind exits: the new pane's
# argv, exactly as case 40b's split gets it, and its folder. Nothing is opened here even where
# it could be: a herdr-app that would answer is on PATH. The stub brackets each argument.
cat > "$ABIN/hc" << HCS
#!/bin/bash
{ printf hc; printf ' [%s]' "\$@"; printf '\n'; } >> "$ROOT/cc-app.log"
HCS
chmod +x "$ABIN/hc"
: > "$ROOT/cc-app.log"
R40=$(env PATH="$ABIN:$CBIN" TMUX= HERDR_ENV= HC_TERMINAL_ID=t9 APP_PANE='"p5"' CCFIND_REPORT=labels \
    CFNS="$CFNS" bash -c 'set -euo pipefail; eval "$CFNS"
        open_alongside "/tmp/a b" claude -r id9; open_alongside /tmp/work nvim .' 2>&1); R40RC=$?
chk "a reported pick exits zero"           "$R40RC" "0"
chk "Enter labels the new pane's argv and its folder" \
    "$(grep -cxF "hc [label] [t9] [ccfind.cwd=/tmp/a b] [ccfind.argv=[$WRAP40,\"/tmp/a b\",\"claude\",\"-r\",\"id9\"]]" "$ROOT/cc-app.log")" "1"
chk "Ctrl-O labels nvim in the session folder" \
    "$(grep -cxF "hc [label] [t9] [ccfind.cwd=/tmp/work] [ccfind.argv=[$WRAP40,\"/tmp/work\",\"nvim\",\".\"]]" "$ROOT/cc-app.log")" "1"
chk "and nothing is opened here"           "$(grep -vc '^hc \[label\] ' "$ROOT/cc-app.log")" "0"

echo "== 41. ccfind finds fzf off the minimal PATH a popup launcher runs with =="
# The same fact case 40 records for the herdr binary, one call earlier: a keybinding's
# command does not run through a login shell, so $PATH is not the one ~/.zshrc builds.
# fzf lives in ~/.local/bin on the clouddesk and under Homebrew's prefix on the Mac, and
# a popup inherits neither. Missing fzf was not a clean 127 either -- the picker is the
# read end of `get_sessions | fzf`, so the write end took SIGPIPE, pipefail reported 141,
# and "command not found" went to a popup that had already closed. Measured at 35ms from
# spawn to exit, which is why the keybinding read as dead rather than as a broken tool.
FHOME="$ROOT/fzfhome"; mkdir -p "$FHOME/.local/bin" "$FHOME/.claude/plugins/config/second-brain"
cp "$CFGF" "$FHOME/.claude/plugins/config/second-brain/config.json"
# Prints nothing, so the picker selects nothing and ccfind exits before any action: this
# case is about reaching fzf at all, and none of the three actions should run here. It
# drains stdin first because the real fzf does, and a reader that exits without draining
# hands SIGPIPE back to get_sessions, which pipefail then reports as 141 — the very status
# this case is asserting the absence of, arriving from the stub rather than from the bug.
cat > "$FHOME/.local/bin/fzf" << FZ
#!/bin/bash
cat > /dev/null
printf 'fzf ran: %s\n' "\$*" >> "$ROOT/cc-fzf.log"
FZ
chmod +x "$FHOME/.local/bin/fzf"
: > "$ROOT/cc-fzf.log"
# env -i for a genuinely bare environment, as the popup has: no PATH from the caller, and
# no HERDR_* either, so the launcher's gate stays shut without relying on the tripwire.
F41=$(env -i HOME="$FHOME" PATH=/usr/bin:/bin XDG_CACHE_HOME="$ROOT/fzfcache" \
    "$PLUGIN/tools/ccfind/ccfind.sh" 2>&1); F41RC=$?
chk "a PATH without fzf is not fatal"   "$F41RC" "0"
chk "the picker still opened"           "$(grep -c 'fzf ran' "$ROOT/cc-fzf.log")" "1"
chk "and it was not a broken pipe"      "$(printf '%s' "$F41" | grep -c 'command not found')" "0"
# The two-step mode picks a tag through a second fzf of its own, before the session
# picker it shares with every other mode, so resolving one does not resolve the other.
: > "$ROOT/cc-fzf.log"
T41=$(env -i HOME="$FHOME" PATH=/usr/bin:/bin XDG_CACHE_HOME="$ROOT/fzfcache" \
    "$PLUGIN/tools/ccfind/ccfind.sh" --by-tag 2>&1); T41RC=$?
chk "--by-tag reaches its tag picker"   "$T41RC" "0"
chk "and ran fzf for the tag list"      "$(grep -c 'fzf ran' "$ROOT/cc-fzf.log")" "1"
# A non-interactive mode must not start needing fzf to list tags.
G41=$(env -i HOME="$FHOME" PATH=/usr/bin:/bin XDG_CACHE_HOME="$ROOT/fzfcache" \
    CCFIND_FZF="$ROOT/nope/fzf" "$PLUGIN/tools/ccfind/ccfind.sh" --tags 2>&1); G41RC=$?
chk "--tags needs no fzf at all"        "$G41RC" "0"
# Found at a later candidate, past a directory that does not have it: the Mac's case, where
# fzf is under Homebrew's prefix and ~/.local/bin holds something else or nothing. Worth its
# own row because the search is a short-circuited `[ -x ] && { ...; }` per directory, and
# only the first-candidate hit is exercised above.
FHOME2="$ROOT/fzfhome2"; mkdir -p "$FHOME2/.local/bin" "$FHOME2/.fzf/bin" \
    "$FHOME2/.claude/plugins/config/second-brain"
cp "$CFGF" "$FHOME2/.claude/plugins/config/second-brain/config.json"
cp "$FHOME/.local/bin/fzf" "$FHOME2/.fzf/bin/fzf"
: > "$ROOT/cc-fzf.log"
L41=$(env -i HOME="$FHOME2" PATH=/usr/bin:/bin XDG_CACHE_HOME="$ROOT/fzfcache2" \
    "$PLUGIN/tools/ccfind/ccfind.sh" 2>&1); L41RC=$?
chk "an empty first candidate is not fatal" "$L41RC" "0"
chk "and the later one is still found"      "$(grep -c 'fzf ran' "$ROOT/cc-fzf.log")" "1"
# An unusable fzf is named, the way an unusable herdr binary is in case 40, rather than
# leaving 141 as the only evidence. $CCFIND_FZF pins the lookup so the assertion does not
# depend on whether the host running the suite happens to have fzf in a system prefix.
# Not exercised: under a popup the message is also held on screen, which needs a tty.
N41=$(env -i HOME="$FHOME" PATH=/usr/bin:/bin XDG_CACHE_HOME="$ROOT/fzfcache" \
    CCFIND_FZF="$ROOT/nope/fzf" "$PLUGIN/tools/ccfind/ccfind.sh" 2>&1); N41RC=$?
chk "an unusable fzf is reported"       "$N41RC" "1"
chk "and the message names fzf"         "$(printf '%s' "$N41" | grep -c 'needs fzf')" "1"
chk "and names the path it tried"       "$(printf '%s' "$N41" | grep -c 'nope/fzf')" "1"

echo "== 42. Ctrl-O splits the pane in front, not whichever tab sorts last =="
# `pane split --pane X` puts the new pane in X's tab, so the wrong X opens nvim in another
# tab. Intermittently, which is what made it look like a Herdr quirk rather than a parse
# bug: a real snapshot carries one focused_pane_id per layout as well as the session's own,
# and a greedy `.*` in front of the pattern matches the LAST one on a one-line document --
# the remembered focus of whichever tab sorts last, whichever tab is actually in front.
# With one tab, or with the front tab last, the two coincide and it is right by luck.
# Case 40 passed throughout because its stub answers with a single focused_pane_id and an
# empty pane list, a shape the real server never sends.
TBIN="$ROOT/tbin"; mkdir -p "$TBIN"
# Modelled on a captured snapshot: session focus first, per-layout focus after it, and a
# last layout pointing somewhere else. It answers `pane current` as well, so the rows below
# assert which pane was split rather than which call was used to choose it.
cat > "$TBIN/herdr" << TB
#!/bin/bash
printf '%s\n' "\$*" >> "$ROOT/cc-tab.log"
case "\$*" in
    "pane split"*)   printf '{"id":"cli:pane:split","result":{"pane":{"pane_id":"w9:pNEW","tab_id":"w9:t1"},"type":"pane_info"}}\n' ;;
    "pane current"*) printf '{"id":"cli:pane:current","result":{"pane":{"cwd":"/tmp","focused":true,"pane_id":"w9:pFRONT","tab_id":"w9:t1","workspace_id":"w9"},"type":"pane_info"}}\n' ;;
    "api snapshot"*) printf '{"id":"cli:api:snapshot","result":{"snapshot":{"focused_pane_id":"w9:pFRONT","focused_tab_id":"w9:t1","focused_workspace_id":"w9","layouts":[{"focused_pane_id":"w9:pFRONT","tab_id":"w9:t1"},{"focused_pane_id":"w9:pBACK","tab_id":"w9:t2"}],"panes":[{"pane_id":"w9:pFRONT","tab_id":"w9:t1"},{"pane_id":"w9:pBACK","tab_id":"w9:t2"}]}}}\n' ;;
esac
TB
chmod +x "$TBIN/herdr"
: > "$ROOT/cc-tab.log"
T42=$(env PATH="$CBIN" TMUX= HERDR_ENV=1 HERDR_BIN_PATH="$TBIN/herdr" CFNS="$CFNS" \
    bash -c 'unset HERDR_PANE_ID; eval "$CFNS"; open_alongside /tmp/work nvim .' 2>&1); T42RC=$?
chk "a popup split still succeeds"        "$T42RC" "0"
chk "the split targets the front pane"    "$(grep -c 'pane split --pane w9:pFRONT' "$ROOT/cc-tab.log")" "1"
chk "and never the last tab's pane"       "$(grep -c 'pane split --pane w9:pBACK' "$ROOT/cc-tab.log")" "0"

echo "== 42b. the picker reads fzf's answer without a pipe that can break =="
# fzf --expect answers with two lines, the key and the pick, and the picker took the key with
# `printf | head -1`. head exits after one line; a printf still writing then dies of SIGPIPE,
# pipefail makes that 141, and set -e ended ccfind there: no message, nothing opened. Live it
# was a race (on the clouddesk all 3 traced Enter presses died there) that a quiet run hits
# too rarely to test. This stub makes it certain: a third line longer than any pipe buffer
# keeps printf writing after head has its line. It is a line of its own because bash's
# pattern removal is quadratic on a long line it has to scan, and the pick is not long.
SBIN="$ROOT/sbin"; mkdir -p "$SBIN"
# head stays on PATH, so the old line fails as it did live, with 141, not with 127.
ln -sf "$(command -v head)" "$SBIN/head"
cat > "$SBIN/fzf" << 'FZ'
#!/bin/bash
while IFS= read -r _; do :; done
printf '%s\n%s\n%*s\n' "$PICK_KEY" "$PICK_ROW" 200000 ''
FZ
chmod +x "$SBIN/fzf"
PFNS=$(sed -n '/^pick_session_from()/,/^}/p' "$PLUGIN/tools/ccfind/ccfind.sh")
for k42 in ctrl-o ""; do
    S42=$(env PATH="$SBIN:$CBIN" PICK_KEY="$k42" PICK_ROW="$CROW" PFNS="$PFNS" bash -c '
        set -euo pipefail
        eval "$PFNS"
        require_fzf() { :; }
        resume_session() { printf "resume %s\n" "$1"; }
        open_session_folder() { printf "nvim %s\n" "$1"; }
        PREVIEW_SCRIPT=:
        FZF_NAV_HEADER=
        FZF_NAV_BINDS=(--no-op)
        printf "row\n" | pick_session_from' 2>&1); S42RC=$?
    chk "${k42:-Enter}: a long answer does not end the picker" "$S42RC" "0"
    chk "${k42:-Enter}: and the action gets the pick" "$S42" "$([ -n "$k42" ] && echo nvim || echo resume) $CROW"
done

# ── create_domain.sh: the one sanctioned domain invention (ADR-0007) ─────────────
# A fresh fixture home, so the map written here cannot leak into earlier fixtures.
DKB="$ROOT/dkb"; DH="$ROOT/dhome"
DCFG="$DH/.claude/plugins/config/second-brain/config.json"
mkdir -p "$DH/.claude/plugins/config/second-brain" "$DKB/projects/cc"
jq -n --arg kb "$DKB" '{knowledge_bank_path:$kb}' > "$DCFG"
CDOM="$PLUGIN/skills/common/create_domain.sh"
env HOME="$DH" "$CDOM" "Bad Name" >/dev/null 2>&1; T43RC=$?
chk "a non-slug name is refused"           "$T43RC" "2"
chk "and creates nothing"                  "$(find "$DKB/projects" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" "1"
env HOME="$DH" "$CDOM" supply-chain --map "/tmp/sct*" --tags "sct, ops" >/dev/null 2>&1; T44RC=$?
chk "an approved slug creates the folder"  "$([ -d "$DKB/projects/supply-chain" ] && echo yes || echo no)" "yes"
chk "and exits clean"                      "$T44RC" "0"
chk "the map entry lands in the config"    "$(jq -r '.project_domains["/tmp/sct*"].domain // ""' "$DCFG")" "supply-chain"
chk "with its default tags"                "$(jq -r '.project_domains["/tmp/sct*"].default_tags | join(",")' "$DCFG")" "sct,ops"
chk "other config keys survive the write"  "$(jq -r '.knowledge_bank_path' "$DCFG")" "$DKB"
env HOME="$DH" "$CDOM" supply-chain >/dev/null 2>&1; T45RC=$?
chk "re-approving the same name resumes, not fails" "$T45RC" "0"
T46=$(env HOME="$DH" bash -c "source '$PLUGIN/skills/common/resolve_project.sh'; resolve_project /tmp/sct-pkgs/sub")
chk "a future session there resolves without a proposal" "$T46" "supply-chain"

echo "== 43. the recap's transcript parser shows every prompt and every inbound session message =="
# The user view used to cut its whole output at 100 lines, so a first prompt that expands
# a long skill body hid every later prompt; and messages from other sessions arrive as
# isMeta records, which a prompt view drops. A real recap missed three days of
# peer-driven work this way and filed a daily log that understated the session.
PT43="$PLUGIN/skills/session-recap/scripts/parse_transcript.sh"
PX43="$ROOT/parse-fixture.jsonl"
{
    printf '%s\n' '{"type":"user","timestamp":"2026-10-01T00:00:00Z","cwd":"/tmp/mapped","message":{"role":"user","content":"<command-name>/long-skill</command-name>"}}'
    printf '{"type":"user","isMeta":true,"timestamp":"2026-10-01T00:00:01Z","message":{"role":"user","content":[{"type":"text","text":"%s"}]}}\n' \
        "$(for i in $(seq 1 150); do printf 'skill line %s\\n' "$i"; done)"
    printf '%s\n' '{"type":"assistant","timestamp":"2026-10-01T00:00:02Z","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"ls"}}]}}'
    printf '%s\n' '{"type":"user","timestamp":"2026-10-01T00:00:03Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"t1","content":"out"}]}}'
    printf '%s\n' '{"type":"user","isMeta":true,"timestamp":"2026-10-02T00:00:00Z","message":{"role":"user","content":"Another Claude session sent a message:\n<cross-session-message from=\"uds:/x.sock\" from-name=\"peer-a\" from-mode=\"prompting\">\nlayer seven found\n</cross-session-message>"}}'
    printf '%s\n' '{"type":"user","timestamp":"2026-10-03T00:00:00Z","message":{"role":"user","content":"the last human prompt"}}'
} > "$PX43"
PU43=$("$PT43" "$PX43" users 2>/dev/null)
chk "the last prompt survives a long first skill body" "$(printf '%s\n' "$PU43" | grep -c 'the last human prompt')" "1"
chk "an expanded skill body is not shown as a prompt"  "$(printf '%s\n' "$PU43" | grep -c 'skill line 50')" "0"
chk "a tool result is not shown as a prompt"           "$(printf '%s\n' "$PU43" | grep -c 'tool_result')" "0"
chk "an inbound session message is shown with its sender" "$(printf '%s\n' "$PU43" | grep -c 'peer-a: *layer seven found')" "1"
chk "and counted in the statistics" "$("$PT43" "$PX43" stats 2>/dev/null | grep -c '^Inbound session messages: 1$')" "1"

echo "== 43b. the recap's statistics count tool calls, Agent spawns and every inbound envelope =="
# Bash commands piped every record that held a call through wc -l, so it counted the
# pretty-printed lines (2061 for 31 calls on a real transcript); Subagents spawned looked
# for a tool named Task when the tool is Agent, so it read 0 for every recap that had
# sub-agents, and the Subagent Invocations listing stayed empty for the same reason; and the
# inbound count matched only the isMeta cross-session envelope, while agent-team reports
# (several <teammate-message> blocks in one plain user record), peer messages and subagent
# hand-backs queued while the session was busy (queued_command attachments) and hand-backs
# delivered to an idle session ("Another Claude session sent a message:" around
# <agent-message>) each arrive in another. With no insight block, `all` also exited 1 from
# the trailing grep -v.
PX43B="$ROOT/parse-stats-fixture.jsonl"
{
    printf '%s\n' '{"type":"user","timestamp":"2026-10-01T00:00:00Z","cwd":"/tmp/mapped","message":{"role":"user","content":"count things"}}'
    printf '%s\n' '{"type":"assistant","timestamp":"2026-10-01T00:00:01Z","message":{"content":[{"type":"text","text":"two calls in one record"},{"type":"tool_use","id":"b1","name":"Bash","input":{"command":"ls\necho one"}},{"type":"tool_use","id":"b2","name":"Bash","input":{"command":"echo two"}}]}}'
    printf '%s\n' '{"type":"user","timestamp":"2026-10-01T00:00:02Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"b1","content":"one"},{"type":"tool_result","tool_use_id":"b2","content":"two"}]}}'
    printf '%s\n' '{"type":"assistant","timestamp":"2026-10-01T00:00:03Z","message":{"content":[{"type":"tool_use","id":"a1","name":"Agent","input":{"subagent_type":"Explore","description":"look around","prompt":"look"}}]}}'
    printf '%s\n' '{"type":"user","timestamp":"2026-10-01T00:00:04Z","message":{"role":"user","content":"Another Claude session sent a message:\n<teammate-message teammate_id=\"reader-1\" summary=\"done\">\nfirst report\n</teammate-message>\n<teammate-message teammate_id=\"reader-2\" summary=\"done\">\nsecond report\n</teammate-message>"}}'
    printf '%s\n' '{"type":"attachment","timestamp":"2026-10-01T00:00:05Z","attachment":{"type":"queued_command","prompt":"<cross-session-message from=\"uds:/x.sock\" from-name=\"peer-b\" from-mode=\"prompting\">\nqueued while busy\n</cross-session-message>","timestamp":"2026-10-01T00:00:05Z"}}'
    printf '%s\n' '{"type":"attachment","timestamp":"2026-10-01T00:00:06Z","attachment":{"type":"queued_command","prompt":"<agent-message from=\"d4e5f6\">\n[Subagent hand-back] queued while busy\n</agent-message>","timestamp":"2026-10-01T00:00:06Z"}}'
    printf '%s\n' '{"type":"attachment","timestamp":"2026-10-01T00:00:07Z","attachment":{"type":"queued_command","prompt":"<task-notification>\n<task-id>t1</task-id>\n</task-notification>","timestamp":"2026-10-01T00:00:07Z"}}'
} > "$PX43B"
PA43B=$(env HOME="$H" "$PT43" "$PX43B" all 2>/dev/null); PA43BRC=$?
chk "two Bash calls in one record count as two"      "$(printf '%s\n' "$PA43B" | grep -c '^Bash commands: 2$')" "1"
chk "an Agent call counts as a spawned subagent"     "$(printf '%s\n' "$PA43B" | grep -c '^Subagents spawned: 1$')" "1"
chk "and the subagent listing names it"              "$(printf '%s\n' "$PA43B" | grep -c '^\[Explore\] look around$')" "1"
chk "two teammate blocks, a queued peer message and a queued hand-back are four inbound, a queued task notification none" \
    "$(printf '%s\n' "$PA43B" | grep -c '^Inbound session messages: 4$')" "1"
chk "and all exits 0 without an insight block"       "$PA43BRC" "0"
printf '%s\n' '{"type":"user","isMeta":true,"timestamp":"2026-10-01T00:00:08Z","message":{"role":"user","content":"Another Claude session sent a message:\n<agent-message from=\"a1b2c3\">\n[Subagent hand-back] the report\n</agent-message>"}}' >> "$PX43B"
chk "a hand-back delivered to an idle session is the fifth inbound envelope" "$("$PT43" "$PX43B" stats 2>/dev/null | grep -c '^Inbound session messages: 5$')" "1"

echo "== 43c. the recap's error list reads is_error, not the words a result happens to use =="
# The section grepped every tool result for error, fail or exception, so on a long session
# quoted ticket text and reports filled its 30 lines, while the results that had actually
# failed, a cat of a missing file among them, named none of those words and never appeared.
PX43C="$ROOT/parse-errors-fixture.jsonl"
{
    printf '%s\n' '{"type":"assistant","timestamp":"2026-10-01T00:00:00Z","message":{"content":[{"type":"tool_use","id":"e1","name":"Bash","input":{"command":"cat missing"}}]}}'
    printf '%s\n' '{"type":"user","timestamp":"2026-10-01T00:00:01Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"e1","is_error":true,"content":"Exit code 1\ncat: missing: No such file or directory"}]}}'
    printf '%s\n' '{"type":"assistant","timestamp":"2026-10-01T00:00:02Z","message":{"content":[{"type":"tool_use","id":"e2","name":"Bash","input":{"command":"cat README.md"}}]}}'
    printf '%s\n' '{"type":"user","timestamp":"2026-10-01T00:00:03Z","message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"e2","content":"Exit code 2 is a usage error"}]}}'
} > "$PX43C"
PE43C=$("$PT43" "$PX43C" errors 2>/dev/null)
chk "errors lists a failed call that names no error word" "$(printf '%s\n' "$PE43C" | grep -c 'No such file or directory')" "1"
chk "errors skips a successful result that quotes one"   "$(printf '%s\n' "$PE43C" | grep -c 'usage error')" "0"

echo "== 43d. the recap's modified-files list sees writes made through Bash, not only Edit and Write =="
# Under auto mode the harness asks for file changes through Bash, so a six-file change made with
# `cat > … <<'EOF'` and `python3 - <<'EOF'` heredocs on a real transcript read "Files modified: 0"
# with an empty section, and the recap recovered the list from the CR description by hand.
PX43D="$ROOT/parse-files-fixture.jsonl"
{
    printf '%s\n' '{"type":"assistant","timestamp":"2026-10-01T00:00:00Z","message":{"content":[{"type":"tool_use","id":"f1","name":"Edit","input":{"file_path":"/tmp/fx/src/A.java","old_string":"a","new_string":"b"}}]}}'
    printf '%s\n' '{"type":"assistant","timestamp":"2026-10-01T00:00:01Z","message":{"content":[{"type":"tool_use","id":"f2","name":"Bash","input":{"command":"M=/tmp/fx/memory; cat > \"$M/note.md\" <<'"'"'EOF'"'"'\n# note\n> [!note] a quoted line\nif x -> y then\nEOF\necho done >> /tmp/fx/log.txt; ls > /dev/null 2>&1; ls | tee /tmp/fx/listing.cfg; sed -n '"'"'/<a>/,/<\\/a>/p'"'"' /tmp/fx/x.xml"}}]}}'
    printf '%s\n' '{"type":"assistant","timestamp":"2026-10-01T00:00:02Z","message":{"content":[{"type":"tool_use","id":"f3","name":"Bash","input":{"command":"python3 - <<'"'"'EOF'"'"'\np = \"packageInfo\"\ns = open(p).read()\nif len(s) > 0:\n    open(p, \"w\").write(s)\nopen(\"/tmp/fx/build.gradle.kts\", \"w\").write(\"x\")\nEOF"}}]}}'
} > "$PX43D"
PF43D=$("$PT43" "$PX43D" files-mod 2>/dev/null)
chk "a heredoc written through an expanded variable is listed" "$(printf '%s\n' "$PF43D" | grep -c '^Bash: /tmp/fx/memory/note.md$')" "1"
chk "an append redirect is listed"                             "$(printf '%s\n' "$PF43D" | grep -c '^Bash: /tmp/fx/log.txt$')" "1"
chk "a tee target is listed"                                   "$(printf '%s\n' "$PF43D" | grep -c '^Bash: /tmp/fx/listing.cfg$')" "1"
chk "a python open(var, w) resolves its variable"              "$(printf '%s\n' "$PF43D" | grep -c '^Bash: packageInfo$')" "1"
chk "a python open(literal, w) is listed"                      "$(printf '%s\n' "$PF43D" | grep -c '^Bash: /tmp/fx/build.gradle.kts$')" "1"
chk "the Edit call is still listed"                            "$(printf '%s\n' "$PF43D" | grep -c '^Edit: /tmp/fx/src/A.java$')" "1"
chk "/dev/null, a blockquote, an arrow, a comparison and a sed script are not files" "$(printf '%s\n' "$PF43D" | grep -cE 'dev/null|\[!note\]|^Bash: y$|^Bash: 0:?$|<|>')" "0"
PS43D=$("$PT43" "$PX43D" stats 2>/dev/null)
chk "the count covers both tools and Bash"                     "$(printf '%s\n' "$PS43D" | grep -c '^Files modified: 6$')" "1"
chk "and says how many came through Bash"                      "$(printf '%s\n' "$PS43D" | grep -c '^Files modified via Bash: 5$')" "1"

echo "== 43e. the recap's modified-files list takes no option and no cut substitution for a file =="
# On a real transcript, 5 of the 66 Bash entries were not files: `-e`, from a `sed -i -e … -e … file`
# whose pattern allowed one script before the file, and four paths cut at `$(date`, from a
# `LOG=/tmp/x-$(date +%s).log` assignment that the VAR=value scan ends at its first space.
PX43E="$ROOT/parse-files-options-fixture.jsonl"
{
    jq -nc --arg c "sed -i -e 's/a/b/g' -e 's/c/d/g' -e \"s/e'f/g/g\" /tmp/fx/smoke.mjs" \
        '{type:"assistant",timestamp:"2026-10-01T00:00:00Z",message:{content:[{type:"tool_use",id:"g1",name:"Bash",input:{command:$c}}]}}'
    jq -nc --arg c 'LOG=/tmp/fx/build-$(date +%s).log; ( cd /tmp/fx && make ) > "$LOG" 2>&1; echo ok > /tmp/fx/ok.txt' \
        '{type:"assistant",timestamp:"2026-10-01T00:00:01Z",message:{content:[{type:"tool_use",id:"g2",name:"Bash",input:{command:$c}}]}}'
} > "$PX43E"
PF43E=$("$PT43" "$PX43E" files-mod 2>/dev/null)
chk "a sed -i with three -e scripts names its file"             "$(printf '%s\n' "$PF43E" | grep -c '^Bash: /tmp/fx/smoke.mjs$')" "1"
chk "an option is never listed as a file"                       "$(printf '%s\n' "$PF43E" | grep -c '^Bash: -')" "0"
chk "a target cut inside a command substitution is not listed"  "$(printf '%s\n' "$PF43E" | grep -cF '$(')" "0"
chk "a plain redirect in the same command still is"             "$(printf '%s\n' "$PF43E" | grep -c '^Bash: /tmp/fx/ok.txt$')" "1"
chk "and the Bash count holds the two files only"               "$("$PT43" "$PX43E" stats 2>/dev/null | grep -c '^Files modified via Bash: 2$')" "1"

echo "== 44. a resumed session's second exit refreshes the memory snapshot in place =="
# cp -r into a memory/ that already exists copies the source inside it, so every exit
# after the first nested a fresh snapshot at memory/memory/ while the note kept linking
# the first exit's copies. Seven real session folders were found nested.
MS44="$H/.claude/projects/-tmp-mapped/memory"
mkdir -p "$MS44"; printf 'first\n' > "$MS44/note.md"
P44=aaaaaaaa-0000-0000-0000-000000000044; TP44="$H/.claude/projects/proj/$P44.jsonl"
turns "$TP44" 9; start $P44 startup mem-snapshot /tmp/mapped >/dev/null
F44="$KB/_sessions/$TODAY/$P44"
endrun x "$TP44" prompt_input_exit
chk "the first exit snapshots memory" "$(cat "$F44/memory/note.md" 2>/dev/null)" "first"
printf 'second\n' > "$MS44/note.md"; printf 'new\n' > "$MS44/added.md"
endrun x "$TP44" prompt_input_exit
chk "a second exit does not nest the snapshot" "$([ -d "$F44/memory/memory" ] && echo nested || echo flat)" "flat"
chk "and refreshes a changed memory in place"  "$(cat "$F44/memory/note.md" 2>/dev/null)" "second"
chk "and the note links a memory added since"  "$(grep -c '^- \[\[added\]\]$' "$F44/session.md")" "1"
rm -rf "$MS44"

echo "== 45. renames and durations survive a GNU userland =="
# tail -r and date -j -f are BSD-only. On GNU both error into /dev/null, so on Linux
# every reverse scan for the latest /rename came back empty and no session note ever
# got a duration: 0 of 80 notes in a real vault.
RC45="$ROOT/rc45"; mkdir -p "$RC45/.claude/projects/-tmp-rc45"
printf '%s\n' '{"type":"custom-title","customTitle":"first-name"}' '{"type":"user","cwd":"/tmp/rc45"}' \
    '{"type":"custom-title","customTitle":"latest-name"}' > "$RC45/.claude/projects/-tmp-rc45/s45.jsonl"
chk "read_custom_title returns the latest rename" \
    "$(env HOME="$RC45" bash -c 'source "$1" >/dev/null 2>&1; read_custom_title /tmp/rc45 s45' _ "$HELPL")" "latest-name"
P45=aaaaaaaa-0000-0000-0000-000000000045; TP45="$H/.claude/projects/proj/$P45.jsonl"
turns "$TP45" 9; start $P45 startup timed /tmp/mapped >/dev/null
endrun x "$TP45" prompt_input_exit
chk "the end hook records a duration" \
    "$(prop "$KB/_sessions/$TODAY/$P45/session.md" duration_seconds | grep -cE '^[0-9]+$')" "1"

echo "== 46. the recap gate survives an apostrophe and a double space in a --docs path =="
# Each --docs and --proposals entry was trimmed with xargs, which reads a single quote as
# the start of a quoted string: "unmatched single quote", exit 1, and under set -e the gate
# died in section 3 or 4 with no verdict line, which a recap reads as a failed gate rather
# than a tool fault. 18 documents in a real vault carry an apostrophe. xargs also collapsed
# a double space inside a name, so that document would have read as not found.
VKB46="$ROOT/vkb46"; mkdir -p "$VKB46/_proposals"
VD46="$VKB46/Taskei Fields Are the Ticket Graph's  Schema.md"
for i in $(seq 1 12); do printf '[[link %s]]\n' "$i"; done > "$VD46"
printf '%s\n' '---' 'type: proposed-improvement' 'severity: low' 'category: tooling' 'target: a script' \
    'classification: mechanical' 'session-folder: _sessions/2026-10-01/x' 'status: pending' '---' > "$VKB46/_proposals/what's-left.md"
V46=$(env HOME="$H" "$PLUGIN/skills/session-recap/scripts/verify_session_recap.sh" --kb-path "$VKB46" --no-reflection \
    --proposals " what's-left.md " --docs " $VD46 " 2>&1)
chk "the gate reaches its summary"                 "$(printf '%s\n' "$V46" | grep -c 'VERIFICATION SUMMARY')" "1"
chk "and counts the apostrophe document's links"   "$(printf '%s\n' "$V46" | grep -c "Graph's  Schema.md: 12 cross-references")" "1"
chk "and checks the apostrophe proposal"           "$(printf '%s\n' "$V46" | grep -c "what's-left.md: complete proposal, pending")" "1"

echo "== 47. a done recap ends its own session, and nothing else does (ADR-0010) =="
# The exit watcher types /exit through Herdr once the recap is done, the session has gone
# idle, nobody has stepped in for the grace, and the prompt box is empty or holds only dim
# ghost text. A stub herdr answers each of those from a file and records every call, so each
# refusal is pinned to the check that makes it rather than passing on the happy path.
WB="$ROOT/wbin"; mkdir -p "$WB"
cat > "$WB/herdr" << 'WSTUB'
#!/bin/bash
printf '%s\n' "$*" >> "$HOME/herdr-calls.log"
case "$*" in
    "agent wait "*"--until idle"*) echo '{"result":{"agent":{"agent_status":"idle"}}}' ;;
    "agent wait "*"--until working"*)
        case "$(cat "$HOME/w-grace")" in
            stepped) echo '{"result":{"agent":{"agent_status":"working"}}}'; exit 0 ;;
            # A person re-requests the recap while the grace runs.
            rerequested) env HOME="$HOME" "$(cat "$HOME/w-rst")" "$(cat "$HOME/w-subj")" clear --force >/dev/null 2>&1
                         env HOME="$HOME" "$(cat "$HOME/w-rst")" "$(cat "$HOME/w-subj")" requested >/dev/null 2>&1 ;;
        esac
        echo '{"error":{"code":"timeout","message":"timed out waiting for agent status"}}'; exit 1 ;;
    "agent explain "*)
        [ "$(cat "$HOME/w-box")" = empty ] && b='❯\n' || b='❯ go ahead: land it\n'
        printf '{"state":"idle","visible_idle":true,"evaluated_rules":[{"id":"live_prompt_box","matched":true,"evidence":{"region_preview":"%s"}}]}\n' "$b" ;;
    "agent read "*)
        # The ghost as Claude Code draws it: the cursor inverse on its first letter, the rest dim.
        case "$(cat "$HOME/w-box")" in
            empty) printf 'the recap is done\n❯ \n' ;;
            ghost) printf 'the recap is done\n❯ \033[7mg\033[27m\033[2mo ahead: land it\033[22m\n' ;;
            text)  printf 'the recap is done\n❯ go ahead: land it\n' ;;
        esac ;;
    "agent prompt "*) : > "$HOME/w-exited" ;;
esac
exit 0
WSTUB
chmod +x "$WB/herdr"
# A stub claude that does what a recap does to its subject, then sits at its prompt until the
# watcher's /exit arrives, as the real session does; a file bounds how long it sits.
cat > "$WB/claude" << 'WCL'
#!/bin/bash
printf 'claude %s%s\n' "$*" "${CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION:+ suggestions=$CLAUDE_CODE_ENABLE_PROMPT_SUGGESTION}" >> "$HOME/claude-calls.log"
subj="${*: -1}"; subj="${subj#/second-brain:session-recap }"
[ "$(cat "$HOME/w-claude-done" 2>/dev/null)" = no ] ||
    "$SECOND_BRAIN_PLUGIN_ROOT/skills/common/recap_status.sh" "$subj" done >/dev/null 2>&1
i=0; n=$(cat "$HOME/w-claude-wait" 2>/dev/null || echo 100)
while [ ! -f "$HOME/w-exited" ] && [ "$i" -lt "$n" ]; do sleep 0.1; i=$((i+1)); done
[ -f "$HOME/w-exited" ] && echo "exited-by-watcher" >> "$HOME/claude-calls.log"
exit 0
WCL
chmod +x "$WB/claude"
nmk 2026-09-14 f4747474-4747-4747-4747-474747474747 w47-subject ''
WSUBJ="$NKB/_sessions/2026-09-14/f4747474-4747-4747-4747-474747474747"
printf '%s' "$RST" > "$NH/w-rst"; printf '%s' "$WSUBJ" > "$NH/w-subj"
WCALLS="$NH/herdr-calls.log"; WLOG="$WSUBJ/recap.log"
# grace answer, box, and the status the subject is left at: requested, running or done.
wset(){ printf '%s' "$1" > "$NH/w-grace"; printf '%s' "$2" > "$NH/w-box"; printf '100' > "$NH/w-claude-wait"
    printf 'yes' > "$NH/w-claude-done"
    rm -f "$NH/w-exited"; : > "$WCALLS"; : > "$NH/claude-calls.log"; : > "$WLOG"
    env HOME="$NH" "$RST" "$WSUBJ" clear --force >/dev/null 2>&1
    env HOME="$NH" "$RST" "$WSUBJ" requested >/dev/null 2>&1
    case "$3" in running|done) env HOME="$NH" "$RST" "$WSUBJ" running >/dev/null 2>&1 ;; esac
    [ "$3" = done ] && env HOME="$NH" "$RST" "$WSUBJ" done >/dev/null 2>&1; }
# The watcher alone, against a stand-in for the recap child that lives $1 seconds.
wwatch(){ sleep "$1" & local kid=$!
    env HOME="$NH" PATH="$WB:$PATH" SECOND_BRAIN_RECAP_EXIT_POLL_S=1 \
        "$PLUGIN/hooks/scripts/recap_exit_watch.sh" "$WSUBJ" w9:pW "$kid" >/dev/null 2>&1
    kill "$kid" 2>/dev/null; wait "$kid" 2>/dev/null; }
wexits(){ grep -c '^agent prompt w9:pW /exit$' "$WCALLS"; }

wset quiet empty done; wwatch 30
chk "W1 a done, idle, unattended recap gets /exit"  "$(wexits)" "1"
chk "W1 after the turn it was in had ended"         "$(grep -c '^agent wait w9:pW --until idle --until done' "$WCALLS")" "1"
chk "W1 and after a grace nobody broke"             "$(grep -c '^agent wait w9:pW --until working --until blocked' "$WCALLS")" "1"
chk "W1 the log says why it typed"                  "$(grep -c 'exit-watch typing /exit into w9:pW: done, idle through the grace, prompt box empty' "$WLOG")" "1"

# The debrief mod's `go ahead: ...` is placeholder text, so /exit typed over it is clean. Read
# as plain text it is indistinguishable from a person's half-typed line; the dim attribute is
# the whole difference, and this pins the styled read rather than the text one.
wset quiet ghost done; wwatch 30
chk "W2 dim ghost text does not hold the session"   "$(wexits)" "1"
chk "W2 and the log names the ghost"                "$(grep -c 'prompt box ghost' "$WLOG")" "1"

wset quiet text done; wwatch 30
chk "W3 text a person typed keeps the session"      "$(wexits)" "0"
chk "W3 and the log says so"                        "$(grep -c 'left open: the prompt box holds text' "$WLOG")" "1"

# A person who types in the pane starts a turn, and from then on the session is theirs.
wset stepped empty done; wwatch 30
chk "W4 a person stepping in keeps the session"     "$(wexits)" "0"
chk "W4 and the box is never even read"             "$(grep -c '^agent explain' "$WCALLS")" "0"
chk "W4 and the log says a person stepped in"       "$(grep -c 'a person stepped in' "$WLOG")" "1"

# ADR-0007 asks its domain question while the status is still running, so a recap waiting on
# a person is never ended, and the watcher leaves with the child, having asked Herdr nothing.
wset quiet empty running; wwatch 2
chk "W5 a recap that never reaches done is left be" "$(wc -l < "$WCALLS" | tr -d ' ')" "0"

wset rerequested empty done; wwatch 30
chk "W6 a re-request during the grace is honoured"  "$(wexits)" "0"
chk "W6 and the log says what it found"             "$(grep -c 'left open: the subject is requested now' "$WLOG")" "1"

# End to end through the child: it starts the watcher itself, behind the launcher's gate.
wset quiet empty requested
WCOUT=$(env HOME="$NH" PATH="$WB:$PATH" HERDR_ENV=1 HERDR_PANE_ID=w9:pW \
    SECOND_BRAIN_RECAP_OF="$WSUBJ" SECOND_BRAIN_RECAP_NAME=recap-w47 SECOND_BRAIN_PLUGIN_ROOT="$PLUGIN" \
    SECOND_BRAIN_RECAP_EXIT_POLL_S=1 bash "$PLUGIN/hooks/scripts/recap_child.sh" "$WSUBJ" 2>&1)
chk "W7 the child's own watcher ends the session"   "$(grep -c '^exited-by-watcher$' "$NH/claude-calls.log")" "1"
chk "W7 the recap runs under its own name"          "$(grep -c -- '-n recap-w47 /second-brain:session-recap' "$NH/claude-calls.log")" "1"
chk "W7 and Claude Code's own suggestions stay on"  "$(grep -c 'suggestions=false' "$NH/claude-calls.log")" "0"
chk "W7 and the TUI recap keeps debrief"            "$(grep -c 'debrief@' "$NH/claude-calls.log")" "0"
chk "W7 the subject stays done"                     "$(prop "$WSUBJ/session.md" recap_status)" "done"
chk "W7 the child logs the exit"                    "$(grep -c 'exit status=done' "$WLOG")" "1"
chk "W7 and the pane says what happened"            "$(printf '%s\n' "$WCOUT" | grep -c 'ended: recap_status done')" "1"
chk "W7 no watcher outlives the child"              "$(pgrep -f "recap_exit_watch.sh $WSUBJ" | wc -l | tr -d ' ')" "0"

# Outside Herdr there is nothing to type /exit through, so no watcher starts and the session
# ends only the way it always has. The pane id is set on purpose: the gate is HERDR_ENV, the
# launcher's own, and with both cleared the watcher's usage check would refuse first and
# hide a gate that had gone missing. The stub sits for 3 s, long enough for a watcher that
# should not exist to poll, find done and type; at 0.5 s it would be stopped before it acted.
wset quiet empty requested; printf '30' > "$NH/w-claude-wait"
env HOME="$NH" PATH="$WB:$PATH" HERDR_ENV= HERDR_PANE_ID=w9:pW \
    SECOND_BRAIN_RECAP_OF="$WSUBJ" SECOND_BRAIN_RECAP_NAME=recap-w47 SECOND_BRAIN_PLUGIN_ROOT="$PLUGIN" \
    SECOND_BRAIN_RECAP_EXIT_POLL_S=1 bash "$PLUGIN/hooks/scripts/recap_child.sh" "$WSUBJ" >/dev/null 2>&1
chk "W8 outside Herdr no watcher starts"            "$(grep -c '^agent ' "$WCALLS")" "0"
chk "W8 and nothing ends the session for it"        "$(grep -c '^exited-by-watcher$' "$NH/claude-calls.log")" "0"

# A recap that ends without reaching done stops its watcher on the way out. The poll is long
# here on purpose, so a watcher left to notice by itself would still be running when this looks.
wset quiet empty requested; printf 'no' > "$NH/w-claude-done"; printf '5' > "$NH/w-claude-wait"
env HOME="$NH" PATH="$WB:$PATH" HERDR_ENV=1 HERDR_PANE_ID=w9:pW \
    SECOND_BRAIN_RECAP_OF="$WSUBJ" SECOND_BRAIN_RECAP_NAME=recap-w47 SECOND_BRAIN_PLUGIN_ROOT="$PLUGIN" \
    SECOND_BRAIN_RECAP_EXIT_POLL_S=37 bash "$PLUGIN/hooks/scripts/recap_child.sh" "$WSUBJ" >/dev/null 2>&1
sleep 0.3
chk "W9 the child stops its watcher on the way out" "$(pgrep -f "recap_exit_watch.sh $WSUBJ" | wc -l | tr -d ' ')" "0"
chk "W9 and its sleep goes with it"                 "$(pgrep -u "$(id -u)" -f '^sleep 37$' | wc -l | tr -d ' ')" "0"
chk "W9 a recap that never got done is failed"      "$(prop "$WSUBJ/session.md" recap_status)" "failed"
chk "W9 and the watcher asked Herdr nothing"        "$(grep -c '^agent ' "$WCALLS")" "0"

echo "== 48. the hooks label the hosting hc terminal with the session folder (ADR-0012) =="
# The Herdr app's Files panel shows a session's folder from one hc label on the terminal
# hosting it, `second-brain.session=<folder>`, declared by the session's own hooks and never
# detected. A stub hc ahead of the tripwire records every call, one bracket per argument so a
# folder split in two would show, and answers `get` with the foreground group it is given. Two
# gates: $HC_TERMINAL_ID, and, when $CLAUDE_PID is set, that claude being in the terminal's
# foreground process group, so a nested claude can neither relabel the host nor take its label
# away. Every SessionStart sets the label (a /clear re-sets the same value, so the panel never
# flickers), a real end removes it in hc's `key=` form, and the clear and resume reasons leave
# it, since the SessionStart that follows each relabels. Without $HC_TERMINAL_ID no hook calls
# hc at all, which is what keeps a terminal without hc a silent no-op: that run goes through the
# suite's own PATH, where the tripwire would record a call. Every run below sets CLAUDE_PID or
# empties it, because a suite run from inside a Claude session inherits that session's.
#
# The gate reads $CLAUDE_PID's group with ps, so the pids here are live processes: the suite
# itself; W48, a member of the suite's group that is not its leader, as Claude Code is under the
# clouddesk's toolbox shim; N48, a process in a group of its own, as a nested claude is; and D48,
# a pid that has already exited. They are started through perl inside $(...), never with a bare
# `&` or a `( )` subshell, because a caller with job control on makes bash give those a group of
# their own, and print a setpgid complaint wherever that is not permitted.
#
# The start write is a detached job that retries for about ten seconds, so a check waits for the
# stub's call with a deadline rather than assume it happened when the hook returned, and a check
# that nothing lands first waits out the job. The stub hangs for good under HC_STUB_SLEEP, with
# exec so that killing it ends the hang, and fails its first HC_STUB_FAIL_FIRST calls without an
# answer; SECOND_BRAIN_LABEL_RETRY_S shortens the job's window. The job's deadline is whole seconds
# from `date +%s`, so an n-second window can close as little as n-1 seconds after the job starts,
# depending on where in a second it started. A check that counts attempts therefore gets a 5 s
# window: at least 4 s, which always leaves room for a second attempt after a hung first one of
# about 2 s. At 3 s, whether a second attempt began depended on that phase.
LBIN="$ROOT/lbin"; mkdir -p "$LBIN"
cat > "$LBIN/hc" << 'STUB'
#!/bin/bash
{ printf hc; printf ' [%s]' "$@"; printf '\n'; } >> "$HOME/hc-calls.log"
[ -z "${HC_STUB_SLEEP-}" ] || exec sleep "$HC_STUB_SLEEP"
if [ -n "${HC_STUB_FAIL_FIRST-}" ]; then
    n=$(( $(cat "$HOME/hc-stub-calls" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$HOME/hc-stub-calls"
    [ "$n" -gt "$HC_STUB_FAIL_FIRST" ] || exit 1
fi
if [ "$1" = get ]; then
    [ -z "${HC_STUB_SILENT-}" ] || exit 0
    if [ -n "${HC_STUB_FG_PID-}" ]; then printf '{"foreground":{"pid":%s}}\n' "$HC_STUB_FG_PID"
    else printf '{"foreground":null}\n'; fi
fi
exit "${HC_STUB_EXIT:-0}"
STUB
chmod +x "$LBIN/hc"
G48=$(ps -o pgid= -p $$ | tr -d ' ')
W48=$(perl -e 'exit 0 if fork; print "$$\n"; open STDOUT, ">", "/dev/null"; open STDERR, ">", "/dev/null"; exec "sleep", "60"')
N48=$(perl -e 'exit 0 if fork; setpgrp(0, 0); print "$$\n"; open STDOUT, ">", "/dev/null"; open STDERR, ">", "/dev/null"; exec "sleep", "60"')
D48=$(sh -c 'echo $$')
L48=48484848-4848-4848-4848-484848484848; LT="$H/.claude/projects/proj/$L48.jsonl"
LF="$KB/_sessions/$TODAY/$L48"; LON=(PATH="$LBIN:$PATH" HC_TERMINAL_ID=t9 CLAUDE_PID=$$ HC_STUB_FG_PID="$G48")
lcount(){ grep -cxF "$1" "$H/hc-calls.log"; }
lverbs(){ grep -c "^hc \[$1\] " "$H/hc-calls.log"; }
lwait(){ # $1=exact call line; prints its count as soon as it is there, else 0 after about 5 s
    local i=0
    until [ "$(lcount "$1")" -gt 0 ] || [ "$i" -ge 50 ]; do sleep 0.1; i=$((i + 1)); done
    lcount "$1"; }
# A job can outlive its check, retrying on a loaded machine, and its calls would then land in the
# next check's log, so every check starts once the last job has finished. The jobs carry their
# value, which is under $KB, on their command line.
ldrain(){ # until no label job of this case is left, up to about 15 s
    local i=0
    while pgrep -f "$KB/_sessions" >/dev/null 2>&1 && [ "$i" -lt 150 ]; do sleep 0.1; i=$((i + 1)); done; }
lreset(){ ldrain; : > "$H/hc-calls.log"; : > "$H/hc-stub-calls"; }
lresume(){ printf '{"session_id":"%s","cwd":"/tmp/mapped","transcript_path":"%s","source":"resume"}' "$L48" "$LT" \
    | env HOME="$H" HERDR_PANE_ID= TMUX_PANE= "${LON[@]}" "$PLUGIN/hooks/scripts/session_resume.sh" >/dev/null 2>&1; }
lreset; start $L48 startup labelled /tmp/mapped "${LON[@]}" >/dev/null
chk "a launch labels its terminal with the folder"    "$(lwait "hc [label] [t9] [second-brain.session=$LF]")" "1"
lreset; start $L48 clear labelled /tmp/mapped "${LON[@]}" >/dev/null
chk "a /clear sets the same label again"              "$(lwait "hc [label] [t9] [second-brain.session=$LF]")" "1"
lreset; lresume
chk "a resume labels too"                             "$(lwait "hc [label] [t9] [second-brain.session=$LF]")" "1"
lreset; endrun x "$LT" clear "${LON[@]}"
chk "an end for /clear leaves the label"              "$(grep -c 'second-brain.session' "$H/hc-calls.log")" "0"
lreset; endrun x "$LT" resume "${LON[@]}"
chk "an end for a resume leaves it too"               "$(grep -c 'second-brain.session' "$H/hc-calls.log")" "0"
lreset; endrun x "$LT" other "${LON[@]}"
chk "a real end removes it"                           "$(lcount 'hc [label] [t9] [second-brain.session=]')" "1"
chk "and asks hc only for the foreground before it"   "$(paste -sd'|' "$H/hc-calls.log")" "hc [get] [t9] [--json]|hc [label] [t9] [second-brain.session=]"
# Claude Code run by a wrapper that does not exec it is in the foreground group without leading
# it: the clouddesk's toolbox runs a shim that runs a wrapper that runs it. The group is what
# counts, and a pid comparison refused every session there.
lreset; start $L48 startup labelled /tmp/mapped "${LON[@]}" CLAUDE_PID="$W48" >/dev/null
chk "a claude in the foreground group but not leading it labels" "$(lwait "hc [label] [t9] [second-brain.session=$LF]")" "1"
# A claude in a group of its own is a nested one, a `claude -p` from a Bash tool say: it asks,
# and then touches nothing, at its start or at its end. It is refused on every attempt rather
# than once, so it keeps asking until its window closes, and never writes.
lreset
start $L48 startup labelled /tmp/mapped "${LON[@]}" CLAUDE_PID="$N48" SECOND_BRAIN_LABEL_RETRY_S=5 >/dev/null; ldrain
chk "a nested claude is asked about on every attempt" "$([ "$(lverbs get)" -ge 2 ] && echo each || echo "asked $(lverbs get)x")" "each"
chk "and does not relabel the host"                   "$(lverbs label)" "0"
lreset; endrun x "$LT" other "${LON[@]}" CLAUDE_PID="$N48"
chk "nor take the host's label away at its end"       "$(lverbs label)" "0"
# A CLAUDE_PID that names no live process has no group, so it is refused before hc is asked.
lreset; start $L48 startup labelled /tmp/mapped "${LON[@]}" CLAUDE_PID="$D48" >/dev/null; ldrain
chk "a CLAUDE_PID that is not running is refused"     "$(lverbs label)|$(lverbs get)" "0|0"
# No CLAUDE_PID means nothing to compare, so the call goes ahead as it did before the gate. The
# helper reads an empty value as unset, which clears it here without a subshell.
lreset; start $L48 startup labelled /tmp/mapped "${LON[@]}" CLAUDE_PID= >/dev/null
chk "without CLAUDE_PID the label is set ungated"     "$(lwait "hc [label] [t9] [second-brain.session=$LF]")|$(lverbs get)" "1|0"
# On a busy machine hc misses the first attempts or never answers at all. The start hook must not
# wait either way, a write that fails at first must land on a retry, and a job that never gets an
# answer must give up after its window with nothing left running.
lreset
start $L48 startup labelled /tmp/mapped "${LON[@]}" HC_STUB_FAIL_FIRST=2 >/dev/null
chk "a write that fails at first lands on a retry"    "$(lwait "hc [label] [t9] [second-brain.session=$LF]")|$(lverbs get)" "1|3"
# An hc that answers nothing at all, exit 0 and no output, must not pass the gate on any attempt:
# under a plain `jq -e`, jq 1.6 (the clouddesk's) reads no input as a pass.
lreset; start $L48 startup labelled /tmp/mapped "${LON[@]}" HC_STUB_SILENT=1 SECOND_BRAIN_LABEL_RETRY_S=5 >/dev/null; ldrain
chk "an empty answer from hc never passes the gate"   "$(lverbs label)|$([ "$(lverbs get)" -ge 2 ] && echo asked || echo "asked $(lverbs get)x")" "0|asked"
WIN48=5; lreset; S48=$(date +%s)
start $L48 startup labelled /tmp/mapped "${LON[@]}" HC_STUB_SLEEP=41 SECOND_BRAIN_LABEL_RETRY_S=$WIN48 >/dev/null
E48=$(date +%s)
chk "a start hook returns promptly while hc hangs" "$([ $((E48 - S48)) -lt 3 ] && echo prompt || echo "took $((E48 - S48)) s")" "prompt"
ldrain; T48=$(date +%s)
chk "and its write retries, then gives up"            "$(lcount "hc [label] [t9] [second-brain.session=$LF]")|$([ "$(lverbs get)" -ge 2 ] && echo retried || echo "asked $(lverbs get)x")" "0|retried"
# The window, then at most the one-second pause and one more attempt of about two seconds, plus
# the start hook's own time and a second of rounding at each end: seven seconds over the window.
chk "within its window and one more attempt"          "$([ $((T48 - S48)) -le $((WIN48 + 7)) ] && echo yes || echo "after $((T48 - S48)) s")" "yes"
chk "leaving no process behind"                       "$(pgrep -f "$LF" | wc -l | tr -d ' ')|$(pgrep -fx 'sleep 41' | wc -l | tr -d ' ')" "0|0"
TRIP48=$(cat "$TRIPWIRE" 2>/dev/null | wc -l | tr -d ' ')
start $L48 startup labelled /tmp/mapped HC_TERMINAL_ID= >/dev/null; endrun x "$LT" other HC_TERMINAL_ID=
chk "without HC_TERMINAL_ID the hooks reach no hc at all" "$(cat "$TRIPWIRE" 2>/dev/null | wc -l | tr -d ' ')" "$TRIP48"
# A core that is down or restarting keeps hc waiting for seconds, and a hook that overruns its
# budget is cancelled. So the whole call, the foreground check included, is bounded: a hung hc
# must hold neither hook for long, and the recap stamp, which the end hook writes before the
# removal, must still land.
env HOME="$H" "$SK" --set auto_recap notify >/dev/null 2>&1
L48B=48484848-4848-4848-4848-48484848484b; LTB="$H/.claude/projects/proj/$L48B.jsonl"; turns "$LTB" 9
S48=$(date +%s)
start $L48B startup hung-hc /tmp/mapped "${LON[@]}" HC_STUB_SLEEP=8 SECOND_BRAIN_LABEL_RETRY_S=1 >/dev/null
endrun x "$LTB" prompt_input_exit "${LON[@]}" HC_STUB_SLEEP=8
E48=$(date +%s)
chk "a hung hc holds neither hook for long" "$([ $((E48 - S48)) -lt 8 ] && echo bounded || echo "took $((E48 - S48)) s")" "bounded"
chk "and the end hook still stamps its recap request" "$(prop "$KB/_sessions/$TODAY/$L48B/session.md" recap_status)" "requested"
# The helpers keep their promise under a caller's set -e and set -u: an hc that fails, or no
# terminal id at all, must not end the caller.
HL48="$PLUGIN/skills/common/obsidian_helpers.sh"
chk "a failing hc does not end a set -e caller" \
    "$(env HOME="$H" "${LON[@]}" HC_STUB_EXIT=3 SECOND_BRAIN_LABEL_RETRY_S=0 bash -c 'source "$1" >/dev/null 2>&1; set -e; label_hc_terminal /f; unlabel_hc_terminal; echo reached' _ "$HL48" 2>/dev/null)" "reached"
chk "an unset terminal id does not end a set -u caller" \
    "$(env -u HC_TERMINAL_ID HOME="$H" bash -c 'source "$1" >/dev/null 2>&1; set -u; label_hc_terminal /f; unlabel_hc_terminal; echo reached' _ "$HL48" 2>/dev/null)" "reached"
kill "$W48" "$N48" 2>/dev/null

echo "== 49. in the Herdr app the recap reuses the terminal it left, else runs as a worker (ADR-0011) =="
# An app pane is an hc terminal: $HC_TERMINAL_ID, no TUI variable. The window lives on another
# machine, so there is no pane to split; the launcher types into the pane it left with `hc send`
# when that pane's shell is free, and starts a worker with `hc run` otherwise. One stub hc for
# every app case: `get` answers from $HOME/hc-state (free, busy, settles, gone, refuses), its
# status from $HOME/hc-status when present; `run` from $HOME/hc-run (ok, taken once, fails);
# `read` draws a screen whose box comes from $HOME/w-box; `keys` with `enter` ends the stub
# claude of case 47. Every call is recorded.
AB="$NH/abin"; mkdir -p "$AB"
cat > "$AB/hc" << 'HSTUB'
#!/bin/bash
printf '%s\n' "$*" >> "$HOME/hc-calls.log"
st=$(cat "$HOME/hc-status" 2>/dev/null)
case "$st" in
    '') status='null' ;;
    stepped) n=$(cat "$HOME/hc-status-gets" 2>/dev/null); n=$(( ${n:-0} + 1 )); printf '%s' "$n" > "$HOME/hc-status-gets"
             [ "$n" -le 2 ] && status='{"state":"idle"}' || status='{"state":"working"}' ;;
    settling) n=$(cat "$HOME/hc-status-gets" 2>/dev/null); n=$(( ${n:-0} + 1 )); printf '%s' "$n" > "$HOME/hc-status-gets"
              [ "$n" -le 3 ] && status='{"state":"working"}' || status='{"state":"idle"}' ;;
    *) status="{\"state\":\"$st\"}" ;;
esac
free="{\"pid\":5555,\"foreground\":{\"pid\":5555,\"name\":\"zsh\"},\"state\":\"live\",\"status\":$status}"
busy="{\"pid\":5555,\"foreground\":{\"pid\":45612,\"name\":\"claude\"},\"state\":\"live\",\"status\":$status}"
case "$1" in
    get)
        case "$(cat "$HOME/hc-state" 2>/dev/null)" in
            busy) echo "$busy" ;;
            settles) n=$(cat "$HOME/hc-gets" 2>/dev/null); n=$(( ${n:-0} + 1 )); printf '%s' "$n" > "$HOME/hc-gets"
                     [ "$n" -ge 3 ] && echo "$free" || echo "$busy" ;;
            gone) echo '{"error":{"kind":"not_found","message":"no terminal"}}' >&2; exit 3 ;;
            *) echo "$free" ;;
        esac ;;
    send)
        [ "$(cat "$HOME/hc-state" 2>/dev/null)" = refuses ] && { echo '{"error":{"kind":"not_found"}}' >&2; exit 3; }
        echo '{"started":null,"status":null}' ;;
    run)
        case "$(cat "$HOME/hc-run" 2>/dev/null)" in
            taken) printf 'ok' > "$HOME/hc-run"
                   echo '{"error":{"kind":"name_taken","message":"a live terminal is already named"}}' >&2; exit 1 ;;
            fails) echo '{"error":{"kind":"spawn_failed","message":"no holder"}}' >&2; exit 1 ;;
        esac
        echo '{"address":"t77","state":"live"}' ;;
    wait) echo '{"status":"idle","reason":"timeout"}' ;;
    read)
        echo "the recap is done"
        [ "$(cat "$HOME/w-box" 2>/dev/null)" = menu ] && echo "  ❯ /exit        Exit the CLI"
        # The box as Claude Code draws it and hc reads it back (measured 2026-11-04 on a done
        # recap): the pointer, a no-break space, then whatever the box holds.
        case "$(cat "$HOME/w-box" 2>/dev/null)" in
            empty|menu) printf '❯\302\240\n' ;;
            *)          printf '❯\302\240go ahead: land it\n' ;;
        esac
        echo "  Model: Opus  Session: recap" ;;
    keys) case "$*" in *enter*) : > "$HOME/w-exited" ;; esac ;;
    kill) echo "hc stub: kill must never be called" >&2; exit 1 ;;
esac
exit 0
HSTUB
chmod +x "$AB/hc"
HCALLS="$NH/hc-calls.log"
aset(){ printf '%s' "$1" > "$NH/hc-state"; printf '%s' "${2:-ok}" > "$NH/hc-run"; printf '0' > "$NH/hc-gets"
    rm -f "$NH/hc-status" "$NH/hc-status-gets"
    env HOME="$NH" "$RST" "$RSUBJ" clear --force >/dev/null 2>&1
    env HOME="$NH" "$RST" "$RSUBJ" requested >/dev/null 2>&1
    : > "$HCALLS"; : > "$NH/herdr-calls.log"; : > "$NH/claude-calls.log"; : > "$RSUBJ/recap.log"; }
# The TUI stub of case 38 stays on PATH behind hc, so a launcher that consulted herdr would be seen.
alaunch(){ env HOME="$NH" PATH="$AB:$NH/.local/bin:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID=t9 \
    SECOND_BRAIN_PANE_WAIT_ATTEMPTS=2 "$@"; }
agets(){ grep -c '^get t9 --json$' "$HCALLS"; }

aset settles
AOUT=$(alaunch CLAUDE_PID=31337 "$LAUNCH" --auto "$RSUBJ" 2>&1)
chk "A1 a free terminal hosts the recap itself"   "$(grep -c '^send t9 .*recap_child.sh' "$HCALLS")" "1"
chk "A1 and no worker is started"                 "$(grep -c '^run ' "$HCALLS")" "0"
chk "A1 it waits for claude to let go"            "$(agets)" "3"
chk "A1 a shell at its prompt keeps its own PATH" "$(grep '^send ' "$HCALLS" | grep -c 'PATH=')" "0"
chk "A1 the markers travel inline"                "$(grep -c 'SECOND_BRAIN_RECAP_OF=' "$HCALLS")" "1"
chk "A1 --auto prints nothing"                    "${AOUT:-empty}" "empty"
chk "A1 and the reuse is logged"                  "$(grep -c 'reusing terminal t9 for recap-inv-recap-hook' "$RSUBJ/recap.log")" "1"
chk "A1 the launcher records nothing"             "$(prop "$RSUBJ/session.md" recap_status)" "requested"
chk "A1 and herdr is never consulted"             "$(grep -c '' "$NH/herdr-calls.log")" "0"

aset busy
alaunch CLAUDE_PID=31337 "$LAUNCH" --auto "$RSUBJ" >/dev/null 2>&1
chk "A2 a busy terminal gets a worker"            "$(grep -c '^run --json --bg --no-notify --outlive-parent --name recap-inv-recap-hook --cwd '"$NKB"' -- .*recap_child.sh' "$HCALLS")" "1"
chk "A2 nothing is sent to the busy terminal"     "$(grep -c '^send ' "$HCALLS")" "0"
chk "A2 it gives up waiting rather than queue"    "$(agets)" "3"
chk "A2 the markers travel inline"                "$(grep -c 'SECOND_BRAIN_RECAP_OF=' "$HCALLS")" "1"
# A worker gets the core's environment, and on 2026-11-11 the core's PATH on one host held no claude: a
# worker printed "claude: NOT FOUND". So the launcher's own PATH travels inline, ahead of the markers.
chk "A2 and so does the launcher's PATH"          "$(grep -c -- " -- PATH=$AB:$NH/.local/bin:.* SECOND_BRAIN_RECAP_OF=" "$HCALLS")" "1"
chk "A2 and the ending session's pid travels"     "$(grep -c 'SECOND_BRAIN_PARENT_PID=31337' "$HCALLS")" "1"
chk "A2 and the worker is logged"                 "$(grep -c 'started recap-inv-recap-hook in hc terminal t77' "$RSUBJ/recap.log")" "1"
chk "A2 the launcher records nothing"             "$(prop "$RSUBJ/session.md" recap_status)" "requested"

aset busy taken
alaunch CLAUDE_PID=31337 "$LAUNCH" --auto "$RSUBJ" >/dev/null 2>&1
chk "A3 a taken name is retried with a suffix"    "$(grep -c -- '--name recap-inv-recap-hook-2 ' "$HCALLS")" "1"
chk "A3 after one refusal"                        "$(grep -c '^run ' "$HCALLS")" "2"
chk "A3 and the retry is what is logged"          "$(grep -c 'started recap-inv-recap-hook in hc terminal t77' "$RSUBJ/recap.log")" "1"

aset busy fails
AFOUT=$(alaunch CLAUDE_PID=31337 "$LAUNCH" --auto "$RSUBJ" 2>&1); AFRC=$?
chk "A4 a worker that will not start exits 0"     "$AFRC" "0"
chk "A4 and stays silent"                         "${AFOUT:-empty}" "empty"
chk "A4 and says why in the log"                  "$(grep -c 'launcher failed: could not start a worker' "$RSUBJ/recap.log")" "1"
chk "A4 and leaves the subject requested"         "$(prop "$RSUBJ/session.md" recap_status)" "requested"

aset free
alaunch "$LAUNCH" --manual "$RSUBJ" >/dev/null 2>&1
chk "A5 a prompt runs the recap inline"           "$(grep -c '^claude cwd=' "$NH/claude-calls.log")" "1"
chk "A5 in the vault"                             "$(sed -n '1s/^claude cwd=\([^ ]*\) .*/\1/p' "$NH/claude-calls.log")" "$NKB"
chk "A5 and hc is read, never told"               "$(grep -cE '^(send|run|keys) ' "$HCALLS")" "0"

aset busy
AMOUT=$(alaunch "$LAUNCH" --manual "$RSUBJ" 2>&1)
chk "A6 a Claude session's Bash tool gets a worker" "$(grep -c '^run .*--name recap-inv-recap-hook ' "$HCALLS")" "1"
chk "A6 the worker is not silenced of notes only"  "$(grep -c '^run .*--no-notify' "$HCALLS")" "1"
chk "A6 nothing runs inline"                      "$(grep -c '^claude cwd=' "$NH/claude-calls.log")" "0"
chk "A6 it asks once and does not wait on a person" "$(agets)" "1"
chk "A6 and says where the recap went"            "$(printf '%s' "$AMOUT" | grep -c 'in hc terminal t77')" "1"

aset gone
alaunch CLAUDE_PID=31337 "$LAUNCH" --auto "$RSUBJ" >/dev/null 2>&1; AGRC=$?
chk "A7 a gone terminal exits 0 under --auto"     "$AGRC" "0"
chk "A7 it is not waited on"                      "$(agets)" "1"
chk "A7 and the recap becomes a worker"           "$(grep -c '^run ' "$HCALLS")" "1"

aset refuses
AROUT=$(alaunch CLAUDE_PID=31337 "$LAUNCH" --auto "$RSUBJ" 2>&1); ARRC=$?
chk "A8 a refused hand-off exits 0"               "$ARRC" "0"
chk "A8 and stays silent"                         "${AROUT:-empty}" "empty"
chk "A8 and says why in the log"                  "$(grep -c 'launcher failed: could not start the recap in terminal t9' "$RSUBJ/recap.log")" "1"
chk "A8 and leaves the subject requested"         "$(prop "$RSUBJ/session.md" recap_status)" "requested"

echo "== 50. in the Herdr app a done recap ends its own session through hc keys, and nothing else does (ADR-0011) =="
# The five steps of case 47 through hc. Two differences are hc's: the box is read as plain
# text, so any text in it leaves the session open, and /exit is typed with `hc keys`, never
# `hc send`, which wraps what it pastes in hc's <hc> tag and would hand the session a prompt.
hcset(){ wset "$1" "$2" "$3"; printf '%s' "${4:-idle}" > "$NH/hc-status"; rm -f "$NH/hc-status-gets"
    printf 'free' > "$NH/hc-state"; : > "$HCALLS"; }
# The grace ends on a whole second (`date +%s`), so a grace of G seconds polled every second gets
# G-1 or G polls by the clock's phase: 3 s always gives the two grace polls H1 and H5 count, where
# 2 s gave one whenever the grace began late in a second (measured 2026-11-04).
hcwatch(){ sleep "$1" & local kid=$!
    env HOME="$NH" PATH="$AB:$WB:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID=t9 \
        SECOND_BRAIN_RECAP_EXIT_POLL_S=1 SECOND_BRAIN_RECAP_EXIT_GRACE_MS=3000 SECOND_BRAIN_RECAP_EXIT_IDLE_MS=5000 \
        "$PLUGIN/hooks/scripts/recap_exit_watch.sh" "$WSUBJ" t9 "$kid" >/dev/null 2>&1
    kill "$kid" 2>/dev/null; wait "$kid" 2>/dev/null; }
hcexits(){ grep -c '^keys t9 / e x i t enter$' "$HCALLS"; }

hcset quiet empty done; hcwatch 30
chk "H1 a done, idle, unattended recap gets /exit as keys" "$(hcexits)" "1"
chk "H1 and after a grace nobody broke"          "$(grep -c '^get t9 --json$' "$HCALLS" | awk '{print ($1 >= 3) ? "polled" : "not polled"}')" "polled"
chk "H1 never with send"                         "$(grep -c '^send ' "$HCALLS")" "0"
chk "H1 never with kill"                         "$(grep -c '^kill ' "$HCALLS")" "0"
chk "H1 and the typing is logged first"          "$(grep -c 'typing /exit into t9 as key presses' "$WLOG")" "1"

hcset quiet text done; hcwatch 30
chk "H2 text in the box keeps the session open"  "$(hcexits)" "0"
chk "H2 and the log says hc cannot tell a ghost" "$(grep -c 'the prompt box holds text, typed or ghost text' "$WLOG")" "1"

hcset quiet ghost done; hcwatch 30
chk "H3 a ghost reads as text under hc, so it keeps the session open" "$(hcexits)" "0"

hcset quiet menu done; hcwatch 30
chk "H4 the command menu's indented pointer is not the box" "$(hcexits)" "1"

hcset quiet empty done stepped; hcwatch 30
chk "H5 a turn started in the grace keeps the session" "$(hcexits)" "0"
chk "H5 and the log says a person stepped in"    "$(grep -c 'a person stepped in' "$WLOG")" "1"

hcset quiet empty done working; hcwatch 30
chk "H6 a session still working after done is left alone" "$(hcexits)" "0"
chk "H6 and the log says it never went idle"     "$(grep -c 'did not go idle after done' "$WLOG")" "1"

hcset quiet empty requested; hcwatch 3
chk "H7 a recap that is not done gets nothing"   "$(hcexits)" "0"
chk "H7 and hc is never asked"                   "$(grep -c '' "$HCALLS")" "0"

# `done` lands mid-turn, and on a live recap `hc wait` came back at once with the turn still
# running (2026-11-04). The stub's wait never blocks, so this pins the retry: the state is read
# back from `hc get`, and the wait repeated a poll apart until the turn has ended.
hcset quiet empty done settling; hcwatch 30
chk "H9 a turn still running when done lands is waited out" "$(hcexits)" "1"
chk "H9 by waiting again when hc wait comes back early" "$(grep -c 'hc wait came back with the session still working' "$WLOG")" "1"
chk "H9 and not taken for a session that never went idle" "$(grep -c 'did not go idle after done' "$WLOG")" "0"

# The child starts the watcher under the app, by hc terminal id, and the watcher's /exit
# reaches the stub claude of case 47 through the stub hc's `keys`.
hcset quiet empty requested; printf '100' > "$NH/w-claude-wait"
env HOME="$NH" PATH="$AB:$WB:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID=t9 \
    SECOND_BRAIN_RECAP_OF="$WSUBJ" SECOND_BRAIN_RECAP_NAME=recap-w49 SECOND_BRAIN_PLUGIN_ROOT="$PLUGIN" \
    SECOND_BRAIN_RECAP_EXIT_POLL_S=1 SECOND_BRAIN_RECAP_EXIT_GRACE_MS=1000 SECOND_BRAIN_RECAP_EXIT_IDLE_MS=2000 \
    bash "$PLUGIN/hooks/scripts/recap_child.sh" "$WSUBJ" >/dev/null 2>&1
chk "H8 the child's watcher ended the session"   "$(grep -c '^exited-by-watcher$' "$NH/claude-calls.log")" "1"
chk "H8 through hc keys"                         "$(hcexits)" "1"
chk "H8 and the start line names the hc terminal" "$(grep -c 'start pane=t9 ' "$WLOG")" "1"
chk "H8 the app recap turns Claude Code's own suggestions off" "$(grep -c -- '-n recap-w49 /second-brain:session-recap .* suggestions=false$' "$NH/claude-calls.log")" "1"
chk "H8 and runs without debrief, whose ghost draft reads as text" "$(grep -c -F -- '--settings {"enabledPlugins":{"debrief@sundayhao-plugins":false}} -n recap-w49 /second-brain:session-recap' "$NH/claude-calls.log")" "1"
chk "H8 and herdr was never asked"               "$(grep -c '^agent ' "$WCALLS")" "0"

# A watcher that left the session open was reaped long before its session ends, and on this host
# the PID cursor wraps in minutes, so by then its PID may name another process (a thread's id
# signals its whole process). The child stops only a watcher still running. A kill function passed
# through the environment records what the child itself signals.
hcset quiet text requested; printf '60' > "$NH/w-claude-wait"; : > "$NH/kill-calls.log"
( kill() { printf '%s %s\n' "${0##*/}" "$*" >> "$HOME/kill-calls.log"; builtin kill "$@"; }; export -f kill
  env HOME="$NH" PATH="$AB:$WB:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID=t9 \
    SECOND_BRAIN_RECAP_OF="$WSUBJ" SECOND_BRAIN_RECAP_NAME=recap-w49 SECOND_BRAIN_PLUGIN_ROOT="$PLUGIN" \
    SECOND_BRAIN_RECAP_EXIT_POLL_S=1 SECOND_BRAIN_RECAP_EXIT_GRACE_MS=1000 SECOND_BRAIN_RECAP_EXIT_IDLE_MS=2000 \
    bash "$PLUGIN/hooks/scripts/recap_child.sh" "$WSUBJ" >/dev/null 2>&1 )
chk "H10 the watcher left first, the box holding text" "$(grep -c 'left open: the prompt box holds text' "$WLOG")" "1"
chk "H10 and the child signals no PID of a watcher already gone" "$(grep -c '^recap_child.sh ' "$NH/kill-calls.log")" "0"

echo "== 51. in the Herdr app a delegate is an hc child that reports back (ADR-0011) =="
DL="$PLUGIN/skills/common/launch_delegate.sh"
dset(){ printf '%s' "${1:-ok}" > "$NH/hc-run"; printf 'busy' > "$NH/hc-state"; : > "$HCALLS"; : > "$NH/herdr-calls.log"; }
dset
DOUT=$(cd "$NH" && env HOME="$NH" PATH="$AB:$NH/.local/bin:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID=t9 \
    CLAUDE_CODE_SESSION_ID=f1111111-1111-1111-1111-111111111111 "$DL" review "Check x.rs only" 2>&1); DRC=$?
chk "D1 the delegate is an hc worker"            "$(grep -c '^run --json --bg --outlive-parent --name review-' "$HCALLS")" "1"
chk "D1 in the launching session's folder"       "$(grep -c -- "--cwd $NH -- " "$HCALLS")" "1"
chk "D1 with hc's notes on"                      "$(grep -c -- '--no-notify' "$HCALLS")" "0"
chk "D1 the launcher marker travels inline"      "$(grep -c 'SECOND_BRAIN_DELEGATED_BY=f1111111-1111-1111-1111-111111111111 ' "$HCALLS")" "1"
# The worker gets the core's environment, whose PATH may hold no claude (case 49, A2). So the launching
# session's PATH travels inline, and claude is started by the path that PATH gives.
chk "D1 the launching session's PATH travels inline" "$(grep -c -- " -- PATH=$AB:$NH/.local/bin:.* SECOND_BRAIN_DELEGATED_BY=" "$HCALLS")" "1"
chk "D1 and claude is started by the path it gives" "$(grep -c " $NH/.local/bin/claude -n review-" "$HCALLS")" "1"
chk "D1 the prompt keeps its text"               "$(grep -c 'Check x.rs only' "$HCALLS")" "1"
chk "D1 and gains hc's reach line"               "$(grep -c 'Report with hc send t9 when done or stuck' "$HCALLS")" "1"
chk "D1 it exits 0"                              "$DRC" "0"
chk "D1 and says where the delegate went"        "$(printf '%s' "$DOUT" | grep -c '^Launched review-.* in hc terminal t77')" "1"
chk "D1 and how to reach it"                     "$(printf '%s' "$DOUT" | grep -c 'reachable as: hc send|wait|read review-')" "1"
chk "D1 herdr is never consulted"                "$(grep -c '' "$NH/herdr-calls.log")" "0"

dset taken
DOUT2=$(cd "$NH" && env HOME="$NH" PATH="$AB:$NH/.local/bin:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID=t9 \
    CLAUDE_CODE_SESSION_ID=f1111111-1111-1111-1111-111111111111 "$DL" review "Check x.rs only" 2>&1)
chk "D2 a taken name is retried with a suffix"   "$(grep -c -- '--name review-[a-z0-9-]*-2 ' "$HCALLS")" "1"
chk "D2 and the session is named the same"       "$(grep -c -- 'claude -n review-[a-z0-9-]*-2 ' "$HCALLS")" "1"
chk "D2 and the retry is what is reported"       "$(printf '%s' "$DOUT2" | grep -c '^Launched review-.*-2 in hc terminal t77')" "1"

# The path is passed as PATH gives it, unresolved: where claude is a link to a launcher that picks the
# version to run, the link is what must be started, not what it points at today.
dset
mkdir -p "$ROOT/dlink"; ln -sf "$NH/.local/bin/claude" "$ROOT/dlink/claude"
(cd "$NH" && env HOME="$NH" PATH="$ROOT/dlink:$AB:$NH/.local/bin:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID=t9 \
    CLAUDE_CODE_SESSION_ID=f1111111-1111-1111-1111-111111111111 "$DL" review "Check x.rs only" >/dev/null 2>&1)
chk "D2b a claude that is a link is started as the link" "$(grep -c " $ROOT/dlink/claude -n review-" "$HCALLS")|$(grep -c " $NH/.local/bin/claude -n review-" "$HCALLS")" "1|0"

dset fails
DOUT3=$(cd "$NH" && env HOME="$NH" PATH="$AB:$NH/.local/bin:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID=t9 \
    CLAUDE_CODE_SESSION_ID=f1111111-1111-1111-1111-111111111111 "$DL" review "Check x.rs only" 2>&1); DRC3=$?
chk "D3 a worker that will not start exits 1"    "$DRC3" "1"
chk "D3 and hands over the command instead"      "$(printf '%s' "$DOUT3" | grep -c 'Run this in a new terminal instead')" "1"

# The TUI path is untouched: a pane split, as before, and hc never consulted.
dset
printf 'free' > "$PINFO"
DOUT4=$(cd "$NH" && env HOME="$NH" PATH="$NH/.local/bin:$PATH" HERDR_ENV=1 HERDR_PANE_ID=w9:pOLD HC_TERMINAL_ID= \
    CLAUDE_CODE_SESSION_ID=f1111111-1111-1111-1111-111111111111 "$DL" review "Check x.rs only" 2>&1)
chk "D4 under the TUI the delegate still gets a pane" "$(grep -c 'pane split --pane w9:pOLD' "$NH/herdr-calls.log")" "1"
chk "D4 and hc is never consulted"               "$(grep -c '' "$HCALLS")" "0"
chk "D4 the TUI prompt carries no reach line"    "$(grep -c 'Report with hc send' "$NH/herdr-calls.log")" "0"
chk "D4 and the pane's shell keeps its own PATH"  "$(grep -c 'PATH=' "$NH/herdr-calls.log")" "0"

# No host at all: the command is handed over, as before.
DOUT5=$(cd "$NH" && env HOME="$NH" PATH="$AB:$NH/.local/bin:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID= \
    CLAUDE_CODE_SESSION_ID=f1111111-1111-1111-1111-111111111111 "$DL" review "Check x.rs only" 2>&1)
chk "D5 without a host the command is printed"   "$(printf '%s' "$DOUT5" | grep -c 'Not running under the Herdr TUI or the Herdr app')" "1"
chk "D5 and nothing is started"                  "$(grep -c '' "$HCALLS")" "0"
chk "D5 and the printed command names no PATH"   "$(printf '%s' "$DOUT5" | grep -c 'PATH=')" "0"

# ── Recap groups (ADR-0013): cases 52 to 58 ──────────────────────────────────────
# A vault and a home of their own, so nothing the earlier cases stamped is a member of a group here, and so
# the group command's state folder, $HOME/.local/state/second-brain/groups, and the registry it reads,
# $HOME/.claude/sessions, are scratch folders. /tmp/gwork maps to the domain team.
GKB="$ROOT/gkb"; GH="$ROOT/ghome"
mkdir -p "$GH/.claude/plugins/config/second-brain" "$GH/.claude/projects/proj" "$GKB/_sessions" \
    "$GKB/projects/cc" "$GKB/projects/team"
gcfg(){ jq -n --arg kb "$GKB" --arg m "$1" \
    '{knowledge_bank_path:$kb,auto_recap:$m,project_domains:{"/tmp/gwork":{domain:"team"}}}' \
    > "$GH/.claude/plugins/config/second-brain/config.json"; }
gcfg notify
# The hooks of cases 11 and 26, against this home and vault.
gstart(){ H="$GH" KB="$GKB" start "$@"; }
gend(){ H="$GH" endrun "$@"; }
gst(){ env HOME="$GH" "$ST" "$@" >/dev/null 2>&1; }
# A session of today in this vault, by id: its note, its folder, its transcript, its recap status.
gmd(){ printf '%s' "$GKB/_sessions/$TODAY/$1/session.md"; }
gf(){ printf '%s' "$GKB/_sessions/$TODAY/$1"; }
gt(){ printf '%s' "$GH/.claude/projects/proj/$1.jsonl"; }
gnow(){ prop "$(gmd "$1")" recap_status; }
# The group command, and what it reads: fake notes, a fake session registry, a fake /proc and a fake hc.
GCMD="$PLUGIN/hooks/scripts/recap_group.sh"
GBIN="$GH/.claude/plugins/config/second-brain/bin/recap-group"   # the stable path a caller knows
gstate(){ printf '%s' "$GH/.local/state/second-brain/groups/$1"; }
# A member note written directly, as a session of that date left it. A note with a status was stamped by its
# end hook, which also wrote the transcript pointer; one with no status has none. The transcript goes where
# Claude Code keeps it for the note's cwd, /tmp/gwork, unless $7 names another project folder.
gmk(){ # $1=date $2=id $3=name $4=status, empty for none $5=group, empty for none $6=assistant records, empty for no transcript $7=project folder
    local d="$GKB/_sessions/$1/$2" t="$GH/.claude/projects/${7:--tmp-gwork}/$2.jsonl"
    mkdir -p "$d/docs" "${t%/*}"
    [ -n "${6:-}" ] && turns "$t" "$6"
    { printf -- '---\nschema_version: "2.1"\nsession_id: "%s"\ndate: %s\nproject: "team"\ncwd: "/tmp/gwork"\nstarted_at: 2026-11-01T10:00:00\n' "$2" "$1"
      if [ -n "$4" ]; then printf 'transcript_source: "%s"\n' "$t"; else printf 'transcript_source:\n'; fi
      printf 'session_name: "%s"\nended_at:\nsummary:\n' "$3"
      [ -n "${5:-}" ] && printf 'recap_group: "%s"\n' "$5"
      [ -n "$4" ] && printf 'recap_status: "%s"\n' "$4"
      printf 'tags:\n---\n\n# Session: %s\n' "$2"; } > "$d/session.md"; }
gmds(){ printf '%s' "$GKB/_sessions/$1/$2/session.md"; }   # $1=date $2=id
# An entry of Claude Code's session registry, one file per live process, and that process as /proc shows it:
# its stat line, whose command name may hold blanks and parentheses, state in field 3, start in field 22.
greg(){ # $1=pid $2=session id $3=procStart
    mkdir -p "$GH/.claude/sessions"
    printf '{"pid":%s,"sessionId":"%s","cwd":"/tmp/gwork","startedAt":1794204430474,"procStart":"%s","version":"2.1.319","kind":"interactive","status":"idle"}\n' \
        "$1" "$2" "$3" > "$GH/.claude/sessions/$1.json"; }
gproc(){ # $1=pid $2=state $3=start
    mkdir -p "$GH/proc/$1"
    printf '%s (claude (x) y) %s 1 %s %s 34816 %s 4194304 100 0 0 0 10 5 0 0 20 0 12 0 %s 1000000 500 18446744073709551615\n' \
        "$1" "$2" "$1" "$1" "$1" "$3" > "$GH/proc/$1/stat"; }
# A UTC time some minutes ago, as the caller's `date -u +%FT%TZ` prints one: GNU date, then BSD.
gago(){ date -u -d "$1 minutes ago" +%FT%TZ 2>/dev/null || date -u -v-"$1"M +%FT%TZ; }
# Every group scenario starts from an empty vault, registry, /proc and state. The fake /proc always exists:
# without it the command would ask the real one about the pids these cases invent.
greset(){ rm -rf "$GKB/_sessions" "$GH/.claude/sessions" "$GH/.claude/projects" "$GH/proc" "$GH/.local/state" "$GH"/hc-* "$GH"/gclaude-*
    mkdir -p "$GKB/_sessions" "$GH/.claude/sessions" "$GH/.claude/projects/proj" "$GH/proc"; : > "$GH/hc-calls.log"; }
# One stub hc for the group cases, ahead of the suite's tripwire. `run` answers with an address and, when
# $HOME/hc-exec exists, runs the command it was given as the terminal would, in the background and with the
# terminal's id in its environment; $HOME/hc-run makes it fail or refuse a taken name once. `get` shows an
# idle session, `read` an empty prompt box, and `keys` with enter ends the stub claude, as in case 49.
GB="$GH/gbin"; mkdir -p "$GB"
cat > "$GB/hc" << 'GHC'
#!/bin/bash
{ printf hc; printf ' [%s]' "$@"; printf '\n'; } >> "$HOME/hc-calls.log"
case "$1" in
    run)
        case "$(cat "$HOME/hc-run" 2>/dev/null)" in
            taken) printf 'ok' > "$HOME/hc-run"
                   echo '{"error":{"kind":"name_taken","message":"a live terminal is already named"}}' >&2; exit 1 ;;
            fails) echo '{"error":{"kind":"spawn_failed","message":"no holder"}}' >&2; exit 1 ;;
        esac
        echo '{"address":"t77","state":"live"}'
        if [ -f "$HOME/hc-exec" ]; then
            ( HC_TERMINAL_ID=t77 bash -c "${@: -1}" >> "$HOME/hc-term.log" 2>&1 & )
        fi ;;
    get)  echo '{"pid":5555,"foreground":{"pid":45612,"name":"claude"},"state":"live","status":{"state":"idle"}}' ;;
    wait) echo '{"status":"idle","reason":"timeout"}' ;;
    read) printf 'the recap is done\n❯\302\240\n  Model: Opus\n' ;;
    keys) case "$*" in *enter*) : > "$HOME/gclaude-exit" ;; esac ;;
    rm)   [ ! -f "$HOME/hc-rm-fails" ] || { echo '{"error":{"kind":"still_live"}}' >&2; exit 1; } ;;
    kill) echo "hc stub: kill must never be called" >&2; exit 1 ;;
esac
exit 0
GHC
chmod +x "$GB/hc"
# A stub claude for a group recap: it does to the members what the skill does, marks each one the run claimed
# done, except those whose name $HOME/gclaude-skip matches, and then leaves. With $HOME/gclaude-stay it sits
# at its prompt until the exit watcher's /exit arrives, as a real session does.
cat > "$GB/claude" << 'GCL'
#!/bin/bash
printf 'claude cwd=%s recap_of=%s args=%s\n' "$PWD" "${SECOND_BRAIN_RECAP_OF:-}" "$*" >> "$HOME/gclaude-calls.log"
key="${*: -1}"; key="${key#/second-brain:session-recap --group }"
skip=$(cat "$HOME/gclaude-skip" 2>/dev/null)
while IFS="$(printf '\t')" read -r folder id name rest; do
    [ -n "$skip" ] && case "$name" in *"$skip"*) continue ;; esac
    "$SECOND_BRAIN_PLUGIN_ROOT/skills/common/recap_status.sh" "$folder" done --project team --summary "recapped with $key" >/dev/null 2>&1
done < "$HOME/.local/state/second-brain/groups/$key/members.tsv"
if [ -f "$HOME/gclaude-stay" ]; then
    i=0; while [ ! -f "$HOME/gclaude-exit" ] && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i+1)); done
    [ -f "$HOME/gclaude-exit" ] && echo "exited-by-watcher" >> "$HOME/gclaude-calls.log"
fi
exit 0
GCL
chmod +x "$GB/claude"
# The command as a caller outside any terminal runs it, a tick in a crontab: no terminal host's variables,
# the stubs first on PATH. $GPROC points it at the fake /proc; empty, it reads the real one, which the cases
# that start a run need, since the run is a real process. Sets GOUT, the line, and GRC, the exit code.
GPROC="$GH/proc"
grun(){ GOUT=$(env HOME="$GH" PATH="$GB:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID= \
        ${GPROC:+SECOND_BRAIN_PROC="$GPROC"} SECOND_BRAIN_GROUP_POLL_S=1 "${GENV[@]}" "$GCMD" "$@" 2>/dev/null); GRC=$?; }
GENV=()
# In a Herdr TUI pane the command starts nothing: the TUI cannot start a session from outside a pane. Cases
# that must sort members without starting a run pass this environment where nothing else holds the run back.
GTUI=(HERDR_ENV=1 HERDR_PANE_ID=w9:pG)
glines(){ printf '%s\n' "$GOUT" | grep -c ''; }
ghas(){ printf '%s' "$GOUT" | grep -c -- "$1"; }
# The same environment for any other program of a group case, and what the cases that start a run wait on:
# a line in a file, and no run left. The keys of those cases begin with G5, which no real caller's does, so
# the wait for "no run left" never waits on a run of the host's own.
gtick(){ env HOME="$GH" PATH="$GB:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID= SECOND_BRAIN_GROUP_POLL_S=1 "$@"; }
gwait(){ # $1=file $2=pattern: until the file holds a line that matches, up to about 30 s
    local i=0; until grep -q -- "$2" "$1" 2>/dev/null || [ "$i" -ge 300 ]; do sleep 0.1; i=$((i + 1)); done; }
gidle(){ # until no run of these cases is left, up to about 30 s
    local i=0; while pgrep -f "recap_group.sh G5" >/dev/null 2>&1 && [ "$i" -lt 300 ]; do sleep 0.1; i=$((i + 1)); done; }
glog(){ grep -c -- "$1" "$(gstate "${2:-G57}")/recap.log" 2>/dev/null; }   # $1=pattern $2=key
ghc(){ grep -c -- "$1" "$GH/hc-calls.log"; }                                # $1=pattern

echo "== 52. deferred is a sixth recap status, with four transitions of its own (ADR-0013) =="
# A session that belongs to a recap group is deferred at its exit: not `requested`, which starts a recap or
# lists the session in the notice, and not `exempt`, which means never. The status writer gains the state and
# four transitions: empty and exempt reach it, the claim leaves it, and done returns to it only when forced.
# Every other move to or from it is refused, as for any pair the table does not name.
DSUBJ="$ROOT/defsubj"; mkdir -p "$DSUBJ"
dnote(){ # $1=status, empty for none
    { printf -- '---\nsession_id: "d"\nsummary: "kept"\n'
      [ -n "$1" ] && printf 'recap_status: "%s"\n' "$1"
      printf 'tags:\n---\n\n# body\n'; } > "$DSUBJ/session.md"; : > "$DSUBJ/recap.log"; }
dst(){ env HOME="$H" "$ST" "$DSUBJ" "$@" >/dev/null 2>&1; }
dnow(){ prop "$DSUBJ/session.md" recap_status; }
dnote ""; dst deferred
chk "empty to deferred lands"                     "$(dnow)" "deferred"
dnote exempt; dst deferred
chk "exempt to deferred lands"                    "$(dnow)" "deferred"
dnote deferred; dst running
chk "deferred to running lands: the claim"        "$(dnow)" "running"
dnote "done"; dst deferred; DRC=$?
chk "done to deferred is refused"                 "$(dnow)|$DRC" "done|3"
dst deferred --force
chk "and lands when forced"                       "$(dnow)" "deferred"
chk "with the forced move in recap.log"           "$(grep -c 'forced done->deferred' "$DSUBJ/recap.log")" "1"
for to in requested "done" failed exempt; do
    dnote deferred; dst "$to"
    chk "deferred to $to is refused"              "$(dnow)" "deferred"
done
for from in requested running failed; do
    dnote "$from"; dst deferred
    chk "$from to deferred is refused"            "$(dnow)" "$from"
done
dnote deferred; dst clear --force
chk "a person can clear a deferred status"        "$(grep -c '^recap_status:' "$DSUBJ/session.md")" "0"
dnote ""; dst deferred --summary "nope"
chk "a description on deferred is a usage error"  "$(dnow)" ""
dnote running; dst failed --force
chk "--force serves requested, deferred and clear only" "$(dnow)" "running"
# The notice lists what stalled, and a deferred session has not: it waits for its group. One failed note
# beside it, so an empty notice cannot pass for the right one.
gnote(){ # $1=date $2=id $3=name $4=status $5=extra frontmatter line
    mkdir -p "$GKB/_sessions/$1/$2"
    { printf -- '---\nsession_id: "%s"\nsession_name: "%s"\n' "$2" "$3"
      [ -n "${5:-}" ] && printf '%s\n' "$5"
      [ -n "$4" ] && printf 'recap_status: "%s"\n' "$4"
      printf 'tags:\n---\n\n# body\n'; } > "$GKB/_sessions/$1/$2/session.md"; }
gnote "$TODAY" 52520000-0000-0000-0000-000000000001 waits-for-its-group deferred 'recap_group: "P52"'
gnote "$TODAY" 52520000-0000-0000-0000-000000000002 broke-on-its-own failed
N52=$(gstart 52520000-0000-0000-0000-000000000009 startup observer /tmp/gwork | jq -r '.systemMessage // ""')
chk "the notice lists the failed session"         "$(printf '%s' "$N52" | grep -c 'broke-on-its-own')" "1"
chk "and never a deferred one"                    "$(printf '%s' "$N52" | grep -c 'waits-for-its-group')" "0"
rm -rf "$GKB/_sessions/$TODAY"/5252*

echo "== 53. a launcher declares a recap group at launch, and the start hook records it (ADR-0013) =="
# SECOND_BRAIN_RECAP_GROUP=<key> on the launched command becomes `recap_group` on the note, at a genuine
# startup only, like the markers before it (ADR-0005). The key holds letters, digits, dot, underscore and
# hyphen, at most 64 characters, because it also names the recap session; any other value is ignored.
G1=53530000-0000-0000-0000-000000000001
gstart $G1 startup p53-ticket-one /tmp/gwork SECOND_BRAIN_RECAP_GROUP=Spec-A7 >/dev/null
chk "startup records the group key"               "$(prop "$(gmd $G1)" recap_group)" "Spec-A7"
G2=53530000-0000-0000-0000-000000000002
gstart $G2 startup plain /tmp/gwork >/dev/null
chk "an undeclared note gains no property"        "$(grep -c '^recap_group:' "$(gmd $G2)")" "0"
# The three other start sources, each on a session of its own: none is a launch.
for src in resume clear compact; do
    GI=53530000-0000-0000-0000-0000000000a${#src}
    gstart $GI "$src" stray-$src /tmp/gwork SECOND_BRAIN_RECAP_GROUP=Spec-A7 >/dev/null
    chk "a marker on a $src start is ignored"     "$(grep -c '^recap_group:' "$(gmd $GI)")" "0"
done
# The resume hook itself, which serves resume and compact, reads no marker at all.
printf '{"session_id":"%s","cwd":"/tmp/gwork","transcript_path":"%s","source":"resume"}' \
    "$G2" "$GH/.claude/projects/proj/$G2.jsonl" \
  | env HOME="$GH" HERDR_PANE_ID= TMUX_PANE= SECOND_BRAIN_RECAP_GROUP=Spec-A7 \
    "$PLUGIN/hooks/scripts/session_resume.sh" >/dev/null 2>&1
chk "and the resume hook records none"            "$(grep -c '^recap_group:' "$(gmd $G2)")" "0"
# A note that already exists at a declared startup, a restart under the same id, is stamped too.
gstart $G2 startup plain /tmp/gwork SECOND_BRAIN_RECAP_GROUP=Spec-A7 >/dev/null
chk "a pre-existing note is stamped at a declared startup" "$(prop "$(gmd $G2)" recap_group)" "Spec-A7"
gstart $G2 startup plain /tmp/gwork SECOND_BRAIN_RECAP_GROUP=P999 >/dev/null
chk "and a note keeps the group it has"           "$(prop "$(gmd $G2)" recap_group)" "Spec-A7"
# The rollout sends both markers, so an older plugin still exempts: the note carries both declarations.
G3=53530000-0000-0000-0000-000000000003
gstart $G3 startup both /tmp/gwork SECOND_BRAIN_RECAP_GROUP=spec.v2_a-1 SECOND_BRAIN_RECAP_EXEMPT=1 >/dev/null
chk "both declarations are recorded"              "$(prop "$(gmd $G3)" recap_group)|$(prop "$(gmd $G3)" recap_exempt)" "spec.v2_a-1|launcher"
# A value that is not a key is ignored, never repaired.
K64=$(printf 'k%.0s' $(seq 1 64)); n=0
for bad in "has space" "a/b" 'q"uote' "semi;colon" "${K64}k" "naïve"; do
    n=$((n + 1)); GI=53530000-0000-0000-0000-0000000000b$n
    gstart $GI startup bad-key /tmp/gwork SECOND_BRAIN_RECAP_GROUP="$bad" >/dev/null
    chk "a marker that is not a key is ignored ($n)" "$(grep -c '^recap_group:' "$(gmd $GI)")" "0"
done
G4=53530000-0000-0000-0000-000000000004
gstart $G4 startup longest /tmp/gwork SECOND_BRAIN_RECAP_GROUP="$K64" >/dev/null
chk "a key of 64 characters is taken"             "$(prop "$(gmd $G4)" recap_group)" "$K64"
# The property survives the end hook's rewrite, which is how every later exit reads it.
turns "$GH/.claude/projects/proj/$G1.jsonl" 2
gend x "$GH/.claude/projects/proj/$G1.jsonl" other
chk "recap_group survives the end rewrite"        "$(prop "$(gmd $G1)" recap_group)" "Spec-A7"

echo "== 53b. the start hook keeps one stable path to the group command (ADR-0013) =="
# The launcher that declares a group complete lives in another package, and this plugin's install folder is
# versioned. So a genuine startup keeps ~/.claude/plugins/config/second-brain/bin/recap-group pointing at
# the command of the plugin copy that ran the hook. A link, so a plugin copy that is removed takes the path
# with it, and a caller that tests the path finds nothing to call.
chk "a startup creates the stable path"           "$([ -L "$GBIN" ] && echo link || echo none)" "link"
chk "pointing at this plugin copy's command"      "$(readlink "$GBIN")" "$GCMD"
chk "which is there to run"                       "$([ -x "$GBIN" ] && echo yes || echo no)" "yes"
# A path that points at a plugin copy since removed is pointed at the current one; clear, resume and
# compact leave it, since a session started under an older copy still runs that copy's hooks.
rm -f "$GBIN"; ln -s "$ROOT/old-version/hooks/scripts/recap_group.sh" "$GBIN"
gstart $G2 clear plain /tmp/gwork >/dev/null
chk "a /clear leaves the stable path alone"       "$(readlink "$GBIN")" "$ROOT/old-version/hooks/scripts/recap_group.sh"
chk "a path whose plugin copy is gone reads as missing" "$([ -e "$GBIN" ] && echo there || echo missing)" "missing"
gstart 53530000-0000-0000-0000-000000000005 startup repoint /tmp/gwork >/dev/null
chk "the next startup points it at the current copy" "$(readlink "$GBIN")" "$GCMD"
touch -h -t 202601010000 "$GBIN" 2>/dev/null
B53=$(ls -l "$GBIN")
gstart 53530000-0000-0000-0000-000000000006 startup again /tmp/gwork >/dev/null
chk "a current path is not rewritten"             "$(ls -l "$GBIN")" "$B53"
chk "and no temporary link is left behind"        "$(ls "$(dirname "$GBIN")" | wc -l | tr -d ' ')" "1"
# The command finds its own plugin copy through the link.
chk "the command runs through the stable path"    "$(env HOME="$GH" "$GBIN" --help 2>&1 | grep -c 'recap-group <key> --complete-at')|$(env HOME="$GH" "$GBIN" --help >/dev/null 2>&1; echo $?)" "1|0"

echo "== 53c. a group's recap session registers as a recap of the group (ADR-0013) =="
# recap_of holds a subject's folder for a recap of one session, and `group:<key>` for a group recap. Each
# reader of it copes: the note takes the domain the run recorded for the group, the title names the key in
# lower case, and the session carries the recap tag and exempts itself at exit like any recap session.
GS53="$GH/.local/state/second-brain/groups/Spec-A7"; mkdir -p "$GS53"
printf 'key=Spec-A7\nproject=team\n' > "$GS53/manifest"
R53=53530000-0000-0000-0000-0000000000c1
RO53=$(gstart $R53 startup "" "$GKB" SECOND_BRAIN_RECAP_OF=group:Spec-A7)
chk "recap_of names the group"                    "$(prop "$(gmd $R53)" recap_of)" "group:Spec-A7"
chk "the note takes the group's domain"           "$(prop "$(gmd $R53)" project)" "team"
chk "and the one hook-written tag"                "$(rfl "$(gmd $R53)" tags)" "session-recap"
chk "an unnamed group recap is named for its key" "$(printf '%s' "$RO53" | jq -r '.hookSpecificOutput.sessionTitle // ""')" "recap-spec-a7"
chk "a group recap session is not a member"       "$(grep -c '^recap_group:' "$(gmd $R53)")" "0"
turns "$GH/.claude/projects/proj/$R53.jsonl" 9
gend x "$GH/.claude/projects/proj/$R53.jsonl" prompt_input_exit
chk "and exempts itself at exit"                  "$(prop "$(gmd $R53)" recap_status)" "exempt"
# A group with no recorded domain, or one outside the set, leaves the project visibly empty.
R53B=53530000-0000-0000-0000-0000000000c2
gstart $R53B startup "" "$GKB" SECOND_BRAIN_RECAP_OF=group:P-none >/dev/null
chk "a group with no recorded domain leaves project empty" "$(prop "$(gmd $R53B)" project)" ""
printf 'key=P-odd\nproject=not-a-domain\n' > "$GS53/manifest"
R53C=53530000-0000-0000-0000-0000000000c3
gstart $R53C startup "" "$GKB" SECOND_BRAIN_RECAP_OF=group:Spec-A7 >/dev/null
chk "a recorded domain outside the set is not taken" "$(prop "$(gmd $R53C)" project)" ""
rm -rf "$GH/.local/state"

echo "== 54. a member of a recap group is deferred at its exit, and nothing starts (ADR-0013) =="
# The exit table of a note that carries recap_group. The hook checks recap_of first, then recap_group, then
# recap_exempt, then size; it reads the group off the note and never off the environment.
gmember(){ # $1=id $2=name $3=assistant records, then extra environment pairs: a member of group P54
    local id="$1" name="$2" n="$3"; shift 3
    turns "$(gt "$id")" "$n"
    gstart "$id" startup "$name" /tmp/gwork SECOND_BRAIN_RECAP_GROUP=P54 "$@" >/dev/null; }
gexit(){ gend x "$(gt "$1")" "${2:-prompt_input_exit}" "${@:3}"; }
# An exit under auto_recap `on`, through a plugin copy whose launcher only records that it was called, as in
# case 35. A session of no group goes first: it must be launched, or "nothing starts" would prove nothing.
GSTUB="$ROOT/gstub"; mkdir -p "$GSTUB/hooks/scripts"
cp -R "$PLUGIN/skills" "$GSTUB/"; cp "$PLUGIN/hooks/scripts/session_end.sh" "$GSTUB/hooks/scripts/"
printf '#!/bin/bash\nprintf "called %%s\\n" "$*" >> "${SB_LAUNCH_LOG:-/dev/null}"\n' > "$GSTUB/hooks/scripts/recap_launcher.sh"
chmod +x "$GSTUB/hooks/scripts/recap_launcher.sh"
GLAUNCH="$ROOT/glaunch.log"
gexit_on(){ # $1=id; prints how many launches the exit caused
    local i=0 n
    gcfg on; : > "$GLAUNCH"
    printf '{"transcript_path":"%s","cwd":"/tmp/gwork","reason":"prompt_input_exit"}' "$(gt "$1")" \
      | env HOME="$GH" HERDR_PANE_ID= TMUX_PANE= SB_LAUNCH_LOG="$GLAUNCH" \
        "$GSTUB/hooks/scripts/session_end.sh" >/dev/null 2>&1
    # The launcher is detached, so it may land a moment after the hook returns.
    while [ ! -s "$GLAUNCH" ] && [ "$i" -lt 15 ]; do sleep 0.1; i=$((i+1)); done
    gcfg notify
    n=$(grep -c 'called' "$GLAUNCH" 2>/dev/null); printf '%s' "${n:-0}"; }
E0=54540000-0000-0000-0000-000000000000
turns "$(gt $E0)" 9; gstart $E0 startup no-group /tmp/gwork >/dev/null
chk "under on, a session of no group is launched"  "$(gexit_on $E0)|$(gnow $E0)" "1|requested"

E1=54540000-0000-0000-0000-000000000001; gmember $E1 real-work 9
chk "under on, a member's exit starts nothing"     "$(gexit_on $E1)" "0"
chk "five or more records are deferred"            "$(gnow $E1)" "deferred"
chk "with one reason line in recap.log"            "$(grep -c 'deferred: declared at launch to belong to recap group P54 (recap_group)' "$(gf $E1)/recap.log")" "1"
E2=54540000-0000-0000-0000-000000000002; gmember $E2 small 2; gexit $E2
chk "fewer than five records are exempt"           "$(gnow $E2)" "exempt"
chk "with no deferral in recap.log"                "$(grep -c 'deferred' "$(gf $E2)/recap.log")" "0"
turns "$(gt $E2)" 5; gexit $E2
chk "exempt for being small, then five: deferred"  "$(gnow $E2)" "deferred"
chk "and the reason is logged then"                "$(grep -c 'deferred: declared at launch' "$(gf $E2)/recap.log")" "1"
E3=54540000-0000-0000-0000-000000000003; gmember $E3 no-transcript 9; rm -f "$(gt $E3)"; gexit $E3
chk "no transcript is exempt"                      "$(gnow $E3)" "exempt"
E4=54540000-0000-0000-0000-000000000004; gmember $E4 unreadable 9; chmod 000 "$(gt $E4)"; gexit $E4
chk "an unreadable transcript stamps nothing"      "$(gnow $E4)" ""
chmod 644 "$(gt $E4)"
# A status that says something is under way or decided is left alone, whatever the session did since.
n=0
for was in deferred requested running failed; do
    n=$((n + 1)); EI=54540000-0000-0000-0000-00000000001$n; gmember $EI "was-$was" 9
    case "$was" in
        deferred)  gexit $EI ;;
        requested) gst "$(gf $EI)" requested ;;
        running)   gst "$(gf $EI)" requested; gst "$(gf $EI)" running ;;
        failed)    gst "$(gf $EI)" requested; gst "$(gf $EI)" failed ;;
    esac
    B54=$(grep -c '' "$(gf $EI)/recap.log"); turns "$(gt $EI)" 30
    chk "under on, $was starts nothing"            "$(gexit_on $EI)" "0"
    chk "$was is left untouched"                   "$(gnow $EI)|$(grep -c '' "$(gf $EI)/recap.log")" "$was|$B54"
done
# A member recapped with its group that then kept working goes back to wait for the group's next run.
E5=54540000-0000-0000-0000-000000000005; gmember $E5 regrowth 10; gexit $E5
gst "$(gf $E5)" running; gst "$(gf $E5)" "done" --summary "recapped with its group"
chk "done stamps the records it saw"               "$(prop "$(gmd $E5)" recap_assistant_records)" "10"
turns "$(gt $E5)" 14; gexit $E5
chk "four more records keep it done"               "$(gnow $E5)" "done"
turns "$(gt $E5)" 15
chk "under on, five more records start nothing"    "$(gexit_on $E5)" "0"
chk "and send it back to deferred"                 "$(gnow $E5)" "deferred"
chk "forced, with the growth in recap.log"         "$(grep -c 'grew by 5 assistant records since the recap (10 -> 15), deferred again for recap group P54' "$(gf $E5)/recap.log")|$(grep -c 'forced done->deferred' "$(gf $E5)/recap.log")" "1|1"
chk "the description is kept"                      "$(prop "$(gmd $E5)" summary)" "recapped with its group"
# clear and resume are not endings.
E6=54540000-0000-0000-0000-000000000006; gmember $E6 cleared 9
gexit $E6 clear;  chk "/clear stamps nothing"      "$(gnow $E6)" ""
gexit $E6 resume; chk "resume stamps nothing"      "$(gnow $E6)" ""
# The marker counted at a genuine startup only, so a session it did not reach is recapped as any other;
# and at exit the note is read, never the environment.
E7=54540000-0000-0000-0000-000000000007; turns "$(gt $E7)" 9
gstart $E7 resume resumed /tmp/gwork SECOND_BRAIN_RECAP_GROUP=P54 >/dev/null; gexit $E7
chk "a marker on a resume start defers nothing"    "$(gnow $E7)" "requested"
E8=54540000-0000-0000-0000-000000000008; turns "$(gt $E8)" 9
gstart $E8 startup undeclared /tmp/gwork >/dev/null; gexit $E8 prompt_input_exit SECOND_BRAIN_RECAP_GROUP=P54
chk "a stray marker at exit defers nothing"        "$(gnow $E8)" "requested"
# Both declarations, which is what the launcher sends while an older plugin may still be installed: the
# group is checked before the exemption, at the first exit and after a recap.
E9=54540000-0000-0000-0000-000000000009; gmember $E9 both 10 SECOND_BRAIN_RECAP_EXEMPT=1; gexit $E9
chk "a note with both declarations is deferred"    "$(gnow $E9)" "deferred"
chk "and logs the deferral, not an exemption"      "$(grep -c 'recap_exempt' "$(gf $E9)/recap.log")" "0"
gst "$(gf $E9)" running; gst "$(gf $E9)" "done"; turns "$(gt $E9)" 20; gexit $E9
chk "and goes back to deferred when it grows"      "$(gnow $E9)" "deferred"
# recap_of comes first: a recap session is exempt for good, whatever else its note says.
EA=54540000-0000-0000-0000-00000000000a; gmember $EA a-recap 9
awk '$0=="tags:"{print "recap_of: \"group:P54\""} {print}' "$(gmd $EA)" > "$(gmd $EA).t" && mv "$(gmd $EA).t" "$(gmd $EA)"
gexit $EA
chk "a recap session is exempt even with a group"  "$(gnow $EA)" "exempt"
# Global off still stamps nothing: the feature off means nothing is tracked.
gcfg off
EB=54540000-0000-0000-0000-00000000000b; gmember $EB feature-off 9; gexit $EB
chk "with auto_recap off a member is stamped nothing" "$(gnow $EB)" ""
gcfg notify
# The hook still reads its predicate's properties in one pass, the group among them.
chk "the group is read in the predicate's one batch" \
    "$(grep -c 'recap_status recap_of recap_assistant_records recap_exempt recap_group' "$PLUGIN/hooks/scripts/session_end.sh")" "1"

echo "== 55. the transcript parser prints a session's own Debrief blocks, for a group's digests =="
# A group recap reads one code-made digest per member in place of its transcript, and a member's Debrief
# blocks are the member's own account of each turn. Only blocks the session wrote count: one quoted in a
# tool result or typed by a person is somebody else's. `all` does not print them, so the digest's size
# stays what was measured for it; the group run adds them as a section of their own.
PT55="$PLUGIN/skills/session-recap/scripts/parse_transcript.sh"
PX55="$ROOT/parse-debrief-fixture.jsonl"
D55='▤ Debrief ────────────────────────────────────'; E55='─────────────────────────────────────────────────'
{
    jq -nc --arg t "$(printf 'Done.\n\n%s\n- **What changed:** the first thing\n- **Next steps:** none\n%s\n' "$D55" "$E55")" \
        '{type:"assistant",timestamp:"2026-10-01T00:00:00Z",message:{content:[{type:"text",text:$t}]}}'
    jq -nc --arg t "$(printf '%s\n- **What changed:** quoted from another session\n%s\n' "$D55" "$E55")" \
        '{type:"user",timestamp:"2026-10-01T00:00:01Z",message:{role:"user",content:[{type:"tool_result",tool_use_id:"x",content:$t}]}}'
    jq -nc --arg t "$(printf 'no block in this turn\n')" \
        '{type:"assistant",timestamp:"2026-10-01T00:00:02Z",message:{content:[{type:"text",text:$t}]}}'
    jq -nc --arg t "$(printf '%s\n- **What changed:** the second thing\n- **Proof:** it ran\n%s\ntrailing prose\n' "$D55" "$E55")" \
        '{type:"assistant",timestamp:"2026-10-01T00:00:03Z",message:{content:[{type:"text",text:$t}]}}'
} > "$PX55"
PD55=$("$PT55" "$PX55" debriefs 2>/dev/null); PD55RC=$?
chk "debriefs exits 0"                             "$PD55RC" "0"
chk "both of the session's own blocks are printed" "$(printf '%s\n' "$PD55" | grep -c '▤ Debrief')" "2"
chk "with their rungs"                             "$(printf '%s\n' "$PD55" | grep -c 'the first thing\|the second thing\|it ran')" "3"
chk "a block quoted in a tool result is not"       "$(printf '%s\n' "$PD55" | grep -c 'quoted from another session')" "0"
chk "nor the prose around a block"                 "$(printf '%s\n' "$PD55" | grep -c 'Done\.\|trailing prose\|no block in this turn')" "0"
printf '%s\n' '{"type":"assistant","timestamp":"2026-10-01T00:00:00Z","message":{"content":[{"type":"text","text":"nothing to report"}]}}' > "$ROOT/parse-nodebrief.jsonl"
chk "a session with no block prints the heading alone" \
    "$("$PT55" "$ROOT/parse-nodebrief.jsonl" debriefs 2>/dev/null | grep -c '')|$?" "1|0"
chk "and all leaves the blocks out"                "$("$PT55" "$PX55" all 2>/dev/null | grep -c '▤ Debrief')" "0"

echo "== 56. the group command sorts the members and answers by exit code, step by step (ADR-0013) =="
# recap-group <key> --complete-at <UTC time> [--label k=v]... answers 0 settled, 1 call again, 2 needs a person,
# with one line that says why. One call takes nine steps in order; each is pinned below, against fake notes, a
# fake registry and a fake /proc. Steps 1 to 8 never start a run: where members wait, a member that is still
# alive inside the hour keeps the answer at 1.
gcfg on
D56=2026-11-0
A56=56560000-0000-0000-0000-0000000000

# Step 1. auto_recap is not `on`: answer 0 and change nothing.
greset; gmk ${D56}1 ${A56}01 ended-unstamped "" P56 9
gcfg notify; grun P56 --complete-at "$(gago 120)"
chk "S1 with auto_recap not on the answer is 0"     "$GRC" "0"
chk "S1 and the one line says why"                  "$(glines)|$(ghas 'auto_recap is notify')" "1|1"
chk "S1 and nothing is changed"                     "$(prop "$(gmds ${D56}1 ${A56}01)" recap_status)|$([ -d "$(gstate P56)" ] && echo state || echo none)" "|none"
grun P56 --complete-at "$(gago 120)" --here
chk "S1 --here is no way round it"                  "$GRC|$(ghas 'auto_recap is notify')|$(prop "$(gmds ${D56}1 ${A56}01)" recap_status)" "0|1|"
gcfg on
grun "bad key" --complete-at "$(gago 120)"
chk "a value that is not a key needs a person"      "$GRC|$(ghas 'not a recap group key')" "2|1"
grun P56 --complete-at yesterday
chk "a time that is not one needs a person"         "$GRC|$(ghas 'is not a UTC time')" "2|1"
grun P56
chk "a call without --complete-at is a usage error" "$GRC" "2"
grun P-nobody --complete-at "$(gago 120)"
chk "a key no session carries is settled"           "$GRC|$(ghas 'no session belongs to recap group P-nobody')" "0|1"
chk "and leaves no state folder behind"             "$([ -d "$(gstate P-nobody)" ] && echo state || echo none)" "none"

# Step 2. The members are the notes whose recap_group equals the key, in every date folder: the notice's
# fourteen newest folders would miss a group that spans weeks. Fifteen later folders hold other sessions.
greset
for d in 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24; do gmk 2026-10-$d ${A56}$d other "done" "" 9; done
gmk 2026-09-01 ${A56}a1 weeks-old deferred P56 9
gmk 2026-10-12 ${A56}a2 mid-month failed P56 9
gmk 2026-10-13 ${A56}a3 longer-key deferred P560 9
gmk 2026-10-13 ${A56}a4 shorter-key deferred P5 9
gmk 2026-10-14 ${A56}a5 dotted-key deferred P.6 9
gmk 2026-10-15 ${A56}a6 saved-in-obsidian "" P56 9
sed -i.bak 's/^recap_group: "P56"$/recap_group: P56/; s/^transcript_source:$/recap_status: deferred/' "$(gmds 2026-10-15 ${A56}a6)"
gmk 2026-10-24 ${A56}a7 still-working "" P56 9; greg 4100 ${A56}a7 500; gproc 4100 S 500
gmk 2026-10-24 ${A56}a8 dotted-and-working "" P.6 9; greg 4108 ${A56}a8 510; gproc 4108 S 510
grun P56 --complete-at "$(gago 5)"
chk "S2 members are found in every date folder"     "$GRC|$(ghas '3 wait to be recapped')" "1|1"
chk "S2 a key is compared whole, never as a prefix" "$(ghas 'longer-key')$(ghas 'shorter-key')$(ghas 'dotted')" "000"
grun P.6 --complete-at "$(gago 5)"
chk "S2 and a dot in a key matches a dot only"      "$GRC|$(ghas '1 waits to be recapped')" "1|1"

# Step 3. Each member is sorted. One with no status is alive while the registry shows a live process for its
# id, the same pid and the same start; otherwise it ended without its end hook and is stamped on its behalf.
greset
gmk ${D56}1 ${A56}b0 live-anchor "" P56 9;          greg 4100 ${A56}b0 500; gproc 4100 S 500
gmk ${D56}1 ${A56}b1 no-entry "" P56 9
gmk ${D56}1 ${A56}b2 small-one "" P56 2
gmk ${D56}1 ${A56}b3 no-transcript "" P56 ""
gmk ${D56}2 ${A56}b4 pid-reused "" P56 9;           greg 4102 ${A56}b4 600; gproc 4102 S 999
gmk ${D56}2 ${A56}b5 zombie "" P56 9;               greg 4103 ${A56}b5 700; gproc 4103 Z 700
gmk ${D56}2 ${A56}b6 pid-gone "" P56 9;             greg 4104 ${A56}b6 800
gmk ${D56}2 ${A56}b7 moved-folder "" P56 9 -some-other-folder
gmk ${D56}3 ${A56}b8 resumed deferred P56 9;        greg 4105 ${A56}b8 900; gproc 4105 S 900
gmk ${D56}3 ${A56}b9 recapped-and-resumed "done" P56 9; greg 4106 ${A56}b9 950; gproc 4106 R 950
grun P56 --complete-at "$(gago 5)"
s56(){ prop "$(gmds ${D56}$1 ${A56}$2)" recap_status; }
chk "S3 the answer is 1 while members are alive"    "$GRC" "1"
chk "S3 a live process keeps a member unstamped"    "$(s56 1 b0)" ""
chk "S3 no registry entry: deferred on its behalf"  "$(s56 1 b1)" "deferred"
chk "S3 with a reason line in its recap.log"        "$(grep -c 'deferred: it ended without its end hook; stamped for recap group P56' "$GKB/_sessions/${D56}1/${A56}b1/recap.log")" "1"
chk "S3 and its transcript found from its cwd and id" "$(prop "$(gmds ${D56}1 ${A56}b1)" transcript_source)" "$GH/.claude/projects/-tmp-gwork/${A56}b1.jsonl"
chk "S3 under five records: exempt on its behalf"   "$(s56 1 b2)|$(grep -c 'exempt: it ended without its end hook, with fewer than five assistant records' "$GKB/_sessions/${D56}1/${A56}b2/recap.log")" "exempt|1"
chk "S3 no transcript: exempt on its behalf"        "$(s56 1 b3)" "exempt"
chk "S3 a pid since reused is not the session"      "$(s56 2 b4)" "deferred"
chk "S3 a zombie is not alive"                      "$(s56 2 b5)" "deferred"
chk "S3 a pid that is gone is not alive"            "$(s56 2 b6)" "deferred"
chk "S3 a transcript in another folder is found by id" "$(s56 2 b7)|$(prop "$(gmds ${D56}2 ${A56}b7)" transcript_source)" "deferred|$GH/.claude/projects/-some-other-folder/${A56}b7.jsonl"
chk "S3 a member with a status and a live process is alive too" "$(ghas '3 members are still alive')|$(ghas '5 wait to be recapped')" "1|1"
chk "S3 and the line names who is alive"            "$(ghas 'live-anchor')|$(ghas 'recapped-and-resumed')" "1|1"
# A registry that cannot be read means alive: the failure is a wait, never a recap of a live transcript.
r56(){ # $1=what is wrong with the registry; the member must stay unstamped and the answer 1
    grun P56 --complete-at "$(gago 5)"
    chk "S3 $1: the member counts as alive"         "$GRC|$(s56 1 c1)|$(ghas '1 member is still alive')" "1||1"; }
greset; gmk ${D56}1 ${A56}c1 unstamped "" P56 9; gmk ${D56}1 ${A56}c2 waits deferred P56 9
rm -rf "$GH/.claude/sessions";                                    r56 "no registry folder"
mkdir -p "$GH/.claude/sessions"; echo 'not json' > "$GH/.claude/sessions/9.json"; r56 "an entry that is not JSON"
echo '{"pid":9,"session":"renamed-key"}' > "$GH/.claude/sessions/9.json"; r56 "an entry in another format"
printf '{"pid":4107,"sessionId":"%s"}\n' ${A56}c1 > "$GH/.claude/sessions/9.json"; gproc 4107 S 1
r56 "an entry with no start to compare"
printf '{"sessionId":"%s","procStart":"1"}\n' ${A56}c1 > "$GH/.claude/sessions/9.json"; r56 "an entry with no pid"
rm -f "$GH/.claude/sessions/9.json"; GENV=("${GTUI[@]}"); grun P56 --complete-at "$(gago 5)"; GENV=()
chk "S3 a registry with no entries is read: nothing is alive" "$(s56 1 c1)" "deferred"

# Step 4. A run for this key is alive: answer 1, or 2 once it has been in progress over three hours.
g4(){ # $1=minutes since the run began $2=pid of the run $3=its start $4... rows of members.tsv
    mkdir -p "$(gstate P56)"; printf 'pid=%s\nstart=%s\nat=%s\nterminal=t77\n' "$2" "$3" "$(( $(date +%s) - $1 * 60 ))" > "$(gstate P56)/run"
    : > "$(gstate P56)/members.tsv"; local f; for f in "${@:4}"; do printf '%s\tid\tname\tteam\t9\tdigest\n' "$f" >> "$(gstate P56)/members.tsv"; done; }
greset; gmk ${D56}1 ${A56}d1 being-recapped running P56 9; gmk ${D56}1 ${A56}d2 recapped "done" P56 9
gproc 4201 S 111; g4 10 4201 111 "$GKB/_sessions/${D56}1/${A56}d1" "$GKB/_sessions/${D56}1/${A56}d2"
grun P56 --complete-at "$(gago 120)"
chk "S4 a live run answers 1"                       "$GRC|$(ghas 'in progress')|$(ghas 't77')" "1|1|1"
chk "S4 and says how far it is"                     "$(ghas '1 of 2 members done')" "1"
chk "S4 and touches no member"                      "$(s56 1 d1)" "running"
g4 181 4201 111 "$GKB/_sessions/${D56}1/${A56}d1" "$GKB/_sessions/${D56}1/${A56}d2"
grun P56 --complete-at "$(gago 240)"
chk "S4 over three hours it needs a person"         "$GRC|$(ghas 'over 3 hours')" "2|1"
chk "S4 and still touches no member"                "$(s56 1 d1)" "running"
g4 10 4201 111
grun P56 --complete-at "$(gago 120)"
chk "S4 a run that has claimed nothing yet is in progress" "$GRC|$(ghas 'in progress')" "1|1"
# A run whose every member is done is over, though its session may still be closing, or a person keeps it.
gst "$GKB/_sessions/${D56}1/${A56}d1" "done"; g4 200 4201 111 "$GKB/_sessions/${D56}1/${A56}d1" "$GKB/_sessions/${D56}1/${A56}d2"
grun P56 --complete-at "$(gago 240)"
chk "S4 a run with every member done is not in progress" "$GRC|$(ghas 'settled')" "0|1"

# Step 5. Members read running but no run is alive: the run died without its exit check. They are marked failed.
# A member that another recap session claimed, one a person recaps alone, is not the dead run's and is left.
greset
gmk ${D56}1 ${A56}e1 claimed-by-the-dead-run running P56 9; gmk ${D56}1 ${A56}e2 also-claimed running P56 9
gmk ${D56}1 ${A56}e3 a-hand-recap running P56 9
gmk ${D56}1 ${A56}e4 live-anchor "" P56 9; greg 4100 ${A56}e4 500; gproc 4100 S 500
g4 30 4202 222 "$GKB/_sessions/${D56}1/${A56}e1" "$GKB/_sessions/${D56}1/${A56}e2"
grun P56 --complete-at "$(gago 5)"
chk "S5 the dead run's members are marked failed"   "$(s56 1 e1)|$(s56 1 e2)" "failed|failed"
chk "S5 with the reason the notice shows"           "$(grep -c 'reason=its group recap (P56) ended before it was marked done' "$GKB/_sessions/${D56}1/${A56}e1/recap.log")" "1"
chk "S5 a member another recap holds is left"       "$(s56 1 e3)" "running"
chk "S5 the run's record is removed"                "$([ -f "$(gstate P56)/run" ] && echo there || echo gone)" "gone"
chk "S5 and the run counts as one that got nowhere" "$(cat "$(gstate P56)/failures" 2>/dev/null)" "1"
chk "S5 the failed members now wait"                "$GRC|$(ghas '2 wait to be recapped')" "1|1"
# A dead run that got some of its members done made progress: the count of runs that got nowhere starts over.
gst "$GKB/_sessions/${D56}1/${A56}e1" running; gst "$GKB/_sessions/${D56}1/${A56}e2" running; gst "$GKB/_sessions/${D56}1/${A56}e2" "done"
g4 30 4202 222 "$GKB/_sessions/${D56}1/${A56}e1" "$GKB/_sessions/${D56}1/${A56}e2"
grun P56 --complete-at "$(gago 5)"
chk "S5 progress resets the count"                  "$(s56 1 e1)|$(cat "$(gstate P56)/failures")" "failed|0"
# The run's own process is gone but its recap session still runs: in progress, and nothing is failed.
gst "$GKB/_sessions/${D56}1/${A56}e1" running
g4 30 4202 222 "$GKB/_sessions/${D56}1/${A56}e1"; gproc 4203 S 333; printf 'pid=4203\nstart=333\n' > "$(gstate P56)/child"
grun P56 --complete-at "$(gago 5)"
chk "S5 a session that outlived its run is in progress" "$GRC|$(ghas 'in progress')|$(s56 1 e1)" "1|1|running"

# Steps 6 and 7. Nothing waits: 0 when nothing is alive either, 1 while a member is.
greset; gmk ${D56}1 ${A56}f1 one "done" P56 9; gmk ${D56}1 ${A56}f2 two exempt P56 2; gmk ${D56}2 ${A56}f3 three "done" P56 9
grun P56 --complete-at "$(gago 5)"
chk "S6 nothing waits and nothing is alive: 0"      "$GRC|$(ghas 'settled: 3 members, 2 done and 1 exempt')" "0|1"
gmk ${D56}2 ${A56}f4 standing-session "done" P56 9; greg 4100 ${A56}f4 500; gproc 4100 S 500
grun P56 --complete-at "$(gago 600)"
chk "S7 nothing waits but a member is alive: 1"     "$GRC|$(ghas '1 of 4 members is still alive (standing-session)')" "1|1"
chk "S7 however long ago the group was completed"   "$(ghas 'nothing waits')" "1"
# A member that another recap session holds is neither waiting nor settled: call again.
greset; gmk ${D56}1 ${A56}f5 one "done" P56 9; gmk ${D56}1 ${A56}f6 a-hand-recap running P56 9
grun P56 --complete-at "$(gago 600)"
chk "S7 a member another recap holds is not settled" "$GRC|$(ghas '1 member is being recapped by another recap session')|$(s56 1 f6)" "1|1|running"

# Step 8. Members wait, a member is alive, and the hour after --complete-at has not passed: 1, and no run.
greset; gmk ${D56}1 ${A56}g1 waits deferred P56 9; gmk ${D56}1 ${A56}g2 standing-session "" P56 9; greg 4100 ${A56}g2 500; gproc 4100 S 500
T56=$(gago 59); grun P56 --complete-at "$T56" --label herdr.space=s1
chk "S8 inside the hour the answer is 1"            "$GRC|$(ghas '1 member is still alive (standing-session)')|$(ghas '1 waits to be recapped')" "1|1|1"
chk "S8 and nothing is claimed or started"          "$(s56 1 g1)|$(grep -c '' "$GH/hc-calls.log")|$([ -f "$(gstate P56)/run" ] && echo run || echo none)" "deferred|0|none"
chk "S8 a time with a fraction of a second is read" "$(grun P56 --complete-at "${T56%Z}.123Z"; echo "$GRC")" "1"
# The caller repeats the call every few minutes; the same answer is logged once.
grun P56 --complete-at "$T56"; grun P56 --complete-at "$T56"
chk "S8 a repeated answer is logged once"           "$(grep -c 'answer 1: waiting' "$(gstate P56)/recap.log")" "1"

echo "== 57. step 9: one run over the members that wait, started from outside any terminal (ADR-0013) =="
# The last step starts a run, or says why it cannot. The run is a real process from here on, detached from
# the call, so these cases read the real /proc and wait for the run with a deadline.
gcfg on
GPROC=""
GL=(--label herdr.space=s1 --label herdr.tab=tb0123456789abcdef)
D57=2026-11-0; A57=57570000-0000-0000-0000-0000000000
s57(){ prop "$(gmds ${D57}$1 ${A57}$2)" recap_status; }
# A startup in this home keeps the stable path, which an answer 2 names in its command to run by hand.
gstart 57570000-0000-0000-0000-0000000000ff startup keeps-the-stable-path /tmp/gwork >/dev/null
T57=$(gago 90)

# What stops a run needs a person, and changes nothing. Each PATH below holds the tools the call needs and
# leaves one program out; the suite's own PATH cannot, since it holds the tripwires and the host's programs.
GTOOLS="$ROOT/gtools"; mkdir -p "$GTOOLS" "$ROOT/gperl" "$ROOT/ghconly" "$ROOT/gclonly"
for t in bash sh jq find xargs grep awk sed cut date cat mkdir rmdir rm mv ln sleep tr dirname basename readlink stat head sort uniq env touch; do
    ln -sf "$(command -v "$t")" "$GTOOLS/$t"
done
ln -sf "$(command -v perl)" "$ROOT/gperl/perl"; cp "$GB/hc" "$ROOT/ghconly/hc"; cp "$GB/claude" "$ROOT/gclonly/claude"
gcant(){ # $1=who calls, for the check's name $2=text the line must hold, then the call's options; GENV stops the run
    grun G57 --complete-at "$T57" "${@:3}"
    chk "9 $1 needs a person"                       "$GRC|$(ghas "$2")" "2|1"
    chk "9 $1 claims and starts nothing"            "$(s57 1 01)|$(s57 1 02)|$(ghc '')|$([ -f "$(gstate G57)/run" ] && echo run || echo none)" "deferred|failed|0|none"; }
greset; gmk ${D57}1 ${A57}01 ticket-one deferred G57 9; gmk ${D57}1 ${A57}02 ticket-two failed G57 9
GENV=("${GTUI[@]}");                               gcant "a call in a Herdr TUI pane" 'no terminal host here can start a session' "${GL[@]}"
chk "9 and its line carries the command to run by hand" "$(ghas "$GBIN G57 --complete-at $T57 --here")" "1"
GENV=();                                           gcant "a call from outside a terminal that names no label" 'no terminal host here can start a session'
GENV=(PATH="$ROOT/gclonly:$ROOT/gperl:$GTOOLS");   gcant "a call where there is no hc" 'no terminal host here can start a session' "${GL[@]}"
GENV=(PATH="$ROOT/ghconly:$ROOT/gclonly:$GTOOLS"); gcant "a call with no perl to detach the run" 'perl is not on' "${GL[@]}"
GENV=(PATH="$ROOT/ghconly:$ROOT/gperl:$GTOOLS");   gcant "a call with no claude on its PATH" 'claude is not on' "${GL[@]}"
GENV=(); mkdir -p "$(gstate G57)"; echo 3 > "$(gstate G57)/failures"
gcant "a call after three runs that got nowhere" 'three runs in a row ended with no member of group G57 done' "${GL[@]}"
chk "9 and that line carries the command too"       "$(ghas "$GBIN G57 --complete-at $T57 --here")" "1"

# The start, and the run's six steps. Three members wait, one of them with a Debrief block in its transcript;
# one is done and one exempt; one belongs to another group. The stub hc runs the session as the core would.
greset; : > "$GH/hc-exec"
gmk ${D57}1 ${A57}01 ticket-one deferred G57 9; gmk ${D57}1 ${A57}02 ticket-two failed G57 9
gmk ${D57}2 ${A57}03 standing-session requested G57 12
gmk ${D57}2 ${A57}04 recapped-by-hand "done" G57 9; gmk ${D57}2 ${A57}05 tiny exempt G57 2
gmk ${D57}2 ${A57}06 another-group deferred G570 9
jq -nc --arg t "$(printf '▤ Debrief ────────────────────────────────────\n- **What changed:** ticket one landed\n─────────────────────────────────────────────────\n')" \
    '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' >> "$GH/.claude/projects/-tmp-gwork/${A57}01.jsonl"
grun G57 --complete-at "$T57" "${GL[@]}"
chk "9 with members waiting and none alive a run starts" "$GRC|$(ghas 'started: a recap of 3 members of group G57')" "1|1"
chk "9 and is on record before the call returns"    "$([ -f "$(gstate G57)/started" ] && echo yes || echo no)" "yes"
gwait "$GH/hc-calls.log" '^hc \[rm\]'; gidle
RUN57=$(grep '^hc \[run\]' "$GH/hc-calls.log")
chk "R4 one session starts on the core, with the caller's labels" \
    "$(ghc '^hc \[run\] \[--json\] \[--bg\] \[--no-parent\] \[--name\] \[recap-g57\] \[--cwd\] \['"$GKB"'\] \[--label\] \[herdr.space=s1\] \[--label\] \[herdr.tab=tb0123456789abcdef\] \[--\] \[PATH=')" "1"
chk "R4 the markers travel inline on its command"   "$(printf '%s\n' "$RUN57" | grep -c "SECOND_BRAIN_RECAP_OF=group:G57 SECOND_BRAIN_RECAP_NAME=recap-g57 SECOND_BRAIN_PLUGIN_ROOT=$PLUGIN bash $PLUGIN/hooks/scripts/recap_child.sh --group G57\]\$")" "1"
chk "R4 and so does the caller's PATH"              "$(printf '%s\n' "$RUN57" | grep -cF "[PATH=$GB:")" "1"
chk "R4 never through a terminal's environment"     "$(ghc '--env')" "0"
DG57="$(gstate G57)/digests/${A57}01.md"
chk "R1 one digest for each member"                 "$(ls "$(gstate G57)/digests" | wc -l | tr -d ' ')" "3"
chk "R1 with a header: name, id, folder, records"   "$(grep -c "^# Digest of ticket-one\$\|^- session id: ${A57}01\$\|^- session folder: $GKB/_sessions/${D57}1/${A57}01\$\|^- assistant records: 10\$" "$DG57")" "4"
chk "R1 what the parser extracts from the transcript" "$(grep -c '^=== Session Statistics ===$\|^=== Errors & Failures ===$' "$DG57")" "2"
chk "R1 and the member's own Debrief blocks"        "$(grep -c '^=== Debrief Blocks ===$\|ticket one landed' "$DG57")" "2"
chk "R3 the members it claimed are listed for the recap" "$(cut -f3 "$(gstate G57)/members.tsv" | sort | paste -sd, -)" "standing-session,ticket-one,ticket-two"
chk "R3 with what the recap needs to know of the group" "$(grep -c "^key=G57\$\|^complete_at=$T57\$\|^project=team\$\|^members=3\$\|^log_date=20" "$(gstate G57)/manifest")" "5"
chk "R5 the recap runs once, in the vault, as a recap of the group" \
    "$(grep -c "^claude cwd=$GKB recap_of=group:G57 args=.*-n recap-g57 /second-brain:session-recap --group G57\$" "$GH/gclaude-calls.log")" "1"
chk "R5 every member the run claimed is done"       "$(s57 1 01)|$(s57 1 02)|$(s57 2 03)" "done|done|done"
chk "R5 each on its own note"                       "$(prop "$(gmds ${D57}1 ${A57}01)" summary)" "recapped with G57"
chk "R5 the settled and another group's are untouched" "$(s57 2 04)|$(s57 2 05)|$(s57 2 06)" "done|exempt|deferred"
chk "R6 with every member done the terminal is removed" "$(ghc '^hc \[rm\] \[t77\]$')" "1"
chk "R6 the run leaves no record of itself"         "$(ls "$(gstate G57)" | grep -c '^run$\|^child$')|$(cat "$(gstate G57)/failures")" "0|0"
chk "R6 and the group's log tells what it did"      "$(glog 'run began for 3 members')|$(glog 'claimed 3 members; started recap-g57 in hc terminal t77')|$(glog 'run ended: 3 of 3 members done')|$(glog 'removed the finished terminal t77')" "1|1|1|1"
grun G57 --complete-at "$T57" "${GL[@]}"
chk "6 then the group is settled"                   "$GRC|$(ghas 'settled: 5 members, 4 done and 1 exempt')" "0|1"
chk "6 and no second session starts"                "$(ghc '^hc \[run\]')" "1"

# A member the recap leaves short of done is failed, the terminal stays, and a later call starts the recap
# again for what is left with nobody involved. The stub recap skips ticket-two.
greset; : > "$GH/hc-exec"; echo ticket-two > "$GH/gclaude-skip"
gmk ${D57}1 ${A57}01 ticket-one deferred G57 9; gmk ${D57}1 ${A57}02 ticket-two deferred G57 9
grun G57 --complete-at "$T57" "${GL[@]}"; gwait "$(gstate G57)/recap.log" 'run ended'; gidle
chk "R5 a member short of done is failed on the way out" "$(s57 1 01)|$(s57 1 02)" "done|failed"
chk "R5 with the reason the notice shows, once"     "$(grep -c 'reason=its group recap (G57) ended before it was marked done' "$GKB/_sessions/${D57}1/${A57}02/recap.log")" "1"
chk "R6 and the terminal is left for a person to read" "$(ghc '^hc \[rm\]')|$(glog 'run ended: 1 of 2 members done')" "0|1"
chk "R6 a run that got a member done made progress" "$(cat "$(gstate G57)/failures")" "0"
grun G57 --complete-at "$T57" "${GL[@]}"
chk "9 the next call starts the recap again"        "$GRC|$(ghas 'started: a recap of 1 member of group G57')" "1|1"
gwait "$(gstate G57)/recap.log" 'run ended: 0 of 1'; gidle
chk "9 a run that gets no member done is counted"   "$(s57 1 02)|$(cat "$(gstate G57)/failures")" "failed|1"
rm -f "$GH/gclaude-skip"
grun G57 --complete-at "$T57" "${GL[@]}"; gwait "$GH/hc-calls.log" '^hc \[rm\]'; gidle
chk "9 and one that does starts the count over"     "$(s57 1 02)|$(cat "$(gstate G57)/failures")" "done|0"

# The core will not start the session, or its name is taken by the session of an earlier run.
greset; echo fails > "$GH/hc-run"; gmk ${D57}1 ${A57}01 ticket-one deferred G57 9
grun G57 --complete-at "$T57" "${GL[@]}"; gwait "$(gstate G57)/recap.log" 'run ended'; gidle
chk "R4 a session that will not start fails its members" "$(s57 1 01)|$(glog 'could not start a session; hc said: .*spawn_failed')|$(cat "$(gstate G57)/failures")" "failed|1|1"
greset; : > "$GH/hc-exec"; echo taken > "$GH/hc-run"; gmk ${D57}1 ${A57}01 ticket-one deferred G57 9
grun G57 --complete-at "$T57" "${GL[@]}"; gwait "$GH/hc-calls.log" '^hc \[rm\]'; gidle
chk "R4 a taken name is retried once with a suffix" "$(ghc '^hc \[run\] .*\[--name\] \[recap-g57-2\]')|$(ghc '^hc \[run\]')|$(s57 1 01)" "1|2|done"
# A session the core starts that never runs the child: the run gives up on it and leaves its terminal.
greset; gmk ${D57}1 ${A57}01 ticket-one deferred G57 9
GENV=(SECOND_BRAIN_GROUP_START_S=2); grun G57 --complete-at "$T57" "${GL[@]}"; GENV=()
gwait "$(gstate G57)/recap.log" 'run ended'; gidle
chk "R5 a session that never starts the recap is given up on" "$(s57 1 01)|$(glog 'did not start the recap within 2 s')|$(ghc '^hc \[rm\]')" "failed|1|0"

# A member whose transcript is missing or cannot be read is claimed, then failed with its reason, and left
# out. From then on it does not wait: no further run starts for it, the run that found it counts for nothing
# against the three, and the group settles without it, with a line that says how many such members there are.
greset; : > "$GH/hc-exec"
gmk ${D57}1 ${A57}01 ticket-one deferred G57 9; gmk ${D57}1 ${A57}02 lost-its-transcript deferred G57 9
L57="$GKB/_sessions/${D57}1/${A57}02"; rm -f "$GH/.claude/projects/-tmp-gwork/${A57}02.jsonl"
grun G57 --complete-at "$T57" "${GL[@]}"; gwait "$GH/hc-calls.log" '^hc \[rm\]'; gidle
chk "U1 a member that cannot be read is claimed, then failed with its reason" \
    "$(s57 1 02)|$(grep -c 'set deferred->running\|set running->failed' "$L57/recap.log")|$(grep -c 'reason=its transcript is missing or cannot be read, so the recap of group G57 left it out' "$L57/recap.log")" "failed|2|1"
chk "U1 and left out, while the rest of the group is recapped" "$(cut -f3 "$(gstate G57)/members.tsv")|$(s57 1 01)" "ticket-one|done"
# The run records it for the group's daily log entry: its folder, its id, its name and its reason, in a file
# that the manifest names. The recap session reads that file; the notice reaches fourteen date folders only.
LO57="$(gstate G57)/left-out.tsv"
chk "U1 the run records it: folder, id, name and reason" "$(cat "$LO57")" \
    "$(printf '%s\t%s\t%s\t%s' "$L57" "${A57}02" lost-its-transcript "its transcript is missing: $GH/.claude/projects/-tmp-gwork/${A57}02.jsonl")"
chk "U1 in a file the manifest names"               "$(grep -c "^left_out_file=$LO57\$" "$(gstate G57)/manifest")" "1"
: > "$GH/hc-calls.log"; grun G57 --complete-at "$T57" "${GL[@]}"
chk "U2 from then on it does not wait: the group settles without it" \
    "$GRC|$(ghas 'settled: 2 members, 1 done and 0 exempt; 1 failed because its transcript is missing or cannot be read (lost-its-transcript)$')" "0|1"
chk "U2 and no further run starts for it"           "$(ghc '^hc \[run\]')|$([ -f "$(gstate G57)/run" ] && echo run || echo none)" "0|none"
# While another member is alive the group is not settled, and the unreadable one still does not wait.
GPROC="$GH/proc"; gmk ${D57}2 ${A57}03 standing-session "done" G57 9; greg 4100 ${A57}03 500; gproc 4100 S 500
grun G57 --complete-at "$T57" "${GL[@]}"; GPROC=""
chk "U2 with a member alive the answer stays 1"     "$GRC|$(ghas '1 of 3 members is still alive (standing-session); nothing waits to be recapped')" "1|1"
rm -rf "$GKB/_sessions/${D57}2" "$GH/.claude/sessions/4100.json"
# The start-of-session notice lists it with its reason, and with a retry command for that one member. The
# command is run as printed, and what it prints in turn, the recap of one subject, is run with a claude
# that marks its subject done: the claim takes the member, and the group then counts it done.
N57=$(gstart 57570000-0000-0000-0000-0000000000fe startup observer /tmp/gwork | jq -r '.systemMessage // ""')
chk "U3 the notice lists it with its reason"        "$(printf '%s\n' "$N57" | grep -c 'lost-its-transcript — failed: its transcript is missing or cannot be read, so the recap of group G57 left it out (see recap.log)')" "1"
R57=$(printf '%s\n' "$N57" | sed -n 's/.*lost-its-transcript.* — retry: //p' | head -1)
chk "U3 and a retry command for that one member"    "$R57" "$PLUGIN/hooks/scripts/recap_launcher.sh --manual $L57"
RO57=$(gtick bash -c "$R57" 2>&1); RRC57=$?
chk "U3 the command runs as printed"                "$RRC57|$(printf '%s\n' "$RO57" | grep -c "recap_child.sh $L57\$")" "0|1"
mkdir -p "$ROOT/gone"
printf '#!/bin/bash\nsubj="${*: -1}"; subj="${subj#/second-brain:session-recap }"\n"$SECOND_BRAIN_PLUGIN_ROOT/skills/common/recap_status.sh" "$subj" done >/dev/null 2>&1\n' > "$ROOT/gone/claude"
chmod +x "$ROOT/gone/claude"
env HOME="$GH" PATH="$ROOT/gone:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID= \
    bash -c "$(printf '%s\n' "$RO57" | sed -n 's/^  cd /cd /p')" >/dev/null 2>&1
chk "U3 the recap it starts claims that member, and can get it done" "$(s57 1 02)|$(grep -c 'set failed->running' "$L57/recap.log")" "done|1"
grun G57 --complete-at "$T57" "${GL[@]}"
chk "U3 after which the group counts it done"       "$GRC|$(ghas 'settled: 2 members, 2 done and 0 exempt$')" "0|1"
# A member whose transcript can be read again at a later call waits again, and the next run takes it. A
# transcript that is there and cannot be read counts as one that is gone.
greset; : > "$GH/hc-exec"
gmk ${D57}1 ${A57}02 lost-its-transcript failed G57 9; chmod 000 "$GH/.claude/projects/-tmp-gwork/${A57}02.jsonl"
grun G57 --complete-at "$T57" "${GL[@]}"
chk "U4 a failed member whose transcript cannot be read does not wait" \
    "$GRC|$(ghas 'settled: 1 member, 0 done and 0 exempt; 1 failed because its transcript is missing or cannot be read')|$(ghc '^hc \[run\]')" "0|1|0"
chmod 644 "$GH/.claude/projects/-tmp-gwork/${A57}02.jsonl"
grun G57 --complete-at "$T57" "${GL[@]}"
chk "U4 once it can be read again the member waits again" "$GRC|$(ghas 'started: a recap of 1 member of group G57')" "1|1"
gwait "$GH/hc-calls.log" '^hc \[rm\]'; gidle
chk "U4 and the run gets it done"                   "$(s57 1 02)" "done"
# A member that failed for another reason, because its run died or its recap gave up, still waits. In a TUI
# pane the call starts nothing, and says how many wait.
greset; gmk ${D57}1 ${A57}01 failed-with-its-run failed G57 9
GENV=("${GTUI[@]}"); grun G57 --complete-at "$T57"; GENV=()
chk "U5 a failed member whose transcript can be read still waits" "$GRC|$(ghas '1 member waits to be recapped')" "2|1"
# A run that finds nothing but unreadable members starts no session and counts for nothing against the
# three: two runs that got nowhere before it stay two.
greset; gmk ${D57}1 ${A57}02 lost-its-transcript deferred G57 9; rm -f "$GH/.claude/projects/-tmp-gwork/${A57}02.jsonl"
mkdir -p "$(gstate G57)"; echo 2 > "$(gstate G57)/failures"
grun G57 --complete-at "$T57" "${GL[@]}"; gwait "$(gstate G57)/recap.log" 'run ended'; gidle
chk "U6 a run with only unreadable members starts no session" "$(ghc '^hc \[run\]')|$(glog 'claimed no member, so no session starts')|$(s57 1 02)" "0|1|failed"
chk "U6 and does not count toward the three"        "$(cat "$(gstate G57)/failures")" "2"
chk "U6 and records what it left out all the same"  "$(cut -f3 "$LO57")" "lost-its-transcript"
grun G57 --complete-at "$T57" "${GL[@]}"
chk "U6 and the next call settles the group"        "$GRC|$(ghas 'settled: 1 member, 0 done and 0 exempt; 1 failed because its transcript is missing or cannot be read')" "0|1"
# The file holds the group's whole list as it stands at the run, not only the members this run tried: one
# that an earlier run left out is on it still. Each row says which it is: a transcript that is missing, one
# that is there and cannot be read, or a note that names none. A member with no name goes by its id.
greset; : > "$GH/hc-exec"
gmk ${D57}1 ${A57}01 ticket-one deferred G57 9
gmk ${D57}1 ${A57}02 left-out-before failed G57 9; rm -f "$GH/.claude/projects/-tmp-gwork/${A57}02.jsonl"
gmk ${D57}1 ${A57}03 "" failed G57 9; chmod 000 "$GH/.claude/projects/-tmp-gwork/${A57}03.jsonl"
gmk ${D57}2 ${A57}04 names-no-transcript failed G57 ""
sed -i.bak 's/^transcript_source: .*/transcript_source:/' "$(gmds ${D57}2 ${A57}04)"
gmk ${D57}2 ${A57}05 failed-with-its-run failed G57 9
grun G57 --complete-at "$T57" "${GL[@]}"; gwait "$GH/hc-calls.log" '^hc \[rm\]'; gidle
chk "U8 the run tries the two members that can be read" "$(cut -f3 "$(gstate G57)/members.tsv" | sort | paste -sd, -)|$(s57 1 01)|$(s57 2 05)" "failed-with-its-run,ticket-one|done|done"
chk "U8 the file holds every member the group has left out" "$(cut -f3 "$LO57" | sort | paste -sd, -)" "${A57:0:8},left-out-before,names-no-transcript"
chk "U8 each with the reason that is its own" \
    "$(cut -f4 "$LO57" | sed "s|$GH/.claude/projects/-tmp-gwork/||" | sort | paste -sd'|' -)" \
    "its note names no transcript, and none was found for its session id|its transcript cannot be read: ${A57}03.jsonl|its transcript is missing: ${A57}02.jsonl"
chk "U8 and with its folder and its id"             "$(grep -c "^$(printf '%s\t%s\tleft-out-before\t' "$GKB/_sessions/${D57}1/${A57}02" "${A57}02")" "$LO57")" "1"
# A later run rewrites the file. A member that can be read again and is recapped drops out of it, which is
# how the line in the group's daily log entry loses it too.
greset; : > "$GH/hc-exec"
gmk ${D57}1 ${A57}01 ticket-one deferred G57 9; gmk ${D57}1 ${A57}02 comes-back deferred G57 9
chmod 000 "$GH/.claude/projects/-tmp-gwork/${A57}02.jsonl"
grun G57 --complete-at "$T57" "${GL[@]}"; gwait "$GH/hc-calls.log" '^hc \[rm\]'; gidle
chk "U9 a member that cannot be read is on the list" "$(cut -f3,4 "$LO57")" \
    "$(printf 'comes-back\tits transcript cannot be read: %s' "$GH/.claude/projects/-tmp-gwork/${A57}02.jsonl")"
chmod 644 "$GH/.claude/projects/-tmp-gwork/${A57}02.jsonl"; : > "$GH/hc-calls.log"
grun G57 --complete-at "$T57" "${GL[@]}"; gwait "$GH/hc-calls.log" '^hc \[rm\]'; gidle
chk "U9 recapped by a later run, it drops out of it" "$(s57 1 02)|$([ -f "$LO57" ] && grep -c '' "$LO57")" "done|0"
# A transcript that is there and that the parser cannot digest is another matter: a fault here, not a
# transcript that is gone. The member is failed with that reason, it waits, and its run counts, so that a
# broken parser ends at a person and never at a group settled with every member failed. A copy of the plugin
# with a parser that fails stands for the fault.
GBROKEN="$ROOT/gbroken"; mkdir -p "$GBROKEN/hooks"
cp -R "$PLUGIN/skills" "$GBROKEN/"; cp -R "$PLUGIN/hooks/scripts" "$GBROKEN/hooks/"
printf '#!/bin/bash\nexit 1\n' > "$GBROKEN/skills/session-recap/scripts/parse_transcript.sh"
greset; gmk ${D57}1 ${A57}01 ticket-one deferred G57 9
gtick "$GBROKEN/hooks/scripts/recap_group.sh" G57 --complete-at "$T57" "${GL[@]}" >/dev/null 2>&1
gwait "$(gstate G57)/recap.log" 'run ended'; gidle
chk "U7 a member that cannot be digested is failed with that reason" \
    "$(s57 1 01)|$(grep -c 'reason=its transcript could not be digested, so the recap of group G57 left it out' "$GKB/_sessions/${D57}1/${A57}01/recap.log")" "failed|1"
GENV=("${GTUI[@]}"); grun G57 --complete-at "$T57"; GENV=()
chk "U7 its run counts, and the member waits"       "$(cat "$(gstate G57)/failures")|$GRC|$(ghas '1 member waits to be recapped')" "1|2|1"
# A member another recap claimed between the call and the run's claim is left out, and left alone. The run
# is called as the command calls it, on a list that names a member already running.
greset; : > "$GH/hc-exec"
gmk ${D57}1 ${A57}01 ticket-one deferred G57 9; gmk ${D57}1 ${A57}02 claimed-meanwhile running G57 9
mkdir -p "$(gstate G57)"; printf '%s\n' "$GKB/_sessions/${D57}1/${A57}01" "$GKB/_sessions/${D57}1/${A57}02" > "$(gstate G57)/waiting"
gtick "$GCMD" G57 --complete-at "$T57" --run "${GL[@]}" >/dev/null 2>&1
chk "R3 a refused claim leaves that member out"     "$(cut -f3 "$(gstate G57)/members.tsv")|$(s57 1 02)|$(glog 'left out claimed-meanwhile: its claim was refused')|$(s57 1 01)" "ticket-one|running|1|done"

# The first caller is a tick in a crontab. It closes stdin, gives the call two files for its output, runs
# it in its own state folder, and kills the call's whole process group the moment the call returns. The
# run has to outlive that, and to leave that folder.
greset; : > "$GH/hc-exec"
gmk ${D57}1 ${A57}01 ticket-one deferred G57 9; gmk ${D57}1 ${A57}02 ticket-two deferred G57 9
TICK57="$ROOT/tick-state"; mkdir -p "$TICK57"
( cd "$TICK57" && exec perl -e 'setpgrp(0, 0); exec @ARGV' /bin/sh -c 'exec "$@" <&-' sh \
    env HOME="$GH" PATH="$GB:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID= SECOND_BRAIN_GROUP_POLL_S=1 \
    "$GCMD" G57 --complete-at "$T57" "${GL[@]}" > "$ROOT/tick.out" 2> "$ROOT/tick.err" ) &
PG57=$!; wait "$PG57"; RC57=$?
RP57=$(sed -n 's/^pid=//p' "$(gstate G57)/run" 2>/dev/null)
if [ -e "/proc/$RP57/cwd" ]; then
    chk "T the run has left the caller's working folder" "$(readlink "/proc/$RP57/cwd")" "$(cd "$(gstate G57)" && pwd -P)"
else
    ok "T no /proc to read the run's working folder from, skipped"
fi
kill -9 -- "-$PG57" 2>/dev/null
chk "T the call answers on the first line of stdout, with stdin closed" \
    "$RC57|$(head -1 "$ROOT/tick.out" | grep -c '^started: a recap of 2 members of group G57$')|$(grep -c '' "$ROOT/tick.out")|$(grep -c '' "$ROOT/tick.err")" "1|1|1|0"
gwait "$GH/hc-calls.log" '^hc \[rm\]'; gidle
chk "T the run outlives the kill of the call's process group" "$(s57 1 01)|$(s57 1 02)|$(ghc '^hc \[rm\] \[t77\]$')" "done|done|1"
chk "T and nothing is written in the caller's working folder" "$(ls -A "$TICK57" | wc -l | tr -d ' ')" "0"

# A run that never puts itself on record: the call does not wait for it past a few seconds, says so, and
# counts it, so that a run that can never start is not retried without a word for ever. A perl that does
# nothing stands for whatever keeps the detached process from starting.
greset; gmk ${D57}1 ${A57}01 ticket-one deferred G57 9
mkdir -p "$ROOT/gdeadperl"; printf '#!/bin/bash\nexit 0\n' > "$ROOT/gdeadperl/perl"; chmod +x "$ROOT/gdeadperl/perl"
GENV=(PATH="$ROOT/gdeadperl:$GB:$PATH"); grun G57 --complete-at "$T57" "${GL[@]}"; GENV=()
chk "9 a run that does not report in is said and counted" "$GRC|$(ghas 'which has not reported in yet')|$(cat "$(gstate G57)/failures")|$(s57 1 01)" "1|1|1|deferred"

# Two callers, a tick and a person, or three: one run.
greset; gmk ${D57}1 ${A57}01 ticket-one deferred G57 9; gmk ${D57}1 ${A57}02 ticket-two deferred G57 9
for n in 1 2 3; do
    ( gtick env SECOND_BRAIN_GROUP_START_S=2 "$GCMD" G57 --complete-at "$T57" "${GL[@]}" > "$ROOT/lock.$n.out" 2>/dev/null
      echo $? > "$ROOT/lock.$n.rc" ) &
done; wait
gwait "$(gstate G57)/recap.log" 'run ended'; gidle
chk "L three calls at once start one run"           "$(ghc '^hc \[run\]')|$(cat "$ROOT"/lock.*.out | grep -c '^started: ')|$(cat "$ROOT"/lock.*.rc | paste -sd, -)" "1|1|1,1,1"

# --here: a person runs the recap in a terminal of their own, where the command could start none, or after
# three runs that got nowhere. No terminal is started and none removed; the recap is the same.
greset; gmk ${D57}1 ${A57}01 ticket-one deferred G57 9; gmk ${D57}1 ${A57}02 ticket-two failed G57 9
mkdir -p "$(gstate G57)"; echo 3 > "$(gstate G57)/failures"
H57=$(gtick "$GCMD" G57 --complete-at "$T57" --here 2>&1); HRC57=$?
chk "H --here runs the recap in the caller's terminal" "$HRC57|$(s57 1 01)|$(s57 1 02)" "0|done|done"
chk "H whatever the count of runs that got nowhere" "$(cat "$(gstate G57)/failures")" "0"
chk "H it tells the person what it is doing"        "$(printf '%s\n' "$H57" | grep -c 'digest 1 of 2: \|digest 2 of 2: \|Group recap of G57 ended: 2 of 2 members done')" "3"
chk "H it starts no terminal and removes none"      "$(ghc '^hc \[run\]\|^hc \[rm\]')" "0"
chk "H and the session is the group's recap"        "$(grep -c "recap_of=group:G57 args=-n recap-g57 /second-brain:session-recap --group G57\$" "$GH/gclaude-calls.log")" "1"
chk "H its log counts two members"                  "$(glog 'run began for 2 members of group G57$')|$(glog 'run claimed 2 members; starting the recap session here$')" "1|1"
greset; gmk ${D57}1 ${A57}01 ticket-one deferred G57 9
gtick "$GCMD" G57 --complete-at "$T57" --here >/dev/null 2>&1
chk "H and calls one member a member"               "$(s57 1 01)|$(glog 'run began for 1 member of group G57$')|$(glog 'run claimed 1 member; starting the recap session here$')" "done|1|1"

# A member still alive when the hour has passed is left out of the run, and gets a run of its own once it
# has ended: a catch-up, which files where the group's documents already are. The live member is a real
# process with a real registry entry; it ends without its end hook.
greset; : > "$GH/hc-exec"
gmk ${D57}1 ${A57}01 ticket-one deferred G57 9; gmk ${D57}2 ${A57}03 standing-session "" G57 12
LP57=$(perl -e 'exit 0 if fork; print "$$\n"; open STDOUT, ">", "/dev/null"; open STDERR, ">", "/dev/null"; exec "sleep", "120"')
greg "$LP57" ${A57}03 "$(bash -c 'source "$1" >/dev/null 2>&1; proc_start_time "$2"' _ "$HELPL" "$LP57")"
grun G57 --complete-at "$(gago 59)" "${GL[@]}"
chk "8 inside the hour a live member holds the run back" "$GRC|$(ghas 'standing-session')|$(ghc '^hc \[run\]')" "1|1|0"
T57B=$(gago 61); grun G57 --complete-at "$T57B" "${GL[@]}"
chk "9 past the hour a run starts without it"       "$GRC|$(ghas 'started: a recap of 1 member of group G57')" "1|1"
gwait "$GH/hc-calls.log" '^hc \[rm\]'; gidle
chk "9 a live member is neither claimed nor stamped" "$(cut -f3 "$(gstate G57)/members.tsv")|$(s57 2 03)|$(s57 1 01)" "ticket-one||done"
chk "9 and the run's log calls one member a member"  "$(glog 'run began for 1 member of group G57$')|$(glog 'run claimed 1 member; started recap-g57 in hc terminal t77$')" "1|1"
grun G57 --complete-at "$T57B" "${GL[@]}"
chk "7 while it lives the caller is told to call again" "$GRC|$(ghas '1 of 2 members is still alive (standing-session)')" "1|1"
kill "$LP57" 2>/dev/null; i=0; while kill -0 "$LP57" 2>/dev/null && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i + 1)); done
: > "$GH/hc-calls.log"
grun G57 --complete-at "$T57B" "${GL[@]}"
chk "9 once it has ended a second run takes it"     "$GRC|$(ghas 'started: a recap of 1 member of group G57')|$(grep -c 'deferred: it ended without its end hook' "$GKB/_sessions/${D57}2/${A57}03/recap.log")" "1|1|1"
gwait "$GH/hc-calls.log" '^hc \[rm\]'; gidle
chk "9 and gets it done"                            "$(s57 2 03)|$(cut -f3 "$(gstate G57)/members.tsv")" "done|standing-session"
chk "9 filing where the group's documents already are" "$(grep -c '^project=team$' "$(gstate G57)/manifest")" "1"
grun G57 --complete-at "$T57B" "${GL[@]}"
chk "6 and then the group is settled"               "$GRC|$(ghas 'settled: 2 members, 2 done and 0 exempt')" "0|1"
GPROC="$GH/proc"

echo "== 58. the recap child and the exit watcher answer for every member of a group (ADR-0013) =="
# The child of a group recap runs one recap for the members its run claimed, claims nothing itself, and on
# its way out fails each member that still reads running. The exit watcher ends the session once every one
# of them is done. Both read the members once: a later run of the same group writes the list anew.
D58=2026-11-01; A58=58580000-0000-0000-0000-0000000000
s58(){ prop "$(gmds $D58 ${A58}$1)" recap_status; }
gmembers(){ : > "$(gstate G58)/members.tsv"; local m
    for m in "$@"; do printf '%s\tid-%s\tname-%s\tteam\t9\tdigest\n' "$GKB/_sessions/$D58/${A58}$m" "$m" "$m" >> "$(gstate G58)/members.tsv"; done; }
gchild(){ env HOME="$GH" PATH="$GB:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID= SECOND_BRAIN_RECAP_OF=group:G58 \
    SECOND_BRAIN_RECAP_NAME=recap-g58 SECOND_BRAIN_PLUGIN_ROOT="$PLUGIN" bash "$PLUGIN/hooks/scripts/recap_child.sh" "$@"; }
g58(){ greset; mkdir -p "$(gstate G58)"
    gmk $D58 ${A58}01 member-one running G58 9; gmk $D58 ${A58}02 member-two running G58 9
    gmk $D58 ${A58}03 not-this-runs deferred G58 9; gmembers 01 02; }
g58; echo name-02 > "$GH/gclaude-skip"
C58=$(gchild --group G58 2>&1)
chk "C1 the child runs the group's one recap"       "$(grep -c "^claude cwd=$GKB recap_of=group:G58 args=-n recap-g58 /second-brain:session-recap --group G58\$" "$GH/gclaude-calls.log")" "1"
chk "C1 and claims nothing: its run did"            "$(cat "$GKB/_sessions/$D58/${A58}01/recap.log" "$GKB/_sessions/$D58/${A58}02/recap.log" | grep -c 'refused')" "0"
chk "C2 a member still running at the end is failed" "$(s58 01)|$(s58 02)" "done|failed"
chk "C2 with the reason the notice shows"           "$(grep -c 'reason=its group recap (G58) ended before it was marked done' "$GKB/_sessions/$D58/${A58}02/recap.log")" "1"
chk "C2 a member that is not this run's is left"    "$(s58 03)" "deferred"
chk "C2 the terminal says how the recap ended"      "$(printf '%s\n' "$C58" | grep -c 'Group recap of G58 ended: 1 of 2 members done')" "1"
chk "C2 and so does the group's log"                "$(glog 'exit status=1 of 2 members done' G58)|$(glog 'start pane=none name=recap-g58' G58)" "1|1"
chk "C3 the child puts its process on record"       "$(grep -c '^pid=[0-9][0-9]*$' "$(gstate G58)/child" 2>/dev/null)" "1"
# A member moved by somebody else while the recap ran is not the child's to fail.
g58; echo name-02 > "$GH/gclaude-skip"; gst "$GKB/_sessions/$D58/${A58}02" requested --force
gchild --group G58 >/dev/null 2>&1
chk "C2 only a member that reads running is failed" "$(s58 01)|$(s58 02)|$(grep -c 'reason=' "$GKB/_sessions/$D58/${A58}02/recap.log")" "done|requested|0"
rm -f "$GH/gclaude-skip"
# With nothing claimed there is nothing to recap, and a value that is not a key names no group.
g58; : > "$(gstate G58)/members.tsv"; gchild --group G58 >/dev/null 2>&1
chk "C4 with no member claimed the child refuses"   "$?|$([ -f "$GH/gclaude-calls.log" ] && echo ran || echo never)" "2|never"
gchild --group "not a key" >/dev/null 2>&1
chk "C4 and it refuses a value that is not a key"   "$?" "2"

# The watcher, under the Herdr app's stub of this block: idle session, empty prompt box.
gwatch(){ # $1=seconds the stand-in for the child lives
    sleep "$1" & local kid=$!
    env HOME="$GH" PATH="$GB:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID=t77 SECOND_BRAIN_RECAP_EXIT_POLL_S=1 \
        SECOND_BRAIN_RECAP_EXIT_GRACE_MS=2000 SECOND_BRAIN_RECAP_EXIT_IDLE_MS=3000 \
        "$PLUGIN/hooks/scripts/recap_exit_watch.sh" --group "$(gstate G58)" t77 "$kid" >/dev/null 2>&1
    kill "$kid" 2>/dev/null; wait "$kid" 2>/dev/null; }
gkeys(){ ghc '^hc \[keys\] \[t77\] \[/\] \[e\] \[x\] \[i\] \[t\] \[enter\]$'; }
g58; gst "$GKB/_sessions/$D58/${A58}01" "done"; gst "$GKB/_sessions/$D58/${A58}02" "done"; gwatch 30
chk "W1 with every member done the session gets /exit" "$(gkeys)" "1"
chk "W1 and the group's log says why"               "$(glog 'exit-watch typing /exit into t77 as key presses: done, idle through the grace, prompt box empty' G58)" "1"
g58; gst "$GKB/_sessions/$D58/${A58}01" "done"; gwatch 3
chk "W2 with a member short of done the session is left" "$(gkeys)|$(ghc '')" "0|0"
# A later run of the group rewrites the members file while this session is still open. The watcher goes by
# the members of its own run, which are done, and not by the new run's, which are not.
g58
( sleep 2; gmembers 03; gst "$GKB/_sessions/$D58/${A58}01" "done"; gst "$GKB/_sessions/$D58/${A58}02" "done" ) &
gwatch 30; wait
chk "W3 the watcher answers for its own run's members" "$(gkeys)|$(s58 03)" "1|deferred"
# End to end through the child, which starts the watcher by the terminal's id and stops it on the way out.
g58; : > "$GH/gclaude-stay"
env HOME="$GH" PATH="$GB:$PATH" HERDR_ENV= HERDR_PANE_ID= HC_TERMINAL_ID=t77 SECOND_BRAIN_RECAP_OF=group:G58 \
    SECOND_BRAIN_RECAP_NAME=recap-g58 SECOND_BRAIN_PLUGIN_ROOT="$PLUGIN" SECOND_BRAIN_RECAP_EXIT_POLL_S=1 \
    SECOND_BRAIN_RECAP_EXIT_GRACE_MS=1000 SECOND_BRAIN_RECAP_EXIT_IDLE_MS=2000 \
    bash "$PLUGIN/hooks/scripts/recap_child.sh" --group G58 >/dev/null 2>&1
chk "W4 the child's own watcher ends the group's session" "$(grep -c '^exited-by-watcher$' "$GH/gclaude-calls.log")|$(gkeys)" "1|1"
chk "W4 every member is done, and none was failed"  "$(s58 01)|$(s58 02)|$(glog 'exit status=2 of 2 members done' G58)" "done|done|1"
chk "W4 no watcher outlives the child"              "$(pgrep -f "recap_exit_watch.sh --group $(gstate G58)" | wc -l | tr -d ' ')" "0"
rm -f "$GH/gclaude-stay"

echo "== 59. what lists sessions that need a recap leaves a deferred one out (ADR-0013) =="
# ccfind --not-recapped is the backlog a person works through: never requested, waiting, or failed. A
# deferred session is none of those. It waits for its group, and recapping it alone is a person's choice,
# not a gap. The filter is run as ccfind runs it, against rows as its cache holds them.
F59=$(sed -n '/^filter_not_recapped()/,/^}/p' "$PLUGIN/tools/ccfind/ccfind.sh")
R59=$(printf 'row\tid-a\t/tmp/x\t/p/a/session.md\t-\t-\t%s\n' - requested failed deferred "done" exempt running \
    | F59="$F59" bash -c 'eval "$F59"; get_sessions() { cat; }; filter_not_recapped' | cut -f7 | paste -sd, -)
chk "the backlog holds what has no recap, waits or failed" "$R59" "-,requested,failed"
chk "and its comment says a deferred session is left out"  "$(sed -n '/^# Sessions whose knowledge has not been distilled/,/^filter_not_recapped()/p' "$PLUGIN/tools/ccfind/ccfind.sh" | grep -c 'deferred')" "1"

echo "== 60. the link check's title search leaves the memory snapshot copies out, and one grep takes many files =="
# The gate resolves a link by title with a search of the vault. That search started one grep for each
# Markdown file, and a real vault holds 155,578 memory snapshot copies under _sessions/<date>/<id>/memory
# beside 8,239 other Markdown files, so each title cost two to three minutes: 64 and 87 minutes of the two
# recaps of one group (2026-11-11). No snapshot copy in that vault holds a title line, so the search
# leaves those folders out, and one grep takes the files of one search. A stub grep records each call.
# The search by file name is as it was and still reaches a snapshot copy. The vault's path holds a space
# and a bracket, which a pattern built from it has to take as they are.
VK60="$ROOT/vk60 [x]"; S60="$VK60/_sessions/2026-11-01/s60"; GL60="$ROOT/grep60.log"
mkdir -p "$VK60/daily-log" "$VK60/projects/p/concepts" "$S60/docs/memory" "$S60/memory/memory" "$ROOT/gbin60"
t60(){ printf '%s\n' '---' "title: $2" '---' 'text' > "$1"; }       # $1=file $2=title
t60 "$VK60/projects/p/concepts/Alpha Doc.md" "Alpha Title"
t60 "$S60/docs/Gamma Design.md"              "Gamma Title"
t60 "$S60/docs/memory/Delta.md"              "Delta Title"
t60 "$S60/memory/Epsilon.md"                 "Epsilon Title"
t60 "$S60/memory/memory/Zeta.md"             "Zeta Title"
printf 'no title here\n' > "$VK60/projects/p/concepts/Beta.md"; printf 'a note\n' > "$S60/session.md"
for i in $(seq 1 20); do printf 'filler %s\n' "$i" > "$VK60/projects/p/concepts/filler-$i.md"; done
printf '%s\n' '[[Alpha Title]] [[Beta]] [[Gamma Title]] [[Delta Title]]' '[[Epsilon Title]] [[Zeta Title]] [[Epsilon]]' \
    '[[_sessions/2026-11-01/s60/session]]' > "$VK60/daily-log/d60.md"
printf '%s\n' '#!/bin/bash' 'printf "%s\n" "$*" >> "$GREP60_LOG"' "exec $(command -v grep) \"\$@\"" > "$ROOT/gbin60/grep"
chmod +x "$ROOT/gbin60/grep"
V60=$(env HOME="$H" PATH="$ROOT/gbin60:$PATH" GREP60_LOG="$GL60" \
    "$PLUGIN/skills/session-recap/scripts/validate_cross_references.sh" "$VK60/daily-log/d60.md" "$VK60" 2>&1); RC60=$?
V60=$(printf '%s\n' "$V60" | sed "s/$(printf '\033')\[[0-9;]*m//g")
v60(){ printf '%s\n' "$V60" | grep -c -F -- "$1"; }                  # $1=text of one output line
chk "a title in a document resolves, whatever the file is called" "$(v60 'VALID: [[Alpha Title]] → Alpha Doc.md')" "1"
chk "and so does one in a session's docs folder"                 "$(v60 'VALID: [[Gamma Title]] → Gamma Design.md')" "1"
chk "and one in a folder named memory below it"                  "$(v60 'VALID: [[Delta Title]] → Delta.md')" "1"
chk "a title that only a memory snapshot copy holds is no match" "$(v60 'BROKEN: [[Epsilon Title]]')|$(v60 'BROKEN: [[Zeta Title]]')" "1|1"
chk "the search by file name is as it was"                       "$(v60 'VALID: [[Beta]] → Beta.md')|$(v60 'VALID: [[Epsilon]] → Epsilon.md')" "1|1"
chk "a path is checked directly"                                 "$(v60 'VALID: [[_sessions/2026-11-01/s60/session]] → session.md')" "1"
chk "the verdict counts them" \
    "$RC60|$(printf '%s\n' "$V60" | grep -c -E '^Total WikiLinks: +8$|^Valid Links: +6$|^Broken Links: +2$')" "1|3"
chk "one grep takes the files of one title search"               "$(grep -c -- '-l \^title: ' "$GL60")" "7"
chk "and no snapshot copy is among them" \
    "$(grep -- '-l \^title: ' "$GL60" | grep -c -F -- 's60/memory/')|$(grep -- '-l \^title: ' "$GL60" | grep -c -F -- 's60/docs/memory/Delta.md')" "0|7"

# The tripwire once more, after the last case that could reach it: case 36 runs before the
# ccfind cases and cases 48 to 51, the callers of herdr-app and hc.
if [ -s "$TRIPWIRE" ]; then
    no "no case reached the real herdr, herdr-app or hc"
    echo "         attempts:"; sed 's/^/           /' "$TRIPWIRE"
else
    ok "no case reached the real herdr, herdr-app or hc"
fi
echo
echo "RESULT: $PASS passed, $FAIL failed"
# The hooks cache a folder path per session id under /tmp, and the ids here are
# fixed, so leaving those files behind lets one run hand a stale path to the next.
# Matched on content, not on the id, so a real session's cache file is never
# touched even if it happens to share an id with a fixture.
for cache_file in "$TMPREAL"/second-brain-folder-*; do
    [ -f "$cache_file" ] || continue
    case "$(cat "$cache_file" 2>/dev/null)" in "$ROOT"/*) rm -f "$cache_file" ;; esac
done
rm -rf "$ROOT"
[ "$FAIL" -eq 0 ]
