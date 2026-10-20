#!/usr/bin/env bash
# Renders one LaTeX math body (stdin) to a transparent PNG sized to whole terminal cells.
# usage: render.sh <cache-dir> <stem> <foreground-rrggbb> [display|inline] [scale] [normal|bold]
#          [cell-aspect] [cjk-font] [cjk-stretch] [cjk-scale]
#        render.sh --check
#        render.sh --preamble
# stdout: "<columns> <rows>"; the PNG is <cache-dir>/<stem>.png. A failure prints the TeX error and exits 1.
# A display formula takes the rows it needs, at scale times the default size (0.5 to 2). An inline
# formula takes one row, with its baseline on the text's. bold sets the formula in the bold math fonts.
# The last four are the plugin options cellAspect, cjkFont, cjkStretch and cjkScale; see below.
# --check prints the tools and LaTeX packages that are missing, and exits 1 when any are.
# --preamble prints the LaTeX preamble of every formula, for tools/commands.py.
#
# The formula is not checked here. LaTeX can read any file the user can, so the caller must pass only
# formulas made of known math commands: hooks/guard.ts does that for the mod.
# LATEX_MATH_RESOLUTION multiplies the pixels in a cell (default 1); the demo renders at 2.4.
set -euo pipefail

# hooks/guard.ts checks a formula against these packages only: it reads backslash commands and ^^.
# A package that makes another character active or a superscript would need a check there too.
preamble() {
  printf '%s\n' '\documentclass[10pt,fleqn]{article}' \
    '\usepackage{amsmath,amssymb,mathtools,bm}' \
    '\setlength{\mathindent}{0pt}\pagestyle{empty}' \
    '\makeatletter\renewcommand{\tagform@}[1]{}\makeatother'
}

if [[ ${1-} == --preamble ]]; then
  preamble
  exit 0
fi

if [[ ${1-} == --check ]]; then
  missing=''
  command -v latex >/dev/null 2>&1 || missing="$missing latex"
  command -v dvipng >/dev/null 2>&1 || missing="$missing dvipng"
  command -v kpsewhich >/dev/null 2>&1 || missing="$missing kpsewhich"
  if ! command -v magick >/dev/null 2>&1 &&
    ! { command -v convert >/dev/null 2>&1 && command -v identify >/dev/null 2>&1; }; then
    missing="$missing magick"
  fi
  if command -v kpsewhich >/dev/null 2>&1; then
    for package in amsmath amssymb mathtools bm preview; do
      [[ -n $(kpsewhich "$package.sty") ]] || missing="$missing $package.sty"
    done
  fi
  echo "${missing# }"
  [[ -z $missing ]] && exit 0
  exit 1
fi

cache=$1 stem=$2 fg=$3 mode=${4:-display} scale=${5:-1} weight=${6:-normal}
aspect=${7:-2} cjk_font=${8:-auto} cjk_stretch=${9:-1.135} cjk_scale=${10:-0.8}
[[ $fg =~ ^[0-9a-fA-F]{6}$ ]] || { echo "not a colour: $fg" >&2; exit 2; }
[[ $scale =~ ^[0-9]+([.][0-9]+)?$ ]] || scale=1
res=${LATEX_MATH_RESOLUTION:-1}
[[ $res =~ ^[0-9]+([.][0-9]+)?$ ]] || res=1
png=$cache/$stem.png cells=$cache/$stem.cells

if [[ -s $png && -s $cells ]]; then
  # The cache drops the least recently used pictures first, so a hit counts as a use.
  touch "$png" "$cells" 2>/dev/null || true
  cat "$cells"
  exit 0
fi

# ImageMagick 7 is one command, magick. ImageMagick 6, as Debian and Ubuntu ship it, is convert and identify.
if command -v magick >/dev/null 2>&1; then
  convert() { magick "$@"; }
  identify() { magick identify "$@"; }
fi

