import 'dart:convert';
import 'dart:typed_data';

/// LyraLink kontrol mesajları.
///
/// El sıkışma sonrası tüm kontrol mesajları şifreli kanaldan JSON olarak geçer.
/// Her mesajın `t` alanı tipi belirtir.
abstract final class MsgType {
  static const String auth = 'auth';
  static const String authResult = 'auth-result';
  static const String offer = 'offer';
  static const String pending = 'pending';
  static const String accept = 'accept';
  static const String reject = 'reject';
  static const String fileStart = 'file-start';
  static const String fileEnd = 'file-end';
  static const String done = 'done';
  static const String cancel = 'cancel';
  static const String error = 'error';
  static const String ping = 'ping';
  static const String pong = 'pong';
}

class LyraProtocolException implements Exception {
  final String message;
  const LyraProtocolException(this.message);

  @override
  String toString() => 'LyraProtocolException: $message';
}

/// El sıkışma sırasındaki açık metin "hello" paketi.
class HelloInfo {
  final int version;
  final String id;
  final String name;
  final String os;
  final String deviceType;
  final List<int> publicKey;
  final String fingerprint;

  const HelloInfo({
    required this.version,
    required this.id,
    required this.name,
    required this.os,
    required this.deviceType,
    required this.publicKey,
    required this.fingerprint,
  });

  Map<String, dynamic> toJson() => {
        't': 'hello',
        'v': version,
        'id': id,
        'name': name,
        'os': os,
        'dev': deviceType,
        'pk': base64Encode(publicKey),
        'fp': fingerprint,
      };

  factory HelloInfo.fromJson(Map<String, dynamic> json) {
    final pk = json['pk'];
    if (json['id'] is! String || pk is! String) {
      throw const LyraProtocolException('hello paketi bozuk');
    }
    List<int> publicKey;
    try {
      publicKey = base64Decode(pk);
    } catch (_) {
      throw const LyraProtocolException('hello paketi: geçersiz açık anahtar');
    }
    final fp = json['fp'];
    return HelloInfo(
      version: (json['v'] as num?)?.toInt() ?? 0,
      id: json['id'] as String,
      name: (json['name'] is String) ? json['name'] as String : 'unknown',
      os: (json['os'] is String) ? json['os'] as String : 'unknown',
      deviceType: (json['dev'] is String) ? json['dev'] as String : 'unknown',
      publicKey: publicKey,
      fingerprint: (fp is String) ? fp : '',
    );
  }

  factory HelloInfo.fromLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map<String, dynamic>) {
      throw const LyraProtocolException('hello satırı geçersiz JSON');
    }
    return HelloInfo.fromJson(decoded);
  }
}

/// Teklif edilen bir dosya.
///
/// [rel] klasör yapısını korur (örn. `fotolar/2026/img.jpg`); boşsa [name]
/// doğrudan kaydetme köküne yazılır.
class OfferedFile {
  final String id;
  final String name;
  final int size;
  final String? mime;
  final String? rel;

  const OfferedFile({
    required this.id,
    required this.name,
    required this.size,
    this.mime,
    this.rel,
  });

  /// Hedefteki göreli yol.
  String get targetPath => (rel != null && rel!.trim().isNotEmpty) ? rel! : name;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'size': size,
        if (mime != null) 'mime': mime,
        if (rel != null) 'rel': rel,
      };

  factory OfferedFile.fromJson(Map<String, dynamic> json) => OfferedFile(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'dosya',
        size: (json['size'] as num?)?.toInt() ?? 0,
        mime: json['mime'] as String?,
        rel: json['rel'] as String?,
      );
}

/// Kanaldan gelen bir olay: kontrol mesajı ya da ham veri karesi.
class LyraEvent {
  final String? type;
  final Map<String, dynamic> data;
  final Uint8List? bytes;

  const LyraEvent.control(this.type, this.data) : bytes = null;
  const LyraEvent.data(this.bytes)
      : type = null,
        data = const {};

  bool get isData => bytes != null;
}

/// Karşı taraftan gelen gönderim teklifi.
class IncomingOffer {
  final String jobId;
  final List<OfferedFile> files;
  final String? text;
  final String? note;

  const IncomingOffer({
    required this.jobId,
    required this.files,
    this.text,
    this.note,
  });

  factory IncomingOffer.fromJson(Map<String, dynamic> json) {
    final rawFiles = (json['files'] as List?) ?? const [];
    return IncomingOffer(
      jobId: json['job'] as String? ?? '',
      files: rawFiles
          .whereType<Map>()
          .map((e) => OfferedFile.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      text: json['text'] as String?,
      note: json['note'] as String?,
    );
  }
}

/// Kabul kararını taşıyan yanıt.
class AcceptDecision {
  final bool accepted;
  final Map<String, int> resumeOffsets;
  final String? reason;

  const AcceptDecision.accept(this.resumeOffsets)
      : accepted = true,
        reason = null;
  const AcceptDecision.reject(this.reason)
      : accepted = false,
        resumeOffsets = const {};
}
