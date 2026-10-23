# LyraLink Protokolü v1

LyraLink, SendLyra için sıfırdan tasarlanmış, sunucusuz ve uçtan uca şifreli
yerel ağ aktarım protokolüdür. İki katmandan oluşur: **keşif** ve **transfer**.

## 1. Keşif (Discovery)

| Özellik | Değer |
|---|---|
| Taşıma | UDP multicast |
| Grup | `224.0.0.167` (admin-yerel; tüm platformlarda güvenilir) |
| Port | `47801` |
| Beacon aralığı | 2 sn |
| Zaman aşımı | 8 sn (beacon gelmezse cihaz listeden düşer) |

Beacon paketi UTF-8 JSON'dur (max 512 bayt):

```json
{
  "t": "beacon",
  "v": 1,
  "id": "<cihaz-kimliği: base64url 128-bit>",
  "name": "SendLyra-42",
  "os": "linux",
  "dev": "desktop",
  "port": 47802,
  "pk": "<base64 X25519 açık anahtar>",
  "fp": "<parmak izi: sha256(pk) tam özet, 64 hex>",
  "ts": 1761000000000
}
```

Kendi beacon'ımız (`id` alanı kendi kimliğimizle eşleşiyorsa) yok sayılır.

## 2. Transfer

| Özellik | Değer |
|---|---|
| Taşıma | TCP |
| Varsayılan port | `47802` |
| Şifreleme | X25519 + HKDF-SHA256 + ChaCha20-Poly1305 |

### 2.1 El sıkışma

Bağlantı kurulunca iki taraf da açık metin NL-JSON `hello` satırı yollar:

```json
{"t":"hello","v":1,"id":"...","name":"...","os":"...","dev":"...","pk":"<base64>","fp":"..."}
```

Taraflar X25519 ile paylaşılan sırrı türetir, HKDF-SHA256 ile iki anahtar çıkarır:

- `tuz` = istemci_pk ‖ sunucu_pk
- `k_c2s` = HKDF(paylaşılan_sır, tuz, "LyraLink-c2s-v1")
- `k_s2c` = HKDF(paylaşılan_sır, tuz, "LyraLink-s2c-v1")

İstemci `k_c2s` ile mühürler / `k_s2c` ile çözer; sunucuda tersi geçerlidir.
Anahtarlar farklı olduğu için her iki yönde nonce sayaçları 0'dan başlayabilir.

**Parmak izi doğrulaması (zorunlu):** `fp` alanı her zaman `sha256(pk)`
tam özetiyle (64 hex karakter) birebir karşılaştırılır. Uyuşmazsa bağlantı
reddedilir. Ek olarak TOFU (trust-on-first-use) pingleme yapılır: bir
`id` ile ilk karşılaşımda parmak izi kaydedilir; sonraki bağlantılarda iz
değişmişse bağlantı reddedilir ve kullanıcı uyarılır.

### 2.2 Kare biçimi (el sıkışma sonrası)

```
[4 bayt: şifreli uzunluk (big-endian)] [şifreli kare]
```

Şifreli karenin çözülmüş hâli:

```
[0x00][JSON utf8]   → kontrol mesajı
[0x01][ham bayt]    → dosya verisi (aktif dosyaya yazılır)
```

Nonce = 8 baytlık sayaç (big-endian) + 4 baytlık sıfır dolgu. Sayaç her
gönderimde artar; aynı anahtarla asla tekrar etmez. ChaCha20-Poly1305
doğrulama etiketi (16 bayt) karenin sonuna eklenir.

Maksimum kare boyutu: 256 KB. Dosya verisi 64 KB'lık parçalarla gönderilir.

### 2.3 Kontrol mesajları

