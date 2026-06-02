import Foundation

final class Logger {
    private let debugEnabled: Bool
    private let queue = DispatchQueue(label: "do.son.kovim.logger")
    private let fileHandle: FileHandle?

    /// Log file the `kovim logs` CLI tails. Truncated once per agent launch so
    /// the file reflects the current session.
    static var logFileURL: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("kovim", isDirectory: true)
            .appendingPathComponent("agent.log")
    }

    init(debugEnabled: Bool) {
        self.debugEnabled = debugEnabled

        // Start each session with a fresh log file.
        let url = Logger.logFileURL
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        fm.createFile(atPath: url.path, contents: nil)
        self.fileHandle = try? FileHandle(forWritingTo: url)
    }

    func log(_ message: String) {
        let line = "kovim-agent: \(message)"
        fputs("\(line)\n", stderr)
        NotificationCenter.default.post(name: .kovimLogLine, object: line)

        if let fileHandle {
            queue.async {
                let stamp = Logger.timestamp()
                if let data = "[\(stamp)] \(message)\n".data(using: .utf8) {
                    fileHandle.write(data)
                }
            }
        }
    }

    func debug(_ message: String) {
        guard debugEnabled else { return }
        log(message)
    }

    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }
}

extension Notification.Name {
    static let kovimLogLine = Notification.Name("KovimLogLine")
}
