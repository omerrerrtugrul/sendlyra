# SendLyra

**Yerel ağda, güvenli ve doğrudan paylaşım.**

SendLyra; aynı yerel ağdaki bilgisayar, telefon ve tabletler arasında dosya,
klasör ve metin paylaşımı yapan, sunucu hesabı gerektirmeyen açık kaynaklı bir
Flutter uygulamasıdır. Cihazlar birbirini otomatik keşfeder; aktarım doğrudan
cihazlar arasında gerçekleşir.

> SendLyra bir bulut depolama hizmeti değildir. Verileriniz yerel ağınızın
> dışına gönderilmez.

## İçindekiler

- [Öne çıkan özellikler](#öne-çıkan-özellikler)
- [Nasıl çalışır?](#nasıl-çalışır)
- [Güvenlik modeli](#güvenlik-modeli)
- [Desteklenen platformlar](#desteklenen-platformlar)
- [Kurulum ve çalıştırma](#kurulum-ve-çalıştırma)
- [Kullanım](#kullanım)
- [Mimari](#mimari)
- [Geliştirme ve test](#geliştirme-ve-test)
- [Ağ ve güvenlik duvarı](#ağ-ve-güvenlik-duvarı)
- [Bilinen sınırlamalar](#bilinen-sınırlamalar)
- [Lisans](#lisans)

## Öne çıkan özellikler

### Doğrudan yerel ağ aktarımı

- UDP multicast ile aynı ağdaki SendLyra cihazlarını otomatik keşfeder.
- Dosya, klasör ve düz metin aktarımını destekler.
- Birden fazla aktarımı aynı anda yönetir.
- İlerleme, aktarım hızı ve tahmini kalan süreyi gösterir.
- Kesilen dosyaları kaldığı yerden sürdürür.
- Meşgul cihazlara yapılacak gönderimleri kuyruğa alır ve yeniden dener.

### Kontrollü paylaşım

- Gelen aktarım istekleri kullanıcı onayına sunulur.
- PIN koruması ve hatalı deneme kilidi bulunur.
- Güvenilir cihaz listesi kullanılabilir.
- QR koduyla cihaz bilgisi paylaşılabilir.
- Android paylaş menüsünden SendLyra'ya dosya veya metin gönderilebilir.
- Yerel web arayüzüyle tarayıcıdan dosya indirme ve yükleme yapılabilir.

### Kişiselleştirilebilir arayüz

- Türkçe ve İngilizce arayüz.
- Açık ve koyu tema.
- Dört vurgu rengi.
- Masaüstü ve dokunmatik ekranlar için uyarlanabilir düzen.

## Nasıl çalışır?

SendLyra iki ayrı ağ katmanı kullanır:

1. **Keşif:** Cihazlar UDP multicast beacon mesajlarıyla kendilerini duyurur.
2. **Aktarım:** Seçilen cihazla TCP bağlantısı kurulur ve aktarım uçtan uca
   şifreli kanal üzerinden yapılır.

Dosyalar herhangi bir merkezi sunucuya, hesaba veya üçüncü taraf depolama
servisine yüklenmez. Alıcı cihaz aktarımı onaylamadan dosya yazımı başlamaz.

Protokolün ayrıntılı teknik tanımı için
[docs/PROTOCOL.md](docs/PROTOCOL.md) dosyasına bakın.

## Güvenlik modeli

SendLyra, yerel ağdaki aktarım içeriğini korumak için şu mekanizmaları kullanır:

- **Anahtar değişimi:** X25519.
- **Oturum anahtarı türetme:** HKDF-SHA256.
- **Kanal şifreleme ve bütünlük:** ChaCha20-Poly1305.
- **Cihaz parmak izi:** Açık anahtarın SHA-256 özeti.
- **TOFU doğrulaması:** İlk bağlantıda parmak izi kaydedilir; sonraki
  bağlantılarda değişiklik tespit edilirse bağlantı reddedilir.
- **PIN doğrulaması:** PIN tanımlıysa kimlik doğrulaması yapılmadan gelen teklif
  kabul edilmez. Hatalı denemeler adres başına sınırlandırılır ve kilitlenir.
- **Dosya bütünlüğü:** Aktarım sonunda SHA-256 doğrulaması yapılır.
- **Yol güvenliği:** Dosya adları temizlenir ve hedef yolunun kayıt klasörü
  dışına çıkması engellenir.
- **Güvenli saklama:** PIN ve hassas yerel sırlar platformun güvenli kasasında
  saklanır (Android Keystore, Apple Keychain ve masaüstü karşılıkları).

### Güvenlik sınırı

Şifreleme, aktarım içeriğini yerel ağdaki dinleyicilere karşı korur. Ancak
cihazın işletim sistemi, hesabı veya ağın kendisi ele geçirilmişse SendLyra
bu tehditleri ortadan kaldıramaz. Cihazları ilk bağlantıda doğrulamanız ve
güvenmediğiniz cihazları onaylamamanız önerilir.

## Desteklenen platformlar

| Platform | Durum | Not |
| --- | --- | --- |
| Android | Destekleniyor | Android 8+ bildirim ve yerel ağ izinleri gerekir. |
| Windows | Destekleniyor | Visual Studio C++ masaüstü araçları gerekir. |
| macOS | Destekleniyor | Yerel ağ izni gerekir. |
| Linux | Destekleniyor | GTK 3 geliştirme paketleri gerekir. |
| iOS | Hazırlanıyor | Yerel ağ kullanım açıklaması ve imzalama ayarı gerekir. |
| Web | Deneysel | Aynı yerel ağda çalışan web paylaşım akışı içindir. |

## Kurulum ve çalıştırma

### Gereksinimler

- Flutter 3.27 veya üzeri.
- Dart 3.4 veya üzeri.
- Platforma uygun SDK ve derleme araçları.
- Android için USB hata ayıklaması açık bir cihaz veya Android emülatörü.

Flutter kurulumundan sonra:

```bash
git clone https://github.com/omerrerrtugrul/sendlyra.git
cd sendlyra
flutter pub get
flutter run
```

Bağlı cihazları görmek için:

```bash
flutter devices
```

Belirli bir cihazı seçerek çalıştırmak için:

```bash
flutter run -d <cihaz-id>
```

### Platform derlemeleri

```bash
# Android
flutter build apk --release

# Windows
flutter build windows --release

# macOS
flutter build macos --release

# Linux
flutter build linux --release
```

Windows derlemesinde `atlbase.h` veya `atlstr.h` bulunamıyorsa Visual Studio
Installer üzerinden **C++ ATL for latest v145 build tools (x86 & x64)**
bileşenini kurun. Ayrıca MSVC C++ araçları, Windows SDK ve CMake araçlarının
kurulu olduğundan emin olun.

## Kullanım

1. SendLyra'yı aynı yerel ağa bağlı cihazlarda açın.
2. **Cihazlar** ekranında hedef cihazın görünmesini bekleyin.
3. Dosya, klasör veya metin seçip hedef cihazı seçin.
4. Hedef cihazdaki kullanıcı aktarımı kabul ettiğinde işlem başlar.
5. Gerekiyorsa PIN girin veya cihazı güvenilir olarak işaretleyin.

### Android paylaş menüsü

Başka bir uygulamada **Paylaş** seçeneğini açıp SendLyra'yı seçebilirsiniz.
SendLyra, dosya ve metni gönderim akışına aktarır; birden fazla dosya
paylaşımı da desteklenir.

### Yerel web paylaşımı

Uygulamadaki **Web** ekranından yerel web sunucusunu başlatın. Gösterilen
yerel ağ adresini aynı ağa bağlı tarayıcıda açarak dosya indirebilir veya
yükleyebilirsiniz. PIN etkinse web oturumu da PIN ile korunur.

## Mimari

```text
lib/
├── app.dart                 # Uygulama kabuğu ve sağlayıcılar
├── core/
│   ├── models/              # Cihaz, aktarım ve geçmiş modelleri
│   ├── protocol/            # LyraLink, keşif, kanal ve aktarım protokolü
│   ├── services/            # Kimlik, ayar, keşif, aktarım ve web servisleri
│   └── utils/               # Biçimlendirme, hash ve yol güvenliği yardımcıları
└── ui/
    ├── screens/             # Cihazlar, aktarımlar, ayarlar ve web ekranları
    └── widgets/             # Ortak Material 3 bileşenleri
```

Temel çalışma akışı:

```text
UDP multicast keşfi
        ↓
cihaz parmak izi ve TOFU kontrolü
        ↓
X25519 + HKDF oturum kurulumu
        ↓
ChaCha20-Poly1305 şifreli TCP aktarımı
        ↓
SHA-256 bütünlük doğrulaması ve geçmiş kaydı
```

## Geliştirme ve test

Bağımlılıkları yükleyin:

```bash
flutter pub get
```

Statik analiz:

```bash
flutter analyze
```

Tüm testler:

```bash
flutter test
```

Test paketi; kriptografik anahtar türetme, kanal çerçeveleri, protokol
mesajları, PIN ve parmak izi doğrulaması, yol güvenliği, aktarım kuyruğu,
web oturumları, Android paylaş akışı ve Material 3 golden ekranlarını kapsar.

İki cihazla gerçek ağ testi için uygulamayı iki cihazda da başlatın ve aynı
Wi-Fi/LAN ağına bağlayın. Keşif çalışmıyorsa işletim sistemi güvenlik
duvarını, ağın istemci izolasyonu ayarını ve aşağıdaki portları kontrol edin.

## Ağ ve güvenlik duvarı

| Amaç | Protokol | Varsayılan port |
| --- | --- | --- |
| Cihaz keşfi | UDP multicast | `47801` |
| Dosya ve metin aktarımı | TCP | `47802` |
| Web paylaşımı | TCP | Uygulama içinde seçilir |

Kurumsal veya misafir Wi-Fi ağlarında istemci izolasyonu etkin olabilir. Bu
durumda cihazlar aynı SSID'de görünse bile birbirleriyle bağlantı kuramaz.

## Bilinen sınırlamalar

- Keşif ve doğrudan aktarım aynı yerel ağda veya birbirine erişebilen ağ
  segmentlerinde çalışır; internet üzerinden aktarım sağlamaz.
- VPN, misafir ağı ve istemci izolasyonu multicast veya TCP bağlantılarını
  engelleyebilir.
- Web modu yerel ağ paylaşımı içindir; HTTPS etkin değilse tarayıcıda açık
  HTTP uyarısı gösterilir.
- iOS ve bazı masaüstü platformlarında ilk çalıştırmada yerel ağ izinleri
  kullanıcı tarafından verilmelidir.

## Lisans

SendLyra, [MIT Lisansı](LICENSE) ile lisanslanmıştır.
