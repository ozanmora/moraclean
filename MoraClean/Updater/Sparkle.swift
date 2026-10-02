import Foundation

struct AppcastItem: Sendable, Equatable {
    var title: String?
    /// sparkle:version → CFBundleVersion karşılığı.
    var version: String?
    /// sparkle:shortVersionString → CFBundleShortVersionString karşılığı.
    var shortVersion: String?
    var downloadURL: URL?
    var length: Int64?
    var edSignature: String?
    var minimumSystemVersion: String?
    var channel: String?
    var releaseNotesURL: URL?
    var isInformational = false

    var displayVersion: String { shortVersion ?? version ?? "?" }
}

/// Sparkle appcast (RSS) ayrıştırıcı. Hem öğe içi `<sparkle:version>` hem de eski
/// `<enclosure sparkle:version="…">` biçimini destekler.
final class AppcastParser: NSObject, XMLParserDelegate {
    private var items: [AppcastItem] = []
    private var current: AppcastItem?
    private var text = ""

    static func parse(_ data: Data) -> [AppcastItem] {
        let delegate = AppcastParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldResolveExternalEntities = false
        parser.parse()
        return delegate.items
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        text = ""
        switch elementName {
        case "item":
            current = AppcastItem()
        case "enclosure":
            guard current != nil else { return }
            // Windows/Linux için ayrılmış enclosure'ları atla.
            if let os = attributes["sparkle:os"], os.lowercased() != "macos" { return }
            if let url = attributes["url"].flatMap(URL.init(string:)) { current?.downloadURL = url }
            if let length = attributes["length"].flatMap(Int64.init) { current?.length = length }
            if let v = attributes["sparkle:version"], current?.version == nil { current?.version = v }
            if let v = attributes["sparkle:shortVersionString"], current?.shortVersion == nil { current?.shortVersion = v }
            if let sig = attributes["sparkle:edSignature"] { current?.edSignature = sig }
        case "sparkle:informationalUpdate":
            current?.isInformational = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { text = "" }
        guard current != nil else { return }
        switch elementName {
        case "item":
            if let item = current { items.append(item) }
            current = nil
        case "title": current?.title = value
        case "sparkle:version": if !value.isEmpty { current?.version = value }
        case "sparkle:shortVersionString": if !value.isEmpty { current?.shortVersion = value }
        case "sparkle:minimumSystemVersion": current?.minimumSystemVersion = value
        case "sparkle:channel": current?.channel = value
        case "sparkle:releaseNotesLink": current?.releaseNotesURL = URL(string: value)
        default: break
        }
    }
}

enum SparkleChecker {
    /// Varsayılan kanaldaki (beta değil), bu macOS sürümüyle uyumlu ve indirilebilir en yeni öğe.
    static func latestItem(in items: [AppcastItem], osVersion: OperatingSystemVersion = ProcessInfo.processInfo.operatingSystemVersion) -> AppcastItem? {
        let os = "\(osVersion.majorVersion).\(osVersion.minorVersion).\(osVersion.patchVersion)"
        let eligible = items.filter { item in
            guard item.channel == nil || item.channel?.isEmpty == true,
                  !item.isInformational,
                  item.downloadURL != nil,
                  item.version != nil || item.shortVersion != nil
            else { return false }
            if let minimum = item.minimumSystemVersion, !minimum.isEmpty,
               VersionComparator.compare(minimum, os) == .orderedDescending {
                return false
            }
            return true
        }
        return eligible.max { a, b in
            VersionComparator.compare(a.version ?? a.shortVersion ?? "", b.version ?? b.shortVersion ?? "") == .orderedAscending
        }
    }

    /// Öğe, kurulu uygulamadan daha yeni mi?
    /// Önce görünen sürümler karşılaştırılır; eşitse derleme numaralarına bakılır.
    static func isNewer(_ item: AppcastItem, than app: InstalledApp) -> Bool {
        if let short = item.shortVersion, !app.version.isEmpty {
            let result = VersionComparator.compare(short, app.version)
            if result != .orderedSame { return result == .orderedDescending }
            guard let version = item.version, !app.build.isEmpty else { return false }
            return VersionComparator.isNewer(version, than: app.build)
        }
        if let version = item.version {
            return VersionComparator.isNewer(version, than: app.build.isEmpty ? app.version : app.build)
        }
        return false
    }

    static func check(_ app: InstalledApp) async throws -> AppcastItem? {
        guard let feed = app.sparkleFeedURL else { return nil }
        var request = URLRequest(url: feed, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("MoraClean/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { return nil }
        guard let latest = latestItem(in: AppcastParser.parse(data)), isNewer(latest, than: app) else { return nil }
        return latest
    }
}
