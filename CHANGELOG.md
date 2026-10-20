# Changelog

## Unreleased

### Added

- On macOS, with `xelatex` and `pdftocairo`, Chinese in a formula is set by XeLaTeX in PingFang SC. The `cjkFont` option names another font, or keeps `gbsn` with `none`.
- The `cellAspect` option sets the cell's height over its width (default 2), for terminal fonts whose cells are not 1 by 2.
- The `cjkStretch` option widens the Chinese characters set in a system font, and `cjkScale` sizes them (defaults 1.135 and 0.8, for a terminal font like Noto Sans Mono). These options and `cellAspect` are part of the picture's file name.

## 0.4.0-cjk.1 (2026-10-20)

### Added

- Chinese and Japanese text in a formula is typeset with `CJKutf8` and the Arphic font `gbsn`. Each run of such characters is wrapped in its own `CJK` environment; a formula without them gets the same file as before.
- A LaTeX error that names a missing character no longer breaks the error message: `tr` reads it as bytes.

## 0.4.0 (2026-10-11)

### Added

- The `weight` option in `/config`. `bold` sets every formula in the bold math fonts (`\boldmath`), whose strokes are easier to read on a dark background. A bold picture has a cache file of its own.

### Fixed

- Formulas sometimes came out white next to coloured text. When Claude Code abandoned a draw while the mod was reading the terminal's colour, the mod took white and kept it for 5 seconds. A colour read that fails or is cut short now leaves the last colour in place, and the next draw reads the colour again.

## 0.3.0 (2026-10-04)

### Security

- The mod renders a formula only when every command in it is on a list of math commands (`hooks/commands.ts`). Before, any formula went to LaTeX, and LaTeX can read every file that the user can read. A formula with another command now shows as its source, with the reason.
- `tools/commands.py` builds the list and probes it: each listed command is called with a canary command name and a canary file in every argument position. CI runs the probe.
- `dvipng` runs with Ghostscript off and stops after 20 seconds. A picture larger than 255 terminal cells in either direction is refused.

### Fixed

- The README and SECURITY.md said that the `openin_any` setting stops a formula from reading files. TeX Live 2026 made that setting a no-op. The documents now describe the command list.

### Changed

- The system prompt section asks Claude to use only the commands of LaTeX and amsmath.
- The line under a formula that is not rendered starts with `not rendered:`.
- The notice about missing tools points to the README and has no link.
- The README says what each hook changes, which programs the mod runs, and what it reads and sends.

## 0.2.0 (2026-10-04)

### Added

- Options in `/config`: `images`, `inline`, `promptSection`, `scale` and `cacheSizeMB`.
- Math as Unicode text in terminals without the kitty graphics protocol, inside tmux or screen, and in background sessions, where Claude Code draws no images. A display formula that Unicode cannot hold becomes a LaTeX code block.
- One notice at the start of a session when the renderer misses a tool or a LaTeX package. Math is then Unicode text.
- Images over SSH: the mod sends the PNG bytes, because the terminal cannot read files on the remote machine.
- A limit on the image cache. When a session starts in the terminal, the least recently used images are deleted until the cache is under `cacheSizeMB`. A deleted image that a session still shows is rendered again.
- A limit of 60 different formulas typeset per reply. A reply that needs more is written as Unicode text.
- `bin/render.sh --check`, which lists the missing tools and LaTeX packages.
- Support for ImageMagick 6, as Debian and Ubuntu ship it.
- CI: `claude plugin validate`, `claude plugin test`, `shellcheck`, and a test of the renderer on real formulas on Ubuntu 24.04.
- PRIVACY.md, SECURITY.md, and sections in the README on settings, troubleshooting, privacy, support, and what the mod runs, reads and sends.
- A plugin icon: a typeset sum and a terminal prompt.

### Changed

- The system prompt section is added only when the mod draws images.
- The mod reads only the `theme` row of `/config`, not the whole settings object.
- The demo renders with `bin/render.sh` at a higher resolution, instead of a copy of the script.

## 0.1.0 (2026-10-04)

- First version: display and inline LaTeX math as images through the kitty graphics protocol, in the text colour of the Claude Code theme.
