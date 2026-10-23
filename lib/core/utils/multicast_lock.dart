import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android'de multicast paketlerinin çekirdek tarafından atılmaması için
/// `WifiManager.MulticastLock` köprüsü. Diğer platformlarda no-op.
class MulticastLock {
  static const MethodChannel _channel = MethodChannel('sendlyra/multicast');

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Multicast kilidini alır (keşif başlarken).
  static Future<void> acquire() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>('acquire');
    } catch (_) {
      // Köprü yoksa (ör. test ortamı) sessizce geç.
    }
  }

  /// Multicast kilidini bırakır (keşif dururken).
  static Future<void> release() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<bool>('release');
    } catch (_) {}
  }
}
