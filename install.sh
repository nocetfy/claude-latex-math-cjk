#!/usr/bin/env bash
# Installs the latex-math plugin of this repository and everything it needs: TeX Live (latex,
# dvipng), the LaTeX packages it uses, the CJK packages and Arphic font for Chinese, and ImageMagick.
# Then it adds this repository as a plugin marketplace, installs the plugin, sets the terminal
# options, and renders one formula with Chinese in it to prove the setup works.
#
# usage: ./install.sh [options]
#   --check            only report what is missing; change nothing
#   --images <mode>    auto | on | off (default: picked from the terminal)
#   --source <src>     marketplace source for `claude plugin marketplace add`
#                      (default: this clone's GitHub origin, else this folder)
#   --skip-deps        do not install system software
#   --skip-plugin      do not touch Claude Code plugins or settings
#   -h, --help
#
# It is safe to run again. It runs without a terminal (from an agent): a command that needs root
# uses sudo without a password when it can, a password dialog on macOS, and otherwise stops and
# prints the command to run by hand.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
MARKET=claude-latex-math-cjk
ID=latex-math@$MARKET
OTHER=latex-math@claude-latex-math # the same mod from its original marketplace
check=0 images='' source='' skip_deps=0 skip_plugin=0

while (($#)); do
  case $1 in
    --check) check=1 ;;
    --images) images=${2:?}; shift ;;
    --source) source=${2:?}; shift ;;
    --skip-deps) skip_deps=1 ;;
    --skip-plugin) skip_plugin=1 ;;
    -h | --help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
case $images in '' | auto | on | off) ;; *) echo "--images takes auto, on or off" >&2; exit 2 ;; esac

