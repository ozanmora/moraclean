import AppKit
import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKey.permanentDelete) private var permanentDelete = false
    @AppStorage(AppSettingsKey.brewUpdateBeforeScan) private var brewUpdateBeforeScan = true
    @State private var language = AppLanguage.current
    private let launchLanguage = AppLanguage.current

    var body: some View {
        Form {
            Section("Language") {
                Picker("App language", selection: $language) {
                    Text("System").tag(AppLanguage.system)
                    ForEach(AppLanguage.explicit, id: \.self) { option in
                        // Dil adları her zaman kendi dilinde gösterilir.
                        Text(verbatim: option.nativeName).tag(option)
                    }
                }
                .onChange(of: language) { _, newValue in
                    AppLanguage.current = newValue
                }
                if language != launchLanguage {
                    HStack {
                        Text("The new language is applied after a restart.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Restart Now") { AppLanguage.relaunch() }
                    }
                }
            }
            Section("Cleanup") {
                Toggle("Delete files permanently", isOn: $permanentDelete)
                Text(permanentDelete
                     ? "Selected files are deleted without going to the Trash. This cannot be undone."
                     : "Selected files are moved to the Trash, so you can restore anything deleted by mistake.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Updates") {
                Toggle("Update Homebrew before scanning (brew update)", isOn: $brewUpdateBeforeScan)
                Text("Turning this off makes scans faster, but Homebrew may not know about the newest versions yet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SupportSection()
        }
        .formStyle(.grouped)
        // Tüm bölümler kaydırmadan görünsün.
        .frame(width: 480, height: 580)
        .padding(.vertical, 8)
    }
}

/// Uygulamaya özel dil tercihi. macOS bu tercihi uygulamanın `AppleLanguages` ayarından okur;
/// değişiklik yeniden başlatınca uygulanır. "System" seçiliyken macOS dili izlenir.
enum AppLanguage: String, Hashable, CaseIterable {
    case system, english = "en", turkish = "tr"

    static let explicit: [AppLanguage] = [.english, .turkish]

    var nativeName: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .turkish: "Türkçe"
        }
    }

    static var current: AppLanguage {
        get {
            let domain = Bundle.main.bundleIdentifier.flatMap { UserDefaults.standard.persistentDomain(forName: $0) }
            guard let code = (domain?["AppleLanguages"] as? [String])?.first else { return .system }
            return explicit.first { code.hasPrefix($0.rawValue) } ?? .system
        }
        set {
            if newValue == .system {
                UserDefaults.standard.removeObject(forKey: "AppleLanguages")
            } else {
                UserDefaults.standard.set([newValue.rawValue], forKey: "AppleLanguages")
            }
        }
    }

    /// Uygulamayı kapatıp yeniden açar.
    @MainActor
    static func relaunch() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }
}