| Tip | Yön | İçerik |
|---|---|---|
| `auth` | C→S | `pin` (boş olabilir) |
| `auth-result` | S→C | `ok`, `reason?` |
| `offer` | C→S | `job`, `files[{id,name,size,mime}]`, `text?`, `note?` |
| `pending` | S→C | (kullanıcı kararı bekleniyor) |
| `accept` | S→C | `job`, `resume{fileId: bayt}`, `names{fileId: yol}` |
| `reject` | S→C | `reason` |
| `file-start` | C→S | `job`, `file`, `offset` |
| `file-end` | C→S | `job`, `file`, `sha256` (zorunlu) |
| `done` | her iki yön | `job` |
| `cancel` | her iki yön | `reason` |
| `error` | her iki yön | `reason` |
| `ping` / `pong` | her iki yön | — |

C = istemci (dosya gönderen), S = sunucu (alan).

Ek kurallar:

- **PIN zorunluluğu**: Sunucuda PIN tanımlıysa `auth` gönderilmeden gelen
  `offer` doğrudan `error` ile reddedilir. PIN karşılaştırması sabit
  zamanlıdır; adres başına deneme kilidi (5 hatalı / 5 dk) uygulanır.
- **Çakışma yönetimi**: Hedef ad doluysa sunucu `ad (2).ext` biçiminde
  çakışmasız yol üretir ve sonucu `accept.names` ile bildirir.
- **Başarı onayı**: Gönderici `done` gönderdikten sonra alıcının `done`
  onayını bekler; onay gelmeden transfer "tamamlandı" sayılmaz.

### 2.4 Akış

```
İstemci                          Sunucu
   |-- hello ------------------>|
   |<-- hello ------------------|
   |   (şifreleme başlar)       |
   |-- auth ------------------->|
   |<-- auth-result ------------|
   |-- offer ------------------>|
   |<-- pending? ---------------|
   |<-- accept / reject --------|
   |-- file-start ------------->|
   |-- data* ------------------>|
   |-- file-end --------------->|   (sha256 doğrulaması + yeniden adlandırma)
   |   ... diğer dosyalar ...   |
   |-- done ------------------->|
   |<-- done -------------------|
```

### 2.5 Devam ettirme (resume)

Alıcı, `accept` mesajında yarım (`.lyrapart`) dosyaların bayt sayılarını
`resume` haritasıyla bildirir. Gönderici ilgili dosyayı `offset` bayttan
itibaren `file-start` ile yeniden başlatır. Hash doğrulaması **tam dosya
üzerinden** yapılır: gönderici atlanan baş kısmı da hash zincirine katar,
alıcı da mevcut `.lyrapart` başını hash'leyerek devam eder. Böylece
resume edilen dosyalarda eski verideki bozulmalar da tespit edilir.

## 3. Güvenlik

- **Uçtan uca şifreleme**: Yerel ağda trafiği dinleyen biri içerik göremez.
- **Kimlik doğrulama**: El sıkışmada parmak izi `sha256(pk)` ile birebir
  doğrulanır; TOFU pingleme ile iz değişimi reddedilir. PIN ek doğrulamadır
  ve atlanamaz (kural gereği `auth`'suz `offer` kabul edilmez).
- **Bütünlük**: Her kare Poly1305 ile doğrulanır; dosya sonunda SHA-256 ile
  bütünlük kontrolü yapılır (resume'da tam dosya).
- **Dizin kaçışı koruması**: Alıcı tarafında dosya adları temizlenir
  (`/`, `\`, `..`, `:` vb. karakterler güvenli biçime çevrilir; Windows
  yedeklenmiş aygıt adları ve geçersiz karakterler engellenir; nihai yol
  kaydetme kökü altında doğrulanır).
- **Onay mekanizması**: İsteğe bağlı kullanıcı onayı, güvenilir cihaz listesi
  (parmak izine bağlı) ve PIN kilitleri.
- **Güvenilir cihazlar**: Güven kayıtları her zaman doğrulanmış parmak
  izine bağlanır; karşı tarafın beyan ettiği kimliğe değil.

Kimlikler ilk açılışta üretilir ve cihazda saklanır; sunucu tarafı yoktur.
