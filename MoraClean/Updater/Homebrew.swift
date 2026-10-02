import Foundation

struct HomebrewCask: Sendable, Equatable {
    let token: String
    /// Homebrew'un kayıtlı kurulu sürümü (uygulama kendini güncellediyse eskimiş olabilir).
    let installedVersion: String?
    /// Cask'taki en güncel sürüm, virgülden sonraki derleme kısmı atılmış hali ("5.8.1,2349" → "5.8.1").
    let latestVersion: String
    let rawLatestVersion: String
    let autoUpdates: Bool
    /// Cask'ın kurduğu .app yolları.
    let appPaths: [String]
}

enum Homebrew {
    static var executable: String? { Shell.which("brew") }

    static var isAvailable: Bool { executable != nil }

    /// `brew update` — cask tanımlarını tazeler.
    static func update() async throws {
        guard let brew = executable else { return }
        try await Shell.runChecked(brew, ["update"], environment: ["HOMEBREW_NO_ENV_HINTS": "1"])
    }

    static func installedCasks() async throws -> [HomebrewCask] {
        guard let brew = executable else { return [] }
        let result = try await Shell.runChecked(
            brew, ["info", "--cask", "--installed", "--json=v2"],
            environment: ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"]
        )
        return try parseInstalledCasks(Data(result.stdout.utf8))
    }

    static func parseInstalledCasks(_ data: Data) throws -> [HomebrewCask] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let casks = root["casks"] as? [[String: Any]]
        else { return [] }

        return casks.compactMap { cask in
            guard let token = cask["token"] as? String else { return nil }
            let raw = (cask["version"] as? String) ?? ""
            let latest = raw.split(separator: ",", maxSplits: 1).first.map(String.init) ?? raw
            let installed = (cask["installed"] as? String)?.split(separator: ",", maxSplits: 1).first.map(String.init)
            let artifacts = cask["artifacts"] as? [Any] ?? []
            let appPaths = artifacts.flatMap(appPaths(from:))
            return HomebrewCask(
                token: token,
                installedVersion: installed,
                latestVersion: latest,
                rawLatestVersion: raw,
                autoUpdates: (cask["auto_updates"] as? Bool) ?? false,
                appPaths: appPaths
            )
        }
    }

    /// `{"app": ["Foo.app"], "target": "/Applications/Foo.app"}` veya eski biçim
    /// `{"app": ["Foo.app", {"target": "Bar.app"}]}` yapılarından .app yollarını çıkarır.
    private static func appPaths(from artifact: Any) -> [String] {
        guard let dict = artifact as? [String: Any], let apps = dict["app"] as? [Any] else { return [] }
        if let target = dict["target"] as? String { return [normalize(target)] }
        var paths: [String] = []
        var lastSource: String?
        for entry in apps {
            if let name = entry as? String {
                if let source = lastSource { paths.append(normalize(source)) }
                lastSource = name
            } else if let options = entry as? [String: Any], let target = options["target"] as? String {
                paths.append(normalize(target))
                lastSource = nil
            }
        }
        if let source = lastSource { paths.append(normalize(source)) }
        return paths
    }

    private static func normalize(_ path: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        if expanded.hasPrefix("/") { return URL(fileURLWithPath: expanded).standardizedFileURL.path }
        return URL(fileURLWithPath: "/Applications").appendingPathComponent((expanded as NSString).lastPathComponent).path
    }

    /// Cask için güncelleme var mı?
    /// İki koşul birlikte aranır: Homebrew kaydı eski **ve** uygulamanın gerçek sürümü cask sürümünden düşük.
    /// Böylece kendini güncelleyen uygulamalar (auto_updates) ve sürüm biçimi farklı cask'lar yanlış alarm vermez.
    static func hasUpdate(cask: HomebrewCask, app: InstalledApp) -> Bool {
        guard !cask.latestVersion.isEmpty, cask.latestVersion != "latest" else { return false }
        let brewOutdated = cask.installedVersion.map { VersionComparator.isNewer(cask.latestVersion, than: $0) } ?? true
        guard brewOutdated else { return false }
        let current = app.comparableVersion
        guard !current.isEmpty else { return true }
        return VersionComparator.isNewer(cask.latestVersion, than: current)
    }

    /// `brew upgrade --cask <token>`. Yönetici izni gerekirse SUDO_ASKPASS ile şifre penceresi açılır.
    static func upgrade(token: String, onLine: @escaping @Sendable (String) -> Void) async throws {
        guard let brew = executable else { throw ShellError.failed(command: "brew", result: ShellResult(status: 127, stdout: "", stderr: String(localized: "Homebrew was not found."))) }
        var env = ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1", "HOMEBREW_COLOR": "0", "HOMEBREW_NO_EMOJI": "1"]
        if let askpass = try? AskPass.scriptPath() { env["SUDO_ASKPASS"] = askpass }
        try await Shell.runChecked(brew, ["upgrade", "--cask", "--greedy", token], environment: env, onLine: onLine)
    }
}

/// sudo'nun GUI'den şifre isteyebilmesi için `SUDO_ASKPASS` betiği.
enum AskPass {
    static func scriptPath() throws -> String {
        let fm = FileManager.default
        let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("MoraClean", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let script = dir.appendingPathComponent("askpass.sh")
        let message = String(localized: "MoraClean needs your administrator password to install this update.")
        let title = String(localized: "MoraClean – Administrator Permission")
        let body = """
        #!/bin/sh
        # MoraClean: sudo'nun istediği yönetici şifresini macOS iletişim kutusuyla sorar.
        exec /usr/bin/osascript \\
          -e \(shellQuoted("text returned of (display dialog \(appleScriptString(message)) default answer \"\" with hidden answer with title \(appleScriptString(title)) with icon caution)"))
        """
        if (try? String(contentsOf: script, encoding: .utf8)) != body {
            try body.write(to: script, atomically: true, encoding: .utf8)
        }
        try fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)
        return script.path
    }

    /// AppleScript çift tırnaklı metin değişmezi.
    static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Kabuk için tek tırnaklı argüman.
    static func shellQuoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
