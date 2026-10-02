import Foundation
import Testing
@testable import MoraClean

struct VersionComparatorTests {
    @Test(arguments: [
        ("1.2.10", "1.2.9"),
        ("2.0", "1.99.99"),
        ("1.0.1", "1.0"),
        ("v0.12.0", "0.11.4"),
        ("1.0", "1.0-beta.6"),
        ("1.0-rc.2", "1.0-rc.1"),
        ("4215", "Build 4200"),
        ("154.0.8037.98", "146.0.7680.80"),
    ])
    func newer(candidate: String, current: String) {
        #expect(VersionComparator.isNewer(candidate, than: current))
        #expect(!VersionComparator.isNewer(current, than: candidate))
    }

    @Test(arguments: [("1.0", "1.0.0"), ("v2.3", "2.3"), ("3.0.7", "3.0.7")])
    func same(a: String, b: String) {
        #expect(VersionComparator.compare(a, b) == .orderedSame)
    }

    @Test func parsesPrefixAndSuffix() {
        let parsed = VersionComparator.parse("Build 4200 (beta)")
        #expect(parsed.numbers == [4200])
        #expect(parsed.suffix == "(beta)")
    }
}
