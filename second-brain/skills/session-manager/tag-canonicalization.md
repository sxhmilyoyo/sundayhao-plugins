# Tag canonicalization

Tags are only useful when the same idea always gets the same word. Every tag the user offers goes
through canonicalization first: match it to the form the vault already uses, and set tags only after
they approve the result.

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

Do not substitute ccfind's cache for this. It is written only when someone runs that tool, it holds
session tags alone, and its absence used to send this step to "the tags already on this session's
note" — which in automatic mode is empty by definition, since having no tags is the condition that
triggered the run. Every tag would then look new and nothing would ever be written.

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

```bash
obsidian vault="knowledge-bank" property:set name="tags" value="<comma, separated>" type="list" path="<vault-relative-path>"
```

How you arrive at that list depends on which mode you are in.

**Interactive**, the ordinary case, where a person asked for tags. Confirm with the
**AskUserQuestion** tool, one option per plausible tag set, and write only what they pick.

**Automatic**, when the start hook's instruction named that mode. Write the tags that already have a
canonical form and stop there. Report any tag the session name implies that the vault has never seen,
and write nothing for it. Do not prompt: the request that shares this turn is the user's, not yours,
and coining a new tag is a deliberate act that belongs to an invocation by hand, where the
confirmation above applies unchanged.

**Done when:** every tag with a canonical form appears in the note in that form, and in automatic mode
anything without one has been named in your report rather than invented.
