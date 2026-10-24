# SendLyra — Özellik Açığı Analizi (GAP_ANALYSIS)

Kaynak: sektör standartları ve ürün özellik envanteri (22 Ekim 2026) — mevcut kod ile karşılaştırma.
Not: Hedef, **özellik ve deneyim eşitliğidir**; mimari tamamen bize ait olan özgün LyraLink
protokolü üzerine kuruludur. Karşılaştırma yalnızca "ne var / ne yok" düzeyinde yapılır.

## ✅ Zaten Var
Tek/çoklu dosya gönderimi, metin mesajı, otomatik keşif (multicast), elle IP ile bağlanma,
cihaz detayı + parmak izi, gelen istek onayı, PIN, otomatik kabul, hedef klasör seçimi,
aktif transfer takibi + iptal, sha256 bütünlük doğrulaması, geçmiş + klasörde gösterme,
tema/dil/port ayarları, QR, sunucu yeniden başlatma.

## ✅ Tamamlandı (22 Ekim — 2. tur)
- 🗂️ **Klasör aktarımı** — özyinelemeli, klasör yapısı korunur (`rel` protokol alanı),
  dizin kaçışı korumalı güvenli yol yazımı (`path_safety.dart`)
- 📝 **Gönderim öncesi inceleme diyaloğu** — liste + öğe çıkarma + toplam boyut
- ⭐ **Favori cihazlar** — yıldızla ekle, özel ad ver, listede üstte göster
- ⚡ **Hızlı kaydetme kipleri** — Onay iste / Herkesten otomatik / Sadece favoriler
  (üçü birbirini dışlar; ayarlardan tek dokunuşla değişir)
- 📤 **Çoklu alıcıya gönderim** — çoklu seçim diyaloğu, her hedefe iş kaydı
- 🖱️ **Masaüstü sürükle-bırak** — pencereye bırakılan dosya/klasörler inceleme
  akışına girer (desktop_drop)

## ✅ Tamamlandı (24 Ekim — Faz 1: güvenlik & kritik düzeltmeler)
- 🔒 **K-1** El sıkışma kimlik doğrulaması: parmak izi artık tam SHA-256
  (64 hex) ve `fp == sha256(pk)` el sıkışmada zorunlu olarak doğrulanır;
  uyuşmazlıkta bağlantı reddedilir. Ek olarak TOFU pingleme: iz değişirse
  bağlantı reddedilir.
- 🔒 **K-2** Güvenilir cihazlar ve favoriler doğrulanmış parmak izine
  bağlandı (self-reported kimliğe değil). Güven kaydı artık taklit edilemez.
- 🔒 **K-3** PIN bypass kapatıldı: PIN tanımlıysa `auth`'suz gelen teklif
  doğrudan reddedilir. Sabit zamanlı PIN karşılaştırması + adres başına
  deneme kilidi (5 hatalı / 5 dk).
- 🔒 **K-4** Path traversal sertleştirildi: Windows sürücü-göreli
  referanslar (`C:...`), yedeklenmiş aygıt adları (`CON`, `NUL`, `COM1`…),
  geçersiz karakterler, sondaki nokta/boşluk, 255 bayt sınırı + nihai
  yolun kök altında kaldığı doğrulaması.
- 📡 **Y-5** Multicast grubu `224.0.0.167` (tüm platformlar/özellikle
  Android uyumlu) + Android `MulticastLock` (platform kanalı).
- 📄 **Y-6** Dosya adı çakışmasında sessiz ezme kalktı: `ad (2).ext`
  üretilir, son ad `accept.names` ile istemciye bildirilir.
- 🔁 **Y-7** Resume bütünlüğü tamamlandı: hash zincirine eski yarım
  dosyanın başı da katılır; her iki tarafta tam dosya özeti karşılaştırılır.
- ⚙️ **Y-8** Ayarlar canlı uygulanır: port/klasör/keşif değişince
  servisler otomatik yeniden başlar ("yeniden başlat" butonu aramaya gerek yok).
