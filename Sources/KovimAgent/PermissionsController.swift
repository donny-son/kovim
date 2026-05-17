import AppKit
import ApplicationServices

/// Tracks Accessibility and Input Monitoring permission state and provides
/// helpers to open the relevant System Settings panes.
@MainActor
final class PermissionsController: ObservableObject {
    @Published private(set) var hasAccessibility: Bool = false
    @Published private(set) var hasInputMonitoring: Bool = false

    private var windowController: PermissionsWindowController?

    init() {
        refresh()
    }

    // MARK: - State

    var allGranted: Bool { hasAccessibility && hasInputMonitoring }

    /// Re-checks Accessibility permission (live API call).
    /// Input Monitoring state is set externally via `setInputMonitoringGranted(_:)`.
    func refresh() {
        hasAccessibility = AXIsProcessTrusted()
    }

    /// Called by EventTapController when it successfully creates (or fails to
    /// create) the CGEvent tap.
    func setInputMonitoringGranted(_ granted: Bool) {
        hasInputMonitoring = granted
    }

    // MARK: - Actions

    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    func openInputMonitoringSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!
        NSWorkspace.shared.open(url)
    }

    /// Shows the KoVim Permissions window (creates it lazily).
    func showPermissionsWindow() {
        if windowController == nil {
            windowController = PermissionsWindowController(permissions: self)
        }
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
