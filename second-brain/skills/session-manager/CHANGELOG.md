# Changelog - session-manager skill

Skill-specific changes. Hook and plugin-level changes are in the plugin's
[CHANGELOG.md](../../CHANGELOG.md).

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [2.13.0] - 2026-09-15

Automatic mode changes hands. See `docs/adr/0006-the-description-is-written-after-the-session-ends.md`.

### Changed
- **Ownership reads by stage, not by writer.** The hooks seed a note at registration and never overwrite;
  this skill is the only writer **while a session runs**; and once a session has ended, the recap writes
  its description — `project`, `tags` and `summary` — from the whole conversation, overwriting what is
  there. `session_name` is not in that list: it is seeded from the launch title and kept in step with
  `/rename` here, and the recap never touches it.
- **`tag-canonicalization.md` gives each mode exactly one writer.** Step 4 opened with the Obsidian CLI
  `property:set` command before the modes split, so a recap following it literally would have written tags
  through the vault, outside the lock the recap's status writer holds, and either duplicated or
  contradicted the write inside it. The CLI command now belongs to interactive mode. Automatic mode
  produces the canonical list and hands it to `recap_status.sh --tags`, writing nothing itself.
- **Automatic mode is triggered by a recap describing a session that has ended**, not by an instruction
  from the start hook, and it may coin a tag the vault has never seen only when the conversation gives
  repeated evidence for it, recording it as a proposal otherwise. Its opening paragraph no longer promises
  that tags are set only after the user approves: nobody is present to approve in that mode, and a recap
  runs in an unfocused pane where a prompt stalls forever.
- The reason given for not substituting ccfind's cache is rewritten. It said the fallback would be "the
  tags already on this session's note", which is wrong twice over now: in automatic mode the note being
  described belongs to a different session than the one running the skill, and in either mode a note's own
  tags are the output rather than the reference.

### Removed
- **The automatic-mode paragraph in `SKILL.md`.** It existed to answer the SessionStart hook's injected
  instruction, which 2.13.0 removed after measuring that it was ignored: five user prompts and
  thirty-nine assistant turns produced no tags, no property write and no skill invocation.

## [2.12.0] - 2026-09-15

### Added
- **An automatic mode.** When the SessionStart hook's injected instruction names it, the skill derives
  tags for a session the hook could name but not describe. It writes tags that already have a canonical
  form in the vault, reports any it could not match, and never prompts, so a derivation cannot interrupt
  the user's first request. Coining a new tag stays a deliberate act, done by invoking the skill by
  hand, where the existing confirmation applies unchanged.
- **A lineage line in the report**, shown when the session was forked or delegated, so an inherited
  project and inherited tags read as inherited rather than chosen.

### Changed
- **`project` is a knowledge-bank domain**, one of the vault's `projects/` folders, not a name seeded
  from the working directory. A value outside that set is unresolved, which is what every note written
  before this holds, so the skill treats it as empty and sets it properly instead of leaving it to be
  read as a domain.
- **The ownership rule is stated as it now works**: the hooks seed a note when the session starts and
  never overwrite a value that is already there, and from then on the skill is the only writer.
- **Canonical tags are read from the vault**, not from ccfind's cache. The cache exists only if someone
  has run that tool, holds session tags alone, and its documented fallback was "the tags already on this
  session's note" — empty by definition in automatic mode, since having no tags is what triggers the
  run. Every tag would have looked new and nothing would ever have been written.

## [2.11.0] - 2026-09-14

### Changed
- Rewritten against the skill-authoring guidance: 160 lines down to 93 plus a disclosed reference, the
  mandatory opening sequence moved to the top, tag handling split into
  [tag-canonicalization.md](tag-canonicalization.md), and the description pruned from 90 words to 36.

### Added
- A verifiable completion criterion for the terminal rename, which is best-effort and reports nothing,
  so a failed rename used to be silent.

### Removed
- The Examples and Constraints sections, which restated what the property table and command form
  already defined.
