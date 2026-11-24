#!/bin/zsh
# Builds M.I.S.A. from this folder and installs her into Applications.
#
#   ./install.sh
#
# Options (environment variables):
#   INSTALL_DIR=~/Applications   where to put the app (default: /Applications, or
#                                ~/Applications if that isn't writable)
#   OPEN=0                       don't open her when the install finishes
set -e

HERE="${0:A:h}"
NAME="M.I.S.A..app"
OPEN="${OPEN:-1}"

say() { print -P "%F{yellow}→%f $1"; }
fail() { print -P "%F{red}✗%f $1" >&2; exit 1; }

# 1. macOS 14 (Sonoma) or newer
major="$(sw_vers -productVersion | cut -d. -f1)"
(( major >= 14 )) || fail "M.I.S.A. needs macOS 14 (Sonoma) or newer. This Mac has $(sw_vers -productVersion)."

# 2. Swift compiler (Xcode or the free Command Line Tools)
if ! xcrun --find swift >/dev/null 2>&1; then
  say "Swift isn't installed. Opening Apple's Command Line Tools installer…"
  xcode-select --install 2>/dev/null || true
  fail "Finish installing the Command Line Tools, then run ./install.sh again."
fi
swift_ver=(${(s:.:)"$(swift --version 2>/dev/null | sed -nE 's/.*Swift version ([0-9]+\.[0-9]+).*/\1/p' | head -1)"})
(( ${swift_ver[1]:-0} * 100 + ${swift_ver[2]:-0} >= 510 )) || fail "Swift 5.10 or newer is needed. Update Xcode or the Command Line Tools (Software Update)."

# 3. A JavaScript package manager for the interface: Bun, or npm from Node.js
if [[ -n "$MISA_JS" ]]; then
  JS="$MISA_JS"
elif command -v bun >/dev/null 2>&1; then
  JS=bun
elif command -v npm >/dev/null 2>&1; then
  JS=npm
elif [[ -x "$HOME/.bun/bin/bun" ]]; then
  JS="$HOME/.bun/bin/bun"
else
  print "The interface is built with Bun or Node.js, and neither is installed."
  # Only offer to install when someone is at the terminal (not during a self-update).
  answer=n
  if [[ -t 0 ]]; then
    if command -v brew >/dev/null 2>&1; then
      read "answer?Install Bun with Homebrew now? [Y/n] "
      [[ "$answer" == [nN]* ]] || { brew install oven-sh/bun/bun && answer=done; }
    else
      read "answer?Install Bun now from bun.sh (into ~/.bun)? [Y/n] "
      [[ "$answer" == [nN]* ]] || { curl -fsSL https://bun.sh/install | bash && answer=done; }
    fi
  fi
  if [[ "$answer" == done ]]; then
    JS="$(command -v bun || echo "$HOME/.bun/bin/bun")"
    [[ -x "$JS" ]] || fail "Bun didn't install. Install it from https://bun.sh, then run ./install.sh again."
  else
    fail "Install one, then run ./install.sh again:
    Bun:     https://bun.sh          (or: brew install oven-sh/bun/bun)
    Node.js: https://nodejs.org     (or: brew install node)"
  fi
fi

# Where to install
if [[ -z "$INSTALL_DIR" ]]; then
  if [[ -w /Applications ]]; then INSTALL_DIR=/Applications; else INSTALL_DIR="$HOME/Applications"; fi
fi
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"
mkdir -p "$INSTALL_DIR"

# Build (web interface, then the Swift app, bundled into build/M.I.S.A..app)
say "Building (the first time downloads packages, so it takes a minute or two)"
MISA_JS=$JS zsh "$HERE/scripts/build.sh"

# Install
DEST="$INSTALL_DIR/$NAME"
if pgrep -xq MISA; then
  say "Quitting the running M.I.S.A."
  osascript -e 'tell application id "app.misa.assistant" to quit' >/dev/null 2>&1 || pkill -x MISA || true
  for _ in {1..20}; do pgrep -xq MISA || break; sleep 0.25; done
  pkill -x MISA 2>/dev/null || true
fi
say "Installing to $DEST"
rm -rf "$DEST"
# From the signed copy outside this folder (see scripts/build.sh), without extended attributes.
ditto --noextattr --noqtn "${MISA_STAGE:-$HOME/Library/Caches/app.misa.build}/$NAME" "$DEST"
codesign --verify --strict "$DEST" || fail "The installed app's signature didn't check out. Run ./install.sh again."
# A ZIP downloaded from GitHub is quarantined, which would make macOS refuse to open the app.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

print -P "%F{green}✓%f Installed M.I.S.A. in $INSTALL_DIR"
echo "  Press ⌥Space or click her to chat. Her menu bar icon has Launch at Login and Quit."
echo "  To remove her later: ./uninstall.sh"

[[ "$OPEN" == 1 ]] && open "$DEST"
exit 0
