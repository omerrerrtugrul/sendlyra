# SendLyra — Özellik Açığı Analizi (GAP_ANALYSIS)

Kaynak: `SendLyra_Ozellik_Raporu_TR.pdf` (22 Ekim 2026) — mevcut kod ile karşılaştırma.
Not: Rapor, Rust çekirdek + HTTP API v2 + port 53317'lik farklı bir mimari tarif ediyor.
Biz **özgün LyraLink protokolünü** koruyoruz; özellikler bu mimariye uyarlanabilir.

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

## ❌ Kalan Eksikler

### Büyük özellikler
| # | Özellik | Not |
|---|---|---|
| 1 | 🌐 Tarayıcı paylaşımı (link ile ver/al, web PIN, HTTP/HTTPS) | Yerleşik web sunucusu + sayfa |
| 2 | 📡 Uzak ağ WebRTC + sinyal sunucusu (WebSocket) + STUN | Ağ altyapısı |
| 3 | 🖥️ sendlyra-cli terminal istemcisi | Ayrı paket |

### Orta özellikler
| # | Özellik |
|---|---|
| 4 | Geçmişten tekil kayıt silme + detay görünümü |
| 5 | Panodan içerik gönderimi |
| 6 | Mobil Share Intent + Android APK seçimi + galeriye kaydetme |
| 7 | Bildirimler (tamamlandı uyarısı) |
| 8 | "Alıcı meşgul" durumu |
| 9 | IPv6 + IP aralığı taraması (yedek keşif) |

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
1. Geçmiş iyileştirmeleri + pano gönderimi (hızlı kazanımlar)
2. Bildirimler + meşgul durumu
3. 🌐 Tarayıcı paylaşımı (en değerli büyük özellik)
4. WebRTC / CLI
