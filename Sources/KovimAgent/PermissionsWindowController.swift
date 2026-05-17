import AppKit
import SwiftUI

// MARK: - Window controller

final class PermissionsWindowController: NSWindowController {

    init(permissions: PermissionsController) {
        let content = PermissionsRootView(controller: permissions)
        let hosting = NSHostingController(rootView: content)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "KoVim – Permission Setup"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = hosting

        super.init(window: window)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) not implemented") }
}

// MARK: - Root view

private struct PermissionsRootView: View {
    @ObservedObject var controller: PermissionsController

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            permissionRows
            Divider()
            footer
        }
        .frame(width: 480)
        // Poll Accessibility every second while the window is open.
        .onReceive(
            Timer.publish(every: 1, on: .main, in: .common).autoconnect()
        ) { _ in
            Task { @MainActor in controller.refresh() }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(spacing: 16) {
            // Use the bundled logo; fall back to an SF Symbol if the bundle
            // isn't available (e.g. during `swift run` dev builds).
            Group {
                if let img = Bundle.main.image(forResource: "AppIcon") ?? NSImage(named: NSImage.applicationIconName) {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 56, height: 56)
                } else {
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.blue)
                        .frame(width: 56, height: 56)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("KoVim Permissions")
                    .font(.title2.weight(.semibold))
                Text("Two macOS permissions let KoVim watch for Esc / Ctrl-[ and switch your input method globally.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private var permissionRows: some View {
        VStack(spacing: 0) {
            PermissionRow(
                systemImage: "figure.arms.open",
                title: "Accessibility",
                description: "Lets KoVim detect mode changes from any terminal or editor via the Accessibility API.",
                isGranted: controller.hasAccessibility,
                action: { controller.openAccessibilitySettings() }
            )
            Divider().padding(.horizontal, 20)
            PermissionRow(
                systemImage: "eye",
                title: "Input Monitoring",
                description: "Lets KoVim watch for Esc / Ctrl-[ keypresses in any app, including terminals.",
                isGranted: controller.hasInputMonitoring,
                action: { controller.openInputMonitoringSettings() }
            )
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            if controller.allGranted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("All permissions granted — KoVim is active.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(.secondary)
                Text("After granting a permission, KoVim retries automatically within a few seconds.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Done") {
                NSApp.keyWindow?.close()
            }
            .keyboardShortcut(.return)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Permission row

private struct PermissionRow: View {
    let systemImage: String
    let title: String
    let description: String
    let isGranted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Status circle
            ZStack {
                Circle()
                    .fill(isGranted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 46, height: 46)
                Image(systemName: isGranted ? "checkmark" : systemImage)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(isGranted ? .green : .orange)
            }

            // Labels
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            // Action / status
            if isGranted {
                Text("Granted")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.green)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
            } else {
                Button("Open Settings…", action: action)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}
