import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

/// Dosyanın tamamının SHA-256 özeti (hex).
///
/// Hesaplama `Isolate.run` ile arka planda yürütülür; böylece büyük
/// dosyalarda kullanıcı arayüzü donmaz (O-17). Resume edilmiş aktarımlarda
/// bile doğrulama her zaman **tam dosya** üzerinden yapılır (Y-7).
Future<String> sha256OfFile(String path) =>
    Isolate.run(() => _hashFile(path));

Future<String> _hashFile(String path) async {
  final raf = await File(path).open();
  final sink = _DigestSink();
  final hasher = sha256.startChunkedConversion(sink);
  try {
    while (true) {
      final chunk = await raf.read(64 * 1024);
      if (chunk.isEmpty) break;
      hasher.add(chunk);
    }
    hasher.close();
    return sink.value;
  } finally {
    await raf.close();
  }
}

class _DigestSink implements Sink<Digest> {
  String value = '';

  @override
  void add(Digest data) {
    value = data.toString();
  }

  @override
  void close() {}
}
