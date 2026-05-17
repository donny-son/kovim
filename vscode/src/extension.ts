import * as vscode from "vscode";
import { KovimClient } from "./kovimClient";

let client: KovimClient;
let output: vscode.OutputChannel;
let statusBar: vscode.StatusBarItem;
let agentAvailable = false;
let debugEnabled = false;

// ── VSCodeVim normalModeKeyBindingsNonRecursive entries to inject ────────────
//
// WHY we do it this way and NOT via package.json keybindings:
//   Keybindings defined in package.json completely intercept the key — the event
//   never reaches VSCodeVim. So binding "i" → kovim.modeInsert means the user's
//   IME is restored but VSCodeVim never receives "i", so insert mode never opens.
//
//   VSCodeVim's normalModeKeyBindingsNonRecursive is the correct seam:
//     "before": ["i"]          — intercept in Normal mode
//     "commands": [...]        — run VSCode commands first (restore IME)
//     "after": ["i"]           — then execute vim's built-in i non-recursively
//
//   This way: IME restores AND the user enters insert mode.

const INSERT_KEYS: { before: string[]; after: string[] }[] = [
  { before: ["i"], after: ["i"] },
  { before: ["a"], after: ["a"] },
  { before: ["o"], after: ["o"] },
  { before: ["I"], after: ["I"] },
  { before: ["A"], after: ["A"] },
  { before: ["O"], after: ["O"] },
  { before: ["s"], after: ["s"] },
  { before: ["S"], after: ["S"] },
  { before: ["C"], after: ["C"] },
];

// ── helpers ──────────────────────────────────────────────────────────────────

function getConfig() {
  return vscode.workspace.getConfiguration("kovim");
}

function log(message: string) {
  if (debugEnabled) {
    output.appendLine(`[${new Date().toISOString()}] ${message}`);
  }
}

async function pingAgent(): Promise<boolean> {
  try {
    const result = await client.health();
    agentAvailable = result.ok === true;
  } catch {
    agentAvailable = false;
  }
  updateStatusBar();
  return agentAvailable;
}

function updateStatusBar(label?: string) {
  if (!agentAvailable) {
    statusBar.text = "$(keyboard) KoVim ✕";
    statusBar.tooltip =
      "kovim-agent is not running.\nStart it from the KoVim.app menu bar icon.";
    statusBar.backgroundColor = new vscode.ThemeColor(
      "statusBarItem.warningBackground",
    );
  } else {
    statusBar.text = label ?? "$(keyboard) KoVim";
    statusBar.tooltip = "KoVim IME controller — active";
    statusBar.backgroundColor = undefined;
  }
}

// ── IME commands ─────────────────────────────────────────────────────────────

async function modeNormal(silent = false) {
  const cfg = getConfig();
  if (!cfg.get<boolean>("enabled")) return;

  log("mode → normal");
  const result = await client.modeNormal();

  if (!result.ok) {
    if (!silent) log(`modeNormal error: ${result.error}`);
    agentAvailable = false;
    updateStatusBar();
    return;
  }

  agentAvailable = true;
  updateStatusBar();
  log(`IME: ${result.currentInputSourceId ?? "unknown"}`);
}

async function modeInsert(silent = false) {
  const cfg = getConfig();
  if (!cfg.get<boolean>("enabled")) return;
  if (!cfg.get<boolean>("restorePreviousOnInsert")) return;

  log("mode → insert");
  const result = await client.modeInsert();

  if (!result.ok) {
    if (!silent) log(`modeInsert error: ${result.error}`);
    agentAvailable = false;
    updateStatusBar();
    return;
  }

  agentAvailable = true;
  updateStatusBar();
  log(`IME: ${result.currentInputSourceId ?? "unknown"}`);
}

async function showStatus() {
  const result = await client.current();
  const lines: string[] = result.ok
    ? [
        `Current:  ${result.currentInputSourceId ?? "unknown"}`,
        `Previous: ${result.previousInputSourceId ?? "none"}`,
        `English:  ${result.englishInputSourceId ?? "unknown"}`,
        `Agent:    ${agentAvailable ? "running" : "offline"}`,
      ]
    : [`kovim-agent offline: ${result.error}`];

  vscode.window.showInformationMessage(lines.join("\n"));
}

// ── VSCodeVim integration setup ───────────────────────────────────────────────

