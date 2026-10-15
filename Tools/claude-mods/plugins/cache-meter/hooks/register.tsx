import { atom, read, update } from 'claude-code'
import type { Register } from 'claude-code'

import type { RequestUsage, Totals } from '../types'

const last = atom({ plugin: 'cache-meter', key: 'last' } as const, null)
const totals = atom({ plugin: 'cache-meter', key: 'totals' } as const, { read: 0, write: 0, fresh: 0, requests: 0 })
const lastAt = atom({ plugin: 'cache-meter', key: 'lastAt' } as const, 0)
const now = atom({ plugin: 'cache-meter', key: 'now' } as const, 0)
const isHidden = atom({ plugin: 'cache-meter', key: 'isHidden' } as const, false)

const TICK_MS = 15_000

export const fmtTokens = (n: number): string =>
  n >= 1_000_000 ? `${(n / 1_000_000).toFixed(1)}M` : n >= 1_000 ? `${Math.round(n / 1_000)}k` : String(n)

export const hitRate = (t: Totals): number => {
  const input = t.read + t.write + t.fresh
  return input === 0 ? 0 : Math.round((t.read / input) * 100)
}

/** Seconds of warm cache left after a response at `lastAtMs`, or 0 when cold. */
export const secondsLeft = (lastAtMs: number, nowMs: number, ttlMinutes: number): number =>
  Math.max(0, Math.round((lastAtMs + ttlMinutes * 60_000 - nowMs) / 1000))

export const fmtLeft = (s: number): string =>
  s >= 60 ? `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')} min` : `${s} s`

export const register: Register = (on, options) => {
  const ttl = Number(options.ttl_minutes) === 5 ? 5 : 60

  on('session.start', async ($, e, next) => {
    const started = await $.clock.now()
    await update($, now, () => started)
    $.clock.every(TICK_MS, async () => {
      const t = await $.clock.now()
      await update($, now, () => t)
    })
    await $.command.register({ name: 'cache-meter', description: 'Show or hide the cache meter band' })
    return next(e)
  })

  on('command.run', { command: 'cache-meter' }, async ($, e, next) => {
    const hidden = await update($, isHidden, h => !h)
    return { text: hidden ? 'Cache meter hidden.' : 'Cache meter shown.' }
  })

  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    const u = result.usage
    if (u && e.agentId === undefined) {
      const req: RequestUsage = {
        read: u.cache_read_input_tokens,
        write: u.cache_creation_input_tokens,
        fresh: u.input_tokens,
      }
      const t = await $.clock.now()
      await update($, last, () => req)
      await update($, totals, s => ({
        read: s.read + req.read,
        write: s.write + req.write,
        fresh: s.fresh + req.fresh,
        requests: s.requests + 1,
      }))
      await update($, lastAt, () => t)
      await update($, now, () => t)
    }
    return result
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const req = await read($, last)
    if (e.props.hasSurvey || req === null || (await read($, isHidden))) {
      return next(e)
    }
    const sum = await read($, totals)
    const left = secondsLeft(await read($, lastAt), await read($, now), ttl)
    const { Box, Text } = $.ui.resolve(e)
    const state = left === 0 ? 'cold' : left < 120 ? 'cooling' : 'warm'
    const color = state === 'cold' ? 'red' : state === 'cooling' ? 'yellow' : 'green'

    return (
      <Box>
        <Text dimColor>
          Cache · read {fmtTokens(req.read)} · write {fmtTokens(req.write)} · uncached {fmtTokens(req.fresh)} · hit
          rate {hitRate(sum)}% ({sum.requests} req) ·{' '}
        </Text>
        <Text color={color}>{state === 'cold' ? `cold (${ttl} min TTL)` : `warm ${fmtLeft(left)}`}</Text>
      </Box>
    )
  })
}
