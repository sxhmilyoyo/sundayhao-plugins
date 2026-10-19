export type Rung = { label: string; value: string }

export type Actor = 'you' | 'me' | 'pending' | 'blocked' | 'none' | 'other'

export type Step = { actor: Actor; text: string }

export type Debrief = {
  turn: number
  at: number
  rungs: Rung[]
  next: Step[]
  raw: string
}

declare module 'claude-code' {
  interface PluginState {
    debrief: { last: Debrief | null; pinned: Debrief | null; newer: number; turn: number }
  }
}
