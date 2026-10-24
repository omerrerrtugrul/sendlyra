import 'dart:io';

/// Biçimlendirme yardımcıları.
String formatBytes(int bytes, {int decimals = 1}) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var size = bytes.toDouble();
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  final text = size >= 100 || unit == 0
      ? size.toStringAsFixed(0)
      : size.toStringAsFixed(decimals);
  return '$text ${units[unit]}';
}

String formatSpeed(double bytesPerSecond) =>
    '${formatBytes(bytesPerSecond.round())}/sn';

String formatDuration(Duration d) {
  if (d.inHours > 0) return '${d.inHours} sa ${d.inMinutes % 60} dk';
  if (d.inMinutes > 0) return '${d.inMinutes} dk ${d.inSeconds % 60} sn';
  return '${d.inSeconds} sn';
}

/// "az önce", "5 dk önce" gibi göreli zaman metni (yerelleştirilmiş, D-33).
String timeAgo(DateTime time, {String locale = 'tr'}) {
  final diff = DateTime.now().difference(time);
  final en = locale == 'en';
  if (diff.inMinutes < 1) return en ? 'just now' : 'az önce';
  if (diff.inHours < 1) {
    return en ? '${diff.inMinutes} min ago' : '${diff.inMinutes} dk önce';
  }
  if (diff.inDays < 1) {
    return en ? '${diff.inHours} h ago' : '${diff.inHours} sa önce';
  }
  return en ? '${diff.inDays} d ago' : '${diff.inDays} gün önce';
}

/// Parmak izinin kısa gösterimi (listeler için); tam iz diyaloglarda görünür.
String fingerprintShort(String fingerprint, {int len = 16}) =>
    fingerprint.length > len ? fingerprint.substring(0, len) : fingerprint;

/// Dosyayı/klasörü sistem görüntüleyicisiyle açar (masaüstü).
Future<bool> openInFileExplorer(String path) async {
  try {
    if (Platform.isWindows) {
      await Process.start('explorer', [path]);
      return true;
    }
    if (Platform.isMacOS) {
      await Process.start('open', [path]);
      return true;
    }
    if (Platform.isLinux) {
      await Process.start('xdg-open', [path]);
      return true;
    }
  } catch (_) {}
  return false;
}
