# Tag canonicalization

Tags are only useful when the same idea always gets the same word. Every tag the user offers goes
through canonicalization first: match it to the form the vault already uses, and set tags only after
they approve the result.

## 1. Load the vault's tags

ccfind's cache holds one session per line with tags in field 5, comma-separated:

```bash
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/ccfind/sessions.tsv"
cut -f5 "$CACHE" 2>/dev/null | tr ',' '\n' | sed 's/^ *//;s/ *$//' | grep -v '^-$' | grep -v '^$' | sort | uniq -c | sort -rn
```

The count matters as much as the tag: a tag used by twenty sessions is the canonical form, one used
once is a candidate for retirement. If the cache is absent, fall back to the tags already on this
session's note.

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

## 4. Confirm, then set

Confirm with the **AskUserQuestion** tool, one option per plausible tag set, and write only what the
user picks:

```bash
obsidian vault="knowledge-bank" property:set name="tags" value="<approved, comma, separated>" type="list" path="<vault-relative-path>"
```

**Done when:** every tag the user offered appears in the note in its canonical form, or the user
dropped it.
