import type { On } from 'claude-code'
import { describe, expect, mock, test } from 'claude-code/testing'

import { collapse, findBlock, inline, plain, wrap, wrapRuns } from '../hooks/parse'

const BLOCK = [
  '▤ Debrief ────────────────────────────────────',
  '- **What changed:** 2.19.8 committed and pushed: six files, 24 insertions',
  '- **Where from:** your "go ahead" on the pending item',
  '- **Why this shape:** explicit staging, so nothing another session left behind rides along',
  '- **Proof:** git log b68ecfc on 98a1f15 · push 98a1f15..b68ecfc · tree clean',
  '- **Next steps:**',
  '  - you: watch for the six-rung block in a fresh session',
  '  - me, on your word: commit the knowledge-bank profile',
  '─────────────────────────────────────────────────',
].join('\n')

const ANSWER = 'Published: b68ecfc is on GitHub main.\n\n' + BLOCK

const BAND = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 20,
  bodyColumns: 92,
  scroll: { offset: 0, bodyRows: 19 },
  view: {},
}

const COMPOSE = {
  model: 'claude-fable-5-1',
  promptModel: 'claude-fable-5-1',
  surfaces: ['terminal' as const],
  tools: [],
  outputStyle: null,
  traits: [] as const,
}

/** What the engine's core would answer beneath the plugin: the kit answers only $.state. */
function core(on: On) {
  on('turn.start', (_$, e) => ({ turnId: e.turnId }))
  on('turn.complete', (_$, e) => ({ text: e.answer }))
  mock.clock(on, { now: 1760000000000 })
  on('prompt.compose', () => ({ sections: [{ id: 'system', text: 'core', scope: 'shared' as const }] }))
  on('ui.render', { component: 'AbovePrompt' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>engine band</Text>
  })
  on('ui.render', { component: 'AssistantMessage' }, ($, e) => {
    const { Text } = $.ui.resolve(e)
    return <Text>{e.props.text}</Text>
  })
}

async function completed($: Parameters<Parameters<typeof test>[1]>[0], answer: string, turnId = 't1') {
  await $.turn.start({ text: 'go', turnId })
  await $.turn.complete({ answer, durationMs: 10, isAborted: false, turnId, reason: 'answer' })
}

describe('parse', () => {
  test('reads the rungs and the actor-tagged next steps', () => {
    const f = findBlock(ANSWER)
    expect(f).not.toBeNull()
    expect(f!.rungs.map(r => r.label)).toEqual(['What changed', 'Where from', 'Why this shape', 'Proof'])
    expect(f!.next.map(s => s.actor)).toEqual(['you', 'me'])
    expect(f!.next[1].text).toBe('commit the knowledge-bank profile')
  })

  test('a lone none is one next step with the none actor', () => {
    const f = findBlock('▤ Debrief ─────\n- **What changed:** x\n- **Next steps:** none\n──────')
    expect(f!.next).toEqual([{ actor: 'none', text: 'none' }])
  })

  test('an unfinished block is not a block', () => {
    expect(findBlock('▤ Debrief ─────\n- **What changed:** still streaming')).toBeNull()
    expect(collapse('▤ Debrief ─────\n- **What changed:** still streaming')).toBeNull()
  })

  test('collapse keeps the prose and removes the block with the blank lines around it', () => {
    const text = collapse(ANSWER)!
    expect(text).toBe('Published: b68ecfc is on GitHub main.')
    expect(collapse(BLOCK)).toBe('')
    expect(collapse(ANSWER + '\n\nMore prose.')).toBe('Published: b68ecfc is on GitHub main.\nMore prose.')
  })

  test('inline markdown becomes styled runs without its markers', () => {
    const runs = inline('the `debrief` mod is **loaded** and *live*, see [docs](https://x.y)')
    expect(plain(runs)).toBe('the debrief mod is loaded and live, see docs')
    expect(runs.find(r => r.text === 'debrief')!.code).toBe(true)
    expect(runs.find(r => r.text === 'loaded')!.bold).toBe(true)
    expect(runs.find(r => r.text === 'live')!.italic).toBe(true)
  })

  test('wrapRuns keeps a style across a line break', () => {
    const lines = wrapRuns(inline('aaa **bbb ccc** ddd'), 8)
    expect(lines.map(plain)).toEqual(['aaa bbb', 'ccc ddd'])
    expect(lines[1][0]).toEqual({ text: 'ccc', bold: true })
  })

  test('wrap fills to the width and cuts a word longer than it', () => {
    expect(wrap('one two three four', 9)).toEqual(['one two', 'three', 'four'])
    expect(wrap('abcdefghijkl', 8)).toEqual(['abcdefgh', 'ijkl'])
  })
})

