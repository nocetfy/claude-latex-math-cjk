import type { PluginOptions } from 'claude-code'

/** The plugin's options, as the user set them under /plugin, each one checked and in its unit. */
export type Settings = {
  /** auto: pictures where the terminal draws them; on: pictures everywhere; off: Unicode text. */
  images: 'auto' | 'on' | 'off'
  /** How inline math is drawn when pictures are on. */
  inline: 'image' | 'unicode'
  /** Whether Claude is told that this terminal typesets math. */
  promptSection: boolean
  /** The size of display formulas, as a multiple of the default, from 0.5 to 2. */
  scale: number
  /** bold: every formula is set in the bold math fonts, whose strokes are heavier. */
  weight: 'normal' | 'bold'
  /** The height of a terminal cell over its width, from 1 to 3. */
  cellAspect: number
  /** auto, none or a system font's name, for Chinese in formulas. */
  cjkFont: string
  /** How much the Chinese characters in a system font are widened, from 0.5 to 2. */
  cjkStretch: number
  /** The size of the Chinese characters in a system font, from 0.5 to 2. */
  cjkScale: number
  /** The largest size of the picture cache, in bytes. */
  cacheBytes: number
}

function oneOf<T extends string>(value: unknown, choices: readonly T[], fallback: T): T {
  return choices.find(choice => choice === value) ?? fallback
}

function between(value: unknown, low: number, high: number, fallback: number): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.min(high, Math.max(low, value)) : fallback
}

export function readSettings(options: PluginOptions): Settings {
  return {
    images: oneOf(options.images, ['auto', 'on', 'off'], 'auto'),
    inline: oneOf(options.inline, ['image', 'unicode'], 'image'),
    promptSection: options.promptSection !== false,
    scale: between(options.scale, 0.5, 2, 1),
    weight: oneOf(options.weight, ['normal', 'bold'], 'normal'),
    cellAspect: between(options.cellAspect, 1, 3, 2),
    // The name goes into TeX, so it may hold only letters, digits, spaces, dashes and dots.
    cjkFont: typeof options.cjkFont === 'string' && /^[A-Za-z0-9 .-]+$/.test(options.cjkFont.trim()) ? options.cjkFont.trim() : 'auto',
    cjkStretch: between(options.cjkStretch, 0.5, 2, 1.135),
    cjkScale: between(options.cjkScale, 0.5, 2, 0.8),
    cacheBytes: between(options.cacheSizeMB, 1, 10000, 100) * 1024 * 1024,
  }
}
