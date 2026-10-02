import Foundation
import Testing
@testable import MoraClean

struct AppMatcherTests {
    private let apps: [String: URL] = [
        "com.example.Editor": URL(fileURLWithPath: "/Applications/Editor.app"),
        "com.example.Browser": URL(fileURLWithPath: "/Applications/Browser.app"),
    ]
    private let named: [String: URL] = [
        "Player": URL(fileURLWithPath: "/Applications/Player.app"),
    ]

    private func item(_ name: String, size: Int64) -> CleanupItem {
        CleanupItem(url: URL(fileURLWithPath: "/tmp/Caches/\(name)"), root: URL(fileURLWithPath: "/tmp/Caches"), size: size, isDirectory: true)
    }

    @Test func bundleIDCandidatesShrinkFromTheEnd() {
        #expect(AppMatcher.bundleIDCandidates(for: "com.example.Editor.helper.cache") ==
                ["com.example.Editor.helper.cache", "com.example.Editor.helper", "com.example.Editor"])
        #expect(AppMatcher.bundleIDCandidates(for: "com.example.Editor") == ["com.example.Editor"])
        #expect(AppMatcher.bundleIDCandidates(for: "Player").isEmpty)
    }

    @Test func groupsCachesByApp() {
        let resolver: AppMatcher.Resolver = { [apps] in apps[$0] }
        let nameResolver: AppMatcher.NameResolver = { [named] in named[$0] }
        let groups = AppMatcher.group([
            item("com.example.Editor", size: 100),
            item("com.example.Editor.ShipIt", size: 50),
            item("com.example.Browser", size: 10),
            item("Player", size: 400),
            item("SomeTool", size: 1_000),
        ], resolver: resolver, nameResolver: nameResolver)

        #expect(groups.map(\.name) == ["SomeTool", "Player", "Editor", "Browser"])
        let editor = groups.first { $0.name == "Editor" }
        #expect(editor?.items.map(\.name) == ["com.example.Editor", "com.example.Editor.ShipIt"])
        #expect(editor?.size == 150)
        #expect(editor?.appURL?.path == "/Applications/Editor.app")
        // Eşleşmeyen klasör kendi başına, uygulamasız grup olur.
        #expect(groups.first?.appURL == nil)
        #expect(groups.first?.items.count == 1)
    }

    @Test func treeListsChildrenBySize() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MoraCleanTree-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("big"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data(count: 200_000).write(to: root.appendingPathComponent("big/blob"))
        try Data(count: 10).write(to: root.appendingPathComponent("small.txt"))

        let nodes = await FileTree.children(of: root)
        #expect(nodes.map(\.name) == ["big", "small.txt"])
        #expect(nodes[0].isDirectory)
        #expect(!nodes[1].isDirectory)
    }
}
