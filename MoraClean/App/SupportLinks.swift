import SwiftUI

/// Projeyi desteklemek için bağlantılar. Yalnızca kullanıcı tıklayınca tarayıcıda açılır.
enum SupportLinks {
    static let githubSponsors = URL(string: "https://github.com/sponsors/ozanmora")!
    static let buyMeACoffee = URL(string: "https://buymeacoffee.com/ozanmora")!
}

/// Uygulama menüsünde "Hakkında"nın altına destek komutları.
struct SupportCommands: Commands {
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Sponsor on GitHub…") { openURL(SupportLinks.githubSponsors) }
            Button("Buy Me a Coffee…") { openURL(SupportLinks.buyMeACoffee) }
        }
    }
}

/// Ayarlar'daki destek bölümü.
struct SupportSection: View {
    var body: some View {
        Section("Support MoraClean") {
            Text("MoraClean is free and open source. If it saves you time, you can support its development.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Link(destination: SupportLinks.githubSponsors) {
                    Label("Sponsor on GitHub", systemImage: "heart")
                }
                Spacer()
                Link(destination: SupportLinks.buyMeACoffee) {
                    Label("Buy Me a Coffee", systemImage: "cup.and.saucer")
                }
            }
        }
    }
}
