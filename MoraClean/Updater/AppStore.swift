import AppKit
import Foundation

struct AppStoreListing: Sendable, Equatable {
    let bundleID: String
    let trackID: Int
    let version: String
    let minimumOSVersion: String?
    let releaseNotes: String?
}

/// Mac App Store sürüm bilgisi Apple'ın herkese açık iTunes Search/Lookup API'sinden alınır.
enum AppStore {
    static var storefront: String {
        Locale.current.region?.identifier.lowercased() ?? "us"
    }

    static func lookup(bundleIDs: [String], country: String = storefront) async throws -> [String: AppStoreListing] {
        var listings: [String: AppStoreListing] = [:]
        for chunk in stride(from: 0, to: bundleIDs.count, by: 50).map({ Array(bundleIDs[$0..<min($0 + 50, bundleIDs.count)]) }) {
            var components = URLComponents(string: "https://itunes.apple.com/lookup")!
            components.queryItems = [
                URLQueryItem(name: "bundleId", value: chunk.joined(separator: ",")),
                URLQueryItem(name: "entity", value: "macSoftware"),
                URLQueryItem(name: "country", value: country),
            ]
            let (data, response) = try await URLSession.shared.data(from: components.url!)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { continue }
            for listing in try parseLookup(data) {
                listings[listing.bundleID] = listing
            }
        }
        return listings
    }

    static func parseLookup(_ data: Data) throws -> [AppStoreListing] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = root["results"] as? [[String: Any]]
        else { return [] }
        return results.compactMap { item in
            guard let bundleID = item["bundleId"] as? String,
                  let trackID = item["trackId"] as? Int,
                  let version = item["version"] as? String
            else { return nil }
            return AppStoreListing(
                bundleID: bundleID,
                trackID: trackID,
                version: version,
                minimumOSVersion: item["minimumOsVersion"] as? String,
                releaseNotes: item["releaseNotes"] as? String
            )
        }
    }

    /// Mağaza sürümü bu Mac'in macOS sürümünde çalışabilir mi?
    static func isCompatible(_ listing: AppStoreListing) -> Bool {
        guard let minimum = listing.minimumOSVersion, !minimum.isEmpty else { return true }
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let current = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        return VersionComparator.compare(minimum, current) != .orderedDescending
    }

    /// [mas](https://github.com/mas-cli/mas) kuruluysa doğrudan günceller (`true` döner).
    /// mas yoksa ya da başarısız olursa uygulamanın App Store sayfasını açar (`false` döner).
    /// Not: `mas update` root yetkisi ister; şifre SUDO_ASKPASS penceresiyle sorulur.
    @discardableResult
    static func update(trackID: Int, onLine: @escaping @Sendable (String) -> Void) async -> Bool {
        if let mas = Shell.which("mas") {
            var env: [String: String] = [:]
            if let askpass = try? AskPass.scriptPath() { env["SUDO_ASKPASS"] = askpass }
            if (try? await Shell.runChecked(mas, ["update", String(trackID)], environment: env, onLine: onLine)) != nil {
                return true
            }
        }
        await openStorePage(trackID: trackID)
        return false
    }

    @MainActor
    static func openStorePage(trackID: Int) {
        if let url = URL(string: "macappstore://apps.apple.com/app/id\(trackID)") {
            NSWorkspace.shared.open(url)
        }
    }
}
