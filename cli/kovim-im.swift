import Foundation
import Carbon

struct InputSource: CustomStringConvertible {
    let id: String
    let name: String
    let category: String?
    let isSelectable: Bool

    var description: String {
        "\(id)\t\(name)"
    }
}

enum CLIError: Error, CustomStringConvertible {
    case noCurrentInputSource
    case missingProperty(String)
    case sourceNotFound(String)
    case sourceNotSelectable(String)
    case selectionFailed(String, OSStatus)
    case invalidArguments

    var description: String {
        switch self {
        case .noCurrentInputSource:
            return "Could not read the current macOS input source."
        case .missingProperty(let property):
            return "Input source is missing property: \(property)."
        case .sourceNotFound(let id):
            return "Input source not found: \(id). Run `kovim-im sources` to list available IDs."
        case .sourceNotSelectable(let id):
            return "Input source is not selectable: \(id)."
        case .selectionFailed(let id, let status):
            return "Failed to select input source \(id) (OSStatus \(status))."
        case .invalidArguments:
            return usage
        }
    }
}

let usage = """
kovim-im: tiny macOS input-source helper for Korean/English editor workflows

Usage:
  kovim-im current             Print current input-source id
  kovim-im select <source-id>  Switch to the input-source id
  kovim-im sources             List selectable input sources
  kovim-im english             Print the first likely English input-source id

Examples:
  kovim-im current
  kovim-im select com.apple.keylayout.ABC
  kovim-im sources
"""

func property<T>(_ source: TISInputSource, _ key: CFString, _ name: String) throws -> T {
    guard let raw = TISGetInputSourceProperty(source, key) else {
        throw CLIError.missingProperty(name)
    }
    return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as! T
}

func optionalProperty<T>(_ source: TISInputSource, _ key: CFString) -> T? {
    guard let raw = TISGetInputSourceProperty(source, key) else {
        return nil
    }
    return Unmanaged<AnyObject>.fromOpaque(raw).takeUnretainedValue() as? T
}

func sourceID(_ source: TISInputSource) throws -> String {
    try property(source, kTISPropertyInputSourceID, "kTISPropertyInputSourceID") as String
}

func sourceName(_ source: TISInputSource) -> String {
    optionalProperty(source, kTISPropertyLocalizedName) ?? "(unnamed)"
}

func currentInputSourceID() throws -> String {
    guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
        throw CLIError.noCurrentInputSource
    }
    return try sourceID(source)
}

func allInputSources() -> [TISInputSource] {
    let properties: NSDictionary = [kTISPropertyInputSourceIsSelectCapable!: true]
    guard let list = TISCreateInputSourceList(properties, false)?.takeRetainedValue() as? [TISInputSource] else {
        return []
    }
    return list
}

func isSelectable(_ source: TISInputSource) -> Bool {
    let selectable: Bool? = optionalProperty(source, kTISPropertyInputSourceIsSelectCapable)
    return selectable == true
}

func selectInputSource(id: String) throws {
    guard let source = allInputSources().first(where: { (try? sourceID($0)) == id }) else {
        throw CLIError.sourceNotFound(id)
    }
    guard isSelectable(source) else {
        throw CLIError.sourceNotSelectable(id)
    }
    let status = TISSelectInputSource(source)
    guard status == noErr else {
        throw CLIError.selectionFailed(id, status)
    }
}

func likelyEnglishInputSourceID() -> String? {
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

func listSources() throws {
    for source in allInputSources() {
        let id = try sourceID(source)
        print("\(id)\t\(sourceName(source))")
    }
}

func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else {
        throw CLIError.invalidArguments
    }

    switch command {
    case "current":
        guard args.count == 1 else { throw CLIError.invalidArguments }
        print(try currentInputSourceID())
    case "select":
        guard args.count == 2 else { throw CLIError.invalidArguments }
        try selectInputSource(id: args[1])
    case "sources":
        guard args.count == 1 else { throw CLIError.invalidArguments }
        try listSources()
    case "english":
        guard args.count == 1 else { throw CLIError.invalidArguments }
        if let id = likelyEnglishInputSourceID() {
            print(id)
        } else {
            throw CLIError.sourceNotFound("English/ABC")
        }
    case "help", "--help", "-h":
        print(usage)
    default:
        throw CLIError.invalidArguments
    }
}

do {
    try main()
} catch let error as CLIError {
    fputs("\(error.description)\n", stderr)
    exit(1)
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