failures=()
say() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
ok() { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*"; failures+=("$*"); }
have() { command -v "$1" >/dev/null 2>&1; }

os=$(uname -s)
pm=''
if [[ $os == Darwin ]]; then pm=brew
elif have apt-get; then pm=apt
elif have pacman; then pm=pacman
elif have dnf; then pm=dnf
fi

# TeX installed by BasicTeX or the TeX Live installer may not be on PATH yet in this shell.
for d in /Library/TeX/texbin /usr/local/texlive/*/bin/*; do
  [[ -d $d && :$PATH: != *:$d:* ]] && PATH=$PATH:$d
done
[[ -x /opt/homebrew/bin/brew && :$PATH: != *:/opt/homebrew/bin:* ]] && PATH=/opt/homebrew/bin:$PATH
export PATH

# ---------- running as root ----------------------------------------------------------------------

askpass=''
cleanup() { [[ -z $askpass ]] || rm -f "$askpass"; }
trap cleanup EXIT

# On macOS without a terminal, sudo (and Homebrew, which honours SUDO_ASKPASS) asks through a dialog.
setup_askpass() {
  [[ $os == Darwin && -z $askpass && ! -t 0 ]] || return 0
  askpass=$(mktemp -t latex-askpass)
  cat >"$askpass" <<'EOF'
#!/bin/bash
exec osascript -e 'display dialog "claude-latex-math-cjk install.sh needs an administrator password to install TeX." default answer "" with hidden answer with title "Administrator password" buttons {"Cancel", "OK"} default button "OK"' -e 'text returned of result'
EOF
  chmod 700 "$askpass"
  export SUDO_ASKPASS=$askpass
}

as_root() {
  if [[ $(id -u) == 0 ]]; then "$@"
  elif sudo -n true 2>/dev/null; then sudo "$@"
  elif [[ -t 0 ]]; then sudo "$@"
  elif [[ $os == Darwin ]]; then setup_askpass; sudo -A "$@"
  else
    bad "needs root; run this by hand, then run install.sh again: sudo $*"
    return 1
  fi
}

# ---------- TeX, ImageMagick ---------------------------------------------------------------------

tex_packages=(amsmath amssymb mathtools bm preview CJKutf8)

missing_deps() {
  local m=()
  for t in latex dvipng kpsewhich perl; do have "$t" || m+=("$t"); done
  have magick || { have convert && have identify; } || m+=(imagemagick)
  if have kpsewhich; then
    for p in "${tex_packages[@]}"; do [[ -n $(kpsewhich "$p.sty") ]] || m+=("$p.sty"); done
    [[ -n $(kpsewhich c70gbsn.fd) ]] || m+=(gbsn-font)
  fi
  echo "${m[*]-}"
}

install_deps() {
  say 'TeX Live, CJK packages, ImageMagick'
  local missing
  missing=$(missing_deps)
  if [[ -z $missing ]]; then ok 'all present'; return 0; fi
  warn "missing: $missing"
  ((check)) && return 0
  case $pm in
    brew)
      have brew || { bad 'Homebrew not found; install it from https://brew.sh and run again'; return 0; }
      if ! have latex; then
        setup_askpass
        brew install --cask basictex || { bad 'brew install --cask basictex failed'; return 0; }
        PATH=$PATH:/Library/TeX/texbin
      fi
      have magick || brew install imagemagick
      # BasicTeX ships tlmgr; an old tlmgr refuses to install until it updates itself.
      local pk=(dvipng preview mathtools cjk arphic)
      as_root tlmgr install "${pk[@]}" ||
        { as_root tlmgr update --self && as_root tlmgr install "${pk[@]}"; } ||
        bad 'tlmgr install failed'
      ;;
    apt)
      as_root apt-get update -qq || true
      as_root apt-get install -y texlive-latex-recommended dvipng preview-latex-style \
        latex-cjk-chinese latex-cjk-chinese-arphic-gbsn00lp imagemagick perl || bad 'apt-get install failed'
      ;;
    pacman)
      as_root pacman -S --needed --noconfirm texlive-bin texlive-basic texlive-latex texlive-latexrecommended \
        texlive-latexextra texlive-langchinese imagemagick perl || bad 'pacman -S failed'
      ;;
    dnf)
      as_root dnf install -y texlive-scheme-basic texlive-dvipng texlive-preview texlive-mathtools \
        texlive-cjk texlive-arphic ImageMagick perl || bad 'dnf install failed'
      ;;
    *)
      bad 'no supported package manager; install by hand: TeX Live with dvipng, preview, mathtools, cjk, arphic; ImageMagick; perl'
      ;;
  esac
  hash -r
  missing=$(missing_deps)
  if [[ -z $missing ]]; then ok 'installed'; else bad "still missing: $missing"; fi
  return 0
}

# fish configs often set PATH outright, which drops /etc/paths.d (where BasicTeX puts itself).
fix_fish_path() {
  [[ $os == Darwin && -d /Library/TeX/texbin ]] || return 0
  have fish || return 0
  local cfg=${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish
  fish -l -c 'command -v latex' >/dev/null 2>&1 && return 0
  if ((check)); then
    warn 'fish does not see /Library/TeX/texbin; Claude Code started from fish will not find latex'
    return 0
  fi
  mkdir -p "$(dirname "$cfg")"
  # shellcheck disable=SC2016 # a fish line, expanded by fish
  printf '\n# Added by claude-latex-math-cjk install.sh: TeX for the latex-math plugin.\n%s\n' \
    'test -d /Library/TeX/texbin; and contains /Library/TeX/texbin $PATH; or set -x PATH $PATH /Library/TeX/texbin' >>"$cfg"
  ok "added /Library/TeX/texbin to $cfg (restart the terminal)"
}

# ---------- Claude Code --------------------------------------------------------------------------

CLAUDE=$(command -v claude 2>/dev/null || true)
[[ -n $CLAUDE ]] || CLAUDE=$HOME/.local/bin/claude

# Prints the install path of plugin id $1, empty when it is not installed.
plugin_path() {
  "$CLAUDE" plugin list --json 2>/dev/null | node -e '
    let s = ""; process.stdin.on("data", d => s += d).on("end", () => {
      const p = JSON.parse(s).find(p => p.id === process.argv[1]); if (p) console.log(p.installPath) })' "$1" 2>/dev/null || true
}

# set_env KEY VALUE: writes env.KEY into ~/.claude/settings.json.
set_env() {
  mkdir -p "$HOME/.claude"
  node -e '
    const fs = require("fs"), [f, k, v] = process.argv.slice(1)
    const s = fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, "utf8")) : {}
    if ((s.env ??= {})[k] === v) process.exit(0)
    s.env[k] = v
    fs.writeFileSync(f, JSON.stringify(s, null, 2) + "\n")' "$HOME/.claude/settings.json" "$1" "$2"
}

pick_images() {
  [[ -n $images ]] && return 0
  case ${TERM_PROGRAM:-}:${TERM:-} in
    ghostty:* | *:xterm-kitty | *:xterm-ghostty) images=auto ;;
    otty:* | WezTerm:*) images=on ;; # kitty graphics, but not recognised by the plugin
    *) images=auto ;;
  esac
  [[ -z ${KITTY_WINDOW_ID:-} ]] || images=auto
}

install_plugin() {
  say 'Claude Code plugin'
  [[ -x $CLAUDE ]] || have claude || { bad 'claude CLI not found'; return 0; }
  have node || { bad 'node is needed to read and edit Claude Code settings'; return 0; }
  if ((check)); then
    if [[ -n $(plugin_path "$ID") ]]; then ok "$ID installed"; else warn "$ID not installed"; fi
    [[ -z $(plugin_path "$OTHER") ]] || warn "another copy, $OTHER, is installed too"
    return 0
  fi

  if [[ -z $source ]]; then
    local url
    url=$(git -C "$here" remote get-url origin 2>/dev/null || true)
    if [[ $url =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then source=${BASH_REMATCH[1]}; else source=$here; fi
  fi
  if "$CLAUDE" plugin marketplace list 2>/dev/null | grep -q "$MARKET"; then
    "$CLAUDE" plugin marketplace update "$MARKET" >/dev/null && ok "marketplace $MARKET updated"
  else
    if "$CLAUDE" plugin marketplace add "$source" >/dev/null; then ok "marketplace $MARKET added from $source"
    else bad "claude plugin marketplace add $source failed"; return 0
    fi
  fi

  # Two copies of the mod would both rewrite each reply.
  if [[ -n $(plugin_path "$OTHER") ]]; then
    "$CLAUDE" plugin uninstall "$OTHER" >/dev/null && ok "uninstalled $OTHER (this plugin replaces it)"
  fi

  pick_images
  if [[ -n $(plugin_path "$ID") ]]; then
    "$CLAUDE" plugin update "$ID" >/dev/null 2>&1 || true
    printf '{"images":"%s"}' "$images" | "$CLAUDE" plugin configure "$ID" --values-stdin >/dev/null
    "$CLAUDE" plugin enable "$ID" >/dev/null 2>&1 || true
    ok "$ID already installed; updated"
  else
    if "$CLAUDE" plugin install "$ID" --config "images=$images" >/dev/null; then ok "$ID installed"
    else bad "claude plugin install $ID failed"; return 0
    fi
  fi
  ok "images=$images"
  # Claude Code itself draws no pictures in a terminal it does not recognise unless told to.
  if [[ $images == on ]]; then
    set_env CLAUDE_CODE_FORCE_TERMINAL_IMAGES 1 && ok 'settings.json env CLAUDE_CODE_FORCE_TERMINAL_IMAGES=1'
  fi
  return 0
}

verify() {
  say 'Test render'
  local tmp root out
  tmp=$(mktemp -d)
  root=$(plugin_path "$ID")
  [[ -n $root ]] || root=$here
  if out=$(printf '%s' '\[ \text{补偿金额} = \sum_{i=1}^{n} \alpha_i x_i \le C \]' |
    bash "$root/bin/render.sh" "$tmp" cjk 000000 display 2>&1); then
    ok "formula with Chinese rendered ($out cells): $tmp/cjk.png"
  else
    bad "render failed: $out"
  fi
}

# ---------- main ---------------------------------------------------------------------------------

if ((check || !skip_deps)); then install_deps; fix_fish_path; fi
((skip_plugin)) || install_plugin
((check)) || verify

echo
if ((${#failures[@]})); then
  say "Finished with ${#failures[@]} problem(s):"
  printf '  - %s\n' "${failures[@]}"
  exit 1
fi
if ((check)); then say 'Check done.'
else say 'Done. Start a new Claude Code session (or run /reload-plugins) to load the plugin.'
fi
