---
status: accepted
date: 2026-10-27
implementation: 2.20.0
---

# A launcher can declare its delegate exempt from the automatic recap

A launcher that ends the sessions it starts can declare them exempt from the automatic recap, by setting
`SECOND_BRAIN_RECAP_EXEMPT` in the launched session's environment. The start hook records
`recap_exempt: launcher` on the note at a genuine startup, and every exit of that session stamps `exempt`,
with the reason in `recap.log`, instead of `requested`. The exemption is final: growth never promotes it, and
a recap made by hand is never re-requested.

The case is the ticket dispatcher. It starts one session per ticket and ends it with `/exit` typed through
Herdr once the ticket is closed. That exit reaches the end hook as `prompt_input_exit`, the reason the
owner's own `/exit` carries, so nothing at exit can tell the two apart. On 2026-10-27, 96 sessions were
registered and 29 recapped, most of them ticket sessions whose work the dispatcher already records in
evidence files, RESOLVED reports and code reviews.

## Considered Options

**Stamp `requested` and start nothing, a per-session `notify`.** Rejected. At about thirty ticket sessions
a day the start-of-session notice, which shows five rows, would list nothing but ticket sessions, and the
owner's own pending recaps would never be seen. `exempt` loses nothing a hand run of the launcher cannot
recover: `exempt` to `running` is an allowed transition.

**Decide at exit.** Rejected, because there is nothing at exit to decide on: the reason is the same, the
transcript records no `/exit`, and Herdr does not say who typed. The dispatcher could stamp the note itself
before typing `/exit`, but that puts the vault's layout and the status writer's contract into another package
for a distinction the launch already knows. Declared at launch and read off the note at exit is the pattern
[ADR-0003](0003-recap-sessions-are-registered-guarded-by-env.md) set for recap sessions and
[ADR-0005](0005-delegation-is-declared-not-detected.md) generalised.

**Detect by name or directory.** Rejected by ADR-0005. Ticket sessions share their directory with the
owner's own sessions in the same repository, and a name pattern is a rule the next launcher breaks.

**Make every delegated session exempt.** Rejected. A delegate started with `launch_delegate.sh` for a review
or a piece of research is the owner's own ask and is recapped today. The dispatcher declares delegation as
well, on the marker ADR-0005 defined, so the two facts stay separate properties.

**Name the property `auto_recap: off`, after the configuration key.** Rejected. The global `off` switches the
feature off and stamps nothing; a session that says no while the feature is on must record that no, because
an empty status is also what a hook killed at its budget leaves behind. One word meaning two things on the
same note was not worth the familiarity.

## Consequences

The marker travels inline on the launched command, never in a pane's or shell's environment, and counts on
a genuine startup only, like the markers before it. Where the terminal manager passes no environment,
`claude --settings '{"env":{...}}'` carries it; the dispatcher already passes its TMPDIR that way, and a
print-mode probe on 2026-10-27 confirmed that both hooks see the variable.

The exemption names the launch, not the exit. A ticket session the owner steps into and `/exit`s by hand is
exempt too, and a session the owner starts and ends by hand, without the launcher, is recapped as before.

Global `auto_recap: off` still stamps nothing for any session. A note lost mid-session and rebuilt at exit
has no `recap_exempt`, so that one exit may request a recap, which is the direction `recap_of` fails in too.

The third kind of exempt session joins the glossary in CONTEXT.md, and the launching session entry says a
launcher may declare it. A launcher that wants the exemption has to opt in; one that does not gets the
behaviour it had.
