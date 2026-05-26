# KoVim Developer & Contributor Guide

Welcome to the KoVim developer documentation! This guide provides a deep dive into the architecture, configuration, APIs, and build processes of KoVim. Whether you are adding support for a new terminal, optimizing latency, or porting to another editor, this document has everything you need to get started.

---

## Architecture Overview

KoVim is designed around a decoupled, client-server model to solve a classic macOS limitation: **editor plugins cannot easily control system-level IME input sources, and global key watchers cannot easily know the editor's internal state (e.g., normal vs. insert mode).**

By separating these responsibilities, KoVim achieves ultra-low latency switching with near-zero input lag.

```
                  ┌─────────────────────────────────────────────────────────┐
                  │                 macOS System Level                      │
                  │                                                         │
                  │   ┌─────────────────────────────────────────────────┐   │
                  │   │                   KoVim.app                     │   │
                  │   │  - Core Swift Agent running in the menu bar     │   │
                  │   │  - Listens to global Escape & Ctrl-[ events     │   │
                  │   │  - Controls IME via Carbon TIS APIs             │   │
                  │   │  - Local HTTP server on 127.0.0.1:57321         │   │
                  │   └────────────────────────┬────────────────────────┘   │
                  └────────────────────────────┼────────────────────────────┘
                                               │
                       ┌───────────────────────┴───────────────────────┐
                       ▼                                               ▼
         ┌───────────────────────────┐                   ┌───────────────────────────┐
         │       Neovim Plugin       │                   │     VSCode Extension      │
         │          (Lua)            │                   │       (TypeScript)        │
         │                           │                   │                           │
         │ - Tracks InsertEnter/Leave│                   │ - Integrates with         │
         │ - Asynchronously notifies │                   │   VSCodeVim bindings      │
         │   Agent via curl          │                   │ - Notifies Agent via HTTP │
         └───────────────────────────┘                   └───────────────────────────┘
```

### Core Components

1. **`KoVim.app` (macOS Swift Agent)**:
   A lightweight, status-bar-only app written in Swift. It does two major things:
   - Registers a **global event tap** (`CGEvent.tapCreate`) to listen for `Escape` and `Control-[` keypresses.
   - Runs a **local TCP server** (`NWListener`) exposing an HTTP API on port `57321` to receive commands from editor integrations.
2. **`kovim-im` (CLI Helper)**:
   A small Swift command-line interface compiled from the same codebase that leverages Carbon's Text Input Services (TIS) API. It queries current and available input sources, and allows scripting switches.
3. **Neovim Plugin (`nvim/`)**:
   Written in Lua. Hooks into `InsertLeave`, `InsertEnter`, and `CmdlineEnter` autocommands to let the agent know when to snapshot, switch to English, or restore the prior IME. Includes a built-in customizable float/sign-column "Banner" indicating active IMEs.
4. **VSCode Extension (`vscode/`)**:
   A TypeScript extension that integrates with the popular `VSCodeVim` extension. It injects custom non-recursive keybindings into VSCodeVim configuration dynamically to ensure that when `i`, `a`, or other insert-triggers are pressed, the previous IME is restored immediately as the editor shifts focus.

---

## Global Event Tap & Input Latency Design

A critical design consideration for any tool modifying keyboard inputs is **keyboard lag/latency**.

Many traditional key-mappers or watchers register event taps as *active filters* (`.defaultTap` or active `.listenOnly` that blocks thread execution), which intercepts the key, processes logic, and re-injects a new key event. If the event-tap callback blocks or encounters thread-scheduling delay, user typing stutters.

### KoVim's Zero-Lag Event Tap Strategy:
1. **Passive Event Tap (`.listenOnly`)**:
   KoVim's Event Tap (`EventTap.swift`) is registered with `.listenOnly` option. It *never* intercept or block keys from completing their OS-level execution path.
2. **Main Thread Non-Blocking**:
   When `Escape` or `Control-[` is detected, the event callback yields immediately by returning the unaltered event reference. It offloads the IME switching task to an asynchronous Swift `Task` running on the `@MainActor`.
3. **App-Targeted Guarding**:
   The Event Tap queries `FrontmostAppWatcher` which utilizes the lightweight `NSWorkspace.shared.frontmostApplication` check. The switch logic is aborted instantly if the active application bundle ID does not match the configured list of text-editors and terminals (`allowedBundleIds`).

