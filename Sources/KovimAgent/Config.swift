import Foundation

struct KovimConfig: Codable, Equatable {
    var englishInputSourceId: String?
    var port: UInt16
    var allowedBundleIds: [String]
    var switchOnEscape: Bool
    var switchOnControlBracket: Bool
    var restorePreviousOnInsert: Bool
    var enableLocalServer: Bool
    var debugLogging: Bool

    static let defaultAllowedBundleIds = [
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
        "dev.warp.Warp",
        "org.alacritty",
        "io.alacritty",
        "com.github.wez.wezterm",
        "com.github.wez.WezTerm",
        "com.mitchellh.ghostty",
        "net.kovidgoyal.kitty",
        "com.microsoft.VSCode",
        "com.microsoft.VSCodeInsiders",
        "com.visualstudio.code.oss"
    ]

    static let `default` = KovimConfig(
        englishInputSourceId: nil,
        port: 57321,
        allowedBundleIds: defaultAllowedBundleIds,
        switchOnEscape: true,
        switchOnControlBracket: true,
        restorePreviousOnInsert: true,
        enableLocalServer: true,
        debugLogging: false
    )
}

enum ConfigStore {
    static var configDirectory: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config", isDirectory: true).appendingPathComponent("kovim", isDirectory: true)
    }

    static var configURL: URL {
        configDirectory.appendingPathComponent("config.json")
    }

    static func load() -> KovimConfig {
        do {
            let url = configURL
            if !FileManager.default.fileExists(atPath: url.path) {
                try writeDefaultConfig(to: url)
                return .default
            }

            let data = try Data(contentsOf: url)
            var config = try JSONDecoder().decode(KovimConfig.self, from: data)

            // Keep newly added defaults available after upgrades.
            if config.allowedBundleIds.isEmpty {
                config.allowedBundleIds = KovimConfig.defaultAllowedBundleIds
            }
            return config
        } catch {
            fputs("kovim-agent: failed to load config, using defaults: \(error)\n", stderr)
            return .default
        }
    }

    static func writeDefaultConfig(to url: URL = configURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(KovimConfig.default)
        try data.write(to: url, options: .atomic)
    }
}
