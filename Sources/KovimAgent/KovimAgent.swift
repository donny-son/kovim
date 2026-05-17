import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var config: KovimConfig!
    private var logger: Logger!
    private var inputSourceManager: InputSourceManager!
    private var frontmostAppWatcher: FrontmostAppWatcher!
    private var eventTapController: EventTapController!
    private var localServer: LocalServer!
    private var statusItem: NSStatusItem!
    private var lastLogLine: String = "Ready"
    private var permissionsController: PermissionsController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        config = ConfigStore.load()
        logger = Logger(debugEnabled: config.debugLogging)
        inputSourceManager = InputSourceManager(englishInputSourceId: config.englishInputSourceId)
        frontmostAppWatcher = FrontmostAppWatcher(allowedBundleIds: config.allowedBundleIds)
        eventTapController = EventTapController(
            config: config,
            frontmostAppWatcher: frontmostAppWatcher,
            inputSourceManager: inputSourceManager,
            logger: logger
        )
        localServer = LocalServer(config: config, inputSourceManager: inputSourceManager, logger: logger)
        permissionsController = PermissionsController()

        // Keep the permissions controller in sync with event tap status.
        eventTapController.onInputMonitoringStatus = { [weak self] granted in
            Task { @MainActor in
                self?.permissionsController.setInputMonitoringGranted(granted)
                self?.updateMenu()
            }
        }

        setupStatusItem()
        observeLogs()

        eventTapController.start()
        localServer.start()
        logger.log("Started. Config: \(ConfigStore.configURL.path)")

        // Show the permissions window automatically on first launch if either
        // permission is missing.
        if !permissionsController.allGranted {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.permissionsController.showPermissionsWindow()
            }
        }
    }

    private func observeLogs() {
        NotificationCenter.default.addObserver(forName: .kovimLogLine, object: nil, queue: .main) { [weak self] note in
            guard let line = note.object as? String else { return }
            Task { @MainActor in
                self?.lastLogLine = line
                self?.updateMenu()
            }
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            // Load the logo as a template image so it adapts to light / dark mode.
            if let img = Bundle.main.image(forResource: "menubar") {
                img.isTemplate = true
                button.image = img
                button.imagePosition = .imageLeft
                button.imageScaling = .scaleProportionallyDown
            }
        }
        updateMenu()
    }

    private func updateMenu() {
        inputSourceManager.refresh()
        permissionsController.refresh()

        // Update the menu-bar button to reflect permission state.
        if let button = statusItem.button {
            let allGranted = permissionsController.allGranted
            // Show a warning badge in the title when permissions are missing.
            button.title = allGranted ? "" : " ⚠"
            button.toolTip = allGranted
                ? "KoVim"
                : "KoVim — permissions required. Click \"Setup Permissions…\" below."
        }

        let menu = NSMenu()

        // ── Permissions banner (shown only when something is missing) ──────
        if !permissionsController.allGranted {
            let permItem = NSMenuItem(
                title: "⚠  Setup Permissions…",
                action: #selector(showPermissionsWindow),
                keyEquivalent: "p",
                target: self
            )
            permItem.attributedTitle = NSAttributedString(
                string: "⚠  Setup Permissions…",
                attributes: [.foregroundColor: NSColor.systemOrange]
            )
            menu.addItem(permItem)
            menu.addItem(.separator())
        }

        // ── IME state ─────────────────────────────────────────────────────
        let current = inputSourceManager.currentInputSourceId ?? "unknown"
        let previous = inputSourceManager.previousInputSourceId ?? "none"

        menu.addItem(disabledTitle: "Current:  \(current)")
        menu.addItem(disabledTitle: "Previous: \(previous)")
        menu.addItem(disabledTitle: "English:  \(inputSourceManager.englishInputSourceId)")
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Switch to English", action: #selector(switchToEnglish), keyEquivalent: "e", target: self))
        menu.addItem(NSMenuItem(title: "Restore Previous",  action: #selector(restorePrevious),  keyEquivalent: "r", target: self))
        menu.addItem(.separator())

        // ── Tools ─────────────────────────────────────────────────────────
        menu.addItem(NSMenuItem(title: "Open Config",                  action: #selector(openConfig),       keyEquivalent: ",", target: self))
        menu.addItem(NSMenuItem(title: "List Input Sources in Terminal", action: #selector(listInputSources), keyEquivalent: "l", target: self))
        menu.addItem(NSMenuItem(title: "Permissions…",                  action: #selector(showPermissionsWindow), keyEquivalent: "p", target: self))
        menu.addItem(.separator())

        // ── Status ────────────────────────────────────────────────────────
        menu.addItem(disabledTitle: "API: http://127.0.0.1:\(config.port)")
        menu.addItem(disabledTitle: lastLogLine)
        menu.addItem(.separator())

        menu.addItem(NSMenuItem(title: "Quit KoVim", action: #selector(quit), keyEquivalent: "q", target: self))
        statusItem.menu = menu
    }

    @objc private func switchToEnglish() {
        do {
            try inputSourceManager.enterNormalMode()
        } catch {
            logger.log("Switch to English failed: \(error)")
        }
        updateMenu()
    }

    @objc private func restorePrevious() {
        do {
            try inputSourceManager.enterInsertMode()
        } catch {
            logger.log("Restore previous failed: \(error)")
        }
        updateMenu()
    }

    @objc private func showPermissionsWindow() {
        permissionsController.showPermissionsWindow()
    }

    @objc private func openConfig() {
        if !FileManager.default.fileExists(atPath: ConfigStore.configURL.path) {
            try? ConfigStore.writeDefaultConfig()
        }
        NSWorkspace.shared.open(ConfigStore.configURL)
    }

    @objc private func listInputSources() {
        let script = """
        tell application "Terminal"
          activate
          do script "~/.local/bin/kovim-im sources"
        end tell
        """
        var error: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&error)
        if let error {
            logger.log("Could not open Terminal for source list: \(error)")
        }
    }

    @objc private func quit() {
        localServer.stop()
        eventTapController.stop()
        NSApp.terminate(nil)
    }
}

private extension NSMenu {
    func addItem(disabledTitle title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        addItem(item)
    }
}

private extension NSMenuItem {
    convenience init(title: String, action: Selector?, keyEquivalent: String, target: AnyObject?) {
        self.init(title: title, action: action, keyEquivalent: keyEquivalent)
        self.target = target
    }
}

@main
enum KovimAgentMain {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
