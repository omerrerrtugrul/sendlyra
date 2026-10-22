import 'dart:io';

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
List<SendFileEntry> expandSelections(List<SendSelection> selections) {
  final out = <SendFileEntry>[];
  final seen = <String>{};
  for (final selection in selections) {
    for (final entry in selection.expand()) {
      if (seen.add(entry.relPath)) {
        out.add(entry);
      }
    }
  }
  return out;
}
