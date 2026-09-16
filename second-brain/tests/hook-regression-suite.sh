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
mkdir -p "$ROOT/bin"
TRIPWIRE="$ROOT/herdr-tripwire.log"
cat > "$ROOT/bin/herdr" << TRIP
#!/bin/bash
printf 'REAL HERDR REACHED: %s\n' "\$*" >> "$TRIPWIRE"
echo "herdr: the regression suite must never call the real binary" >&2
exit 1
TRIP
chmod +x "$ROOT/bin/herdr"
export PATH="$ROOT/bin:$PATH"
# Six variables, not four. HERDR_SOCKET_PATH is the channel to the running daemon, so the
# real binary reaches the live workspace through it whatever pane id it was handed, which
# is how a split lands in someone's terminal rather than failing. HERDR_BIN_PATH is an
# absolute path to the real binary and would bypass PATH order entirely, so the tripwire
# above cannot cover it; nothing in the plugin reads that one today, which makes it latent
# rather than live, and exactly the kind of thing to clear before it becomes live.
export HERDR_ENV= HERDR_PANE_ID= HERDR_TAB_ID= HERDR_WORKSPACE_ID= \
       HERDR_SOCKET_PATH= HERDR_BIN_PATH= TMUX_PANE=

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
# /private/tmp, not /tmp: on macOS /tmp is a symlink and find does not descend it,
# so this assertion passed no matter what the hook wrote.
[ -z "$(find /private/tmp -maxdepth 1 -name 'second-brain-startup-*' -print -quit 2>/dev/null)" ] && ok "no rendezvous key written" || no "no rendezvous key written"

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

echo "== 15. the end hook backfills the lineage name, never the tags =="
SH=99999999-9999-9999-9999-999999999999
fork_transcript $SH "$KB/_sessions/$TODAY/$S9"
start $SH fork "" /tmp/mapped >/dev/null
MH="$KB/_sessions/$TODAY/$SH/session.md"
sed -i '' 's/^forked_from_name: .*/forked_from_name: ""/' "$MH"
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

echo "== 28. the launcher hands over a command that carries the markers inline =="
LSUBJ="$NKB/_sessions/2026-09-13/f1111111-1111-1111-1111-111111111111"
LOUT=$(env HOME="$NH" HERDR_ENV= HERDR_PANE_ID= "$PLUGIN/hooks/scripts/recap_launcher.sh" --manual "$LSUBJ/" 2>&1)
chk "the subject marker is inline"     "$(printf '%s' "$LOUT" | grep -c "SECOND_BRAIN_RECAP_OF=")" "1"
chk "the name travels with it"         "$(printf '%s' "$LOUT" | grep -c 'SECOND_BRAIN_RECAP_NAME=recap-inv-recap-hook')" "1"
chk "it runs the child, not claude"    "$(printf '%s' "$LOUT" | grep -c 'recap_child.sh')" "1"
# --env would put the marker in the pane's root shell, where every later session in that
# pane would inherit it, register as a recap and be stamped exempt at its own exit.
chk "never through the pane's env"     "$(printf '%s' "$LOUT" | grep -c -- '--env')" "0"
chk "a trailing slash is normalised"   "$(printf '%s' "$LOUT" | grep -c 'f1111111-1111-1111-1111-111111111111 ')" "1"
env HOME="$NH" "$PLUGIN/hooks/scripts/recap_launcher.sh" --manual /nope/nothing >/dev/null 2>&1 \
    && no "a missing subject is refused" || ok "a missing subject is refused"
# --auto has no terminal to talk to, so outside Herdr it does nothing and says nothing:
# the subject is already `requested` and the notice covers it. `on` degrading to `notify`
# where there is no Herdr is the documented behaviour.
AOUT=$(env HOME="$NH" HERDR_ENV= HERDR_PANE_ID= "$PLUGIN/hooks/scripts/recap_launcher.sh" --auto "$LSUBJ" 2>&1)
chk "--auto outside Herdr exits 0"      "$?" "0"
chk "and prints nothing at all"         "${AOUT:-empty}" "empty"
chk "but records why in recap.log"      "$(grep -c 'not under Herdr' "$LSUBJ/recap.log")" "1"

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
chk "and reads the payload in one jq pass" \
    "$(grep -c 'echo "\$INPUT" | jq' "$PLUGIN/hooks/scripts/session_end.sh")" "1"
# Two are legitimate: the folder rebuild path and nothing else. This goes red if
# per-property reads creep back into the hook body.
chk "no per-property reads remain in the end hook" \
    "$(grep -c 'read_frontmatter_prop "' "$PLUGIN/hooks/scripts/session_end.sh")" "0"

echo "== 34. on mode launches the recap in a pane of its own =="
# A stub herdr records every call, so the Herdr flow is asserted without touching a real
# workspace. process-info answers with a shell_pid, which is what the launcher waits for.
mkdir -p "$NH/.local/bin"
cat > "$NH/.local/bin/herdr" << 'STUB'
#!/bin/bash
printf '%s\n' "$*" >> "$HOME/herdr-calls.log"
case "$*" in
    *"pane split"*)        echo '{"result":{"pane":{"pane_id":"w9:pNEW"}}}' ;;
    *"pane process-info"*) echo '{"result":{"process_info":{"shell_pid":4242}}}' ;;
esac
exit 0
STUB
chmod +x "$NH/.local/bin/herdr"
ASUBJ="$NKB/_sessions/2026-09-13/f1111111-1111-1111-1111-111111111111"
: > "$NH/herdr-calls.log"; : > "$ASUBJ/recap.log"
AOUT2=$(env HOME="$NH" PATH="$NH/.local/bin:$PATH" HERDR_ENV=1 HERDR_PANE_ID=w9:pOLD \
    CLAUDE_PID=31337 "$PLUGIN/hooks/scripts/recap_launcher.sh" --auto "$ASUBJ" 2>&1)
chk "--auto prints nothing even on success" "${AOUT2:-empty}" "empty"
chk "it splits the ending session's pane" \
    "$(grep -c 'pane split --pane w9:pOLD --direction right --no-focus --cwd' "$NH/herdr-calls.log")" "1"
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

echo
echo "RESULT: $PASS passed, $FAIL failed"
# The hooks cache a folder path per session id under /tmp, and the ids here are
# fixed, so leaving those files behind lets one run hand a stale path to the next.
# Matched on content, not on the id, so a real session's cache file is never
# touched even if it happens to share an id with a fixture.
for cache_file in /private/tmp/second-brain-folder-*; do
    [ -f "$cache_file" ] || continue
    case "$(cat "$cache_file" 2>/dev/null)" in "$ROOT"/*) rm -f "$cache_file" ;; esac
done
rm -rf "$ROOT"
[ "$FAIL" -eq 0 ]
