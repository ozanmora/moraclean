import Foundation

/// Uygulama sürümlerini karşılaştırır. Kaynaklar arasında biçim farklı olabildiği için
/// (ör. "Build 4200", "5.8.1,2349", "v0.12.0-beta.6", "3.0 (1234)") toleranslı çalışır.
enum VersionComparator {
    struct Parsed: Equatable {
        var numbers: [Int]
        /// Sayısal kısımdan sonra gelen ek ("-beta.6", " (1234)" gibi), küçük harfe çevrilmiş.
        var suffix: String
    }

    static func parse(_ raw: String) -> Parsed {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // İlk rakamdan önceki öneki ("v", "build " vb.) at.
        guard let start = text.firstIndex(where: \.isNumber) else {
            return Parsed(numbers: [], suffix: text)
        }
        var numbers: [Int] = []
        var current = ""
        var index = start
        while index < text.endIndex {
            let char = text[index]
            if char.isASCII, char.isNumber {
                current.append(char)
            } else if char == ".", !current.isEmpty {
                numbers.append(Int(current) ?? 0)
                current = ""
            } else {
                break
            }
            index = text.index(after: index)
        }
        if !current.isEmpty { numbers.append(Int(current) ?? 0) }
        let suffix = String(text[index...]).trimmingCharacters(in: CharacterSet(charactersIn: " .-_+"))
        return Parsed(numbers: numbers, suffix: suffix)
    }

    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let a = parse(lhs)
        let b = parse(rhs)
        let count = max(a.numbers.count, b.numbers.count)
        for i in 0..<count {
            let x = i < a.numbers.count ? a.numbers[i] : 0
            let y = i < b.numbers.count ? b.numbers[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return compareSuffix(a.suffix, b.suffix)
    }

    /// `candidate`, `current`'tan daha yeni mi?
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        compare(candidate, current) == .orderedDescending
    }

    private static let preReleaseMarkers = ["alpha", "beta", "rc", "pre", "preview", "dev", "a", "b"]

    private static func isPreRelease(_ suffix: String) -> Bool {
        preReleaseMarkers.contains { suffix.hasPrefix($0) }
    }

    private static func compareSuffix(_ a: String, _ b: String) -> ComparisonResult {
        if a == b { return .orderedSame }
        // Ek yoksa ve diğerinde ön sürüm eki varsa: "1.0" > "1.0-beta".
        if a.isEmpty { return isPreRelease(b) ? .orderedDescending : .orderedAscending }
        if b.isEmpty { return isPreRelease(a) ? .orderedAscending : .orderedDescending }
        let aPre = isPreRelease(a)
        let bPre = isPreRelease(b)
        if aPre != bPre { return aPre ? .orderedAscending : .orderedDescending }
        return a.compare(b, options: .numeric)
    }
}
