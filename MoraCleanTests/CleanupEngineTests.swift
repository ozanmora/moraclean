import Foundation
import Testing
@testable import MoraClean

struct CleanupEngineTests {
    private func makeSandbox() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MoraCleanTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func scansChildrenWithSizesAndFilters() async throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("cache-a/nested"), withIntermediateDirectories: true)
        try Data(count: 50_000).write(to: root.appendingPathComponent("cache-a/nested/blob"))
        try Data(count: 10).write(to: root.appendingPathComponent("keep.dmg"))
        try Data(count: 10).write(to: root.appendingPathComponent("skip.txt"))
        try fm.createDirectory(at: root.appendingPathComponent("excluded"), withIntermediateDirectories: true)

        let all = CleanupCategory(id: .userCaches, title: "", subtitle: "", symbol: "", selectedByDefault: true, alwaysPermanent: false,
                                  targets: [CleanupTarget(root: root, excludedNames: ["excluded"])])
        let result = await CleanupEngine.scan(all)
        #expect(Set(result.items.map(\.name)) == ["cache-a", "keep.dmg", "skip.txt"])
        #expect(result.items.first?.name == "cache-a")
        #expect((result.items.first?.size ?? 0) >= 50_000)

        let installers = CleanupCategory(id: .downloadInstallers, title: "", subtitle: "", symbol: "", selectedByDefault: false, alwaysPermanent: false,
                                         targets: [CleanupTarget(root: root, extensions: ["dmg"])])
        #expect(await CleanupEngine.scan(installers).items.map(\.name) == ["keep.dmg"])
    }

    @Test func refusesItemsOutsideAllowedRoots() async throws {
        let root = try makeSandbox()
        let other = try makeSandbox()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: other)
        }
        let victim = other.appendingPathComponent("important.txt")
        try Data("x".utf8).write(to: victim)
        let nested = root.appendingPathComponent("a/b.txt")
        try FileManager.default.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: nested)

        let forged = [
            CleanupItem(url: victim, root: root, size: 1),               // başka klasör
            CleanupItem(url: nested, root: root, size: 1),               // doğrudan alt öğe değil
        ]
        let report = await CleanupEngine.clean(forged, permanently: { _ in true }, allowedRoots: [root])
        #expect(report.removedCount == 0)
        #expect(report.failures.count == 2)
        #expect(FileManager.default.fileExists(atPath: victim.path))
        #expect(FileManager.default.fileExists(atPath: nested.path))
    }

    @Test func deletesDirectChildrenPermanently() async throws {
        let root = try makeSandbox()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("old.log")
        try Data(count: 100).write(to: file)

        let item = CleanupItem(url: file, root: root, size: 100)
        let report = await CleanupEngine.clean([item], permanently: { _ in true }, allowedRoots: [root])
        #expect(report.removedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(FileManager.default.fileExists(atPath: root.path))
    }
}
