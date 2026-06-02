#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KOVIM_BIN_DIR="$HOME/.local/bin"

echo "=== KoVim Installer ==="
echo ""

# ─── helpers ─────────────────────────────────────────────────────────────────

step() { echo ""; echo "► $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }

# ─── 1. Build binaries ───────────────────────────────────────────────────────

step "Building kovim-agent and kovim CLI..."
cd "$ROOT"
bash "$ROOT/scripts/build-app.sh"
ok "App bundle: $ROOT/.build/KoVim.app"

# ─── 2. Install kovim CLI ────────────────────────────────────────────────────

step "Installing kovim CLI → $KOVIM_BIN_DIR/kovim"
mkdir -p "$KOVIM_BIN_DIR"
cp "$ROOT/.build/release/kovim" "$KOVIM_BIN_DIR/kovim"
chmod +x "$KOVIM_BIN_DIR/kovim"
# Backward-compat alias for older callers that still invoke `kovim-im`.
ln -sf "kovim" "$KOVIM_BIN_DIR/kovim-im"
ok "kovim installed (kovim-im kept as an alias)"

if ! echo "$PATH" | grep -q "$KOVIM_BIN_DIR"; then
  warn "$KOVIM_BIN_DIR is not in your PATH."
  warn "Add this to your shell profile:"
  warn "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

# ─── 3. Install Neovim plugin ────────────────────────────────────────────────

bash "$ROOT/scripts/install-nvim.sh"

# ─── 4. macOS app ────────────────────────────────────────────────────────────

step "Installing macOS app → /Applications/KoVim.app"
if [ -d "/Applications/KoVim.app" ]; then
  warn "Replacing existing /Applications/KoVim.app"
  rm -rf "/Applications/KoVim.app"
fi
cp -r "$ROOT/.build/KoVim.app" "/Applications/KoVim.app"
ok "Installed to /Applications/KoVim.app"

# ─── 5. Launch agent ─────────────────────────────────────────────────────────

step "Launching KoVim agent..."

# Check if already running
if pgrep -x "KoVim" > /dev/null 2>&1; then
  warn "KoVim agent is already running. Restarting..."
  pkill -x "KoVim" || true
  sleep 1
fi

open "/Applications/KoVim.app"
ok "KoVim agent launched"

# ─── 6. macOS permissions reminder ──────────────────────────────────────────

echo ""
echo "┌─────────────────────────────────────────────────────────────────┐"
echo "│  macOS Permissions Required                                     │"
echo "│                                                                 │"
echo "│  On first launch, macOS will ask for two permissions:           │"
echo "│                                                                 │"
echo "│  1. Accessibility                                               │"
echo "│     System Settings → Privacy & Security → Accessibility       │"
echo "│     Enable KoVim                                               │"
echo "│                                                                 │"
echo "│  2. Input Monitoring                                            │"
echo "│     System Settings → Privacy & Security → Input Monitoring    │"
echo "│     Enable KoVim                                               │"
echo "│                                                                 │"
echo "│  After enabling both, KoVim will restart automatically.        │"
echo "│                                                                 │"
echo "│  The ⌨︎ KoVim icon will appear in your menu bar when ready.   │"
echo "└─────────────────────────────────────────────────────────────────┘"

# ─── 7. VSCode extension (optional) ──────────────────────────────────────────

echo ""
echo "────────────────────────────────────────────────────────────────────"
echo "  VSCode extension (optional)"
echo "────────────────────────────────────────────────────────────────────"
echo "  Using VSCode + VSCodeVim? Install the KoVim extension with:"
echo ""
echo "    bash scripts/install-vscode.sh"
echo ""
echo "  Neovim users can ignore this — the plugin is already installed."
echo "────────────────────────────────────────────────────────────────────"
echo ""
echo "=== Done! ==="