---

## Local API Specification

The agent runs a local HTTP server on `127.0.0.1:57321` (port is configurable). All requests are local, ensuring maximum privacy and security.

### 1. `GET /health`
Returns the status of the agent, the current active IME input source, the previously snapshotted IME, and the detected English layout.

- **Request**: `GET /health`
- **Response**: `200 OK`
```json
{
  "ok": true,
  "status": "ok",
  "currentInputSourceId": "com.apple.inputmethod.Korean.2SetKorean",
  "previousInputSourceId": "com.apple.keylayout.ABC",
  "englishInputSourceId": "com.apple.keylayout.ABC"
}
```

### 2. `GET /ime/current`
Returns current active, previous snapshotted, and English IME IDs.

- **Request**: `GET /ime/current`
- **Response**: `200 OK`
```json
{
  "ok": true,
  "currentInputSourceId": "com.apple.keylayout.ABC",
  "previousInputSourceId": "com.apple.inputmethod.Korean.2SetKorean",
  "englishInputSourceId": "com.apple.keylayout.ABC"
}
```

### 3. `GET /ime/sources`
Lists all selectable keyboard input methods configured on the host macOS system.

- **Request**: `GET /ime/sources`
- **Response**: `200 OK`
```json
{
  "ok": true,
  "sources": [
    {
      "id": "com.apple.keylayout.ABC",
      "name": "ABC"
    },
    {
      "id": "com.apple.inputmethod.Korean.2SetKorean",
      "name": "2-Set Korean"
    }
  ]
}
```

### 4. `POST /mode/normal` (or `POST /ime/english`)
Tells the agent that the editor has transitioned to Normal Mode.
The agent immediately:
1. Takes a single snapshot of the current active input source and stores it as the `previousInputSourceId` (if we are not already in Normal mode).
2. Switches the active macOS IME to `englishInputSourceId`.

- **Request**: `POST /mode/normal`
- **Response**: `200 OK`
```json
{
  "ok": true,
  "mode": "normal",
  "currentInputSourceId": "com.apple.keylayout.ABC",
  "previousInputSourceId": "com.apple.inputmethod.Korean.2SetKorean",
  "englishInputSourceId": "com.apple.keylayout.ABC"
}
```

### 5. `POST /mode/insert` (or `POST /ime/restore`)
Tells the agent that the editor has transitioned to Insert Mode.
The agent immediately switches the keyboard input source back to the stored `previousInputSourceId`.

- **Request**: `POST /mode/insert`
- **Response**: `200 OK`
```json
{
  "ok": true,
  "mode": "insert",
  "currentInputSourceId": "com.apple.inputmethod.Korean.2SetKorean",
  "previousInputSourceId": "com.apple.inputmethod.Korean.2SetKorean",
  "englishInputSourceId": "com.apple.keylayout.ABC"
}
```

---

## Source Build Guide

KoVim can be compiled completely from source.

### Prerequisites
- macOS 13.0 or higher
- Xcode Command Line Tools (`xcode-select --install`)
- Swift 5.9+ compiler
- Node.js & npm (only if compiling the VSCode extension)

### 1. Compiling the Swift Targets (Agent + CLI)
We use Swift Package Manager (SPM). To build the release binaries:

```bash
# Build the binaries
swift build -c release

# Verify build outputs
.build/release/kovim-agent --help
.build/release/kovim-im sources
```

### 2. Bundling the macOS App (`KoVim.app`)
We provide an automated script to structure the binaries, load resources (menubar icons, app icons), generate `Info.plist`, and perform code-signing.

```bash
bash scripts/build-app.sh
```
This generates `KoVim.app` inside `.build/`.

### 3. Compiling the VSCode Extension
```bash
cd vscode
npm install
npm run compile
```
This checks TypeScript typing and compiles `extension.ts` and `kovimClient.ts` to Javascript in `out/`.

---

## Detailed Configuration

The configuration lives in JSON format at:
`~/.config/kovim/config.json`

### Field Specifications

