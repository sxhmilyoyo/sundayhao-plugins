import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Actor, Debrief } from '../types'
import { collapse, draft, findBlock, inline, len, wrapRuns } from './parse'
import type { Run } from './parse'

const last = atom({ plugin: 'debrief', key: 'last' } as const, null)
const pinned = atom({ plugin: 'debrief', key: 'pinned' } as const, null)
const newer = atom({ plugin: 'debrief', key: 'newer' } as const, 0)
const turn = atom({ plugin: 'debrief', key: 'turn' } as const, 0)

const RULE = [
  'A substantial turn ends with a ▤ Debrief block, the last thing in the final message. A turn is substantial when it changed a file, committed or pushed, or ran five or more tool calls; a one-line answer gets no block.',
  '',
  'The two frame lines are plain text: no backticks and no other markup around them. Each rung is its own bullet so the lines never merge. Empty rungs are skipped, except Next steps, which always appears and reads none when nothing is pending. Exactly this shape:',
  '',
  '▤ Debrief ────────────────────────────────────',
  '- **What changed:** …',
  '- **Where from:** …',
  '- **New terms:** …',
  '- **Why this shape:** …',
  '- **Proof:** …',
  '- **Next steps:** …',
  '─────────────────────────────────────────────────',
  '',
  'The first five rungs answer the questions the person would otherwise ask one by one: what changed, where it came from, which new terms appeared, why this shape rather than the alternative, and the evidence from this session that proves it. Next steps lists every pending item, opening with who holds it: "you:" for an action or decision of the person\'s, "me, on your word:" for work prepared but not done, "pending:" for something in flight, "blocked:" with what it waits on. One item sits on the rung line; several become indented sub-bullets, one per item. Offers and ideas are not next steps.',
].join('\n')

const LABEL_W = 14
const GUTTER = 2 + LABEL_W + 2
/** How long the ghost text waits before a second offer, when the box could not show the first. */
const GHOST_RETRY_MS = 400

type Seg = { text: string; color?: string; bold?: boolean; dim?: boolean; italic?: boolean }
/** One row of the card: its gutter, its body, and for a pressable row the draft a press puts in the prompt box. */
type Row = { lead: Seg[]; body: Seg[]; press?: { key: string; draft: string } }

const ACTOR_STYLE: Record<Actor, Pick<Seg, 'color' | 'bold' | 'dim'>> = {
  you: { color: 'warning', bold: true },
  me: { color: 'suggestion', bold: true },
  pending: { color: 'subtle' },
  blocked: { color: 'error', bold: true },
  none: { dim: true },
  other: {},
}

const pad = (s: string, n: number) => s + ' '.repeat(Math.max(0, n - len(s)))

function hhmm(ms: number): string {
  const d = new Date(ms)
  return `${String(d.getHours()).padStart(2, '0')}:${String(d.getMinutes()).padStart(2, '0')}`
}

/** A styled run as a drawn segment: inline code in the permission color, bold and italic as written. */
function seg(r: Run, extra: Partial<Seg> = {}): Seg {
  const s: Seg = { text: r.text, ...extra }
  if (r.code) s.color = 'permission'
  if (r.bold) s.bold = true
  if (r.italic) s.italic = true
  return s
}

/** The wrapped lines of a value, or its first line with an ellipsis when one line is all there is room for. */
function lines(value: string, width: number, oneLine: boolean): Run[][] {
  const all = wrapRuns(inline(value), width)
  if (!oneLine || all.length <= 1) return all
  return [[...(all[0] ?? []), { text: '…' }]]
}

function rungRows(width: number, label: string, value: string, oneLine: boolean): Row[] {
  return lines(value, width - GUTTER - 3, oneLine).map((runs, i) => ({
    lead: [{ text: i === 0 ? `  ${pad(label, LABEL_W)}  ` : ' '.repeat(GUTTER), bold: i === 0 }],
    body: runs.map(r => seg(r)),
  }))
}

/** The Next steps rows; the first row of a `me` step is pressable and drafts its prompt. */
function nextRows(width: number, d: Debrief, oneLine: boolean): Row[] {
  const steps = d.next.length ? d.next : [{ actor: 'none' as Actor, text: 'none' }]
  const shown = oneLine ? steps.slice(0, 1) : steps
  const rows: Row[] = []
  shown.forEach((s, k) => {
    const tag = s.actor === 'other' || s.actor === 'none' ? '' : s.actor
    const head = tag ? `${tag} ▸ ` : ''
    const prompt = draft(s)
    lines(s.text, width - GUTTER - 3 - len(head), oneLine).forEach((runs, i) => {
      const first = k === 0 && i === 0
      const segs: Seg[] = []
      if (tag) segs.push(i === 0 ? { text: tag, ...ACTOR_STYLE[s.actor] } : { text: ' '.repeat(len(tag)) }, i === 0 ? { text: ' ▸ ', dim: true } : { text: '   ' })
      segs.push(...runs.map(r => seg(r, s.actor === 'none' ? { dim: true } : {})))
      const row: Row = { lead: [{ text: first ? `  ${pad('Next steps', LABEL_W)}  ` : ' '.repeat(GUTTER), bold: first }], body: segs }
      if (i === 0 && prompt) row.press = { key: `me-${k}`, draft: prompt }
      rows.push(row)
    })
  })
  return rows
}

