# Changelog - WDYM Skill

All notable changes to the wdym skill are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [2.0.0] - 2026-11-21

### Changed
- A decode is written from zero. A new section, From zero, tells the agent to write for a
  new hire on the person's team: an engineer at the person's own level who knows the daily
  stack and nothing of the project or of the session. The answer opens with the point in
  everyday words, uses only the names the point needs and explains each one where it first
  appears. It gives the reason for the rule the point rests on, shows the whole table when
  the subject is one case of a rule set, and says what it means for the person. When the
  person set a decision aside to ask, the agent puts that decision to the person again
  after the answer. A follow-up gets the direct answer, one table and the reason. Before it
  sends the answer, the agent re-reads it as the new hire.
- A name counts as explained only when the answer just before explained it, or when the
  person points back to the answer that did. A name that the person repeats or quotes is
  still new.
- The answer is sized to the ask. Rejected alternatives, proof tables and side findings
  stay out unless the person asks why this way or asks for proof. Calibration gives a word
  limit for a follow-up, for any other decode of one phrase, answer, change or decision,
  and for a whole topic from zero.
- A decode reads what the answer needs from its source and cites it: what the session does
  not hold, and the evidence behind an earlier claim that the person doubts or builds on. A
  new check runs only in the session's scratch directory, and the answer says so.
- The ladder no longer drives a decode. Debrief mode walks all five rungs; a decode answers
  the rung that the person asks.
- Verification posture: four marks (verified, with what was read and when; reported, with
  who said it; inferred; not read). A claim about a set is limited to the part that was
  read. A status claim carries its read time, or `as of <time>, not re-read`. A correction
  comes right after the point. The claim the point rests on gets its full location and the
  quoted lines.
- Calibration: one brief analogy at most, after the point. The first answer on a topic
  traces one real case with its actual values; a change is traced on the same case before
  and after; a built example runs through the real code and says which values are made up.
- The profile overrides the Calibration defaults only.
- The description has one trigger for each kind of ask. An ask from zero that names no
  other audience belongs to this skill, and a persona that the person takes on for themself
  is still the person.
- Format escalation: a table or a text tree belongs to rung 1.

## [1.0.2] - 2026-10-19

### Changed
- Debrief mode closes with next steps: every pending item, one line each, naming who holds
  it, or `none` — the one rung that never skips, so "nothing pending" is told apart from
  "unsaid".

## [1.0.1] - 2026-10-10

### Fixed
- Step 0 sourced `skills/common/get_kb_path.sh` by a cwd-relative path, which resolves only
  from the plugin root; it now uses `${CLAUDE_PLUGIN_ROOT}`, as the hooks do.

### Changed
- Step 0 describes the profile as carrying the calibration not already in the person's
  always-on instructions. A person whose CLAUDE.md carries the register keeps only the
  evolving parts (confusion clusters, ladder, inbox) in the profile.

## [1.0.0] - 2026-10-06

### Added
- Initial release: on-demand decoder for agent output, triggered by self-directed
  comprehension/verification asks ("wdym", "what do you mean", "how did you verify",
  "prove it") with no named audience.
- Profile-driven calibration from `$KB_PATH/rules/comprehension-profile.md`; generic
  engineer-peer defaults when no profile exists.
- Interrogation-ladder checklist (what changed → where from → what is X → why this way →
  prove it) — never leave the next rung unaddressed.
- Three-rung format escalation: 80%-STE prose → diagram (every edge restated as a sentence)
  → one focused interactive HTML page. Videos out of scope.
- Verification posture: session-evidence citations, explicit verified-vs-inferred marking.
- Learning loop: dated confusion records appended to the profile Inbox; "recompile my
  profile" folds them in.
- Promotion offer (never auto-write) of landed explanations to knowledge-bank concept docs
  with the "## The Analogy (from the session's ELI5)" heading.
- `wdym debrief` end-of-task mode.
- Design inputs: Karpathy's 2026-10-02 format ladder (rungs 1–3 adopted) and a mining pass
  over 264 knowledge-bank reflections plus daily-log Human Input tables.