| Key | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `englishInputSourceId` | `String?` | `null` | The primary English layout ID. If `null`, KoVim tries to auto-detect (`ABC`, `US`, or `British`). Set manually if using custom layouts (e.g., Colemak/Dvorak). |
| `port` | `UInt16` | `57321` | Port of the local HTTP server. |
| `allowedBundleIds` | `[String]` | *(List)* | macOS Bundle IDs where the global `Esc`/`Ctrl-[` key interception should trigger switching. |
| `switchOnEscape` | `Bool` | `true` | Watch for `Escape` key tap to switch IME. |
| `switchOnControlBracket` | `Bool` | `true` | Watch for `Control-[` key combination to switch IME. |
| `restorePreviousOnInsert` | `Bool` | `true` | Global flag to control whether entering insert mode restores previous IME. |
| `enableLocalServer` | `Bool` | `true` | Whether to spin up the local HTTP endpoint. Disable only if you just want global Esc watching. |
| `debugLogging` | `Bool` | `false` | Enable verbose printing of event taps and state updates to console/logs. |

### Listing and Customizing Input Layout IDs
To find your exact input source IDs, use the `kovim-im` utility:

```bash
# List all active system keyboards
kovim-im sources

# Example Output:
# com.apple.keylayout.ABC	ABC
# com.apple.inputmethod.Korean.2SetKorean	2-Set Korean
# com.apple.inputmethod.Korean.3SetKorean	3-Set Korean
```

Then, set `englishInputSourceId` in your `config.json` directly to your desired layout ID.

---

## Development & Debugging Workflows

### 1. Running the Agent in Debug Mode
To run with live logs outputting straight to terminal, enable `debugLogging` in your config, then launch the binary directly:

```bash
# Stop running App Store / application instances first
pkill -x "KoVim" || true

# Run agent via SPM in debug configuration
swift run kovim-agent
```

### 2. Inspecting Logs
Logs are posted to standard Cocoa logging channels. If the app is run as a bundled macOS app, you can view logs by reading the status bar menu, or utilizing macOS's `log` utility:

```bash
log show --predicate 'senderImagePath contains "KoVim"' --info --debug
```

### 3. Debugging the Neovim Plugin
To trace Neovim communication with the local agent, pass `debug = true` into the setup call:

```lua
require("kovim").setup({
  debug = true
})
```
This will trigger pop-up notifications (`vim.notify`) in Neovim showing request payloads and outcomes. Use `:messages` to review past events or run `:KovimHealth` for immediate verification.

### 4. Debugging the VSCode Extension
Open the `vscode` directory in VSCode:
1. Press `F5` to launch an "Extension Development Host" window.
2. In the host window, open the "Output" panel and choose the "KoVim" channel from the drop-down.
3. Configure `"kovim.debug": true` in the host settings to see active logging of mode transitions.

---

## Code Signing & macOS Security Permissions

macOS enforces strict sandboxing and security. For KoVim to successfully intercept keystrokes globally and invoke system IME switching, it must acquire user permissions.

### Sandbox & Permissions
- **Accessibility**: Required by `CGEvent.tapCreate` to capture keyboard inputs. Without this, the event tap returns `nil`.
- **Input Monitoring**: Required in newer macOS versions (macOS 10.15+) for any app capturing keystrokes globally.

### Code Signing
Because the app is built locally from source, it must be signed to prevent macOS from terminating it immediately with code-signature errors.
`scripts/build-app.sh` signs the app using **Ad-Hoc Signing** (`-`):
```bash
codesign --force --deep --sign - ".build/KoVim.app"
```
Ad-Hoc signing is perfectly adequate for local developer builds. However, when distributing built binaries to other users, a valid Apple Developer Certificate is required.

---

## Style Guide & Contribution Guidelines

We welcome contributions of all types! Here are our coding style preferences:

### Swift (Agent & CLI)
- Follow the official Swift API Design Guidelines.
- Prefer `async/await` and structured concurrency (`Task`, `TaskGroup`) over GCD completion handlers.
- Mark UI/App level classes with `@MainActor` to prevent race conditions on the main thread.

### Lua (Neovim Plugin)
- Keep dependencies minimal. Use `vim.system` for Neovim 0.10+ and fall back to `vim.fn.jobstart` gracefully.
- Do not poll local endpoints with aggressive timers. The Banner uses a non-blocking `uv_timer` loop that suspends completely when entering Normal mode.

### TypeScript (VSCode Extension)
- Keep workspace modifications minimal. Do not pollute `settings.json` unless requested by the user.
- Handle connection failures gracefully to avoid spamming user popups when the agent is offline.