/** The card's body: one group of rows per section, an empty row between groups. */
function body(width: number, d: Debrief, compact: boolean): Row[] {
  const picked = compact ? d.rungs.filter(r => /^what changed$/i.test(r.label)) : d.rungs
  const groups = [...picked.map(r => rungRows(width, r.label, r.value, compact)), nextRows(width, d, compact)]
  const rows: Row[] = []
  groups.forEach((g, i) => {
    if (i > 0) rows.push({ lead: [], body: [] })
    rows.push(...g)
  })
  return rows
}

/** Puts `text` in the prompt box as the person's draft; says so when the box would not take it. */
function fill($: EngineInterface, text: string): void {
  void $.prompt.fill({ text }).then(
    r => r.isFilled || $.ui.toast('the prompt box did not take the draft'),
    err => $.ui.toast(`could not draft: ${String(err)}`),
  )
}

/** Offers `text` as the prompt box's ghost text, once more a moment later when the box could not show it yet. */
async function ghost($: EngineInterface, text: string): Promise<void> {
  const r = await $.prompt.suggest({ text }).catch(() => ({ isShown: false }))
  if (!r.isShown) $.clock.after(GHOST_RETRY_MS, () => void $.prompt.suggest({ text }).catch(() => undefined))
}

export const register: Register = on => {
  on('prompt.compose', async ($, e, next) => {
    const r = await next(e)
    if (e.traits.some(t => t === 'bare' || t === 'print' || t === 'teammate' || t === 'sdk-preset')) return r
    return { sections: [...r.sections, { id: 'debrief:rule', text: RULE, scope: 'session' as const }] }
  })

  on('turn.start', async ($, e, next) => {
    await update($, turn, n => n + 1)
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    if (e.agentId || e.reason !== 'answer') return r
    const found = findBlock(e.answer)
    if (found) {
      const d: Debrief = { turn: await read($, turn), at: await $.clock.now(), rungs: found.rungs, next: found.next, raw: found.raw }
      await update($, last, () => d)
      if (await read($, pinned)) await update($, newer, k => k + 1)
      const first = d.next.map(draft).find(t => t !== '')
      if (first) void ghost($, first)
    }
    return r
  })

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const text = collapse(e.props.text)
    return text === null ? next(e) : next({ ...e, props: { ...e.props, text } })
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const held = await read($, pinned)
    const shown = held ?? (await read($, last))
    if (!shown || e.props.hasSurvey || e.props.isWorking || e.props.view.agentId) return next(e)
    const below = await next(e)
    const more = held ? await read($, newer) : 0
    const { Box, Text, Button } = $.ui.resolve(e)

    const width = Math.max(44, e.props.bodyColumns)
    let rows = body(width, shown, false)
    if (rows.length + 2 > e.props.maxRows) rows = body(width, shown, true)

    const stamp = ` · turn ${shown.turn} · ${hhmm(shown.at)}${more ? ` · +${more} newer` : ''} `
    const pinLabel = held ? 'Unpin' : 'Pin'
    const dashes = Math.max(1, width - 3 - 9 - len(stamp) - 8 - 1 - (pinLabel.length + 4) - 3)

    const togglePin = () => {
      void update($, newer, () => 0)
      void update($, pinned, p => (p ? null : shown))
    }
    const draw = (s: Seg) => (
      <Text color={s.color} bold={s.bold} dimColor={s.dim} italic={s.italic} wrap="truncate">{s.text}</Text>
    )
    const rest = (row: Row) => ' '.repeat(Math.max(0, width - 2 - [...row.lead, ...row.body].reduce((n, s) => n + len(s.text), 0)))

    return (
      <Box flexDirection="column">
        <Box>
          <Text color="subtle">╭─ </Text>
          <Text color="suggestion" bold>▤ Debrief</Text>
          <Text dimColor>{stamp}</Text>
          <Text color="subtle">{'─'.repeat(dashes)}</Text>
          <Button key="copy" label="Copy" onPress={() => void $.ui.copy({ text: shown.raw })} />
          <Text> </Text>
          <Button key="pin" label={pinLabel} onPress={togglePin} />
          <Text color="subtle"> ─╮</Text>
        </Box>
        {rows.map(row => {
          const press = row.press
          return (
            <Box>
              <Text color="subtle">│</Text>
              {row.lead.map(draw)}
              {press ? (
                <Button key={press.key} plain onPress={() => fill($, press.draft)}>
                  {row.body.map(draw)}
                </Button>
              ) : (
                row.body.map(draw)
              )}
              <Text>{rest(row)}</Text>
              <Text color="subtle">│</Text>
            </Box>
          )
        })}
        <Text color="subtle">{'╰' + '─'.repeat(width - 2) + '╯'}</Text>
        {below}
      </Box>
    )
  })
}
