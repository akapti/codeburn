import Foundation
import Testing

/// Guards the fix for the test-only `UserDefaults(suiteName:` leak: every
/// scratch suite must go through `TestDefaults.make`/`open`, whose only
/// direct call sites live in `TestDefaults.swift`, so its plist actually gets
/// cleaned up via `TestDefaults.forget`.
@Suite("UserDefaults suite leak guard")
struct UserDefaultsSuiteLeakGuardTests {
    private static var testsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // CodeBurnMenubarTests
            .deletingLastPathComponent()  // Tests
    }

    @Test("the guard can actually see the files it is meant to check")
    func testsAreReachable() throws {
        let files = try swiftFiles(in: Self.testsDirectory)
        #expect(
            files.count > 10,
            "found \(files.count) Swift files under \(Self.testsDirectory.path); if the tree moved, this guard checks nothing"
        )
    }

    @Test("no test file creates a UserDefaults suite outside TestDefaults.swift")
    func noDirectSuiteCreation() throws {
        let needle = "UserDefaults(" + "suiteName"
        let exempt: Set<String> = ["TestDefaults.swift", "UserDefaultsSuiteLeakGuardTests.swift"]
        var offenders: [String] = []
        for file in try swiftFiles(in: Self.testsDirectory) where !exempt.contains(file.lastPathComponent) {
            let contents = try String(contentsOf: file, encoding: .utf8)
            for (index, line) in contents.components(separatedBy: "\n").enumerated() where line.contains(needle) {
                offenders.append("\(file.lastPathComponent):\(index + 1)")
            }
        }
        #expect(
            offenders.isEmpty,
            """
            \(offenders.count) test call site(s) create a UserDefaults suite directly, \
            bypassing TestDefaults.forget and leaking its plist: \(offenders). \
            Use TestDefaults.make(_:) or TestDefaults.open(_:) instead.
            """
        )
    }

    private func swiftFiles(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil
        ) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
    }
}
