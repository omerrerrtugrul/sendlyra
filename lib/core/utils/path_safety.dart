/// Yol güvenliği: gelen dosya yollarının dizin kaçışına izin vermemesi için.
///
/// Karşı taraftan gelen `rel` (göreli yol) bilgisi asla doğrudan dosya
/// sistemine yazılmaz; her parça tek tek temizlenir.
String sanitizeSegment(String segment) {
  var s = segment.replaceAll(RegExp(r'[/\\]'), '_').trim();
  s = s.replaceAll(RegExp(r'^\.\.$'), '_');
  if (s.isEmpty || s == '.' || s == '..') s = '_';
  return s;
}

/// `rel` yolunu güvenli alt yola çevirir (klasör yapısı korunur).
///
/// Örn. `safeJoin("/kaydet", "fotolar/2026/img.jpg")`
///   → `/kaydet/fotolar/2026/img.jpg`
String safeJoin(String dir, String rel) {
  final parts = rel
      .split(RegExp(r'[/\\]+'))
      .where((p) => p.trim().isNotEmpty)
      .map(sanitizeSegment)
      .toList();
  if (parts.isEmpty) parts.add('dosya');
  final base = dir.endsWith('/') ? dir.substring(0, dir.length - 1) : dir;
  return '$base/${parts.join('/')}';
}

/// Yalnızca dosya adını güvenli biçime çevirir.
String sanitizeFileName(String name) => sanitizeSegment(name);
