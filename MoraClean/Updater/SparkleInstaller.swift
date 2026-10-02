import AppKit
import CryptoKit
import Foundation
import Security

enum InstallError: LocalizedError {
    case missingDownload
    case downloadFailed(Int)
    case missingSignature
    case invalidSignature
    case unsupportedArchive(String)
    case appNotFoundInArchive
    case codeSignatureInvalid(String)
    case teamMismatch(expected: String, found: String?)
    case appStillRunning
    case replaceFailed(String)
    /// .pkg gibi kullanıcı etkileşimi gerektiren kurulumlar Yükleyici'de açıldı.
    case handedOffToInstaller

    var errorDescription: String? {
        switch self {
        case .missingDownload: String(localized: "The appcast has no download link.")
        case let .downloadFailed(code): String(localized: "Download failed (HTTP \(code)).")
        case .missingSignature: String(localized: "The app expects an EdDSA signature but the update has none; it was not installed for safety.")
        case .invalidSignature: String(localized: "The downloaded file has an invalid EdDSA signature; it was not installed for safety.")
        case let .unsupportedArchive(ext): String(localized: "Unsupported archive format: .\(ext)")
        case .appNotFoundInArchive: String(localized: "The archive contains no app with the same bundle identifier.")
        case let .codeSignatureInvalid(reason): String(localized: "Could not verify the new version's code signature: \(reason)")
        case let .teamMismatch(expected, found): String(localized: "The developer identity does not match (expected \(expected), found \(found ?? String(localized: "none"))); it was not installed.")
        case .appStillRunning: String(localized: "The app could not be quit. Quit it and try again.")
        case let .replaceFailed(reason): String(localized: "Could not replace the app: \(reason)")
        case .handedOffToInstaller: String(localized: "The installer package was opened in Installer; complete the steps there.")
        }
    }
}

/// Sparkle güncellemesini Sparkle'ın kendisi olmadan uygular:
/// indir → EdDSA imzasını doğrula → aç → kod imzası ve Team ID kontrolü → uygulamayı kapat → değiştir → yeniden aç.
enum SparkleInstaller {
    static func install(app: InstalledApp, item: AppcastItem, progress: @escaping @Sendable (String) -> Void) async throws {
        guard let downloadURL = item.downloadURL else { throw InstallError.missingDownload }
        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("MoraClean-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        progress(String(localized: "Downloading…"))
        let (temp, response) = try await URLSession.shared.download(from: downloadURL)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw InstallError.downloadFailed(http.statusCode)
        }
        let fileName = response.suggestedFilename ?? downloadURL.lastPathComponent
        let archive = work.appendingPathComponent(fileName.isEmpty ? "update" : fileName)
        try fm.moveItem(at: temp, to: archive)

        progress(String(localized: "Verifying signature…"))
        try verifyEdSignature(archive: archive, signature: item.edSignature, publicKey: app.sparklePublicEDKey)

        if ["pkg", "mpkg"].contains(archive.pathExtension.lowercased()) {
            // Paket kurulumları yönetici izni ve kullanıcı onayı ister; Yükleyici'ye bırakılır.
            let keep = fm.temporaryDirectory.appendingPathComponent(archive.lastPathComponent)
            try? fm.removeItem(at: keep)
            try fm.copyItem(at: archive, to: keep)
            _ = await MainActor.run { NSWorkspace.shared.open(keep) }
            throw InstallError.handedOffToInstaller
        }

        progress(String(localized: "Extracting…"))
        let extracted = work.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        try await extract(archive, to: extracted)

        guard let newApp = findApp(bundleID: app.bundleID, in: extracted) else { throw InstallError.appNotFoundInArchive }

        progress(String(localized: "Checking code signature…"))
        try await verifyCodeSignature(newApp: newApp, oldApp: app.url)

        progress(String(localized: "Installing…"))
        let wasRunning = try await quitIfRunning(bundleID: app.bundleID, path: app.url)
        try replace(app.url, with: newApp)
        if wasRunning {
            let target = app.url
            await MainActor.run {
                NSWorkspace.shared.openApplication(at: target, configuration: NSWorkspace.OpenConfiguration())
            }
        }
    }

    // MARK: - EdDSA