describe('system prompt', () => {
  test('adds the rule as the last session section', async ($, on) => {
    core(on)
    const r = await $.prompt.compose(COMPOSE)
    const section = r.sections[r.sections.length - 1]
    expect(section.id).toBe('debrief:rule')
    expect(section.scope).toBe('session')
    expect(section.text).toContain('▤ Debrief')
  })

  test('leaves a print or bare prompt alone', async ($, on) => {
    core(on)
    const r = await $.prompt.compose({ ...COMPOSE, traits: ['print'] })
    expect(r.sections.some(s => s.id === 'debrief:rule')).toBe(false)
  })
})

describe('band', () => {
  test('is quiet before any debrief', async ($, on) => {
    core(on)
    const ui = await $.ui.mount({ plugin: 'debrief', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await ui.find({ text: /Debrief/ })).toBeUndefined()
    expect(await ui.find({ text: /engine band/ })).toBeDefined()
  })

  test('draws the last debrief as a card with Copy and Pin', async ($, on) => {
    core(on)
    await completed($, ANSWER)
    const ui = await $.ui.mount({ plugin: 'debrief', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await ui.find({ text: /▤ Debrief/ })).toBeDefined()
    expect(await ui.find({ text: /turn 1 ·/ })).toBeDefined()
    expect(await ui.find({ text: /What changed/ })).toBeDefined()
    expect(await ui.find({ text: /Why this shape/ })).toBeDefined()
    expect(await ui.find({ text: /^you$/ })).toBeDefined()
    expect(await ui.find({ type: 'Button', text: 'Copy' })).toBeDefined()
    expect(await ui.find({ type: 'Button', text: 'Pin' })).toBeDefined()
  })

  test('draws inline code and bold in a value without their markers', async ($, on) => {
    core(on)
    const marked = ANSWER.replace('2.19.8 committed and pushed: six files, 24 insertions', 'the `debrief` mod is **loaded**')
    await completed($, marked)
    const ui = await $.ui.mount({ plugin: 'debrief', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await ui.find({ text: 'debrief' })).toBeDefined()
    expect(await ui.find({ text: /`/ })).toBeUndefined()
    expect(await ui.find({ text: /\*\*/ })).toBeUndefined()
  })

  test('separates the sections with an empty row', async ($, on) => {
    core(on)
    await completed($, ANSWER)
    const ui = await $.ui.mount({ plugin: 'debrief', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    const rows = await ui.findAll({ type: 'Box' })
    const blank = rows.filter(r => r.text.includes('│') && r.text.replace(/[│\s]/g, '') === '')
    expect(blank.length).toBe(4)
  })

  test('falls back to the compact form when the pane is short', async ($, on) => {
    core(on)
    await completed($, ANSWER)
    const ui = await $.ui.mount({ plugin: 'debrief', surface: 'terminal', component: 'AbovePrompt', props: { ...BAND, maxRows: 6 } })
    expect(await ui.find({ text: /What changed/ })).toBeDefined()
    expect(await ui.find({ text: /Next steps/ })).toBeDefined()
    expect(await ui.find({ text: /Why this shape/ })).toBeUndefined()
  })

  test('hides while a turn runs', async ($, on) => {
    core(on)
    await completed($, ANSWER)
    const ui = await $.ui.mount({ plugin: 'debrief', surface: 'terminal', component: 'AbovePrompt', props: { ...BAND, isWorking: true } })
    expect(await ui.find({ text: /Debrief/ })).toBeUndefined()
  })

  test('ignores a subagent turn', async ($, on) => {
    core(on)
    await $.turn.complete({ answer: ANSWER, durationMs: 10, isAborted: false, turnId: 'a1', agentId: 'agent-1', reason: 'answer' })
    const ui = await $.ui.mount({ plugin: 'debrief', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    expect(await ui.find({ text: /Debrief/ })).toBeUndefined()
  })

  test('pin holds the card and counts newer debriefs', async ($, on) => {
    core(on)
    await completed($, ANSWER)
    const ui = await $.ui.mount({ plugin: 'debrief', surface: 'terminal', component: 'AbovePrompt', props: BAND })
    await ui.press({ key: 'pin' })
    expect(await ui.find({ type: 'Button', text: 'Unpin' })).toBeDefined()
    await completed($, ANSWER.replace('2.19.8 committed', 'something newer'), 't2')
    expect(await ui.find({ text: /2\.19\.8 committed/ })).toBeDefined()
    expect(await ui.find({ text: /\+1 newer/ })).toBeDefined()
  })
})

describe('message', () => {
  test('removes the inline block from the drawing and leaves the prose', async ($, on) => {
    core(on)
    const ui = await $.ui.mount({
      plugin: 'debrief',
      surface: 'terminal',
      component: 'AssistantMessage',
      props: { text: ANSWER, isFirstOfReply: true },
    })
    expect(await ui.find({ text: /debrief → band/ })).toBeUndefined()
    expect(await ui.find({ text: /What changed/ })).toBeUndefined()
    expect(await ui.find({ text: /▤/ })).toBeUndefined()
    expect(await ui.find({ text: /Published: b68ecfc/ })).toBeDefined()
  })
})
