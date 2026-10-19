# debrief

A substantial turn ends with a **▤ Debrief** block — what changed, where it came from, new
terms, why this shape, the proof, and the next steps or `none`. This mod puts the rule in the
system prompt and draws the latest block as a card in the band above the prompt, with **Copy**
and **Pin**; the block itself is removed from the message's drawing (the stored message keeps
it). It is a plugin of function hooks: no shell, hot-reloads while you edit it.

## Install

```
/plugin marketplace add sxhmilyoyo/sundayhao-plugins   # once
/plugin install debrief@sundayhao-plugins
```

The band appears after the first turn that ends with a block.

## What it does

| Hook | Effect |
|---|---|
| `prompt.compose` | Appends the debrief rule as the last `session` section of the system prompt; skipped for `print`, `bare`, `teammate` and `sdk-preset` prompts |
| `turn.complete` | Parses the main loop's answer for the last complete block (subagent turns ignored) |
| `ui.render` on `AbovePrompt` | Draws the card: rounded border, title with turn and time, bold labels in an 18-column gutter, values with inline markdown rendered, `you` / `me` / `pending` / `blocked` in theme colours, sections separated by a blank row; a compact form (What changed, Next steps) when the band is too short; hidden while a turn runs |
| `ui.render` on `AssistantMessage` | Removes the block from the message's drawing; the transcript keeps the text |

**Copy** puts the block's plain text on the clipboard. **Pin** holds the card through later
debriefs and counts them as `+N newer` in the title; the engine's `[-]` collapses the band.

## The block

```
▤ Debrief ────────────────────────────────────
- **What changed:** …
- **Where from:** …
- **New terms:** …
- **Why this shape:** …
- **Proof:** …
- **Next steps:** …
─────────────────────────────────────────────────
```

Plain frame lines, one bullet per rung, empty rungs skipped except Next steps, which reads
`none` when nothing is pending; several next steps become indented sub-bullets, each opening
with who holds it (`you:`, `me, on your word:`, `pending:`, `blocked:`).

## Develop

```
claude plugin validate debrief
claude plugin test debrief        # on a Toolbox install, call the root-level binary directly
```

Vocabulary: `GLOSSARY.md` at the repository root (Debrief, Interrogation ladder, Comprehension
register). The compact companion for a session-wide register is `second-brain`'s `wdym` skill,
whose `wdym debrief` produces the same rungs in full.
