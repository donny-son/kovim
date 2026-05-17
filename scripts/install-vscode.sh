#!/usr/bin/env bash
# Builds the KoVim VSCode extension and installs it for local use.
#
# The extension only uses the 'vscode' API and Node built-ins, so it needs no
# runtime node_modules — it is installed as a plain folder under
# ~/.vscode/extensions, with no .vsix packaging or publisher account required.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VSCODE_SRC="$ROOT/vscode"

step() { echo ""; echo "► $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }
info() { echo "  · $*"; }
die()  { echo "  ✗ $*" >&2; exit 1; }

command -v npm >/dev/null 2>&1 || die "npm not found — install Node.js (https://nodejs.org) first."

# ── 1. Build ────────────────────────────────────────────────────────────────
step "Building KoVim VSCode extension..."
cd "$VSCODE_SRC"
npm install --silent
npm run compile
[ -f "$VSCODE_SRC/out/extension.js" ] || die "Compile produced no out/extension.js"
ok "Compiled to out/extension.js"

# ── 2. Install into the VSCode extensions folder ────────────────────────────
step "Installing extension..."
VERSION="$(node -p "require('$VSCODE_SRC/package.json').version")"
PUBLISHER="$(node -p "require('$VSCODE_SRC/package.json').publisher")"
NAME="$(node -p "require('$VSCODE_SRC/package.json').name")"
DEST="$HOME/.vscode/extensions/${PUBLISHER}.${NAME}-${VERSION}"

if [ -d "$DEST" ]; then
  warn "Replacing existing $DEST"
  rm -rf "$DEST"
fi
mkdir -p "$DEST"
cp -r "$VSCODE_SRC/out"          "$DEST/out"
cp    "$VSCODE_SRC/package.json" "$DEST/package.json"
ok "Installed to $DEST"

# ── 3. Check VSCodeVim ──────────────────────────────────────────────────────
if command -v code >/dev/null 2>&1; then
  if code --list-extensions 2>/dev/null | grep -qi '^vscodevim.vim$'; then
    ok "VSCodeVim is installed"
  else
    warn "VSCodeVim is not installed — KoVim needs it for mode-aware switching."
    info "Install it with:  code --install-extension vscodevim.vim"
  fi
else
  info "'code' CLI not found — make sure the VSCodeVim extension is installed."
fi

echo ""
ok "VSCode extension install complete."
info "Reload VSCode (Cmd+Shift+P → 'Developer: Reload Window') to activate KoVim."
info "The status bar shows '⌨︎ KoVim' when connected to the agent."
