import 'dart:io';
import 'dart:isolate';

/// Gönderim için seçilen bir kök öğe (dosya veya klasör).
class SendSelection {
  final String path;
  final bool isDirectory;

  const SendSelection({required this.path, required this.isDirectory});

  String get displayName {
    final parts = path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? path : parts.last;
  }

  /// Seçimin toplam boyutu (klasörlerde özyinelemeli toplam).
  int get size {
    if (!isDirectory) {
      try {
        return File(path).lengthSync();
      } catch (_) {
        return 0;
      }
    }
    var total = 0;
    for (final item in expand()) {
      total += item.sizeBytes;
    }
    return total;
  }

  /// Seçimi gönderilecek dosyalara açar (alt klasörler dahil).
  ///
  /// Boş klasörler atlanır; göreli yollar klasör adıyla başlar.
  List<SendFileEntry> expand() {
    if (!isDirectory) {
      return [SendFileEntry(file: File(path), relPath: displayName)];
    }
    final rootName = displayName;
    final out = <SendFileEntry>[];
    final dir = Directory(path);
    List<FileSystemEntity> children;
    try {
      children = dir.listSync(recursive: true, followLinks: false);
    } catch (_) {
      return out;
    }
    for (final entity in children) {
      if (entity is! File) continue;
      final relInside = entity.path.substring(dir.path.length + 1);
      final rel = '$rootName/${relInside.replaceAll('\\', '/')}';
      int size;
      try {
        size = entity.lengthSync();
      } catch (_) {
        continue;
      }
      out.add(SendFileEntry(file: entity, relPath: rel, size: size));
    }
    return out;
  }
}

/// Gönderime hazır tek dosya + hedefteki göreli yolu.
class SendFileEntry {
  final File file;
  final String relPath;
  final int? size;

  const SendFileEntry({required this.file, required this.relPath, this.size});

  int get sizeBytes {
    final s = size;
    if (s != null) return s;
    try {
      return file.lengthSync();
    } catch (_) {
      return 0;
    }
  }
}

/// Seçimleri gönderilecek dosya listesine açar.
///
/// Farklı köklerden gelen aynı göreli yollar sessizce atılmaz (O-31);
/// çakışan yola kök öneki eklenerek tekilleştirilir.
List<SendFileEntry> expandSelections(List<SendSelection> selections) {
  final out = <SendFileEntry>[];
  final seen = <String>{};
  for (final selection in selections) {
    for (final entry in selection.expand()) {
      var rel = entry.relPath;
      if (!seen.add(rel)) {
        var i = 2;
        var candidate = '${selection.displayName}-$rel';
        while (!seen.add(candidate)) {
          i++;
          candidate = '$i-${selection.displayName}-$rel';
        }
        rel = candidate;
        out.add(SendFileEntry(
            file: entry.file, relPath: rel, size: entry.size));
        continue;
      }
      out.add(entry);
    }
  }
  return out;
}

/// [expandSelections] ile aynı işi, dosya sistemi taramasını arka plan
/// isolate'inde yaparak yapar (O-30): büyük klasörlerde UI donmaz.
Future<List<SendFileEntry>> expandSelectionsAsync(
    List<SendSelection> selections) async {
  final scanned = await Isolate.run(() {
    final out = <Map<String, Object?>>[];
    for (final selection in selections) {
      for (final entry in selection.expand()) {
        out.add({
          'path': entry.file.path,
          'rel': entry.relPath,
          'size': entry.size,
        });
      }
    }
    return out;
  });
  final entries = [
    for (final item in scanned)
      SendFileEntry(
        file: File(item['path'] as String),
        relPath: item['rel'] as String,
        size: item['size'] as int?,
      ),
  ];
  // Tekilleştirme aynı kuralla yapılır.
  final out = <SendFileEntry>[];
  final seen = <String>{};
  for (var i = 0; i < entries.length; i++) {
    final entry = entries[i];
    var rel = entry.relPath;
    if (!seen.add(rel)) {
      final root = selections
          .map((s) => s.displayName)
          .firstWhere((_) => true, orElse: () => 'kok');
      var candidate = '$root-$rel';
      var n = 2;
      while (!seen.add(candidate)) {
        n++;
        candidate = '$n-$root-$rel';
      }
      rel = candidate;
      out.add(
          SendFileEntry(file: entry.file, relPath: rel, size: entry.size));
      continue;
    }
    out.add(entry);
  }
  return out;
}
