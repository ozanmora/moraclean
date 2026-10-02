import Foundation
import Testing
@testable import MoraClean

struct LocalizationTests {
    private static let catalogURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("MoraClean/Resources/Localizable.xcstrings")

    private static let placeholder = try! NSRegularExpression(pattern: "%(?:lld|ld|d|@)")

    private static func placeholders(_ text: String) -> [String] {
        placeholder.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    @Test func everyStringHasTurkishTranslation() throws {
        let data = try Data(contentsOf: Self.catalogURL)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(root["sourceLanguage"] as? String == "en")
        let strings = try #require(root["strings"] as? [String: [String: Any]])
        #expect(!strings.isEmpty)

        for (key, entry) in strings {
            if entry["shouldTranslate"] as? Bool == false { continue }
            let localizations = entry["localizations"] as? [String: Any]
            let unit = (localizations?["tr"] as? [String: Any])?["stringUnit"] as? [String: Any]
            #expect(unit?["state"] as? String == "translated", "Türkçe çeviri eksik: \(key)")
            if let value = unit?["value"] as? String {
                #expect(Self.placeholders(value) == Self.placeholders(key), "Yer tutucular uyuşmuyor: \(key)")
            }
        }
    }

    @Test func appBundleShipsTurkish() throws {
        let path = try #require(Bundle.main.path(forResource: "tr", ofType: "lproj"))
        let turkish = try #require(Bundle(path: path))
        #expect(turkish.localizedString(forKey: "Scan Again", value: nil, table: nil) == "Yeniden Tara")
        #expect(turkish.localizedString(forKey: "Updates Available (%lld)", value: nil, table: nil) == "Güncelleme Var (%lld)")
    }

    @Test func englishPluralForms() throws {
        let path = try #require(Bundle.main.path(forResource: "en", ofType: "lproj"))
        let english = try #require(Bundle(path: path))
        let format = english.localizedString(forKey: "%lld items", value: nil, table: nil)
        let locale = Locale(identifier: "en")
        #expect(String(format: format, locale: locale, 1) == "1 item")
        #expect(String(format: format, locale: locale, 3) == "3 items")
    }
}

struct AskPassQuotingTests {
    private let tricky = "Şifre \"gerekli\" – it's a \\ test"

    @Test func shellQuotingRoundTrips() async throws {
        let result = try await Shell.run("/bin/sh", ["-c", "printf %s \(AskPass.shellQuoted(tricky))"])
        #expect(result.stdout == tricky)
    }

    @Test func appleScriptStringRoundTrips() async throws {
        let result = try await Shell.run("/usr/bin/osascript", ["-e", "return \(AskPass.appleScriptString(tricky))"])
        #expect(result.stdout.trimmingCharacters(in: .newlines) == tricky)
    }
}