    static func verifyEdSignature(archive: URL, signature: String?, publicKey: String?) throws {
        guard let publicKey, !publicKey.isEmpty else { return } // Uygulama anahtar yayınlamıyorsa kod imzası kontrolüne güvenilir.
        guard let signature, !signature.isEmpty else { throw InstallError.missingSignature }
        guard let keyData = Data(base64Encoded: publicKey),
              let signatureData = Data(base64Encoded: signature),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { throw InstallError.invalidSignature }
        let data = try Data(contentsOf: archive, options: .mappedIfSafe)
        guard key.isValidSignature(signatureData, for: data) else { throw InstallError.invalidSignature }
    }

    // MARK: - Arşiv

    private static func extract(_ archive: URL, to destination: URL) async throws {
        let name = archive.lastPathComponent.lowercased()
        if name.hasSuffix(".zip") {
            try await Shell.runChecked("/usr/bin/ditto", ["-x", "-k", archive.path, destination.path])
        } else if name.hasSuffix(".tar") || name.hasSuffix(".tar.gz") || name.hasSuffix(".tgz")
                    || name.hasSuffix(".tar.bz2") || name.hasSuffix(".tbz") || name.hasSuffix(".tar.xz") {
            try await Shell.runChecked("/usr/bin/tar", ["-xf", archive.path, "-C", destination.path])
        } else if name.hasSuffix(".dmg") {
            let mount = destination.deletingLastPathComponent().appendingPathComponent("mount", isDirectory: true)
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            try await Shell.runChecked("/usr/bin/hdiutil", ["attach", archive.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path])
            do {
                guard let app = findApp(bundleID: nil, in: mount) else { throw InstallError.appNotFoundInArchive }
                try await Shell.runChecked("/usr/bin/ditto", [app.path, destination.appendingPathComponent(app.lastPathComponent).path])
            } catch {
                _ = try? await Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
                throw error
            }
            _ = try? await Shell.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
        } else {
            throw InstallError.unsupportedArchive(archive.pathExtension)
        }
    }

    /// Klasörde (en fazla 3 seviye) .app arar; `bundleID` verilirse onunla eşleşeni döndürür.
    static func findApp(bundleID: String?, in directory: URL, depth: Int = 3) -> URL? {
        guard depth > 0,
              let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return nil }
        let apps = children.filter { $0.pathExtension == "app" }
        if let match = apps.first(where: { bundleID == nil || bundleIdentifier(of: $0) == bundleID }) { return match }
        for child in children where child.pathExtension != "app" {
            guard (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { continue }
            if let found = findApp(bundleID: bundleID, in: child, depth: depth - 1) { return found }
        }
        return nil
    }

    private static func bundleIdentifier(of app: URL) -> String? {
        guard let data = try? Data(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        return info["CFBundleIdentifier"] as? String
    }

    // MARK: - Kod imzası

    private static func verifyCodeSignature(newApp: URL, oldApp: URL) async throws {
        let result = try await Shell.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path])
        guard result.succeeded else { throw InstallError.codeSignatureInvalid(result.failureSummary) }
        if let expected = teamIdentifier(of: oldApp) {
            let found = teamIdentifier(of: newApp)
            guard found == expected else { throw InstallError.teamMismatch(expected: expected, found: found) }
        }
    }

    static func teamIdentifier(of url: URL) -> String? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return nil }
        return dict[kSecCodeInfoTeamIdentifier as String] as? String
    }

    // MARK: - Değiştirme

    /// Uygulama açıksa kapatır; açık olup olmadığını döndürür.
    @MainActor
    private static func quitIfRunning(bundleID: String, path: URL) async throws -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.bundleURL?.standardizedFileURL == path.standardizedFileURL }
        guard !running.isEmpty else { return false }
        running.forEach { $0.terminate() }
        for _ in 0..<40 {
            if running.allSatisfy(\.isTerminated) { return true }
            try await Task.sleep(for: .milliseconds(250))
        }
        throw InstallError.appStillRunning
    }

    /// Eski uygulamayı Çöp Kutusuna taşır, yenisini aynı yere koyar. Hata olursa eskisini geri getirir.
    private static func replace(_ old: URL, with new: URL) throws {
        let fm = FileManager.default
        var trashed: NSURL?
        do {
            try fm.trashItem(at: old, resultingItemURL: &trashed)
        } catch {
            throw InstallError.replaceFailed(error.localizedDescription)
        }
        do {
            try fm.moveItem(at: new, to: old)
        } catch {
            if let trashed = trashed as URL? { try? fm.moveItem(at: trashed, to: old) }
            throw InstallError.replaceFailed(error.localizedDescription)
        }
    }
}