# One cell is CELL_W x CELL_H pixels of the picture; the terminal scales that to its real cell.
# 262 dpi makes 11pt of TeX one row tall, so 10pt math has the x-height of the terminal's text.
# BASELINE is where a monospace font puts its baseline in the cell, in pixels from the top.
# SQUEEZE is how many pixels over whole cells an inline formula is pressed into them.
# The cell aspect is the cell's height over its width (default 2, 1 to 3): Noto Sans Mono, for one,
# has cells of 1 by 2.27, and a picture made for 1 by 2 is drawn about 13% too tall there.
[[ $aspect =~ ^[0-9]+([.][0-9]+)?$ ]] || aspect=2
read -r CELL_W CELL_H DPI PAD_Y BASELINE SQUEEZE < <(LC_ALL=C awk -v r="$res" -v s="$scale" -v m="$mode" -v a="$aspect" 'BEGIN {
  z = (m == "display") ? s : 1; if (z < 0.5) z = 0.5; if (z > 2) z = 2
  if (a < 1) a = 1; if (a > 3) a = 3
  printf "%d %d %d %d %d %d\n", 20 * r + 0.5, 20 * a * r + 0.5, 262 * r * z + 0.5, 4 * r + 0.5, 15.5 * a * r + 0.5, 4 * r + 0.5
}')

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$cache"

# pdfTeX has no font for Chinese. Each run of Chinese or Japanese characters is set as text, and every
# other character stays as it was. A character that the font lacks is an error, so no character is
# dropped or drawn wrong, and a formula without such a run gets the same file as before.
# With a system font, the formula is set by XeLaTeX and the runs in that font: cjk-font names it, and
# auto is PingFang SC on macOS. pdftocairo makes the picture. Without one (none, auto on another
# system, or no xelatex or pdftocairo), each run is set in a CJK environment of CJKutf8, from the
# Arphic font gbsn (TeX Live packages cjk and arphic); its active characters only typeset characters.
# cjk-stretch widens the system font's characters (default 1.135, 0.5 to 2): a terminal that draws a
# picture taller than it is, as one with cells of 1 by 2.27 does at the default cell aspect, makes
# square characters tall, and 1.135 makes them square again there; 1 is for cells of 1 by 2.
# cjk-scale sizes them (default 0.8, 0.5 to 2), to match the terminal's own Chinese text.
[[ $cjk_stretch =~ ^[0-9]+([.][0-9]+)?$ ]] || cjk_stretch=1.135
[[ $cjk_scale =~ ^[0-9]+([.][0-9]+)?$ ]] || cjk_scale=0.8
read -r cjk_stretch cjk_scale < <(LC_ALL=C awk -v s="$cjk_stretch" -v z="$cjk_scale" 'BEGIN {
  if (s < 0.5) s = 0.5; if (s > 2) s = 2; if (z < 0.5) z = 0.5; if (z > 2) z = 2; printf "%.3f %.3f\n", s, z
}')
if [[ $cjk_font == auto ]]; then
  cjk_font=''
  [[ $(uname) != Darwin ]] || cjk_font='PingFang SC'
fi
[[ $cjk_font != none ]] || cjk_font=''
command -v xelatex >/dev/null 2>&1 && command -v pdftocairo >/dev/null 2>&1 || cjk_font=''
cat >"$work/body.tex"
engine=latex packages=''
if [[ -n $(LC_ALL=C tr -d '\000-\177' <"$work/body.tex") ]]; then
  # $1 is perl's, so the quotes keep the shell from expanding it.
  # shellcheck disable=SC2016
  if [[ -n $cjk_font ]]; then
    wrap='{\\text{\\cjkfont $1}}'
  else
    wrap='{\\text{\\begin{CJK}{UTF8}{gbsn}$1\\end{CJK}}}'
  fi
  if perl -CSD -pe 's/([\p{Han}\p{Hiragana}\p{Katakana}\x{3000}-\x{303F}\x{FF00}-\x{FFEF}]+)/'"$wrap"'/g' \
    <"$work/body.tex" >"$work/cjk.tex" && ! cmp -s "$work/body.tex" "$work/cjk.tex"; then
    mv "$work/cjk.tex" "$work/body.tex"
    if [[ -n $cjk_font ]]; then
      engine=xelatex
      # The name goes into TeX, so it may hold only letters, digits, spaces, dashes and dots.
      [[ $cjk_font =~ ^[A-Za-z0-9\ .-]+$ ]] || { echo "not a font name: $cjk_font" >&2; exit 2; }
      packages="\\usepackage{fontspec,xcolor}\\tracinglostchars=3\\newfontfamily\\cjkfont[FakeStretch=$cjk_stretch,Scale=$cjk_scale]{$cjk_font}"
    else
      packages='\usepackage{CJKutf8}\tracinglostchars=3'
    fi
  fi
