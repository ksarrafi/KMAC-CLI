import Foundation

/// Persists the most recently suggested fixes so `kmac fix` (one process)
/// and `kmac execute-fix <index>` (a later process) can share state.
public struct FixStore {

    private static var storeURL: URL {
        let base = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/KMac", isDirectory: true)
        return base.appendingPathComponent("last-fixes.json")
    }

    /// Writes the suggested fixes to disk, replacing any prior set.
    public static func save(_ fixes: [SuggestedFix]) throws {
        let dir = storeURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(fixes)
        try data.write(to: storeURL, options: .atomic)
    }

    /// Loads the last persisted fixes, or an empty array if none exist.
    public static func load() -> [SuggestedFix] {
        guard let data = try? Data(contentsOf: storeURL),
              let fixes = try? JSONDecoder().decode([SuggestedFix].self, from: data) else {
            return []
        }
        return fixes
    }
}
