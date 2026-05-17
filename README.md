# KoVim

> Automatic Korean ↔ English IME switching for Korean–English Vim users on macOS.

Fixes the most common frustration when writing Korean in Vim:

```
Korean insert mode → press Esc → normal-mode keys (hjkl, w, :, /) work immediately
Enter insert mode → previous Korean IME restored automatically
```

---

## How it works

```
┌─────────────────────────────────────────────────────────┐
│  KoVim.app  (macOS menu bar agent)                      │
│                                                         │
│  • Global Esc / Ctrl-[ watcher (all terminals + VSCode) │
│  • macOS IME controller (TIS APIs)                      │
│  • Local HTTP API  http://127.0.0.1:57321               │
└──────────────────┬──────────────────┬───────────────────┘
                   │                  │
         ┌─────────┘                  └──────────┐
         ▼                                       ▼
 ┌───────────────┐                   ┌─────────────────────┐
 │ Neovim plugin │                   │  VSCode extension   │
 │  (Lua)        │                   │  (TypeScript)       │
 │               │                   │                     │
 │ InsertLeave   │                   │ Esc / Ctrl-[        │
 │   → /mode/normal                  │   → /mode/normal    │
 │ InsertEnter   │                   │ i / a / o / s / c   │
 │   → /mode/insert                  │   → /mode/insert    │
 └───────────────┘                   └─────────────────────┘
```

### MVP coverage

Even without any editor plugin, the global key watcher alone handles:

| Scenario | Works |
|---|---|
| Neovim in iTerm2, Terminal, Warp, Alacritty, WezTerm, Kitty | ✓ |
| VSCode + VSCodeVim | ✓ |
| Neovim over SSH in any of those terminals | ✓ |

Editor plugins add reliable **insert-mode restoration** (restoring Korean when you press `i`/`a`/`o`).

---

## Install

```bash
git clone https://github.com/yourname/kovim.git
cd kovim
bash scripts/install.sh
```

This will:

1. Build `KoVim.app` and `kovim-im` CLI
2. Install `kovim-im` to `~/.local/bin/`
3. Install the Neovim plugin and wire it into your plugin manager (see below)
4. Copy `KoVim.app` to `/Applications/`
5. Launch the agent