fi

{
  preamble
  # The bold math version changes the fonts and no command, so the check in hooks/guard.ts holds for it.
  if [[ $weight == bold ]]; then
    printf '%s\n' '\AtBeginDocument{\boldmath}'
  fi
  [[ -z $packages ]] || printf '%s\n' "$packages"
  if [[ $engine == xelatex && $mode == inline ]]; then
    # The box's height and depth go to the log; the 4pt border keeps ink that leaves the box.
    printf '%s\n' '\usepackage[active,tightpage]{preview}\setlength{\PreviewBorder}{4pt}' \
      '\begin{document}\sbox0{\color[HTML]{'"$fg"'}'
    cat "$work/body.tex"
    printf '%s\n' '}\typeout{MATHBOX \the\ht0/\the\dp0}\begin{preview}\usebox0\end{preview}\end{document}'
  elif [[ $mode == inline ]]; then
    # preview's tight page is what lets dvipng report the formula's height and depth.
    printf '%s\n' '\usepackage[active,tightpage]{preview}\setlength{\PreviewBorder}{0pt}' \
      '\begin{document}\begin{preview}'
    cat "$work/body.tex"
    printf '%s\n' '\end{preview}\end{document}'
  else
    printf '%s\n' '\begin{document}'
    [[ $engine == latex ]] || printf '%s\n' '\color[HTML]{'"$fg"'}'
    cat "$work/body.tex"
    printf '\n%s\n' '\end{document}'
  fi
} >"$work/f.tex"

# A formula that never ends is stopped after 20 seconds. macOS has no timeout unless coreutils is
# installed, and then it is gtimeout.
if command -v timeout >/dev/null 2>&1; then
  run_latex() { timeout 20 "$engine" "$@"; }
  run_dvipng() { timeout 20 dvipng "$@"; }
elif command -v gtimeout >/dev/null 2>&1; then
  run_latex() { gtimeout 20 "$engine" "$@"; }
  run_dvipng() { gtimeout 20 dvipng "$@"; }
else
  run_latex() { "$engine" "$@"; }
  run_dvipng() { dvipng "$@"; }
fi

# No shell escape, and writes only in the work folder. openin_any limits reads only before
# TeX Live 2026, where it became a no-op.
if ! (cd "$work" && export openin_any=p openout_any=p &&
  run_latex -no-shell-escape -interaction=nonstopmode -halt-on-error f.tex >/dev/null 2>&1); then
  # TeX writes a missing character as its raw byte, which is not UTF-8, so tr reads bytes.
  { grep -m1 -A1 '^!' "$work/f.log" 2>/dev/null || echo "$engine did not run"; } | LC_ALL=C tr '\n' ' ' >&2
  exit 1
fi

