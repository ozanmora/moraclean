import CryptoKit
import Foundation
import Testing
@testable import MoraClean

private func app(version: String, build: String = "1", publicKey: String? = nil) -> InstalledApp {
    InstalledApp(
        url: URL(fileURLWithPath: "/Applications/Test.app"),
        name: "Test",
        bundleID: "com.example.test",
        version: version,
        build: build,
        sparkleFeedURL: URL(string: "https://example.com/appcast.xml"),
        sparklePublicEDKey: publicKey,
        isFromAppStore: false
    )
}

struct AppcastTests {
    let feed = """
    <?xml version="1.0" encoding="utf-8"?>
    <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
      <channel>
        <title>Test</title>
        <item>
          <title>2.0 beta</title>
          <sparkle:version>200</sparkle:version>
          <sparkle:shortVersionString>2.0b1</sparkle:shortVersionString>
          <sparkle:channel>beta</sparkle:channel>
          <enclosure url="https://example.com/Test-2.0b1.zip" length="10" type="application/octet-stream"/>
        </item>
        <item>
          <title>1.5</title>
          <sparkle:version>150</sparkle:version>
          <sparkle:shortVersionString>1.5</sparkle:shortVersionString>
          <sparkle:minimumSystemVersion>11.0</sparkle:minimumSystemVersion>
          <enclosure url="https://example.com/Test-1.5.zip" length="1234" type="application/octet-stream" sparkle:edSignature="abc=="/>
        </item>
        <item>
          <title>Gelecek sürüm</title>
          <enclosure url="https://example.com/Test-9.dmg" sparkle:version="900" sparkle:shortVersionString="9.0" length="1"/>
          <sparkle:minimumSystemVersion>99.0</sparkle:minimumSystemVersion>
        </item>
        <item>
          <title>1.4 (eski biçim)</title>
          <enclosure url="https://example.com/Test-1.4.zip" sparkle:version="140" sparkle:shortVersionString="1.4" length="1"/>
        </item>
      </channel>
    </rss>
    """

    @Test func parsesBothFormats() {
        let items = AppcastParser.parse(Data(feed.utf8))
        #expect(items.count == 4)
        #expect(items[0].channel == "beta")
        #expect(items[1].edSignature == "abc==")
        #expect(items[1].length == 1234)
        #expect(items[3].version == "140")
        #expect(items[3].shortVersion == "1.4")
    }

    @Test func picksLatestStableCompatibleItem() {
        let items = AppcastParser.parse(Data(feed.utf8))
        let latest = SparkleChecker.latestItem(in: items, osVersion: OperatingSystemVersion(majorVersion: 14, minorVersion: 0, patchVersion: 0))
        #expect(latest?.shortVersion == "1.5")
    }

    @Test func comparesAgainstInstalledApp() {
        let item = AppcastItem(version: "150", shortVersion: "1.5", downloadURL: URL(string: "https://example.com/a.zip"))
        #expect(SparkleChecker.isNewer(item, than: app(version: "1.4", build: "140")))
        #expect(!SparkleChecker.isNewer(item, than: app(version: "1.5", build: "150")))
        // Görünen sürüm aynı, derleme yeni.
        #expect(SparkleChecker.isNewer(item, than: app(version: "1.5", build: "149")))
    }

    @Test func verifiesEdSignature() throws {
        let key = Curve25519.Signing.PrivateKey()
        let payload = Data("arşiv içeriği".utf8)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try payload.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let signature = try key.signature(for: payload).base64EncodedString()

        try SparkleInstaller.verifyEdSignature(archive: file, signature: signature, publicKey: publicKey)
        let wrong = try Curve25519.Signing.PrivateKey().signature(for: payload).base64EncodedString()
        #expect(throws: InstallError.self) {
            try SparkleInstaller.verifyEdSignature(archive: file, signature: wrong, publicKey: publicKey)
        }
        #expect(throws: InstallError.self) {
            try SparkleInstaller.verifyEdSignature(archive: file, signature: nil, publicKey: publicKey)
        }
        // Uygulama anahtar yayınlamıyorsa EdDSA kontrolü atlanır.
        try SparkleInstaller.verifyEdSignature(archive: file, signature: nil, publicKey: nil)
    }
}

