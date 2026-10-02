import AppKit
import Foundation

/// Bir önbellek klasörünün ait olduğu uygulama altında toplanmış öğeler.
struct CleanupGroup: Identifiable, Sendable, Hashable {
    /// Uygulama yolu ya da (eşleşme yoksa) öğenin kendi yolu.
    let id: String
    let name: String
    /// Eşleşen uygulama; ikon bundan alınır. `nil` ise öğe tek başına listelenir.
    let appURL: URL?
    let items: [CleanupItem]

    var size: Int64 { items.reduce(0) { $0 + $1.size } }
}

/// Önbellek klasörlerini kurulu uygulamalarla eşleştirir.
/// Klasör adı çoğunlukla paket kimliğidir (`com.example.App`, `com.example.App.helper`),
/// bazen de uygulamanın adıdır (`Example`).
enum AppMatcher {
    typealias Resolver = @Sendable (_ bundleID: String) -> URL?
    typealias NameResolver = @Sendable (_ name: String) -> URL?

    static let systemResolver: Resolver = { bundleID in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    static let systemNameResolver: NameResolver = { name in
        let fm = FileManager.default
        let roots = ["/Applications", fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path]
        for root in roots {
            let path = "\(root)/\(name).app"
            if fm.fileExists(atPath: path) { return URL(fileURLWithPath: path) }
        }
        return nil
    }

    /// Klasör adından denenecek paket kimlikleri: tam ad, ardından sondan kısaltılmış halleri
    /// (en az üç bileşen kalacak şekilde): `com.a.App.helper.x` → `com.a.App.helper`, `com.a.App`.
    static func bundleIDCandidates(for name: String) -> [String] {
        let parts = name.split(separator: ".")
        guard parts.count >= 2 else { return [] }
        var candidates = [name]
        var count = parts.count - 1
        while count >= 3 {
            candidates.append(parts.prefix(count).joined(separator: "."))
            count -= 1
        }
        return candidates
    }

    static func appURL(
        forFolderNamed name: String,
        resolver: Resolver = systemResolver,
        nameResolver: NameResolver = systemNameResolver
    ) -> URL? {
        for candidate in bundleIDCandidates(for: name) {
            if let url = resolver(candidate) { return url }
        }
        return nameResolver(name)
    }

    static func group(
        _ items: [CleanupItem],
        resolver: Resolver = systemResolver,
        nameResolver: NameResolver = systemNameResolver
    ) -> [CleanupGroup] {
        var byApp: [String: (url: URL, items: [CleanupItem])] = [:]
        var standalone: [CleanupGroup] = []
        for item in items {
            if let app = appURL(forFolderNamed: item.name, resolver: resolver, nameResolver: nameResolver) {
                let key = app.standardizedFileURL.path
                byApp[key, default: (app, [])].items.append(item)
            } else {
                standalone.append(CleanupGroup(id: item.id, name: item.name, appURL: nil, items: [item]))
            }
        }
        let apps = byApp.map { key, value in
            CleanupGroup(
                id: key,
                name: value.url.deletingPathExtension().lastPathComponent,
                appURL: value.url,
                items: value.items.sorted { $0.size > $1.size }
            )
        }
        return (apps + standalone).sorted { $0.size > $1.size }
    }
}
