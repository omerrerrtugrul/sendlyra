# Değişiklik Günlüğü (CHANGELOG)

Bu dosya SendLyra sürümleri arasındaki önemli değişiklikleri kaydeder.

## [Unreleased]

### 🌐 Faz 4 — Tarayıcı Paylaşımı (W-01…W-05, bu sürüm)
- **W-01 Web sunucu modu:** uygulama içinden başlat/durdur; LAN IP + port ile
  erişim linki, QR, kopyala; yeni **"Web" sekmesi**.
- **W-02 İndirme sayfası:** tarayıcıdan dosya listesi, tekil indirme ve
  **toplu indirme** (yerel `ZipWriter` — streaming, bellek dostu, ZIP
  uyumluluğu python `zipfile` ile doğrulandı).
- **W-03 Yükleme sayfası:** tarayıcıdan sürükle-bırak / dosya seçici ile
  yükleme; yüklemeler kayıt klasörüne düşer (`ad (2).ext` çakışma kuralı),
  geçmişe "alınan" kayıt olarak geçer.
- **W-04 Web PIN + oturum:** PIN güvenli kasada saklanır (R-2 disiplini),
  sabit zamanlı karşılaştırma; IP başına token'lı oturum çerezi.
- **W-05 Güvenlik:** yalnız yerel aralık erişimi (genel IP'ler reddedilir),
  HTTP'de net uyarı; isteğe bağlı HTTPS (kullanıcı sertifika/anahtarı ile
  `bindSecure`).
- 🧪 8 yeni test: yerel aralık filtresi, ZIP yapısı + CRC, index/indirme,
  yükleme + çakışma, PIN/oturum akışı, HTTP uyarısı. Toplam **86/86 yeşil**.
- 🔧 **Test altyapısı:** port yarışı düzeltmesi (`port: 0` + `boundPort`) —
  paralel test yükünde sunucuların yanlış portu ele geçirmesi flake'ları
  giderildi; golden'lar yeni sekme ile güncellendi.

### ✨ Faz 3 — Deneyim Tamamlama (E-02 / E-03 / E-04, bu sürüm)
- **E-02 Panodan gönderim:** cihaz menüsünden "Panodan gönder" — pano metni
  önizleme onayıyla doğrudan hedefe yollanır; boş pano uyarısı.
- **E-03 Bildirimler:** transfer tamamlandı/başarısız bildirimleri
  (`flutter_local_notifications`, Android 8+ kanalı, ses + titreşim, Android 13+
  izin akışı). Bildirim altyapısı yoksa transferler sessizce sürer.
- **E-04 Meşgul kuyruklaması:** meşgul cihaza gönderim artık kuyruğa düşer
  (`JobState.queued`); cihaz uygun olunca ya da `err.busy` reddinden sonra
  otomatik yeniden denenir. Kuyruktaki iş iptal edilebilir.
- 🐞 **Kritik protokol düzeltmesi:** `LyraChannel._pump` yarım kare tamponda
  beklerken kendini mikro-görev zinciriyle sürekli yeniden çağırıyordu — bu,
  olay döngüsünü boğup timer'ları ve soket verisini askıya alıyordu (gerçek
  ağda paketler parça parça geldiğinde uygulama donması). Artık yalnızca
  ilerleme varsa yeniden planlanır; kalan baytlar `feed` ile gelince sürer.
  Ayrıca E-04'ün uçtan uca (loopback) test paketi eklendi.

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
