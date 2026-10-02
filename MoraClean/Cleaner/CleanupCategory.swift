import Foundation

/// Temizlenecek bir klasör. Temizlik yalnızca kökün **doğrudan alt öğelerini** siler; kökün kendisine dokunulmaz.
struct CleanupTarget: Sendable, Hashable {
    let root: URL
    /// Doluysa yalnızca bu uzantılara sahip alt öğeler listelenir (ör. İndirilenler'de .dmg).
    var extensions: Set<String> = []
    /// Listelenmeyecek alt öğe adları.
    var excludedNames: Set<String> = []
}

struct CleanupCategory: Identifiable, Sendable {
    enum ID: String, CaseIterable, Sendable {
        case userCaches, userLogs, xcode, developerCaches, trash, downloadInstallers
    }

    let id: ID
    let title: String
    let subtitle: String
    let symbol: String
    let selectedByDefault: Bool
    /// Çöp Kutusu gibi, ayardan bağımsız olarak her zaman kalıcı silinen kategoriler.
    let alwaysPermanent: Bool
    let targets: [CleanupTarget]
    /// Öğeler ait oldukları uygulamaya göre gruplanır (ikon ve uygulama adıyla).
    var groupsByApp = false
}

extension CleanupCategory {
    static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [CleanupCategory] {
        let library = home.appendingPathComponent("Library")
        let developer = library.appendingPathComponent("Developer")
        let ownBundleID = Bundle.main.bundleIdentifier ?? "works.mora.moraclean"

        return [
            CleanupCategory(
                id: .userCaches,
                title: String(localized: "User Caches"),
                subtitle: String(localized: "Temporary files that apps can recreate (~/Library/Caches)"),
                symbol: "internaldrive",
                selectedByDefault: true,
                alwaysPermanent: false,
                targets: [CleanupTarget(root: library.appendingPathComponent("Caches"), excludedNames: [ownBundleID])],
                groupsByApp: true
            ),
            CleanupCategory(
                id: .userLogs,
                title: String(localized: "Log Files"),
                subtitle: String(localized: "App and diagnostic logs (~/Library/Logs)"),
                symbol: "doc.text.magnifyingglass",
                selectedByDefault: true,
                alwaysPermanent: false,
                targets: [CleanupTarget(root: library.appendingPathComponent("Logs"))]
            ),
            CleanupCategory(
                id: .xcode,
                title: String(localized: "Xcode Leftovers"),
                subtitle: String(localized: "DerivedData, device support files and simulator caches"),
                symbol: "hammer",
                selectedByDefault: true,
                alwaysPermanent: false,
                targets: [
                    CleanupTarget(root: developer.appendingPathComponent("Xcode/DerivedData")),
                    CleanupTarget(root: developer.appendingPathComponent("Xcode/iOS DeviceSupport")),
                    CleanupTarget(root: developer.appendingPathComponent("Xcode/watchOS DeviceSupport")),
                    CleanupTarget(root: developer.appendingPathComponent("Xcode/macOS DeviceSupport")),
                    CleanupTarget(root: developer.appendingPathComponent("CoreSimulator/Caches")),
                ]
            ),
            CleanupCategory(
                id: .developerCaches,
                title: String(localized: "Developer Caches"),
                subtitle: String(localized: "npm, Composer, Gradle, Yarn and Cargo package caches"),
                symbol: "shippingbox",
                selectedByDefault: true,
                alwaysPermanent: false,
                targets: [
                    CleanupTarget(root: home.appendingPathComponent(".npm/_cacache")),
                    CleanupTarget(root: home.appendingPathComponent(".composer/cache")),
                    CleanupTarget(root: home.appendingPathComponent(".cache/composer")),
                    CleanupTarget(root: home.appendingPathComponent(".gradle/caches")),
                    CleanupTarget(root: home.appendingPathComponent(".yarn/berry/cache")),
                    CleanupTarget(root: home.appendingPathComponent(".cargo/registry/cache")),
                ]
            ),
            CleanupCategory(
                id: .trash,
                title: String(localized: "Trash"),
                subtitle: String(localized: "Items in the Trash are deleted permanently"),
                symbol: "trash",
                selectedByDefault: false,
                alwaysPermanent: true,
                targets: [CleanupTarget(root: home.appendingPathComponent(".Trash"))]
            ),
            CleanupCategory(
                id: .downloadInstallers,
                title: String(localized: "Installer Files"),
                subtitle: String(localized: ".dmg, .pkg and .xip files in your Downloads folder"),
                symbol: "arrow.down.app",
                selectedByDefault: false,
                alwaysPermanent: false,
                targets: [CleanupTarget(root: home.appendingPathComponent("Downloads"), extensions: ["dmg", "pkg", "mpkg", "xip"])]
            ),
        ]
    }
}
