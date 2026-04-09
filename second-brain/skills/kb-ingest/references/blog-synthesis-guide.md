# Blog Synthesis Guide

## When to Use

After a Study mode ingest, when the user chooses "Blog post" synthesis. The input is the digest + learning notes + user's personal reframings — not the raw source.

## Writing Prompt

Act as a thoughtful writer and synthesizer of ideas, tasked with creating an engaging and readable blog post for a popular online publishing platform known for its clean aesthetic and insightful content.

Your goal is to distill the top most surprising, counter-intuitive, or impactful takeaways from the provided source materials into a compelling listicle.

The writing style should be clean, accessible, and highly scannable, employing a conversational yet intelligent tone.

### Structure

1. **Headline** — Craft a compelling, click-worthy headline
2. **Introduction** — Hook the reader by establishing a relatable problem or curiosity (short)
3. **Takeaway sections** — Each takeaway as a distinct section with a clear, bolded subheading:
   - Use short paragraphs to explain the concept clearly
   - Don't just summarize — offer analysis or reflection on why this point is interesting or important
   - If a powerful quote exists in the sources, feature it in a blockquote for emphasis
4. **Conclusion** — Brief, forward-looking summary that leaves the reader with a thought-provoking question or powerful takeaway to ponder

## Output Structure

Save to `docs/polished-blog-YYYYMMDD/`:

| File | Purpose |
|------|---------|
| `original.md` | First draft generated from the prompt above |
| `{Title}.md` | Current polished version (updated through revision rounds) |
| `changelog.md` | Tracks each revision round — what changed and why |
| `feedback.md` | Records user's revision requests and how they were addressed |

## Voice Ownership

The user owns their voice in shared writing. When the user provides their own phrasing for key passages — especially openings and thesis statements:

- **Polish** their grammar and flow
- **Keep** their framing, word choices, and analytical angle
- **Don't** replace their voice with a polished AI voice

When the user rewrites a passage, that's the direction — refine it, don't override it.

## Revision Rounds

Expect multiple rounds of feedback. The user may:
- Rewrite the opening paragraph themselves
- Ask to make it more concise
- Request a different tone or emphasis

After each round, update the polished version, append to changelog, and record feedback.

## Slack Message Adaptation

If the user also wants a Slack version, save to `docs/polished-slack-YYYYMMDD/`.

Default style (adjust based on user preferences):
- Narrative prose over bullet points — reads like someone talking, not presenting
- Concise — two short body paragraphs, roughly 100-200 words
- Links at bottom rather than inline
- Ask the user about their team's Slack tone if unsure
