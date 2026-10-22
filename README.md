# SendLyra

**Yerel ağında özgürce paylaş.** Sunucusuz, şifreli, çapraz platform dosya ve
mesaj paylaşım uygulaması.

SendLyra, aynı yerel ağdaki cihazların birbirini otomatik bulup internet
kullanmadan dosya, klasör ve metin aktarmasını sağlar. Kendi ağı
(LyraLink) üzerinde çalışır; tüm kod ve protokol bu proje için özgün olarak
tasarlanmıştır.

## Özellikler

- **Otomatik keşif** — aynı ağdaki cihazlar saniyeler içinde listelenir
  (UDP multicast).
- **Uçtan uca şifreleme** — X25519 anahtar değişimi + ChaCha20-Poly1305;
  ağdaki kimse içeriği okuyamaz.
- **Çoklu aktarım** — eşzamanlı işler, ilerleme, hız ve kalan süre tahmini.
- **Devam ettirme** — yarıda kalan aktarımlar kaldığı yerden sürer.
- **Metin paylaşımı** — dosyaların yanında düz metin mesajları da gönderilir.
- **PIN + onay + güvenilir cihazlar** — gelen aktarımları sen kontrol edersin.
- **QR ile tanışma** — kendi bağlantı QR'ını göster, karşı taraf IP ile bağlanır.
- **TR / EN arayüz**, açık-koyu tema, 4 vurgu rengi.
- **Tamamen yerel** — hiçbir veri sunucuya gitmez, hesap gerekmez.

## Mimari

```
lib/
├── core/
│   ├── protocol/        # LyraLink protokolü (keşif, kanal, transfer)
│   ├── services/        # kimlik, ayarlar, keşif, transfer orkestrasyonu
│   ├── models/          # cihaz, transfer işi, geçmiş modelleri
│   └── utils/           # biçimlendirme yardımcıları
└── ui/                  # tema, ekranlar, widget'lar (Material 3)
```

Protokol detayları: [docs/PROTOCOL.md](docs/PROTOCOL.md)

## Geliştirme

Gereksinimler: [Flutter](https://docs.flutter.dev/get-started/install) 3.24+
(Dart 3.4+).

```bash
flutter pub get
flutter run            # bağlı cihaz/emülatör
flutter test           # birim testleri
flutter analyze        # statik analiz
```

### Platform derlemeleri

| Platform | Komut | Not |
|---|---|---|
| Android | `flutter build apk --release` | Ağ izinleri manifestte tanımlı |
| iOS | `flutter build ios --release` | Yerel ağ erişim açıklaması gerekir |
| Windows | `flutter build windows --release` | Windows 10+ |
| macOS | `flutter build macos --release` | Yerel ağ izni gerekir |
| Linux | `flutter build linux --release` | GTK 3 geliştirme paketleri |

> Güvenlik duvarı notu: ilk çalıştırmada UDP `47801` (keşif) ve TCP `47802`
> (transfer) portlarına izin verin.

## Test

```bash
flutter test
```

Birim testleri şunları kapsar: HKDF test vektörü (RFC 5869), oturum anahtarı
uyumu, kare mühürleme/çözme, bozuk kare reddi, protokol mesaj JSON turları,
biçimlendirme yardımcıları.

İki cihazla gerçek ağ testi için her iki makinede `flutter run` çalıştırıp
aynı Wi-Fi/LAN ağına bağlanmanız yeterli — cihazlar birkaç saniye içinde
birbirini görmelidir.

## Lisans

Bu projenin tüm kodu özgün olarak yazılmıştır. Dağıtmak isterseniz
`LICENSE` dosyası ekleyip (örn. Apache-2.0 veya MIT) seçiminizi belirtebilirsiniz.
