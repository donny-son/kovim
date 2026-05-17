import AppKit
import Carbon
import Foundation

@MainActor
final class EventTapController {
    private let config: KovimConfig
    private let frontmostAppWatcher: FrontmostAppWatcher
    private let inputSourceManager: InputSourceManager
    private let logger: Logger

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTask: Task<Void, Never>?

    /// Called whenever Input Monitoring status changes.
    /// `true`  = event tap created successfully (permission granted).
    /// `false` = tap creation failed (permission not yet granted).
    var onInputMonitoringStatus: ((Bool) -> Void)?

    init(
        config: KovimConfig,
        frontmostAppWatcher: FrontmostAppWatcher,
        inputSourceManager: InputSourceManager,
        logger: Logger
    ) {
        self.config = config
        self.frontmostAppWatcher = frontmostAppWatcher
        self.inputSourceManager = inputSourceManager
        self.logger = logger
    }

    func start() {
        tryCreateTap()
    }

    /// Attempts to create the CGEvent tap. On failure, automatically retries
    /// every 5 s so the tap activates the moment Input Monitoring is granted
    /// — no app restart needed.
    private func tryCreateTap() {
        guard eventTap == nil else { return }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            logger.log("Event tap creation failed — open System Settings › Privacy & Security › Accessibility and Input Monitoring and enable KoVim.")
            onInputMonitoringStatus?(false)
            scheduleRetry()
            return
        }

        retryTask?.cancel()
        retryTask = nil

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        onInputMonitoringStatus?(true)
        logger.log("Event tap started")
    }

    private func scheduleRetry() {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 s
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.tryCreateTap() }
        }
    }

    func stop() {
        retryTask?.cancel()
        retryTask = nil
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        logger.log("Event tap stopped")
    }

    fileprivate nonisolated func handleEvent(_ event: CGEvent) {
        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        let isEscape = keyCode == CGKeyCode(kVK_Escape)
        let isControlBracket = keyCode == CGKeyCode(kVK_ANSI_LeftBracket) && flags.contains(.maskControl)
        let inputSourceBeforeNormalKey = (isEscape || isControlBracket)
            ? try? InputSourceManager.currentInputSourceID()
            : nil

        Task { @MainActor in
            guard self.frontmostAppWatcher.isFrontmostAppAllowed() else { return }
            guard (self.config.switchOnEscape && isEscape) || (self.config.switchOnControlBracket && isControlBracket) else { return }

            do {
                try self.inputSourceManager.enterNormalMode(capturedSource: inputSourceBeforeNormalKey)
                self.logger.debug(
                    "Global normal-mode key in \(self.frontmostAppWatcher.frontmostBundleId ?? "unknown"); switched to English; previous=\(self.inputSourceManager.previousInputSourceId ?? "none")"
                )
            } catch {
                self.logger.log("Failed to switch to English from global key event: \(error)")
            }
        }
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
    guard type == .keyDown, let userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let controller = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue()
    controller.handleEvent(event)

    // Listen-only tap: never block or mutate the user's key event.
    return Unmanaged.passUnretained(event)
}
