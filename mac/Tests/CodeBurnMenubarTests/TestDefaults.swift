import Darwin
import Foundation

/// Fully forgets a scratch `UserDefaults` suite (or `setPersistentDomain`
/// named domain) created for one test.
///
/// `removePersistentDomain(forName:)` only clears the in-memory domain --
/// cfprefsd still leaves the backing `~/Library/Preferences/<name>.plist`
/// (and sometimes a `.lockfile` beside it) on disk. Every test that hands out
/// a throwaway suite or domain name must call this instead of
/// `removePersistentDomain` directly -- typically via `defer { TestDefaults.forget(suiteName) }`
/// right after creating it -- so a full `swift test` run does not grow the
/// file count under Preferences.
enum TestDefaults {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var everForgotten: Set<String> = []
    private static let registerFinalSweep: Void = {
        atexit {
            TestDefaults.finalSweep()
        }
    }()

    /// A fresh scratch `UserDefaults` suite named `<prefix>.<uuid>`, paired
    /// with its suite name for `forget(_:)`.
    static func make(_ prefix: String = "CodeBurnMenubarTests") -> (UserDefaults, String) {
        let suiteName = "\(prefix).\(UUID().uuidString)"
        return (open(suiteName), suiteName)
    }

    /// Opens a suite/domain name as `UserDefaults`, for call sites that build
    /// their own name instead of using `make(_:)`'s uuid.
    static func open(_ suiteName: String) -> UserDefaults {
        UserDefaults(suiteName: suiteName)!
    }

    static func forget(_ suiteName: String) {
        _ = registerFinalSweep
        lock.lock()
        everForgotten.insert(suiteName)
        lock.unlock()
        reallyForget(suiteName)
    }

    private static func reallyForget(_ suiteName: String) {
        // A `UserDefaults` instance scoped to the suite -- not `.standard` --
        // so `synchronize()` below flushes *this* domain's own dirty state.
        let scoped = UserDefaults(suiteName: suiteName)
        scoped?.removePersistentDomain(forName: suiteName)
        // cfprefsd flushes a cleared domain to disk asynchronously; without
        // forcing that flush now, it can land *after* the delete below and
        // resurrect an empty `<suiteName>.plist`.
        scoped?.synchronize()
        let preferences = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
        for suffix in ["plist", "plist.lockfile"] {
            try? FileManager.default.removeItem(
                at: preferences.appendingPathComponent("\(suiteName).\(suffix)")
            )
        }
    }

    /// cfprefsd can still write the emptied domain back to disk ~10s after
    /// `forget(_:)`'s own delete; `synchronize()` does not close that window.
    /// Runs once at process exit, waits it out, and deletes again.
    /// ponytail: a fixed 20s pause, measured empirically -- if leftovers ever
    /// creep back despite every call site using `forget`, raise it here first.
    private static func finalSweep() {
        let names: [String]
        lock.lock()
        names = Array(everForgotten)
        lock.unlock()
        guard !names.isEmpty else { return }
        Thread.sleep(forTimeInterval: 20)
        let preferences = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
        for name in names {
            for suffix in ["plist", "plist.lockfile"] {
                try? FileManager.default.removeItem(
                    at: preferences.appendingPathComponent("\(name).\(suffix)")
                )
            }
        }
    }
}