- ⚡ **Y-9** Performans: ilerleme bildirimleri 300 ms'de bir tazelenir;
  her 64 KB'da tam yeniden çizim tetiklenmez.
- 🧩 **Y-10** `pubspec` Flutter kısıtı `>=3.27.0` ile koddaki API kullanımı
  (Color.withValues) uyumlandı.
- ✅ **Y-11** Erken başarı ilanı kalktı: gönderici, alıcının `done`
  onayını bekler; hash reddi/hata gönderene yansır.
- 🧪 Doğrulama: **52/52 test** (yeni: 6 güvenlik entegrasyon testi —
  sahte parmak izi reddi, PIN bypass reddi, PIN kilidi, TOFU, güvenilir
  listesi; + Windows yol güvenliği vektörleri). `flutter analyze` temiz.
- 📖 `docs/PROTOCOL.md` protokol değişiklikleriyle güncellendi
  (fp doğrulaması, `names` alanı, done onayı, PIN kuralı, çakışma kuralı).

## ❌ Kalan Eksikler

> **24.10.2026 güncellemesi:** Yapılan kod incelemesinde aşağıdaki maddelerin
> aslında tamamlandığı doğrulandı — doküman bayat kalmıştı:
> - **#4 Geçmişten tekil kayıt silme + detay** → ✅ `transfers_page.dart`
>   (`detail` + `remove`) kodda mevcut.
> - **#8 "Alıcı meşgul" durumu** → ✅ beacon `busy` yayını + cihaz listesinde
>   `[meşgul]` rozeti mevcut; kalan: gönderim kuyruklaması.
> - **O-20 hata kodu yerelleştirmesi** → ✅ `AppStrings.errorText()` + UI
>   kullanımı doğrulandı.
> Ayrıca kapatılan rezidüel bulgular: R-2 (PIN kasa), R-4 (kök öneki),
> R-5 (bayt bazlı ad sınırı), R-6 (protokol limitleri), R-3 (göç diyaloğu).
> Yeni eklenenler: **QR tarama yok** (yeni madde #16), LICENSE/CHANGELOG
> (CHANGELOG eklendi; LICENSE için lisans kararı bekleniyor).

### Büyük özellikler
| # | Özellik | Not |
|---|---|---|
| 1 | 🌐 Tarayıcı paylaşımı (link ile ver/al, web PIN, HTTP/HTTPS) | Yerleşik web sunucusu + sayfa |
| 2 | 📡 Uzak ağ WebRTC + sinyal sunucusu (WebSocket) + STUN | Ağ altyapısı |
| 3 | 🖥️ sendlyra-cli terminal istemcisi | Ayrı paket |

### Orta özellikler
| # | Özellik |
|---|---|
| 5 | Panodan içerik gönderimi |
| 6 | Mobil Share Intent + Android APK seçimi + galeriye kaydetme |
| 7 | Bildirimler (tamamlandı uyarısı) |
| 9 | IPv6 + IP aralığı taraması (yedek keşif) |
| 16 | 📷 QR tarama (kamera ile bağlanma) + QR parmak izi karşılaştırmalı eşleşme (R-1) |

### Cila
| # | Özellik |
|---|---|
| 10 | Sistem tepsisi, her zaman üstte, pencere konumu, başlangıçta başlatma, `--hidden` |
| 11 | Windows bağlam menüsü, taşınabilir `settings.json` |
| 12 | Ağ arayüzü filtresi, keşif zaman aşımı, multicast grubu ayarları |
| 13 | Checksum aç/kapa, şifreleme aç/kapa, TOFU fingerprint doğrulama ekranı |
| 14 | Animasyon toggle, özel renk paletleri, 60 dil |
| 15 | Gizlilik politikası / changelog / sorun giderme ekranları |

## Önerilen sonraki sıra
1. ~~Geçmiş iyileştirmeleri~~ (tamam) + pano gönderimi (hızlı kazanımlar)
2. Bildirimler + meşgul kuyruklaması
3. 🌐 Tarayıcı paylaşımı (en değerli büyük özellik)
4. QR tarama (R-1 kapanışı) → WebRTC / CLI
