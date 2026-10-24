# Değişiklik Günlüğü (CHANGELOG)

Bu dosya SendLyra sürümleri arasındaki önemli değişiklikleri kaydeder.

## [Unreleased]

### 🔒 Güvenlik — Faz 1 (kritik yamalar, 24.10.2026)
- **K-1** El sıkışmada `fp == sha256(pk)` zorunlu doğrulama; tam SHA-256 parmak
  izi + TOFU (iz değişirse bağlantı reddi).
- **K-2** Güvenilir cihazlar ve favoriler doğrulanmış parmak izine bağlandı.
- **K-3** PIN bypass kapatıldı: PIN tanımlıysa `auth`'suz teklif reddedilir;
  sabit zamanlı karşılaştırma + 5 hatalı denemede 5 dk kilit.
- **K-4** Path traversal sertleştirildi (Windows vektörleri, rezerve adlar,
  kök altında kalma doğrulaması).
- **Y-5…Y-11** Multicast grubu uyumluluğu + MulticastLock, dosya ezme koruması
  (`ad (2).ext`), resume hash zinciri, canlı ayarlar, 300 ms ilerleme tazeleme,
  güvenilir başarı (done onayı).

### 🔧 Rezidüel düzeltmeler (denetim v3.0 — R-1…R-6, bu sürüm)
- **R-2** PIN artık düz metin `SharedPreferences`'tan okunmuyor; güvenli kasa
  (Keychain/Keystore) üzerinden yüklenir. Güvenli kasaya erişilemeyen
  ortamlarda eski düz metin kopya otomatik olarak kasaya taşınır (migrasyon).
- **R-4** `expandSelectionsAsync` kök öneki hatası düzeltildi (çakışan
  göreli yollar artık kendi kökünün adıyla tekilleştirilir).
- **R-5** Dosya/klasör adı sınırı artık UTF-8 **bayt** bazlıdır; Türkçe
  karakterlerde disk adı 255 baytı aşmaz.
- **R-6** Protokol limitleri zorlanır: cihaz adı ≤64 karakter (hem üretim hem
  kabul), beacon ≤512 bayt.
- **R-3** Güven/favori kayıtlarının parmak izine taşınmasıyla ilgili tek
  seferlik bilgilendirme diyaloğu eklendi.

### ⚠️ Güncelleme Notu (güven/favori göçü)
Güvenilir cihazlar ve favoriler **kimlikten parmak izine** taşındı. Güvenlik
açısından eski (doğrulanmamış kimliğe dayalı) kayıtlar **aktarılmaz**; ilk
açılışta bir bilgi diyaloğu gösterilir ve cihazları yeniden onaylamanız istenir.

## [0.1.0] — İlk yayın (22.10.2026)
- LyraLink v1 protokolü: UDP multicast keşif + TCP transfer,
  X25519 + HKDF-SHA256 + ChaCha20-Poly1305.
- Dosya/klasör/metin gönderimi, çoklu alıcı, otomatik keşif, elle IP bağlanma.
- PIN kilidi, hızlı kaydetme kipleri (onay / herkesten / favoriler), favoriler.
- Gönderim öncesi inceleme, sürükle-bırak (masaüstü), QR gösterimi.
- Geçmiş + detay/silme, tema/dil/port ayarları, sha256 bütünlük doğrulaması,
  yarım kalan transferi devam ettirme (resume).
