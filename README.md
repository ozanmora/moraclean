# MoraClean

macOS için tamamen yerel çalışan bakım uygulaması: gereksiz dosyaları temizler, kurulu uygulamaların güncellemelerini
bulur ve tek tek ya da toplu olarak günceller. Hesap, abonelik, telemetri ya da analitik yoktur.

## İndirme ve kurulum

1. [Releases](../../releases/latest) sayfasından `MoraClean-<sürüm>.zip` dosyasını indirin (Apple Silicon ve Intel için tek dosya).
2. Arşivi açın, `MoraClean.app` dosyasını **Uygulamalar** klasörüne taşıyın.
3. İlk açılış: uygulama Apple noter onayından (notarization) geçmediği için macOS ilk açılışı engeller.
   Bir kez açmayı deneyin, ardından **Sistem Ayarları › Gizlilik ve Güvenlik** bölümünde MoraClean için
   **Yine de Aç** düğmesine basın.

İndirilen dosyanın bütünlüğünü sürüm notlarındaki SHA-256 değeriyle karşılaştırabilirsiniz:

```bash
shasum -a 256 MoraClean-0.1.0.zip
```

## Özellikler

### Temizlik

| Kategori | Konum | Varsayılan |
|---|---|---|
| Kullanıcı önbellekleri | `~/Library/Caches` | seçili |
| Günlük dosyaları | `~/Library/Logs` | seçili |
| Xcode artıkları | `~/Library/Developer` altındaki DerivedData, DeviceSupport ve simülatör önbellekleri | seçili |
| Geliştirici önbellekleri | `~/.npm/_cacache`, `~/.composer/cache`, `~/.cache/composer`, `~/.gradle/caches`, `~/.yarn/berry/cache`, `~/.cargo/registry/cache` | seçili |
| Çöp Kutusu | `~/.Trash` (her zaman kalıcı silinir) | seçili değil |
| Kurulum dosyaları | `~/Downloads` içindeki `.dmg .pkg .mpkg .xip` dosyaları | seçili değil |

- Tarama yalnızca okur; hiçbir şey onayınız olmadan silinmez.
- Varsayılan olarak dosyalar **Çöp Kutusuna taşınır** (geri alınabilir). Ayarlar'dan kalıcı silmeye geçilebilir.
- Uygulama yalnızca yukarıdaki klasörlerin **doğrudan alt öğelerini** silebilir; başka bir yol kod düzeyinde reddedilir.

### Güncelleyici

`/Applications` ve `~/Applications` taranır (macOS ile gelen sistem uygulamaları hariç). Her uygulamanın güncelleme
kaynağı sırayla aranır:

1. **Homebrew cask** — uygulama Homebrew ile kurulduysa `brew upgrade --cask` ile güncellenir.
2. **Mac App Store** — sürüm bilgisi Apple'ın herkese açık arama servisinden alınır. Komut satırı aracı
   `mas` kuruluysa doğrudan güncellenir, değilse uygulamanın App Store sayfası açılır.
3. **Sparkle akışı** — uygulama kendi güncelleme akışını (`SUFeedURL`) yayınlıyorsa yeni sürüm indirilir ve kurulur.

Tek tek, seçilenleri ya da tümünü güncelleyebilir; istemediğiniz uygulamayı sağ tık › *Bu Uygulamayı Yoksay* ile
listeden çıkarabilirsiniz.

## İzinler ve erişimler

