import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Diğer uygulamalardan (Android "Paylaş" menüsü) gelen içerik (P-01).
///
/// Kanal sözleşmesi (`io.sendlyra/share_intent`):
/// - Kotlin → Dart: `onShared(Map)` — yeni paylaşım geldiğinde
/// - Dart → Kotlin: `getInitialItems()` — uygulama kapalıyken gelen paylaşım
/// - Dart → Kotlin: `clearInitial()` — ilk paylaşım tüketildi
///
/// Gelen harita biçimi: `{"text": String?, "files": [{"path": String, "name": String}]}`

/// Paylaşılan tek dosya (native tarafın cache'e kopyaladığı içerik).
class SharedFileEntry {
  final String path;
  final String name;

  const SharedFileEntry({required this.path, required this.name});

  factory SharedFileEntry.fromMap(Map<Object?, Object?> map) => SharedFileEntry(
        path: '${map['path']}',
        name: '${map['name'] ?? map['path']}',
      );
}

/// Paylaşılan içerik: dosya listesi ve/veya düz metin.
class SharedItems {
  final List<SharedFileEntry> files;
  final String? text;

  const SharedItems({this.files = const [], this.text});

  bool get isEmpty => files.isEmpty && (text == null || text!.trim().isEmpty);

  /// Kanal haritasından ayrıştırır; geçersiz kayıtlar sessizce elenir
  /// (yanlışlıkla "paylaşıldı" akışına düşmemesi için).
  factory SharedItems.fromMap(Map<Object?, Object?> map) {
    final text = (map['text'] as String?)?.trim();
    final rawFiles = map['files'];
    final files = <SharedFileEntry>[
      if (rawFiles is List)
        for (final item in rawFiles)
          if (item is Map) SharedFileEntry.fromMap(item),
    ].where((f) => f.path.isNotEmpty && f.path != 'null').toList();
    return SharedItems(
        files: files,
        text: (text == null || text.isEmpty) ? null : text);
  }
}

/// Platform bağı test edilebilirliği için kanal soyutlaması.
abstract class ShareIntentPlatform {
  Future<Map<Object?, Object?>?> getInitialItems();
  Future<void> clearInitial();
  set onShared(void Function(Map<Object?, Object?> items)? handler);
}

/// MethodChannel tabanlı gerçek uygulama.
class MethodChannelShareIntentPlatform implements ShareIntentPlatform {
  final MethodChannel channel;

  MethodChannelShareIntentPlatform(
      {this.channel = const MethodChannel('io.sendlyra/share_intent')}) {
    channel.setMethodCallHandler(_handle);
  }

  void Function(Map<Object?, Object?> items)? _onShared;

  Future<dynamic> _handle(MethodCall call) async {
    if (call.method == 'onShared' && call.arguments is Map) {
      _onShared?.call(Map<Object?, Object?>.from(call.arguments as Map));
    }
    return null;
  }

  @override
  set onShared(void Function(Map<Object?, Object?> items)? handler) =>
      _onShared = handler;

  @override
  Future<Map<Object?, Object?>?> getInitialItems() async {
    final raw = await channel.invokeMethod<dynamic>('getInitialItems');
    return raw is Map ? Map<Object?, Object?>.from(raw) : null;
  }

  @override
  Future<void> clearInitial() => channel.invokeMethod<void>('clearInitial');
}

/// Paylaşılan içeriği kuyruğa alan servis.
///
/// Tüketim modeli: [start] çağrıldığında bekleyen ilk paylaşım kuyruğa girer;
/// uygulama açıkken gelenler de aynı kuyruğa eklenir. UI tarafı [consume] ile
/// alır — böylece paylaşım hiçbir koşulda kaybolmaz.
class ShareIntentService extends ChangeNotifier {
  final ShareIntentPlatform platform;
  final _queue = <SharedItems>[];
  final _controller = StreamController<SharedItems>.broadcast();

  ShareIntentService({ShareIntentPlatform? platform})
      : platform = platform ?? MethodChannelShareIntentPlatform();

  /// Yeni paylaşım bildirimleri (kuyruğa eklenmesi tetikler).
  Stream<SharedItems> get shared => _controller.stream;

  int get pendingCount => _queue.length;

  /// Paylaşılan içerik geldiğinde çağrılır (platform veya test tarafından).
  void enqueue(SharedItems items) {
    if (items.isEmpty) return;
    _queue.add(items);
    _controller.add(items);
    notifyListeners();
  }

  /// Servisi başlatır; uygulama kapalıyken gelen paylaşımı kuyruğa alır.
  Future<void> start() async {
    platform.onShared = (raw) => enqueue(SharedItems.fromMap(raw));
    try {
      final initial = await platform.getInitialItems();
      if (initial != null) {
        await platform.clearInitial();
        enqueue(SharedItems.fromMap(initial));
      }
    } catch (_) {
      // Platform kanalı yok (ör. test/olmayan platform) — kuyruk boş kalır.
    }
  }

  /// Kuyruğun başındaki paylaşımı alır; boşsa null.
  SharedItems? consume() => _queue.isEmpty ? null : _queue.removeAt(0);

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }
}
