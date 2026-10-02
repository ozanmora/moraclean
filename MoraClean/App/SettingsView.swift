import SwiftUI

struct SettingsView: View {
    @AppStorage(AppSettingsKey.permanentDelete) private var permanentDelete = false
    @AppStorage(AppSettingsKey.brewUpdateBeforeScan) private var brewUpdateBeforeScan = true

    var body: some View {
        Form {
            Section("Temizlik") {
                Toggle("Dosyaları kalıcı olarak sil", isOn: $permanentDelete)
                Text(permanentDelete
                     ? "Seçilen dosyalar Çöp Kutusuna uğramadan silinir; geri alınamaz."
                     : "Seçilen dosyalar Çöp Kutusuna taşınır; yanlışlıkla silinen bir şeyi geri alabilirsiniz.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Güncellemeler") {
                Toggle("Taramadan önce Homebrew'u güncelle (brew update)", isOn: $brewUpdateBeforeScan)
                Text("Kapalıyken tarama hızlanır ama Homebrew yeni sürümleri henüz bilmiyor olabilir.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .padding(.vertical, 8)
    }
}
