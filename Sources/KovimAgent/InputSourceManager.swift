import AppKit
import Carbon
import Foundation

struct InputSourceInfo: Codable, Equatable {
    let id: String
    let name: String
}

enum InputSourceError: Error, CustomStringConvertible {
    case noCurrentInputSource
    case missingProperty(String)
    case sourceNotFound(String)
    case sourceNotSelectable(String)
    case selectionFailed(String, OSStatus)
    case noEnglishInputSource

    var description: String {
        switch self {
        case .noCurrentInputSource:
            return "Could not read the current macOS input source."
        case .missingProperty(let property):
            return "Input source is missing property: \(property)."
        case .sourceNotFound(let id):
            return "Input source not found: \(id)."
        case .sourceNotSelectable(let id):
            return "Input source is not selectable: \(id)."
        case .selectionFailed(let id, let status):
            return "Failed to select input source \(id) (OSStatus \(status))."
        case .noEnglishInputSource:
            return "Could not find an English/ABC input source. Configure englishInputSourceId explicitly."
        }
    }
}

@MainActor
final class InputSourceManager: ObservableObject {
    @Published private(set) var currentInputSourceId: String?
    @Published private(set) var previousInputSourceId: String?
    @Published private(set) var englishInputSourceId: String

    /// True while the editor is in normal (or command-line) mode. Used to take
    /// the insert-mode IME snapshot exactly once per insert→normal transition,
    /// so that multiple overlapping signals (global Esc tap + editor plugin)
    /// don't clobber it once the IME has already been switched to English.
    private(set) var isNormalMode = false

    init(englishInputSourceId: String?) {
        self.englishInputSourceId = englishInputSourceId ?? InputSourceManager.likelyEnglishInputSourceID() ?? "com.apple.keylayout.ABC"
        self.currentInputSourceId = try? Self.currentInputSourceID()
    }

    func refresh() {
        currentInputSourceId = try? Self.currentInputSourceID()
    }

    /// Signals that the editor entered normal mode (via Esc / Ctrl-[ or an
    /// editor plugin). The IME active during the just-ended insert session is
    /// snapshot exactly once per insert→normal transition — **including when it
    /// was English**, so that returning to insert mode after typing English
    /// stays English instead of restoring a stale Korean IME. Then switches to
    /// English so normal-mode keys work.
    ///
    /// - Parameter capturedSource: the IME read at key-press time by the global
    ///   event tap. More reliable than reading it now (it predates our own
    ///   switch to English); falls back to the current source when omitted,
    ///   e.g. on the editor-plugin HTTP path.
    func enterNormalMode(capturedSource: String? = nil) throws {
        if !isNormalMode {
            if let snapshot = capturedSource ?? (try? Self.currentInputSourceID()) {
                previousInputSourceId = snapshot
            }
            isNormalMode = true
        }
        try Self.selectInputSource(id: englishInputSourceId)
        refresh()
    }

    /// Signals that the editor entered insert mode. Restores the IME captured on
    /// the last insert→normal transition — which may be English (you were typing
    /// English) or e.g. Korean.
    func enterInsertMode(restoreIME: Bool = true) throws {
        isNormalMode = false
        guard restoreIME, let previousInputSourceId else { return }
        try Self.selectInputSource(id: previousInputSourceId)
        refresh()
    }

    func select(id: String, rememberAsPrevious: Bool = false) throws {
        try Self.selectInputSource(id: id)
        if rememberAsPrevious {
            previousInputSourceId = id
        }
        refresh()
    }

    nonisolated static func property<T>(_ source: TISInputSource, _ key: CFString, _ name: String) throws -> T {
        guard let raw = TISGetInputSourceProperty(source, key) else {
            throw InputSourceError.missingProperty(name)
        }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as! T
    }

    nonisolated static func optionalProperty<T>(_ source: TISInputSource, _ key: CFString) -> T? {
        guard let raw = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
    }

    nonisolated static func sourceID(_ source: TISInputSource) throws -> String {
        try property(source, kTISPropertyInputSourceID, "kTISPropertyInputSourceID") as String
    }

    nonisolated static func sourceName(_ source: TISInputSource) -> String {
        optionalProperty(source, kTISPropertyLocalizedName) ?? "(unnamed)"
    }

    nonisolated static func currentInputSourceID() throws -> String {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            throw InputSourceError.noCurrentInputSource
        }
        return try sourceID(source)
    }

    static func allInputSources() -> [TISInputSource] {
        let properties: NSDictionary = [kTISPropertyInputSourceIsSelectCapable!: true]
        guard let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource] else {
            return []
        }
        return list
    }

    static func selectableInputSources() -> [InputSourceInfo] {
        allInputSources().compactMap { source in
            guard let id = try? sourceID(source) else { return nil }
            return InputSourceInfo(id: id, name: sourceName(source))
        }
    }

    static func isSelectable(_ source: TISInputSource) -> Bool {
        let selectable: Bool? = optionalProperty(source, kTISPropertyInputSourceIsSelectCapable)
        return selectable == true
    }

    static func selectInputSource(id: String) throws {
        guard let source = allInputSources().first(where: { (try? sourceID($0)) == id }) else {
            throw InputSourceError.sourceNotFound(id)
        }
        guard isSelectable(source) else {
            throw InputSourceError.sourceNotSelectable(id)
        }
        let status = TISSelectInputSource(source)
        guard status == noErr else {
            throw InputSourceError.selectionFailed(id, status)
        }
    }

    static func likelyEnglishInputSourceID() -> String? {
        let preferredIDs = [
            "com.apple.keylayout.ABC",
            "com.apple.keylayout.US",
            "com.apple.keylayout.British"
        ]
        let sources = allInputSources()
        for preferredID in preferredIDs {
            if sources.contains(where: { (try? sourceID($0)) == preferredID }) {
                return preferredID
            }
        }
        return sources.compactMap { source -> String? in
            guard let id = try? sourceID(source) else { return nil }
            let lower = id.lowercased()
            if lower.contains("abc") || lower.contains("roman") || lower.contains("us") {
                return id
            }
            return nil
        }.first
    }
}