MoraClean sandbox dışında çalışır (önbellek klasörlerine ve `/Applications`'a erişebilmek için). Aşağıda uygulamanın
istediği ya da macOS'un sorabileceği **tüm** izinler ve nedenleri listelenmiştir.

### macOS izinleri

| İzin | Ne zaman istenir | Neden | Vermezseniz |
|---|---|---|---|
| **İndirilenler klasörüne erişim** | Temizlik taramasında; macOS ilk seferde sorar | "Kurulum Dosyaları" kategorisi `~/Downloads` içindeki `.dmg/.pkg/.xip` dosyalarını listeler | Bu kategori boş görünür, diğerleri çalışır |
| **Tam Disk Erişimi** (isteğe bağlı) | Siz vermediğiniz sürece hiç istenmez; uygulama yalnızca uyarı gösterir | Çöp Kutusu (`~/.Trash`) ve macOS'un koruduğu bazı önbellek klasörleri bu izin olmadan okunamaz | Bu klasörler "İzin gerekli" olarak işaretlenir ve atlanır |
| **Uygulama Yönetimi** | Bir uygulamayı güncellerken, macOS gerekli görürse | macOS, başka bir geliştiricinin uygulamasını değiştiren programlardan bu izni isteyebilir | O uygulamanın güncellemesi başarısız olur |
| **Yönetici şifresi** | Yalnızca bir Homebrew ya da `mas` güncellemesi yönetici yetkisi isterse | Sistem genelinde kurulum yapan paketler `sudo` gerektirir | O güncelleme başarısız olur |

Tam Disk Erişimi vermek için: **Sistem Ayarları › Gizlilik ve Güvenlik › Tam Disk Erişimi** › MoraClean'i ekleyin,
ardından uygulamayı yeniden başlatın.

**Yönetici şifresi hakkında:** Şifre, macOS'un kendi iletişim kutusuyla (`osascript`) sorulur ve doğrudan `sudo`
sürecine iletilir. MoraClean şifreyi kaydetmez, günlüğe yazmaz ve hiçbir yere göndermez. Bu iletişim kutusunu açan küçük
betik `~/Library/Application Support/MoraClean/askpass.sh` konumuna yalnızca sizin okuyabileceğiniz izinle (0700) yazılır.

### Ağ bağlantıları

Uygulama yalnızca siz **Tara** ya da **Güncelle** düğmesine bastığınızda ağa çıkar:

| Hedef | Amaç |
|---|---|
| `itunes.apple.com` | App Store uygulamalarının güncel sürüm numarasını sorgulamak (yalnızca paket kimlikleri gönderilir) |
| Her uygulamanın kendi güncelleme akışı ve indirme adresi | Sparkle ile güncellenen uygulamaların yeni sürümünü kontrol etmek ve indirmek |
| Homebrew'un kendi sunucuları | `brew update` / `brew upgrade` komutları üzerinden (Homebrew'un kendi davranışı) |

Kullanım verisi, cihaz bilgisi ya da kişisel veri hiçbir yere gönderilmez.

### Dosya sistemi ve diğer işlemler

- **Okuma:** Temizlik tablosundaki klasörler; `/Applications` ve `~/Applications` içindeki uygulamaların `Info.plist`
  dosyaları.
- **Silme / Çöp Kutusuna taşıma:** Yalnızca temizlik tablosundaki klasörlerin doğrudan alt öğeleri ve yalnızca siz
  onayladıktan sonra. Güncellenen uygulamanın eski sürümü Çöp Kutusuna taşınır.
- **Yazma:** Ayarlar (`~/Library/Preferences/works.mora.moraclean.plist`), yukarıdaki `askpass.sh` betiği ve indirmeler
  için geçici klasör (işlem bitince silinir).
- **Uygulamaları kapatma:** Sparkle ile güncellenen uygulama açıksa kapatma isteği gönderilir, güncellemeden sonra
  yeniden açılır.
- **Çalıştırılan komutlar:** `brew`, `mas`, `/usr/bin/ditto`, `/usr/bin/tar`, `/usr/bin/hdiutil`, `/usr/bin/codesign`,
  `/usr/bin/osascript` (yalnızca şifre iletişim kutusu için).

### Güncelleme güvenliği

Sparkle kaynağından gelen bir güncelleme kurulmadan önce:

1. Uygulama bir EdDSA anahtarı (`SUPublicEDKey`) yayınlıyorsa indirilen dosyanın imzası doğrulanır; imza yoksa ya da
   geçersizse kurulum durur.
2. Yeni sürümün kod imzası `codesign --verify --deep --strict` ile kontrol edilir.
3. Yeni sürümün geliştirici kimliği (Team ID) kurulu sürümle aynı olmalıdır.
4. Bir adım başarısız olursa eski sürüm yerinde kalır.

## Kaynaktan derleme

Gereksinimler: macOS 14 Sonoma veya üzeri, Xcode 16+, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project MoraClean.xcodeproj -scheme MoraClean -configuration Release -derivedDataPath build/DerivedData build
open build/DerivedData/Build/Products/Release/MoraClean.app
```

Testler:

```bash
xcodebuild -project MoraClean.xcodeproj -scheme MoraClean -derivedDataPath build/DerivedData test
```

## Proje yapısı

```
MoraClean/
  App/       Uygulama girişi, kenar çubuğu, ayarlar
  Core/      Komut çalıştırıcı, sürüm karşılaştırma, biçimlendirme
  Cleaner/   Temizlik kategorileri, tarama/silme motoru, arayüz
  Updater/   Uygulama envanteri, Homebrew / App Store / Sparkle kaynakları, kurulum, arayüz
MoraCleanTests/
tools/make-icon.swift   Uygulama ikonunu üretir (geometrik çizim)
```

## Marka notu

MoraClean bağımsız bir projedir; adı geçen hiçbir şirket ya da projeyle bağlantılı değildir ve onlar tarafından
desteklenmez. Apple, macOS, Mac App Store ve Xcode, Apple Inc.'in ticari markalarıdır. Homebrew, Sparkle, `mas`, npm,
Composer, Gradle, Yarn ve Cargo adları yalnızca birlikte çalışılan araçları belirtmek için kullanılır ve ilgili
sahiplerine aittir.