The VSCode extension is **not** installed by `install.sh` — run
[`scripts/install-vscode.sh`](#vscode-extension) separately if you use VSCode.

### Editor plugins are optional

`KoVim.app` on its own already switches to **English on `Esc` / `Ctrl-[`** in
every supported terminal and in VSCode — no plugin required. The editor plugins
add exactly one thing: restoring your **previous IME (e.g. Korean) when you
re-enter insert mode**, which a global key watcher cannot detect reliably.

### macOS permissions

After the first launch, two permissions are required:

| Permission | Where |
|---|---|
| **Accessibility** | System Settings → Privacy & Security → Accessibility |
| **Input Monitoring** | System Settings → Privacy & Security → Input Monitoring |

Enable both for KoVim, then the ⌨︎ KoVim icon will appear in your menu bar.

---

## Neovim plugin

### Install

`scripts/install.sh` installs the plugin for you. To (re)install it on its own:

```bash
bash scripts/install-nvim.sh
```

This copies the plugin to `~/.local/share/nvim/site/pack/kovim/start/kovim`, then:

- **lazy.nvim detected** → writes a spec to `~/.config/nvim/lua/plugins/kovim.lua`.
  lazy.nvim manages its own runtimepath and does **not** auto-load `site/pack`
  plugins, so this step is required — without it `setup()` never runs.
- **No plugin manager** → Neovim auto-loads the plugin from `site/pack`; it
  self-initializes via `plugin/kovim.lua`, nothing else to do.

Restart Neovim, then run `:KovimHealth` to verify the autocmds and agent.

### Manual plugin-manager setup

If the installer can't locate your config, add the plugin yourself.

**lazy.nvim** — create `~/.config/nvim/lua/plugins/kovim.lua`:

```lua
return {
  {
    dir = vim.fn.expand("~/.local/share/nvim/site/pack/kovim/start/kovim"),
    name = "kovim",
    lazy = false,
    config = function()
      require("kovim").setup()
    end,
  },
}
```

**packer.nvim:**

```lua
use {
  "~/.local/share/nvim/site/pack/kovim/start/kovim",
  as = "kovim",
  config = function() require("kovim").setup() end,
}
```

**No plugin manager** — nothing to add; the plugin auto-loads. To pass options,
put `require("kovim").setup({ ... })` in your `init.lua`.

### Options

```lua
require("kovim").setup({
  endpoint = "http://127.0.0.1:57321",   -- kovim-agent API
  enabled  = true,

  restore_on_insert              = true, -- restore Korean on InsertEnter
  force_english_on_insert_leave  = true, -- switch to English on InsertLeave
  force_english_on_cmdline_enter = true, -- switch to English on : / ?

  debug = false,                         -- print debug notifications
})
```

### Commands

| Command | Effect |
|---|---|
| `:KovimEnglish` | Immediately switch to English |
| `:KovimRestore` | Restore previous IME |
| `:KovimHealth` | Diagnose agent connectivity and autocmd setup |

---

## SSH support

The global Esc watcher fires locally, so IME switches to English even when you are inside a remote Neovim session over SSH. No configuration is needed for the basic case.

For full mode-aware restoration over SSH (restoring Korean when entering insert mode remotely), forward the agent port:

```bash
# One-time
ssh -R 57321:127.0.0.1:57321 user@server

# Or in ~/.ssh/config
Host myserver
  HostName example.com
  User youruser
  RemoteForward 57321 127.0.0.1:57321
```

The remote Neovim plugin will then call the local macOS agent transparently.

---

## VSCode extension

Requires the [VSCodeVim](https://marketplace.visualstudio.com/items?itemName=vscodevim.vim) extension.

### Install

```bash
bash scripts/install-vscode.sh
```

This builds the extension (`npm install` + `npm run compile`) and installs it
into `~/.vscode/extensions/`. It needs Node.js (`npm`) and also checks that
VSCodeVim is present.

Because the extension only uses the `vscode` API and Node built-ins, it is
installed as a plain folder — no `.vsix` packaging or Marketplace publisher
account required. **Reload VSCode** afterwards
(`Cmd+Shift+P` → `Developer: Reload Window`) to activate it.

### VSCode settings

```json
{
  "kovim.enabled": true,
  "kovim.endpoint": "http://127.0.0.1:57321",
  "kovim.restorePreviousOnInsert": true,
  "kovim.debug": false
}
```

The status bar shows **⌨︎ KoVim** when the agent is connected, **⌨︎ KoVim ✕** when it is offline.

---

## Config file

The agent config lives at `~/.config/kovim/config.json` and is created with defaults on first run.

```json
{
  "allowedBundleIds": [
    "com.googlecode.iterm2",
    "com.apple.Terminal",
    "dev.warp.Warp-Stable",
    "org.alacritty",
    "com.github.wez.wezterm",
    "net.kovidgoyal.kitty",
    "com.microsoft.VSCode",
    "com.microsoft.VSCodeInsiders"
  ],
  "debugLogging": false,
  "enableLocalServer": true,
  "englishInputSourceId": null,
  "port": 57321,
  "restorePreviousOnInsert": true,
  "switchOnControlBracket": true,
  "switchOnEscape": true
}
```

Set `englishInputSourceId` explicitly if the agent cannot auto-detect your English layout.  
Run `kovim-im sources` to list all available IDs.

---

## CLI reference

`kovim-im` is a small helper that ships with the agent for diagnostics:

```bash
kovim-im current            # print current input source ID
kovim-im english            # print the likely English input source ID
kovim-im sources            # list all selectable input sources
kovim-im select <id>        # switch to a specific input source
```

---

## Local API

The agent exposes a simple HTTP API on `127.0.0.1:57321`:

| Method | Path | Effect |
|---|---|---|
| `GET` | `/health` | Health check + current state |
| `GET` | `/ime/current` | Current IME state |
| `GET` | `/ime/sources` | List selectable input sources |
| `POST` | `/mode/normal` | Save current IME → switch to English |
| `POST` | `/mode/insert` | Restore previous IME |
| `POST` | `/ime/english` | Force English |
| `POST` | `/ime/restore` | Restore previous |

Example:

```bash
curl -s http://127.0.0.1:57321/health | jq
curl -s -X POST http://127.0.0.1:57321/mode/normal
```

---

## Project structure

```
kovim/
  cli/                    kovim-im.swift          IME CLI helper
  Sources/KovimAgent/     Swift macOS agent
    KovimAgent.swift      AppDelegate, entry point
    InputSourceManager.swift
    EventTap.swift        Global key watcher
    FrontmostAppWatcher.swift
    LocalServer.swift     HTTP API (NW framework)
    Config.swift
    Logger.swift
  nvim/                   Neovim Lua plugin
    lua/kovim/
      init.lua            setup()
      client.lua          HTTP client
      config.lua          defaults
    plugin/kovim.lua
  vscode/                 VSCode extension (TypeScript)
    src/
      extension.ts
      kovimClient.ts
  scripts/
    build-app.sh          builds KoVim.app
    install.sh            full install (app + CLI + Neovim plugin)
    install-nvim.sh       Neovim plugin only
    install-vscode.sh     VSCode extension only
```

---

## License

MIT
