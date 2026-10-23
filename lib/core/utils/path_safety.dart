/// Yol güvenliği: gelen dosya yollarının dizin kaçışına izin vermemesi için.
///
/// Karşı taraftan gelen `rel` (göreli yol) bilgisi asla doğrudan dosya
/// sistemine yazılmaz; her parça tek tek temizlenir ve nihai yol
/// kaydetme kökünün altında kalır.
library;

/// Windows yedeklenmiş aygıt adları — dosya/klasör adı olarak kullanılamaz.
const _reservedNames = {
  'CON', 'PRN', 'AUX', 'NUL',
  'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
  'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
};

/// Windows'ta geçersiz karakterler ( `:` dahil — `C:evil.txt` gibi
/// sürücü-göreli referansları da engeller) ve kontrol karakterleri.
final _invalidChars = RegExp(r'[:*?"<>|\x00-\x1f]');

/// Tek bir yol parçasını güvenli biçime çevirir.
///
/// - `/` ve `\` → `_` (ayraç olarak yalnızca üst katman böler)
/// - `:` `*` `?` `"` `<` `>` `|` ve kontrol karakterleri → `_`
/// - sondaki nokta ve boşluklar atılır (Windows davranışı)
/// - `.` ve `..` parçaları → `_`
/// - yedeklenmiş aygıt adları (`CON`, `NUL`, `COM1`…) → `_` öneki
/// - 255 bayttan uzun adlar kırpılır
String sanitizeSegment(String segment) {
  var s = segment.replaceAll(RegExp(r'[/\\]'), '_');
  s = s.replaceAll(_invalidChars, '_');
  // Sondaki nokta/boşluklar Windows'ta dosya adına eklenemez.
  s = s.replaceFirst(RegExp(r'[. ]+$'), '');
  if (s.isEmpty || s == '.' || s == '..') s = '_';

  // Yedeklenmiş aygıt adları (büyük/küçük harf duyarsız, uzantıdan bağımsız).
  final stem = s.split('.').first.toUpperCase();
  if (_reservedNames.contains(stem)) {
    s = '_$s';
  }

  // Ad uzunluğu sınırı (bayt cinsinden, UTF-8).
  if (s.length > 255) {
    s = s.substring(0, 255);
    s = s.replaceFirst(RegExp(r'[. ]+$'), '');
    if (s.isEmpty) s = '_';
  }
  return s;
}

/// `rel` yolunu güvenli alt yola çevirir (klasör yapısı korunur).
///
/// Örn. `safeJoin("/kaydet", "fotolar/2026/img.jpg")`
///   → `/kaydet/fotolar/2026/img.jpg`
///
/// Dönen yol her zaman [dir] kökü altındadır; hiçbir parça `..` üretmez.
String safeJoin(String dir, String rel) {
  final parts = rel
      .split(RegExp(r'[/\\]+'))
      .where((p) => p.trim().isNotEmpty)
      .map(sanitizeSegment)
      .toList();
  if (parts.isEmpty) parts.add('dosya');
  var base = dir;
  while (base.length > 1 &&
      (base.endsWith('/') || base.endsWith(r'\'))) {
    base = base.substring(0, base.length - 1);
  }
  final joined = '$base/${parts.join('/')}';
  // Savunma amaçlı doğrulama: yol kök dışında kalamaz.
  if (!isInsideRoot(base, joined)) {
    return '$base/${sanitizeSegment(parts.last)}';
  }
  return joined;
}

/// [path] gerçekten [root] altında mı? (normalize ederek kontrol eder)
bool isInsideRoot(String root, String path) {
  final normRoot = _normalize(root);
  final normPath = _normalize(path);
  if (normPath == normRoot) return true;
  final prefix = normRoot.endsWith('/') ? normRoot : '$normRoot/';
  return normPath.startsWith(prefix);
}

String _normalize(String path) {
  final sep = path.contains(r'\') && !path.contains('/') ? r'\' : '/';
  final parts = path.split(RegExp(r'[/\\]+'));
  final out = <String>[];
  for (final p in parts) {
    if (p.isEmpty || p == '.') continue;
    if (p == '..') {
      if (out.isNotEmpty) out.removeLast();
      continue;
    }
    out.add(p);
  }
  final leading = path.startsWith('/') ? '/' : '';
  return '$leading${out.join(sep)}';
}

/// Yalnızca dosya adını güvenli biçime çevirir.
String sanitizeFileName(String name) => sanitizeSegment(name);

/// Çakışma durumunda `ad.pdf` → `ad (2).pdf` üretir.
///
/// [exists] hedef yolun mevcut olup olmadığını söyler; en fazla 999 deneme.
String uniqueName(String name, bool Function(String candidate) exists) {
  if (!exists(name)) return name;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  for (var i = 2; i < 1000; i++) {
    final candidate = '$stem ($i)$ext';
    if (!exists(candidate)) return candidate;
  }
  return '$stem (${DateTime.now().millisecondsSinceEpoch})$ext';
}
