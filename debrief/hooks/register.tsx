import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { Actor, Debrief } from '../types'
import { collapse, findBlock, inline, len, wrapRuns } from './parse'
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

type Seg = { text: string; color?: string; bold?: boolean; dim?: boolean; italic?: boolean }
type Row = Seg[]

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
  return [[...all[0], { text: '…' }]]
}

/** One bordered row: `│` + the segments + padding to `width` + `│`. */
function bordered(width: number, inner: Seg[]): Row {
  const used = inner.reduce((n, s) => n + len(s.text), 0)
  return [{ text: '│', color: 'subtle' }, ...inner, { text: ' '.repeat(Math.max(0, width - 2 - used)) }, { text: '│', color: 'subtle' }]
}

function rungRows(width: number, label: string, value: string, oneLine: boolean): Row[] {
  return lines(value, width - GUTTER - 3, oneLine).map((runs, i) =>
    bordered(width, [
      { text: i === 0 ? `  ${pad(label, LABEL_W)}  ` : ' '.repeat(GUTTER), bold: i === 0 },
      ...runs.map(r => seg(r)),
    ]),
  )
}

function nextRows(width: number, d: Debrief, oneLine: boolean): Row[] {
  const steps = d.next.length ? d.next : [{ actor: 'none' as Actor, text: 'none' }]
  const shown = oneLine ? steps.slice(0, 1) : steps
  const rows: Row[] = []
  shown.forEach((s, k) => {
    const tag = s.actor === 'other' || s.actor === 'none' ? '' : s.actor
    const head = tag ? `${tag} ▸ ` : ''
    lines(s.text, width - GUTTER - 3 - len(head), oneLine).forEach((runs, i) => {
      const first = k === 0 && i === 0
      const segs: Seg[] = [{ text: first ? `  ${pad('Next steps', LABEL_W)}  ` : ' '.repeat(GUTTER), bold: first }]
      if (tag) segs.push(i === 0 ? { text: tag, ...ACTOR_STYLE[s.actor] } : { text: ' '.repeat(len(tag)) }, i === 0 ? { text: ' ▸ ', dim: true } : { text: '   ' })
      segs.push(...runs.map(r => seg(r, s.actor === 'none' ? { dim: true } : {})))
      rows.push(bordered(width, segs))
    })
  })
  return rows
}

/** The card's body: one group of rows per section, an empty bordered row between groups. */
function body(width: number, d: Debrief, compact: boolean): Row[] {
  const picked = compact ? d.rungs.filter(r => /^what changed$/i.test(r.label)) : d.rungs
  const groups = [...picked.map(r => rungRows(width, r.label, r.value, compact)), nextRows(width, d, compact)]
  const rows: Row[] = []
  groups.forEach((g, i) => {
    if (i > 0) rows.push(bordered(width, []))
    rows.push(...g)
  })
  return rows
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
    if (e.agentId || e.reason !== 'answer') return next(e)
    const found = findBlock(e.answer)
    if (found) {
      const d: Debrief = { turn: await read($, turn), at: await $.clock.now(), rungs: found.rungs, next: found.next, raw: found.raw }
      await update($, last, () => d)
      if (await read($, pinned)) await update($, newer, k => k + 1)
    }
    return next(e)
  })

  on('ui.render', { component: 'AssistantMessage' }, async ($, e, next) => {
    const text = collapse(e.props.text)
    return text === null ? next(e) : next({ ...e, props: { ...e.props, text } })
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const held = await read($, pinned)
    const shown = held ?? (await read($, last))
    if (!shown || e.props.hasSurvey || e.props.isWorking || e.props.view.agentId) return next(e)
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
        {rows.map(row => (
          <Box>
            {row.map(s => (
              <Text color={s.color} bold={s.bold} dimColor={s.dim} italic={s.italic} wrap="truncate">{s.text}</Text>
            ))}
          </Box>
        ))}
        <Text color="subtle">{'╰' + '─'.repeat(width - 2) + '╯'}</Text>
      </Box>
    )
  })
}
