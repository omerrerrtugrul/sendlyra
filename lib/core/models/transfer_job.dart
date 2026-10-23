import 'dart:convert';

/// Transfer işinin yönü.
enum JobDirection { send, receive }

/// Transfer işinin durumu.
enum JobState {
  connecting,
  waitingApproval,
  transferring,
  completed,
  failed,
  cancelled,
}

/// İş içindeki tek bir dosya.
class FileTransfer {
  final String id;
  final String name;
  final int size;
  String? relPath; // klasör yapısını koruyan göreli yol (çakışma adı için değiştirilebilir)
  int done;
  String? savedPath;
  bool completed;
  String? error;

  FileTransfer({
    required this.id,
    required this.name,
    required this.size,
    this.relPath,
    this.done = 0,
    this.savedPath,
    this.completed = false,
    this.error,
  });

  double get progress => size <= 0 ? 1 : (done / size).clamp(0, 1);
}

/// Bir gönderim/alım işi.
class TransferJob {
  final String id;
  final JobDirection direction;
  final String peerId;
  final String peerName;
  final String peerAddress;
  final List<FileTransfer> files;
  final String? text;
  final DateTime createdAt;

  JobState state;
  String? error;
  int transferred = 0;
  double speedBps = 0;
  DateTime? finishedAt;
  DateTime? lastSampleAt;
  int lastSampleBytes = 0;

  TransferJob({
    required this.id,
    required this.direction,
    required this.peerId,
    required this.peerName,
    required this.peerAddress,
    required this.files,
    this.text,
    required this.createdAt,
    this.state = JobState.connecting,
    this.error,
  });

  int get totalBytes {
    var total = 0;
    for (final f in files) {
      total += f.size;
    }
    return total;
  }

  double get progress {
    final total = totalBytes;
    if (total <= 0) return state == JobState.completed ? 1 : 0;
    return (transferred / total).clamp(0, 1);
  }

  bool get isFinished =>
      state == JobState.completed ||
      state == JobState.failed ||
      state == JobState.cancelled;

  String get displayName {
    if (files.length == 1) return files.first.relPath ?? files.first.name;
    if (files.length > 1) {
      final first = files.first.relPath ?? files.first.name;
      return '$first +${files.length - 1}';
    }
    return text != null ? _preview(text!) : 'mesaj';
  }

  static String _preview(String text) {
    final t = text.trim();
    return t.length > 30 ? '${t.substring(0, 30)}…' : t;
  }
}

/// Geçmiş kaydı — tamamlanan işlerin özeti.
class HistoryEntry {
  final String id;
  final JobDirection direction;
  final String peerName;
  final String title;
  final int bytes;
  final DateTime time;
  final bool success;

  const HistoryEntry({
    required this.id,
    required this.direction,
    required this.peerName,
    required this.title,
    required this.bytes,
    required this.time,
    required this.success,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'dir': direction == JobDirection.send ? 'send' : 'recv',
        'peer': peerName,
        'title': title,
        'bytes': bytes,
        'time': time.millisecondsSinceEpoch,
        'ok': success,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> json) => HistoryEntry(
        id: json['id'] as String? ?? '',
        direction: json['dir'] == 'send' ? JobDirection.send : JobDirection.receive,
        peerName: json['peer'] as String? ?? '',
        title: json['title'] as String? ?? '',
        bytes: (json['bytes'] as num?)?.toInt() ?? 0,
        time: DateTime.fromMillisecondsSinceEpoch(
            (json['time'] as num?)?.toInt() ?? 0),
        success: json['ok'] as bool? ?? false,
      );

  static List<HistoryEntry> listFromJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! List) return [];
    return decoded
        .whereType<Map>()
        .map((e) => HistoryEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}
