import Foundation

struct CleanupItem: Identifiable, Sendable, Hashable {
    var id: String { url.path }
    let url: URL
    let root: URL
    let size: Int64
    var isDirectory = false

    var name: String { url.lastPathComponent }
}

struct CategoryScanResult: Sendable {
    let categoryID: CleanupCategory.ID
    let items: [CleanupItem]
    /// Okunamayan kökler (çoğunlukla Tam Disk Erişimi izni gerektirir).
    let inaccessibleRoots: [URL]
    /// `groupsByApp` kategorilerde uygulamalara göre gruplar; diğerlerinde `nil`.
    var groups: [CleanupGroup]? = nil

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
}

struct CleanupReport: Sendable {
    var removedCount = 0
    var freedBytes: Int64 = 0
    var failures: [(path: String, reason: String)] = []
}

enum CleanupError: LocalizedError {
    case outsideAllowedRoot(String)

    var errorDescription: String? {
        switch self {
        case let .outsideAllowedRoot(path): String(localized: "Safety check: \(path) is not a direct child of an allowed folder.")
        }
    }
}

/// Tarama ve silme işlemleri. Ağır dosya sistemi işleri ana iş parçacığı dışında yapılır.
enum CleanupEngine {
    static func scan(_ category: CleanupCategory) async -> CategoryScanResult {
        await Task.detached(priority: .userInitiated) {
            var items: [CleanupItem] = []
            var inaccessible: [URL] = []
            let fm = FileManager.default
            for target in category.targets {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: target.root.path, isDirectory: &isDir), isDir.boolValue else { continue }
                let children: [URL]
                do {
                    children = try fm.contentsOfDirectory(at: target.root, includingPropertiesForKeys: nil, options: [])
                } catch {
                    inaccessible.append(target.root)
                    continue
                }
                for child in children {
                    if Task.isCancelled { break }
                    let name = child.lastPathComponent
                    if target.excludedNames.contains(name) || name == ".DS_Store" || name == ".localized" { continue }
                    if !target.extensions.isEmpty, !target.extensions.contains(child.pathExtension.lowercased()) { continue }
                    let size = allocatedSize(of: child)
                    let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    let isDirectory = values?.isDirectory == true && values?.isSymbolicLink != true
                    items.append(CleanupItem(url: child, root: target.root, size: size, isDirectory: isDirectory))
                }
            }
            items.sort { $0.size > $1.size }
            let groups = category.groupsByApp ? AppMatcher.group(items) : nil
            return CategoryScanResult(categoryID: category.id, items: items, inaccessibleRoots: inaccessible, groups: groups)
        }.value
    }

    /// Bir dosya ya da klasörün diskte kapladığı alan. Sembolik bağlantılar izlenmez.
    static func allocatedSize(of url: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let values = try? url.resourceValues(forKeys: keys) else { return 0 }
        if values.isSymbolicLink == true { return 0 }
        if values.isDirectory != true {
            return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        var total: Int64 = 0
        let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: Array(keys),
            options: [],
            errorHandler: { _, _ in true }
        )
        while let next = enumerator?.nextObject() as? URL {
            guard let v = try? next.resourceValues(forKeys: keys), v.isDirectory != true, v.isSymbolicLink != true else { continue }
            total += Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
        }
        return total
    }

    /// Öğenin, izin verilen köklerden birinin doğrudan alt öğesi olduğunu doğrular.
    static func validate(_ item: CleanupItem, allowedRoots: Set<URL>) throws {
        let parent = item.url.standardizedFileURL.deletingLastPathComponent().standardizedFileURL.path
        let rootPaths = Set(allowedRoots.map { $0.standardizedFileURL.path })
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
        guard rootPaths.contains(parent),
              rootPaths.contains(item.root.standardizedFileURL.path),
              item.url.lastPathComponent != "..",
              parent != "/", parent != home
        else {
            throw CleanupError.outsideAllowedRoot(item.url.path)
        }
    }

    static func clean(
        _ items: [CleanupItem],
        permanently: @escaping @Sendable (CleanupItem) -> Bool,
        allowedRoots: Set<URL>
    ) async -> CleanupReport {
        await Task.detached(priority: .userInitiated) {
            var report = CleanupReport()
            let fm = FileManager.default
            for item in items {
                do {
                    try validate(item, allowedRoots: allowedRoots)
                    if permanently(item) {
                        try fm.removeItem(at: item.url)
                    } else {
                        try fm.trashItem(at: item.url, resultingItemURL: nil)
                    }
                    report.removedCount += 1
                    report.freedBytes += item.size
                } catch {
                    report.failures.append((item.url.path, error.localizedDescription))
                }
            }
            return report
        }.value
    }
}
