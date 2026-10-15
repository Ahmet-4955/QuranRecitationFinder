import { expect, mock, test } from 'claude-code/testing'

import { fmtLeft, fmtTokens, hitRate, secondsLeft } from './register'

test('formats tokens, hit rate and countdown', async () => {
  expect(fmtTokens(950)).toBe('950')
  expect(fmtTokens(42_400)).toBe('42k')
  expect(fmtTokens(1_250_000)).toBe('1.3M')
  expect(hitRate({ read: 90, write: 5, fresh: 5, requests: 2 })).toBe(90)
  expect(hitRate({ read: 0, write: 0, fresh: 0, requests: 0 })).toBe(0)
  expect(secondsLeft(0, 0, 60)).toBe(3600)
  expect(secondsLeft(1_000, 1_000 + 30 * 60_000, 60)).toBe(1800)
  expect(secondsLeft(1_000, 1_000 + 6 * 60_000, 5)).toBe(0)
  expect(fmtLeft(125)).toBe('2:05 min')
  expect(fmtLeft(42)).toBe('42 s')
})

const BAND = {
  hasSurvey: false,
  isWorking: false,
  maxRows: 1,
  bodyColumns: 120,
  scroll: { offset: 0, bodyRows: 40 },
  view: {},
}

const step = { turnId: 't1', index: 0, model: 'test-model', messageCount: 1 }

test('band shows the last main-thread request and the warm countdown', async ($, on) => {
  mock.clock(on)
  // stands for the engine's own band: an empty box
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box />
  })
  on('turn.step', async function* () {
    return {
      turnId: 't1',
      index: 0,
      answer: 'ok',
      toolUses: [],
      stopReason: 'end_turn' as const,
      usage: {
        model: 'test-model',
        input_tokens: 2_000,
        output_tokens: 100,
        cache_read_input_tokens: 90_000,
        cache_creation_input_tokens: 8_000,
      },
    }
  })

  for (const surface of ['terminal', 'desktop'] as const) {
    const before = await $.ui.mount({ plugin: 'cache-meter', surface, component: 'AbovePrompt', props: BAND })
    expect(await before.find({ type: 'Text', text: /Cache/ })).toBeUndefined()
    await before.unmount()
  }

  for await (const _ of $.turn.step(step)) {
    // drain the stream
  }

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ plugin: 'cache-meter', surface, component: 'AbovePrompt', props: BAND })
    expect(await ui.find({ type: 'Text', text: /read 90k · write 8k · uncached 2k · hit\s+rate 90%/ })).toBeDefined()
    expect(await ui.find({ type: 'Text', text: /warm/ })).toBeDefined()
    await ui.unmount()
  }
})

test('band turns cold once the TTL has passed', { options: { ttl_minutes: '5' } }, async ($, on) => {
  const clock = mock.clock(on)
  on('ui.render', ($, e) => {
    const { Box } = $.ui.resolve(e)
    return <Box />
  })
  on('turn.step', async function* () {
    return {
      turnId: 't1',
      index: 0,
      answer: '',
      toolUses: [],
      stopReason: 'end_turn' as const,
      usage: { model: 'm', input_tokens: 10, output_tokens: 1, cache_read_input_tokens: 0, cache_creation_input_tokens: 500 },
    }
  })
  on('session.start', (_$, e) => ({ ...e }))
  on('command.register', (_$, e) => ({ value: { command: e.name } }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  for await (const _ of $.turn.step(step)) {
    // drain the stream
  }
  const warm = await $.ui.mount({ plugin: 'cache-meter', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  expect(await warm.find({ type: 'Text', text: /warm 5:00 min/ })).toBeDefined()
  await warm.unmount()
  await clock.advance(6 * 60_000)
  for await (const _ of $.turn.step({ ...step, agentId: 'sub-1' })) {
    // a subagent's request must not rewarm the main cache
  }
  const ui = await $.ui.mount({ plugin: 'cache-meter', surface: 'terminal', component: 'AbovePrompt', props: BAND })
  expect(await ui.find({ type: 'Text', text: /\(1 req\)/ })).toBeDefined()
  expect(await ui.find({ type: 'Text', text: /cold \(5 min TTL\)/ })).toBeDefined()
  await ui.unmount()
})
