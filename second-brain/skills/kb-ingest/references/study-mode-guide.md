# Study Mode Guide

## Theme Walkthrough Example

Studying an article on event sourcing (theme 2 of 4):

**Present:**
> "The article argues projections should be rebuildable from the event stream at any time. This means your read models are disposable — you never need to worry about their schema drifting from truth, because you can always rebuild from events."

**Explore:**
> "I found a related talk by Greg Young where he argues this is also the key to schema migration — you never migrate projections, you rebuild them. Also found a case study where Shopify uses this pattern for their order history, rebuilding projections nightly to catch drift."

**Pause:**
> "What stands out to you here?"

**User notes:**
> "The key insight is that disposable read models eliminate an entire class of migration bugs. We hit exactly this problem with our cache layer — stale schemas after deploys."

**Capture:** Record the user's framing ("disposable read models eliminate migration bugs") and their connection to their own cache layer problem. This goes into the learning notes as-is — the user's synthesis is sharper than the source.

---

## Explore Step: Depth Guidance

The goal of online research is to **add context**, not exhaustively survey. For each theme:

- Find **2-3 relevant pieces** — related work, counter-arguments, real-world applications, or deeper explanations
- Prioritize pieces that **challenge, extend, or concretize** the theme — not just confirm it
- Stop when you have enough to give the user a richer perspective than the source alone provides
- If the theme is self-contained and well-explained, a quick search finding nothing notable is fine — say so and move on

**Good explore results:**
- A practitioner's case study showing the pattern in production
- A counter-argument or known limitation
- A related concept from a different domain that illuminates the same principle

**Over-exploring (avoid):**
- Reading 10+ articles per theme
- Summarizing entire papers when a key finding suffices
- Researching tangential topics the source only mentions in passing

---

## Capturing User Notes

The user's notes are the most valuable output of study mode. They often reframe concepts more sharply than the source — for example, "every harness component encodes an assumption about model capability" is a user reframing, not a direct quote.

When capturing:
- **Preserve the user's exact framing** when it's sharper than the source
- **Note connections** the user draws to their own work or existing KB knowledge
- **Flag disagreements** — if the user pushes back on a point, that's worth recording
- **Don't paraphrase** the user's notes into more "polished" language — their words are the point
