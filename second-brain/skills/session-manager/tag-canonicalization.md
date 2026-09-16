# Tag canonicalization

Tags are only useful when the same idea always gets the same word, so every tag goes through
canonicalization first: match it to the form the vault already uses. Who confirms the result depends on
the mode in step 4. A person confirms when a person asked. Nobody confirms when a recap is describing a
session that has ended, which is why that mode may not coin freely.

## 1. Load the vault's tags

Read them from the vault, which is where they actually live. `$KB` is the vault root, the part of the
injected docs path above `_sessions/`:

```bash
find "$KB" -name '*.md' -not -path '*/.obsidian/*' -print0 \
  | xargs -0 awk 'FNR==1 { fm=0; in_tags=0 }
      /^---$/ { fm++; next }
      fm==1 && /^tags:/ { in_tags=1; next }
      fm==1 && /^[a-z_]/ { in_tags=0 }
      fm==1 && in_tags && /^ *- / { sub(/^ *- */, ""); print }' \
  | sort | uniq -c | sort -rn
```

The count matters as much as the tag: a tag used by twenty documents is the canonical form, one used
once is a candidate for retirement.

Do not substitute ccfind's cache for this. It is written only when someone runs that tool and it holds
session tags alone, so it is a fraction of the vault's vocabulary and can be stale by any amount. Nor
read the tags off the note you are about to write: in automatic mode that note belongs to a different
session than the one running this skill, and in either mode a note's own tags are the output here, not
the reference. The vault is the only complete record.

## 2. Find each tag's canonical form

| Case | Canonical form |
|---|---|
| Exact match | the existing tag |
| Differs by hyphenation, `rule-forge` against `ruleforge` | the existing tag |
| Differs by casing, `A2X` against `a2x` | the existing tag |
| Differs by a spelling slip | the existing tag |
| No near match | the user's tag, which becomes canonical for the next session |

## 3. Show the mapping with its evidence

```
| Your tag    | Canonical form   | Why                 |
|-------------|------------------|---------------------|
| rule-forge  | ruleforge (6x)   | existing, no hyphen |
| debugging   | debugging (6x)   | exact match         |
| new-feature | new-feature      | no near match       |
```

## 4. Set them

How the list reaches the note depends on which mode you are in. Each mode has exactly one writer.

**Interactive**, the ordinary case, where a person asked for tags. Confirm with the **AskUserQuestion**
tool, one option per plausible tag set, write only what they pick, and write it yourself:

```bash
obsidian vault="knowledge-bank" property:set name="tags" value="<comma, separated>" type="list" path="<vault-relative-path>"
```

**Automatic**, when a recap is describing a session that has ended. Produce the canonical list and hand
it to the status writer, which writes it. Write nothing yourself:

```bash
recap_status.sh "$SUBJECT" done "$OWN_SESSION_FOLDER" \
    --project "$PROJECT" --tags "<comma, separated>" --summary "$SUMMARY"
```

That is not plumbing detail. The status writer holds a per-folder lock and writes the description and
the status inside it, so tags written through the vault here would land outside that lock and either
duplicate or contradict the write inside it. One writer per stage is what makes the description
recoverable when two things run at once.

In automatic mode, write every tag that already has a canonical form. A tag the vault has never seen may
be written only when the conversation gives repeated evidence for it, such as a tool, component or
technique that recurs. Otherwise record it as a proposed tag in the daily log and in `recap.log` and
write nothing for it. Never prompt: a recap runs unattended in an unfocused pane, so a question there
stalls forever, and an unattended writer that coins freely is how a shared vocabulary drifts.

**Done when:** every tag with a canonical form is on the note in that form, written by the one writer
that mode names, and in automatic mode anything without one has been recorded as a proposal rather than
invented.
