import type { Rung, Step } from '../types'

export type Found = { rungs: Rung[]; next: Step[]; raw: string; start: number; end: number }

/** One styled run of a value: inline markdown resolved to flags, markers gone. */
export type Run = { text: string; code?: true; bold?: true; italic?: true }

const OPEN = /^\s*`?▤ Debrief\b[^\n]*$/
const CLOSE = /^\s*`?─{5,}`?\s*$/
const BULLET = /^- \*\*(.+?):\*\*\s*(.*)$/
const SUB = /^\s{2,}- (.*)$/
const ACTOR = /^(you|me(?:,\s*on your word)?|pending|blocked)\s*:?\s*(?:▸\s*)?(.*)$/i
const LINK = /^\[([^\]]+)\]\(([^)]+)\)/

export const len = (s: string) => [...s].length

function step(s: string): Step {
  const m = ACTOR.exec(s)
  if (m) {
    const head = m[1].toLowerCase()
    const actor: Step['actor'] = head.startsWith('me') ? 'me' : (head as Step['actor'])
    return { actor, text: m[2].trim() }
  }
  if (/^none\b/i.test(s)) return { actor: 'none', text: s.trim() }
  return { actor: 'other', text: s.trim() }
}

/** The last complete debrief block in `text`: its rungs, its next steps, its raw lines. */
export function findBlock(text: string): Found | null {
  const lines = text.split('\n')
  let open = -1
  for (let i = lines.length - 1; i >= 0; i--) {
    if (OPEN.test(lines[i])) {
      open = i
      break
    }
  }
  if (open < 0) return null
  let close = -1
  for (let i = open + 1; i < lines.length; i++) {
    if (CLOSE.test(lines[i])) {
      close = i
      break
    }
  }
  if (close < 0) return null

  const rungs: Rung[] = []
  const next: Step[] = []
  let cur: Rung | null = null
  let inNext = false
  for (const line of lines.slice(open + 1, close)) {
    const b = BULLET.exec(line)
    if (b) {
      cur = { label: b[1].trim(), value: b[2].trim() }
      inNext = /^next steps$/i.test(cur.label)
      if (inNext) {
        if (cur.value) next.push(step(cur.value))
      } else {
        rungs.push(cur)
      }
      continue
    }
    const s = SUB.exec(line)
    if (s && inNext) {
      next.push(step(s[1].trim()))
      continue
    }
    if (cur && line.trim()) {
      if (inNext && next.length) next[next.length - 1].text += ' ' + line.trim()
      else if (!inNext) cur.value += ' ' + line.trim()
    }
  }
  return { rungs, next, raw: lines.slice(open, close + 1).join('\n'), start: open, end: close }
}

/** `text` without its complete debrief block and the blank lines around it; null when there is none. */
export function collapse(text: string): string | null {
  const f = findBlock(text)
  if (!f) return null
  const lines = text.split('\n')
  let start = f.start
  while (start > 0 && lines[start - 1].trim() === '') start--
  let end = f.end
  while (end + 1 < lines.length && lines[end + 1].trim() === '') end++
  lines.splice(start, end - start + 1)
  return lines.join('\n')
}

/** Inline markdown of one value as styled runs: `code`, **bold**, *italic*, [text](url) → text. */
export function inline(md: string): Run[] {
  const runs: Run[] = []
  let buf = ''
  let bold = false
  let italic = false
  const flush = () => {
    if (!buf) return
    const run: Run = { text: buf }
    if (bold) run.bold = true
    if (italic) run.italic = true
    runs.push(run)
    buf = ''
  }
  let i = 0
  while (i < md.length) {
    const c = md[i]
    if (c === '`') {
      const j = md.indexOf('`', i + 1)
      if (j > i + 1) {
        flush()
        runs.push({ text: md.slice(i + 1, j), code: true })
        i = j + 1
        continue
      }
    }
    if (md.startsWith('**', i)) {
      flush()
      bold = !bold
      i += 2
      continue
    }
    if (c === '*') {
      flush()
      italic = !italic
      i += 1
      continue
    }
    if (c === '[') {
      const m = LINK.exec(md.slice(i))
      if (m) {
        buf += m[1]
        i += m[0].length
        continue
      }
    }
    buf += c
    i += 1
  }
  flush()
  return runs
}

const same = (a: Run, b: Run) => a.code === b.code && a.bold === b.bold && a.italic === b.italic

/** Greedy word wrap of styled runs to `width` cells, styles kept; a word longer than the width is cut. */
export function wrapRuns(runs: Run[], width: number): Run[][] {
  const w = Math.max(8, width)
  const lines: Run[][] = []
  let line: Run[] = []
  let used = 0
  const push = (r: Run) => {
    const last = line[line.length - 1]
    if (last && same(last, r)) last.text += r.text
    else line.push({ ...r })
    used += len(r.text)
  }
  const newline = () => {
    const last = line[line.length - 1]
    if (last) last.text = last.text.replace(/\s+$/, '')
    lines.push(line)
    line = []
    used = 0
  }
  for (const r of runs) {
    for (const tok of r.text.split(/(\s+)/)) {
      if (!tok) continue
      if (/^\s+$/.test(tok)) {
        if (used > 0 && used < w) push({ ...r, text: ' ' })
        continue
      }
      let t = tok
      while (len(t) > 0) {
        if (used > 0 && used + len(t) > w) newline()
        if (len(t) <= w) {
          push({ ...r, text: t })
          t = ''
        } else {
          const cut = [...t].slice(0, w).join('')
          push({ ...r, text: cut })
          t = [...t].slice(w).join('')
          newline()
        }
      }
    }
  }
  if (line.length || lines.length === 0) lines.push(line)
  return lines.map(l => (l.length ? l : [{ text: '' }]))
}

/** Plain text of styled runs, for width and tests. */
export const plain = (runs: Run[]) => runs.map(r => r.text).join('')

/** Greedy word wrap of plain text; kept for the tests of the layout arithmetic. */
export function wrap(text: string, width: number): string[] {
  return wrapRuns([{ text }], width).map(plain)
}