if [[ $engine == xelatex ]]; then
  if ! pdftocairo -png -singlefile -transp -r "$DPI" "$work/f.pdf" "$work/raw" >"$work/dvipng.log" 2>&1; then
    head -c 300 "$work/dvipng.log" >&2
    exit 1
  fi
  # The crop to the ink, as dvipng -T tight does it.
  read -r tw th tx ty < <(identify -format '%@\n' "$work/raw.png" | tr 'x+' '  ')
  convert "$work/raw.png" -crop "${tw}x${th}+${tx}+${ty}" +repage "PNG32:$work/f.png"
  if [[ $mode == inline ]]; then
    # The baseline is the border and the box's height below the page's top; 72.27 TeX points are an inch.
    read -r bh _ < <(sed -n 's|^MATHBOX \([0-9.]*\)pt/\([0-9.]*\)pt.*|\1 \2|p' "$work/f.log")
    [[ -n ${bh-} ]] || { echo 'xelatex reported no box' >&2; exit 1; }
    LC_ALL=C awk -v h="$bh" -v dpi="$DPI" -v ty="$ty" -v th="$th" 'BEGIN {
      b = int((4 + h) * dpi / 72.27 + 0.5); printf "depth=%d height=%d\n", ty + th - b, b - ty
    }' >"$work/dvipng.log"
  fi
else
  color=$(LC_ALL=C awk -v r=$((16#${fg:0:2})) -v g=$((16#${fg:2:2})) -v b=$((16#${fg:4:2})) \
    'BEGIN { printf "rgb %.3f %.3f %.3f", r / 255, g / 255, b / 255 }')
  if ! run_dvipng -D "$DPI" -T tight --depth --height --truecolor --nogs -bg Transparent -fg "$color" \
    -o "$work/f.png" "$work/f.dvi" >"$work/dvipng.log" 2>&1; then
    head -c 300 "$work/dvipng.log" >&2
    exit 1
  fi
fi

read -r w h < <(identify -format '%w %h\n' "$work/f.png")
# 255 cells is the most the terminal draws in either direction.
if ((w > 255 * CELL_W || h > 255 * CELL_H)); then
  echo "the formula is too large: $w x $h pixels" >&2
  exit 1
fi
if [[ $mode == inline ]]; then
  [[ $(<"$work/dvipng.log") =~ depth=([0-9]+)\ height=([0-9]+) ]] || { echo 'dvipng reported no baseline' >&2; exit 1; }
  depth=${BASH_REMATCH[1]} height=${BASH_REMATCH[2]}
  # A formula taller than the row is scaled to fit it. The baseline moves off the text's only when
  # the part above or below it needs more room than the font leaves there. A width up to SQUEEZE
  # pixels over whole cells is pressed into them, so a single letter takes one cell and not two.
  read -r percent columns x y < <(LC_ALL=C awk -v w="$w" -v h="$height" -v d="$depth" \
    -v cw="$CELL_W" -v ch="$CELL_H" -v base="$BASELINE" -v squeeze="$SQUEEZE" 'BEGIN {
      s = (h + d > ch) ? ch / (h + d) : 1
      hs = h * s; ds = d * s; ws = int(w * s + 0.5); if (ws < 1) ws = 1
      b = base; if (b > ch - ds) b = ch - ds; if (b < hs) b = hs
      c = int((ws + cw - 1 - squeeze) / cw); if (c < 1) c = 1
      if (ws > c * cw) { s = s * c * cw / ws; hs = h * s; ws = c * cw }
      printf "%.2f %d %d %d\n", s * 100, c, int((c * cw - ws) / 2), int(b - hs + 0.5)
    }')
  rows=1
  convert "$work/f.png" -resize "$percent%" -background none -gravity northwest \
    -extent "$((columns * CELL_W))x${CELL_H}-${x}-${y}" "PNG32:$work/padded.png"
else
  columns=$(((w + CELL_W - 1) / CELL_W))
  rows=$(((h + 2 * PAD_Y + CELL_H - 1) / CELL_H))
  convert "$work/f.png" -background none -gravity west \
    -extent "$((columns * CELL_W))x$((rows * CELL_H))" "PNG32:$work/padded.png"
fi

# Both files land by rename, so a reader never sees half of one.
echo "$columns $rows" >"$work/f.cells"
mv "$work/padded.png" "$png"
mv "$work/f.cells" "$cells"
echo "$columns $rows"