async function setupVSCodeVim() {
  const vimCfg = vscode.workspace.getConfiguration("vim", null);

  // ── normalModeKeyBindingsNonRecursive ──────────────────────────────────────
  // Inject bindings for each insert-mode entry key.
  // Each entry runs kovim.modeInsert then the native vim key, non-recursively.

  const existing: Record<string, unknown>[] =
    vimCfg.get<Record<string, unknown>[]>(
      "normalModeKeyBindingsNonRecursive",
    ) ?? [];

  // Remove any stale kovim entries so re-running this is safe.
  const withoutKovim = existing.filter(
    (b) =>
      !Array.isArray(b.commands) ||
      !(b.commands as string[]).includes("kovim.modeInsert"),
  );

  const newBindings = INSERT_KEYS.map((k) => ({
    before: k.before,
    commands: ["kovim.modeInsert"],
    after: k.after,
  }));

  await vimCfg.update(
    "normalModeKeyBindingsNonRecursive",
    [...withoutKovim, ...newBindings],
    vscode.ConfigurationTarget.Global,
  );

  vscode.window
    .showInformationMessage(
      "KoVim: VSCodeVim remaps configured for i, a, o, I, A, O, s, S, C.\n" +
        "Reload the window to activate.",
      "Reload Window",
    )
    .then((choice) => {
      if (choice === "Reload Window") {
        vscode.commands.executeCommand("workbench.action.reloadWindow");
      }
    });
}

// ── activation ───────────────────────────────────────────────────────────────

export async function activate(context: vscode.ExtensionContext) {
  output = vscode.window.createOutputChannel("KoVim");
  context.subscriptions.push(output);

  const cfg = getConfig();
  debugEnabled = cfg.get<boolean>("debug") ?? false;
  const endpoint = cfg.get<string>("endpoint") ?? "http://127.0.0.1:57321";
  client = new KovimClient(endpoint);

  statusBar = vscode.window.createStatusBarItem(
    vscode.StatusBarAlignment.Right,
    100,
  );
  statusBar.command = "kovim.showStatus";
  statusBar.text = "$(keyboard) KoVim";
  statusBar.show();
  context.subscriptions.push(statusBar);

  context.subscriptions.push(
    vscode.commands.registerCommand("kovim.modeNormal", () => modeNormal()),
    vscode.commands.registerCommand("kovim.modeInsert", () => modeInsert()),
    vscode.commands.registerCommand("kovim.showStatus", () => showStatus()),
    vscode.commands.registerCommand("kovim.setupVSCodeVim", () =>
      setupVSCodeVim(),
    ),
  );

  context.subscriptions.push(
    vscode.workspace.onDidChangeConfiguration((e) => {
      if (e.affectsConfiguration("kovim")) {
        const updated = getConfig();
        debugEnabled = updated.get<boolean>("debug") ?? false;
        const newEndpoint =
          updated.get<string>("endpoint") ?? "http://127.0.0.1:57321";
        client = new KovimClient(newEndpoint);
        pingAgent();
      }
    }),
  );

  await pingAgent();

  // Prompt first-time VSCodeVim setup if VSCodeVim is installed but not configured.
  promptVSCodeVimSetupIfNeeded();

  // Periodic ping every 10 s to keep status bar accurate.
  const timer = setInterval(() => pingAgent(), 10_000);
  context.subscriptions.push({ dispose: () => clearInterval(timer) });

  log("KoVim activated");
}

function promptVSCodeVimSetupIfNeeded() {
  const vimExt = vscode.extensions.getExtension("vscodevim.vim");
  if (!vimExt) return;

  const vimCfg = vscode.workspace.getConfiguration("vim", null);
  const existing: Record<string, unknown>[] =
    vimCfg.get<Record<string, unknown>[]>(
      "normalModeKeyBindingsNonRecursive",
    ) ?? [];

  const alreadyConfigured = existing.some(
    (b) =>
      Array.isArray(b.commands) &&
      (b.commands as string[]).includes("kovim.modeInsert"),
  );

  if (!alreadyConfigured) {
    vscode.window
      .showInformationMessage(
        "KoVim: VSCodeVim is installed but not configured for IME restore on insert. Set it up now?",
        "Set Up",
        "Later",
      )
      .then((choice) => {
        if (choice === "Set Up") {
          setupVSCodeVim();
        }
      });
  }
}

export function deactivate() {
  log("KoVim deactivated");
}
