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
    case agentControl(String)
    case invalidArguments

    var description: String {
        switch self {
        case .noCurrentInputSource:
            return "Could not read the current macOS input source."
        case .missingProperty(let property):
            return "Input source is missing property: \(property)."
        case .sourceNotFound(let id):
            return "Input source not found: \(id). Run `kovim sources` to list available IDs."
        case .sourceNotSelectable(let id):
            return "Input source is not selectable: \(id)."
        case .selectionFailed(let id, let status):
            return "Failed to select input source \(id) (OSStatus \(status))."
        case .agentControl(let message):
            return message
        case .invalidArguments:
            return usage
        }
    }
}

let usage = """
kovim: control the KoVim menubar agent and macOS input sources

Agent:
  kovim start              Launch the KoVim menubar agent
  kovim stop               Quit the running agent
  kovim restart            Restart the agent
  kovim status             Show agent + IME status
  kovim logs [-f]          Show recent agent logs (-f to follow)

IME (via the running agent):
  kovim normal             Switch to English / normal mode
  kovim insert             Restore previous IME / insert mode

IME (direct, no agent required):
  kovim current            Print current input-source id
  kovim select <id>        Switch to the given input-source id
  kovim sources            List selectable input sources
  kovim english            Print the likely English input-source id

  kovim help               Show this help

Examples:
  kovim status
  kovim restart
  kovim logs -f
  kovim select com.apple.keylayout.ABC
"""

// ── macOS input-source helpers (TIS) ─────────────────────────────────────────

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

// ── Agent control helpers ────────────────────────────────────────────────────

/// The agent runs as "KoVim" when installed (app bundle) or "kovim-agent" when
/// run straight from `.build` during development.
let agentProcessNames = ["KoVim", "kovim-agent"]
let agentBundleID = "do.son.kovim"

var logFilePath: String {
    FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/kovim/agent.log").path
}

func configPort() -> Int {
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/kovim/config.json")
    guard
        let data = try? Data(contentsOf: url),
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let port = obj["port"] as? Int
    else {
        return 57321
    }
    return port
}

@discardableResult
func run(_ launchPath: String, _ args: [String]) -> (status: Int32, output: String) {
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: launchPath)
    proc.arguments = args
    let pipe = Pipe()
    proc.standardOutput = pipe
    proc.standardError = pipe
    do {
        try proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return (proc.terminationStatus, String(data: data, encoding: .utf8) ?? "")
    } catch {
        return (-1, "\(error)")
    }
}

func isAgentRunning() -> Bool {
    for name in agentProcessNames where run("/usr/bin/pgrep", ["-x", name]).status == 0 {
        return true
    }
    return false
}

/// Blocking HTTP request to the agent's local API. Returns nil if unreachable.
func apiRequest(method: String, path: String) -> (status: Int, json: [String: Any]?)? {
    let port = configPort()
    guard let url = URL(string: "http://127.0.0.1:\(port)\(path)") else { return nil }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 2

    let semaphore = DispatchSemaphore(value: 0)
    var result: (Int, [String: Any]?)?
    let task = URLSession.shared.dataTask(with: request) { data, response, _ in
        defer { semaphore.signal() }
        guard let http = response as? HTTPURLResponse else { return }
        let json = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        result = (http.statusCode, json)
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 3)
    return result
}

func startAgent() throws {
    if isAgentRunning() {
        print("KoVim agent is already running.")
        return
    }
    var result = run("/usr/bin/open", ["-b", agentBundleID])
    if result.status != 0 {
        let appPath = "/Applications/KoVim.app"
        if FileManager.default.fileExists(atPath: appPath) {
            result = run("/usr/bin/open", [appPath])
        }
    }
    guard result.status == 0 else {
        throw CLIError.agentControl("Could not launch KoVim.app. Is it installed? Run scripts/install.sh.")
    }
    print("KoVim agent launched.")
}

func stopAgent() {
    if !isAgentRunning() {
        print("KoVim agent is not running.")
        return
    }
    for name in agentProcessNames {
        run("/usr/bin/pkill", ["-x", name])
    }
    print("KoVim agent stopped.")
}

func restartAgent() throws {
    if isAgentRunning() {
        for name in agentProcessNames {
            run("/usr/bin/pkill", ["-x", name])
        }
        Thread.sleep(forTimeInterval: 1.0)
    }
    try startAgent()
}

func printStatus() {
    let running = isAgentRunning()
    print("KoVim agent:  \(running ? "running" : "stopped")")

    let port = configPort()
    if running, let res = apiRequest(method: "GET", path: "/health"), res.status == 200 {
        print("Local API:    reachable (port \(port))")
    } else if running {
        print("Local API:    not reachable (port \(port))")
    }

    if let id = try? currentInputSourceID() {
        print("Current IME:  \(id)")
    }
}

func showLogs(follow: Bool) {
    let path = logFilePath
    guard FileManager.default.fileExists(atPath: path) else {
        print("No log file yet at \(path).")
        print("Start the agent with `kovim start`.")
        return
    }
    if follow {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/tail")
        proc.arguments = ["-n", "50", "-f", path]
        try? proc.run()
        proc.waitUntilExit()
    } else {
        let result = run("/usr/bin/tail", ["-n", "50", path])
        print(result.output, terminator: "")
    }
}

/// POST to a mode endpoint on the running agent.
func switchMode(path: String, label: String) throws {
    guard isAgentRunning() else {
        throw CLIError.agentControl("KoVim agent is not running. Start it with `kovim start`.")
    }
    guard let res = apiRequest(method: "POST", path: path), res.status == 200 else {
        throw CLIError.agentControl("Request to \(path) failed. Is the local API enabled in your config?")
    }
    print("mode: \(label)")
}

// ── Dispatch ─────────────────────────────────────────────────────────────────

func main() throws {
    let args = Array(CommandLine.arguments.dropFirst())
    guard let command = args.first else {
        throw CLIError.invalidArguments
    }

    switch command {
    // Agent lifecycle
    case "start":
        guard args.count == 1 else { throw CLIError.invalidArguments }
        try startAgent()
    case "stop":
        guard args.count == 1 else { throw CLIError.invalidArguments }
        stopAgent()
    case "restart":
        guard args.count == 1 else { throw CLIError.invalidArguments }
        try restartAgent()
    case "status":
        guard args.count == 1 else { throw CLIError.invalidArguments }
        printStatus()
    case "logs":
        let follow = args.contains("-f") || args.contains("--follow")
        guard args.count == 1 || follow else { throw CLIError.invalidArguments }
        showLogs(follow: follow)

    // IME via the agent
    case "normal":
        guard args.count == 1 else { throw CLIError.invalidArguments }
        try switchMode(path: "/mode/normal", label: "normal")
    case "insert":
        guard args.count == 1 else { throw CLIError.invalidArguments }
        try switchMode(path: "/mode/insert", label: "insert")

    // IME direct (TIS)
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
