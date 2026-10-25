/// Parmak izi karşılaştırma yardımcıları (R-1).
///
/// Doğrulama akışında kullanıcının karşı cihazın ekranında (QR paneli veya
/// cihaz bilgisi) gördüğü parmak izi, elle girilerek ya da görsel olarak
/// karşılaştırılarak doğrulanır. Karşılaştırma; boşluk, iki nokta, tire gibi
/// gösterim ayraçlarından ve büyük/küçük harf farkından bağımsızdır.
library;

/// Gösterim ayraçlarını temizleyip küçük harfe çevirir.
String normalizeFingerprint(String fingerprint) => fingerprint
    .replaceAll(RegExp(r'[\s:\-_]'), '')
    .toLowerCase();

/// İki parmak izinin aynı olup olmadığını kontrol eder.
///
/// Boş değerler hiçbir zaman eşleşmez (yanlışlıkla doğrulamayı önlemek için).
bool fingerprintsMatch(String a, String b) {
  final na = normalizeFingerprint(a);
  final nb = normalizeFingerprint(b);
  return na.isNotEmpty && nb.isNotEmpty && na == nb;
}

/// Parmak izini okunaklı bloklara böler (örn. 8'li gruplar halinde).
String groupFingerprint(String fingerprint, {int groupSize = 8}) {
  final n = normalizeFingerprint(fingerprint);
  if (n.isEmpty) return '';
  final buf = StringBuffer();
  for (var i = 0; i < n.length; i += groupSize) {
    if (i > 0) buf.write(' ');
    buf.write(n.substring(i, i + groupSize > n.length ? n.length : i + groupSize));
  }
  return buf.toString();
}
