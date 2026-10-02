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
}

extension CleanupCategory {
    static func all(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [CleanupCategory] {
        let library = home.appendingPathComponent("Library")
        let developer = library.appendingPathComponent("Developer")
        let ownBundleID = Bundle.main.bundleIdentifier ?? "works.mora.moraclean"

        return [
            CleanupCategory(
                id: .userCaches,
                title: "Kullanıcı Önbellekleri",
                subtitle: "Uygulamaların yeniden oluşturabildiği geçici dosyalar (~/Library/Caches)",
                symbol: "internaldrive",
                selectedByDefault: true,
                alwaysPermanent: false,
                targets: [CleanupTarget(root: library.appendingPathComponent("Caches"), excludedNames: [ownBundleID])]
            ),
            CleanupCategory(
                id: .userLogs,
                title: "Günlük Dosyaları",
                subtitle: "Uygulama ve tanılama günlükleri (~/Library/Logs)",
                symbol: "doc.text.magnifyingglass",
                selectedByDefault: true,
                alwaysPermanent: false,
                targets: [CleanupTarget(root: library.appendingPathComponent("Logs"))]
            ),
            CleanupCategory(
                id: .xcode,
                title: "Xcode Artıkları",
                subtitle: "DerivedData, cihaz destek dosyaları ve simülatör önbellekleri",
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
                title: "Geliştirici Önbellekleri",
                subtitle: "npm, Composer, Gradle, Yarn ve Cargo paket önbellekleri",
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
                title: "Çöp Kutusu",
                subtitle: "Çöp Kutusu'ndaki öğeler kalıcı olarak silinir",
                symbol: "trash",
                selectedByDefault: false,
                alwaysPermanent: true,
                targets: [CleanupTarget(root: home.appendingPathComponent(".Trash"))]
            ),
            CleanupCategory(
                id: .downloadInstallers,
                title: "Kurulum Dosyaları",
                subtitle: "İndirilenler klasöründeki .dmg, .pkg ve .xip dosyaları",
                symbol: "arrow.down.app",
                selectedByDefault: false,
                alwaysPermanent: false,
                targets: [CleanupTarget(root: home.appendingPathComponent("Downloads"), extensions: ["dmg", "pkg", "mpkg", "xip"])]
            ),
        ]
    }
}
