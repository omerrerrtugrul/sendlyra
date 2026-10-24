import 'dart:convert';

/// Ağda görünen bir SendLyra cihazı.
class LyraDevice {
  final String id;
  String name;
  final String os;
  final String deviceType;
  final String address;
  final int port;
  final String publicKeyBase64;
  final String fingerprint;
  DateTime lastSeen;

  /// Karşı cihazın beacon'da bildirdiği meşgul durumu (aktif transfer var).
  bool busy;

  LyraDevice({
    required this.id,
    required this.name,
    required this.os,
    required this.deviceType,
    required this.address,
    required this.port,
    required this.publicKeyBase64,
    required this.fingerprint,
    required this.lastSeen,
    this.busy = false,
  });

  List<int> get publicKey => base64Decode(publicKeyBase64);

  @override
  bool operator ==(Object other) => other is LyraDevice && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
