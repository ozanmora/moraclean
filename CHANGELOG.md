# Changelog

Biçim [Keep a Changelog](https://keepachangelog.com/tr-TR/1.1.0/), sürümleme [SemVer](https://semver.org/lang/tr/).

## [0.3.0] - 2026-10-02

### Değişti
- Temizlik ekranı: kategoriler akordeon oldu. Başlığın tamamına tıklayınca açılıp kapanır, ok en sağda "V" biçiminde.
- Onay kutuları her seviyede aynı hizada; macOS'un kendi onay kutusu kullanılıyor ve kısmi seçimde "–" gösteriyor.

### Eklendi
- Kullanıcı Önbellekleri uygulamalara göre gruplanır: klasörler paket kimliği ya da ada göre kurulu uygulamalarla
  eşleştirilir, uygulamanın ikonu ve adıyla gösterilir. Eşleşmeyen klasörler tek başına listelenir.
- Ağaç görünümü: klasörlerin içeriğine boyutlarıyla göz atılabilir (açıldıkça yüklenir); her satırda Finder'da göster.
- Erişilebilirlik: akordeon başlıkları ve ağaç satırları VoiceOver'da açılıp kapanabilir düğmeler olarak okunur.

## [0.2.0] - 2026-10-02

### Eklendi
- Arayüze İngilizce dil desteği. Geliştirme dili İngilizce, Türkçe tam çeviri olarak String Catalog'da
  (`MoraClean/Resources/Localizable.xcstrings`); İngilizcede tekil/çoğul biçimleri.
- Ayarlar'da dil seçimi (Sistem / English / Türkçe) ve "Şimdi Yeniden Başlat" düğmesi.
- Yönetici şifresi penceresi de seçili dilde; metin AppleScript ve kabuk için güvenli biçimde kaçışlanır.
- Testler: tüm metinlerin Türkçe çevirisi ve yer tutucu uyumu, paketlenen çeviriler, çoğul biçimleri, kaçışlama.

## [0.1.1] - 2026-10-02

### Eklendi
- MIT lisansı (`LICENSE`); README'ye lisans bölümü, indirilebilir pakete LICENSE dosyası.

## [0.1.0] - 2026-10-02

### Eklendi
- **Temizlik**: kullanıcı önbellekleri, günlükler, Xcode artıkları (DerivedData, DeviceSupport, simülatör önbellekleri),
  geliştirici önbellekleri (npm, Composer, Gradle, Yarn, Cargo), Çöp Kutusu ve İndirilenler'deki kurulum dosyaları.
  Kategori ya da tek tek öğe seçimi, Finder'da gösterme, boyut özeti.
- Silme modu ayarı: varsayılan **Çöp Kutusuna taşı**, istenirse kalıcı silme. Çöp Kutusu kategorisi her zaman kalıcı silinir.
- Güvenlik: yalnızca tanımlı klasörlerin doğrudan alt öğeleri silinebilir; Tam Disk Erişimi gerektiren klasörler için uyarı.
- **Güncelleyici**: /Applications ve ~/Applications taranır, kaynak otomatik bulunur:
  - Homebrew cask (`brew upgrade --cask`; yönetici izni gerekirse şifre penceresi). Kendini güncelleyen uygulamalar
    yanlış alarm vermez (kurulu sürüm ile cask sürümü karşılaştırılır).
  - Mac App Store (Apple lookup API; `mas` kuruluysa doğrudan, değilse App Store sayfası açılır).
  - Sparkle appcast: indirme, EdDSA imza doğrulaması, kod imzası ve Team ID kontrolü, eski sürüm Çöp Kutusuna,
    açıksa uygulamayı kapatıp yeniden açma. Beta kanalları ve uyumsuz macOS sürümleri atlanır.
- Tekil, seçili ya da tüm güncellemeleri sırayla uygulama; satır bazında ilerleme; uygulama yoksayma.
- Kenar çubuğunda başlangıç diski doluluğu, ayarlar penceresi.
- README'de uygulamanın istediği tüm izinler, ağ bağlantıları ve dosya erişimleri belgelendi.
- İndirilebilir derlenmiş sürüm (Apple Silicon + Intel) GitHub Releases'ta.
- Birim testleri (Swift Testing) ve GitHub Actions CI.
