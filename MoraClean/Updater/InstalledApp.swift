import Foundation

struct InstalledApp: Identifiable, Sendable, Hashable {
    var id: String { url.path }
    let url: URL
    let name: String
    let bundleID: String
    /// CFBundleShortVersionString (kullanıcıya görünen sürüm).
    let version: String
    /// CFBundleVersion (derleme numarası).
    let build: String
    let sparkleFeedURL: URL?
    let sparklePublicEDKey: String?
    let isFromAppStore: Bool

    /// Karşılaştırmada kullanılacak sürüm. Görünen sürüm sayı içermiyorsa derleme numarası,
    /// derleme numarası görünen sürümün ayrıntılı hali ise ("136.0" / "136.0.6008.52") derleme kullanılır.
    /// Büyük tamsayı derleme numaraları ("239619") görünen sürümün yerini almaz.
    var comparableVersion: String {
        let short = VersionComparator.parse(version).numbers
        let detailed = VersionComparator.parse(build).numbers
        if short.isEmpty { return build }
        if detailed.count > short.count, Array(detailed.prefix(short.count)) == short { return build }
        return version
    }

    var displayVersion: String { comparableVersion.isEmpty ? version : comparableVersion }
}

enum AppInventory {
    static var defaultSearchRoots: [URL] {
        [
            URL(fileURLWithPath: "/Applications"),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
        ]
    }

    /// Uygulama klasörlerini tarar. Alt klasörlere bir seviye iner (ör. /Applications/Utilities).
    static func scan(roots: [URL] = defaultSearchRoots) async -> [InstalledApp] {
        await Task.detached(priority: .userInitiated) {
            var seen = Set<String>()
            var apps: [InstalledApp] = []
            for root in roots {
                for url in appBundles(in: root, depth: 2) {
                    let resolved = url.resolvingSymlinksInPath().path
                    guard seen.insert(resolved).inserted, let app = read(url) else { continue }
                    apps.append(app)
                }
            }
            return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }.value
    }

    private static func appBundles(in directory: URL, depth: Int) -> [URL] {
        guard depth > 0,
              let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return [] }
        var result: [URL] = []
        for child in children {
            if child.pathExtension == "app" {
                result.append(child)
            } else if (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                result.append(contentsOf: appBundles(in: child, depth: depth - 1))
            }
        }
        return result
    }

    static func read(_ url: URL) -> InstalledApp? {
        let plistURL = url.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String
        else { return nil }

        let isAppStore = FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/_MASReceipt/receipt").path)
        // macOS ile gelen Apple uygulamaları sistem güncellemesiyle güncellenir.
        if bundleID.hasPrefix("com.apple."), !isAppStore { return nil }

        let feed = (info["SUFeedURL"] as? String)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .flatMap(URL.init(string:))
            .flatMap { $0.scheme == "https" || $0.scheme == "http" ? $0 : nil }

        return InstalledApp(
            url: url,
            // Finder'da görünen ad.
            name: url.deletingPathExtension().lastPathComponent,
            bundleID: bundleID,
            version: (info["CFBundleShortVersionString"] as? String) ?? "",
            build: (info["CFBundleVersion"] as? String) ?? "",
            sparkleFeedURL: feed,
            sparklePublicEDKey: info["SUPublicEDKey"] as? String,
            isFromAppStore: isAppStore
        )
    }
}
