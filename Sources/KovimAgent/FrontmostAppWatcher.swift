import AppKit
import Foundation

final class FrontmostAppWatcher {
    private var allowedBundleIds: Set<String>

    init(allowedBundleIds: [String]) {
        self.allowedBundleIds = Set(allowedBundleIds)
    }

    func updateAllowedBundleIds(_ bundleIds: [String]) {
        self.allowedBundleIds = Set(bundleIds)
    }

    var frontmostBundleId: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    var frontmostName: String? {
        NSWorkspace.shared.frontmostApplication?.localizedName
    }

    func isFrontmostAppAllowed() -> Bool {
        guard let bundleId = frontmostBundleId else { return false }
        return allowedBundleIds.contains(bundleId)
    }
}