struct HomebrewTests {
    let json = """
    {"formulae": [], "casks": [
      {"token": "sample-mouse", "installed": "0.10.4", "version": "0.11.4", "auto_updates": true,
       "artifacts": [{"uninstall": []}, {"app": ["SampleMouse.app"], "target": "/Applications/SampleMouse.app"}, {"zap": []}]},
      {"token": "sample-launcher", "installed": "5.7.2,2312", "version": "5.8.1,2349", "auto_updates": true,
       "artifacts": [{"app": ["Sample Launcher 5.app"]}]},
      {"token": "old-style", "installed": "1.0", "version": "1.0",
       "artifacts": [{"app": ["Foo.app", {"target": "Bar.app"}]}]},
      {"token": "sample-driver", "installed": "2024", "version": "27", "artifacts": [{"pkg": ["x.pkg"]}]}
    ]}
    """

    @Test func parsesCasks() throws {
        let casks = try Homebrew.parseInstalledCasks(Data(json.utf8))
        #expect(casks.count == 4)
        #expect(casks[0].appPaths == ["/Applications/SampleMouse.app"])
        #expect(casks[1].latestVersion == "5.8.1")
        #expect(casks[1].installedVersion == "5.7.2")
        #expect(casks[1].appPaths == ["/Applications/Sample Launcher 5.app"])
        #expect(casks[2].appPaths == ["/Applications/Bar.app"])
        #expect(casks[3].appPaths.isEmpty)
    }

    @Test func detectsUpdatesWithoutFalsePositives() throws {
        let casks = try Homebrew.parseInstalledCasks(Data(json.utf8))
        // Homebrew kaydı eski ama uygulama kendini güncellemiş → güncelleme yok.
        #expect(!Homebrew.hasUpdate(cask: casks[0], app: app(version: "0.11.4")))
        // Gerçekten eski.
        #expect(Homebrew.hasUpdate(cask: casks[1], app: app(version: "5.7.2", build: "2312")))
        // Büyük derleme numarası güncellemeyi gizlememeli.
        #expect(Homebrew.hasUpdate(cask: casks[1], app: app(version: "5.7.2", build: "999999")))
        // Görünen sürüm kısa, derleme ayrıntılı: "136.0" / "136.0.6008.80".
        #expect(!Homebrew.hasUpdate(cask: casks[1], app: app(version: "5.8", build: "5.8.1.2349")))
        #expect(Homebrew.hasUpdate(cask: casks[1], app: app(version: "5.8", build: "5.8.0.1")))
        // Homebrew kaydı güncel.
        #expect(!Homebrew.hasUpdate(cask: casks[2], app: app(version: "0.1")))
    }
}

struct InstalledAppTests {
    @Test func comparableVersion() {
        #expect(app(version: "136.0", build: "136.0.6008.52").comparableVersion == "136.0.6008.52")
        #expect(app(version: "4.91.0", build: "239619").comparableVersion == "4.91.0")
        #expect(app(version: "", build: "6.1").comparableVersion == "6.1")
        #expect(app(version: "154.0.8037.93", build: "8037.93").comparableVersion == "154.0.8037.93")
    }
}

struct AppStoreTests {
    @Test func parsesLookup() throws {
        let json = """
        {"resultCount": 1, "results": [{"bundleId": "com.example.windowtool", "trackId": 1000000001, "version": "3.0.7", "minimumOsVersion": "13.0"}]}
        """
        let listings = try AppStore.parseLookup(Data(json.utf8))
        #expect(listings == [AppStoreListing(bundleID: "com.example.windowtool", trackID: 1000000001, version: "3.0.7", minimumOSVersion: "13.0", releaseNotes: nil)])
        #expect(AppStore.isCompatible(listings[0]))
        #expect(!AppStore.isCompatible(AppStoreListing(bundleID: "x", trackID: 1, version: "1", minimumOSVersion: "99.0", releaseNotes: nil)))
    }
}
