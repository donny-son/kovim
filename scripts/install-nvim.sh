#!/usr/bin/env bash
# Installs the KoVim Neovim plugin and wires it into the detected plugin manager.
#
# KoVim.app already switches to English on Esc/Ctrl-[ without any plugin.
# This plugin adds reliable restoration of the previous IME (e.g. Korean)
# when you re-enter insert mode — something a global key watcher cannot
# detect on its own.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

step() { echo ""; echo "► $*"; }
ok()   { echo "  ✓ $*"; }
warn() { echo "  ⚠ $*"; }
info() { echo "  · $*"; }

NVIM_SHARE="${XDG_DATA_HOME:-$HOME/.local/share}/nvim"
NVIM_CONFIG="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
PACK_DIR="$NVIM_SHARE/site/pack/kovim/start/kovim"

# lazy.nvim spec, printed to stdout. Uses the absolute install path so it
# works regardless of how the user's config resolves "~".
emit_spec() {
  cat <<EOF
-- KoVim: automatic Korean <-> English IME switching for Vim mode.
-- The plugin files live in Neovim's site/pack directory; this spec just tells
-- lazy.nvim to load them (lazy.nvim does not auto-load site/pack plugins).
return {
  {
    dir = "$PACK_DIR",
    name = "kovim",
    lazy = false, -- load at startup so the InsertEnter autocmd is always armed
    config = function()
      require("kovim").setup {
        -- debug = true, -- uncomment to see IME-switch notifications
      }
    end,
  },
}
EOF
}

step "Installing KoVim Neovim plugin..."

# ── 1. Copy plugin files to the canonical location ──────────────────────────
if [ -d "$PACK_DIR" ]; then
  warn "Removing existing plugin at $PACK_DIR"
  rm -rf "$PACK_DIR"
fi
mkdir -p "$PACK_DIR"
cp -r "$ROOT/nvim/lua"    "$PACK_DIR/lua"
cp -r "$ROOT/nvim/plugin" "$PACK_DIR/plugin"
ok "Plugin files installed at $PACK_DIR"

# ── 2. Wire into the plugin manager ─────────────────────────────────────────
if [ -f "$NVIM_CONFIG/lazy-lock.json" ] || [ -d "$NVIM_SHARE/lazy/lazy.nvim" ]; then
  step "lazy.nvim detected"
  warn "lazy.nvim manages runtimepath itself and does not auto-load site/pack plugins."

  PLUGINS_DIR="$NVIM_CONFIG/lua/plugins"
  SPEC="$PLUGINS_DIR/kovim.lua"

  if [ -f "$SPEC" ]; then
    info "Spec already exists: $SPEC (left untouched)"
  elif [ -d "$PLUGINS_DIR" ]; then
    emit_spec > "$SPEC"
    ok "Wrote lazy.nvim spec: $SPEC"
  else
    warn "Could not find $PLUGINS_DIR — add this spec to your lazy.nvim config:"
    echo ""
    emit_spec | sed 's/^/    /'
  fi
else
  ok "No plugin manager detected — Neovim auto-loads the plugin from site/pack."
  info "It self-initializes via plugin/kovim.lua. To pass options, add to init.lua:"
  info '  require("kovim").setup({ debug = true })'
fi

echo ""
ok "Neovim plugin install complete."
info "Restart Neovim, then run  :KovimHealth  to verify."
