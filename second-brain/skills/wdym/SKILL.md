---
name: wdym
description: "From-zero decode of this session's agent work for the person supervising it. Use when the person does not follow something the agent said or showed ('wdym', 'what do you mean'), wants it from zero ('like I have no context', 'from scratch'), asks what a word, step or output of this session means or why the agent did it that way, asks for proof ('how did you verify', 'prove it'), or says 'wdym debrief'. An explanation for an audience other than the person belongs to the eli5 skill; a pure visual request belongs to show-me."
user-invocable: true
---

# WDYM — What Do You Mean

Re-explain a stretch of this session's agent work to the person supervising it. The subject
is what happened in this session. From zero says which background the reader needs for it.

## Step 0: Load the profile

```bash
source "${CLAUDE_PLUGIN_ROOT}/skills/common/get_kb_path.sh" && KB_PATH=$(get_kb_path)
cat "$KB_PATH/rules/comprehension-profile.md"
```

The profile carries the person's calibration that is not already in their always-on
instructions — register, analogy policy, native formats, daily-stack anchors, known confusion
clusters — and overrides the Calibration defaults only. If the file is missing, use the
defaults and offer once to compile a profile from the knowledge bank's reflections.

## From zero

Write for a new hire on the person's team. This reader is an engineer at the person's own
level. They know general software engineering and the daily stack that the person's
instructions or profile lists. They know nothing of this project's systems, people, history
or state, and nothing of this session. Use this reader on the person's own project too.

To this reader every name is new: a term, an acronym, a system, a team, a person, an id, a
label you coined. Treat a name as explained only when the answer just before explained it
or said that it keeps an earlier explanation, or when the person points back to the answer
that did. A name that the person repeats or quotes is still new. Always explain the name
that the person asks about. When unsure, explain it again.

- Open with the point in everyday words, before any name appears. For an issue, give the
  harm, its cause and the fix, one short sentence each.
- Use only the names the point needs. Explain each one in the sentence that first uses it,
  or the sentence before: a system or a team by its job in this case, a person by role and
  by what they did. Use the source's own name. Say which labels you coined. When you write
  "both" or "the two", list them.
- When the person says that they do not know a name, show the real thing it names (print
  the file, open the record) and explain it in one plain line.
- For the rule the point rests on, give the reason. When others own the rule, quote the
  reason from where they recorded it, or mark the reason not read.
- When the subject is one case of a rule set that fits one table, show the whole table with
  that case's row in bold.
- Read what the answer needs from its source, and cite it: what the session does not hold
  (a definition, another system's behaviour, a reason), and the evidence behind any earlier
  claim that the person doubts or builds on. When that evidence breaks the premise of the
  ask, say so in the point. Run a new check only in the session's own scratch directory (its
  docs path or a temporary folder), and say so in the answer.
- Before you point the person at a thing to find or to act on, check that it exists where
  they will look.
- Before the trigger list, say what it means for the person's own case: what is done and
  what is pending. If the person set a decision aside to ask this, put that decision to the
  person again after the answer, worded for the same reader.

A follow-up is a confirmation or a narrow question about the answer just before. Answer it
with the direct answer first (yes, no or partly to a confirmation), then one table, then
the reason. Add no other part.

Size the answer to the ask, within the limits that Calibration gives. Leave out rejected
alternatives, proof tables and side findings unless the person asks why this way or asks
for proof. Keep the proof of the point. Send the shortest answer that passes the check below.

Before you send, re-read the answer as the new hire. Done when the opening states the point,
no name comes before its explanation, every claim carries a mark, and each line above is met
or does not apply.

## Calibration (generic defaults; the profile overrides)

- Peer register for a working engineer. Never a child's register.
- Prose at "80% of the way to ASD-STE100": short sentences, active voice, one term per
  concept, one idea per sentence. Soften rather than follow the spec strictly — strict STE
  measurably drops facts.
- One brief analogy at most, after the point. In the first answer on a topic, trace one real
  case from this session with its actual values and its file, log line, or command. For a
  change, trace the old path and the new path on the same case. Run a built example through
  the real code, and say which values you made up. An analogy without the real case is a
  non-answer.
- Anything with layers, roles, or directions gets a 2-axis table or a decision tree, not prose.
- Size: a follow-up in under 400 words, any other decode of one phrase, answer, change or
  decision in under 1,000, a whole topic from zero in under 1,600.
- Close substantial explanations with a trigger list: "you'll know X applies when …".

## The ladder

The person's own questions escalate predictably:

1. What changed?
2. Where does it come from? (file, config, upstream system)
3. What is X?
4. Why this way? (the alternative considered, and why not)
5. Prove it. (the verification evidence)

Debrief mode walks all five. In a decode, answer the rung that the person asks. From zero
sets what else a decode covers, its order and its size.

## Format escalation

A table or a text tree belongs to rung 1. Start at rung 1; climb only while the point is not
landing:

1. **Prose** — 80%-STE, calibrated as above.
2. **Diagram** — when the subject has layers, roles, directions, or flow. After drawing,
   restate every edge as a checkable sentence; a missing arrow silently claims "no dependency".
3. **Interactive HTML** — one focused page, only when a static diagram cannot carry it (state
   spaces, before/after comparisons, things worth poking at). Reuse the show-me grammar.

Explainer videos are out of scope.

## Verification posture

Clarity must not outrun truth: a wrong claim in a clean diagram is MORE convincing, not less.

- Cite the evidence of every claim: `file:line`, the actual log line, the command and its
  output, or the document you read it from. For the claim the point rests on, give the full
  location (package, path, function) and quote the lines, or show the rows of its run.
- Mark each claim **verified** (what you read, and when), **reported** (who said it),
  **inferred** (reasoning, not yet checked) or **not read**.
- Limit a claim about a set to the part you read. Read the whole set before you write "all",
  "none" or "never".
- Give each status claim (what merged, what runs where, who answered) its read time. Read it
  again when the point rests on it and its last read is from an earlier day. Otherwise write
  "as of <time>, not re-read". A rule about what should happen is not a read of what did.
- When a new read contradicts or updates an earlier answer, say so right after the point.
- If a verification gap exists, say so plainly — the "prove it" rung exists because gaps hide.

## Learning loop

When the person's confusion is new, or a known cluster repeats, append one dated line to the
profile's `## Inbox` section:

```
- YYYY-MM-DD: confused by <X> in <context>; <what explanation landed>
```

On "recompile my profile": fold the Inbox and recent reflections into the profile body, then
empty the Inbox.

## Promotion

After a substantial explanation that resolved real confusion, offer once — never auto-write —
to promote it to a knowledge-bank concept doc, preserving the analogy under a
`## The Analogy (from the session's ELI5)` heading. Use the kb-ingest workflow.

## Debrief mode

`wdym debrief` (or asked at task end): walk the ladder over the whole task — what changed,
where it came from, new terms, why this shape, and the verification evidence — pre-answering
the questions the person would otherwise ask one by one. Close with next steps: every pending
item, one line each, naming who holds it, or `none`.

## Boundaries

- An audience other than the person ("explain this to my manager") → the eli5 skill. An ask
  from zero with no other audience named belongs here. A persona that the person takes on
  for themself is still the person.
- A standalone visual with no comprehension question → show-me.
- "How did we handle X before" / service documentation → knowledge-bank-lookup.
- Deliberate multi-session study of a topic → teach.
