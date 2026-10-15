/** Token split of one main-thread model request. */
export type RequestUsage = {
  read: number
  write: number
  fresh: number
}

/** Sums over the session's main-thread requests. */
export type Totals = {
  read: number
  write: number
  fresh: number
  requests: number
}

declare module 'claude-code' {
  interface PluginState {
    'cache-meter': {
      last: RequestUsage | null
      totals: Totals
      /** Epoch ms of the last main-thread response with usage; read only once `last` is set. */
      lastAt: number
      /** Epoch ms of the last timer tick, so the countdown redraws. */
      now: number
      isHidden: boolean
    }
  }
}
