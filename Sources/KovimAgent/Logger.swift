import Foundation

final class Logger {
    private let debugEnabled: Bool

    init(debugEnabled: Bool) {
        self.debugEnabled = debugEnabled
    }

    func log(_ message: String) {
        let line = "kovim-agent: \(message)"
        fputs("\(line)\n", stderr)
        NotificationCenter.default.post(name: .kovimLogLine, object: line)
    }

    func debug(_ message: String) {
        guard debugEnabled else { return }
        log(message)
    }
}

extension Notification.Name {
    static let kovimLogLine = Notification.Name("KovimLogLine")
}
