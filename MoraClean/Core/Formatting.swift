import Foundation

enum Bytes {
    static func format(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false // "Zero KB" yerine "0 KB"
        return formatter.string(fromByteCount: value)
    }
}

enum DiskSpace {
    /// Başlangıç diskinde kullanılabilir alan (önemli kullanım için ayrılabilir alan dahil).
    static func available() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    static func total() -> Int64? {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return values?.volumeTotalCapacity.map(Int64.init)
    }
}

enum AppSettingsKey {
    static let permanentDelete = "permanentDelete"
    static let brewUpdateBeforeScan = "brewUpdateBeforeScan"
    static let ignoredBundleIDs = "ignoredBundleIDs"
}
