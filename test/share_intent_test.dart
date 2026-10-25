import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/services/share_intent_service.dart';

/// P-01: Android "Paylaş" menüsü — içerik ayrıştırma ve kuyruk testleri.
class FakeShareIntentPlatform implements ShareIntentPlatform {
  Map<Object?, Object?>? initial;
  bool cleared = false;

  @override
  void Function(Map<Object?, Object?> items)? onShared;

  @override
  Future<Map<Object?, Object?>?> getInitialItems() async => initial;

  @override
  Future<void> clearInitial() async {
    cleared = true;
    initial = null;
  }
}

void main() {
  group('SharedItems.fromMap', () {
    test('dosya ve metni ayrıştırır', () {
      final items = SharedItems.fromMap({
        'text': ' merhaba ',
        'files': [
          {'path': '/cache/a.png', 'name': 'a.png'},
          {'path': '/cache/b.pdf', 'name': 'b.pdf'},
        ],
      });
      expect(items.text, 'merhaba');
      expect(items.files, hasLength(2));
      expect(items.files.first.name, 'a.png');
      expect(items.isEmpty, isFalse);
    });

    test('geçersiz kayıtlar elenir', () {
      final items = SharedItems.fromMap({
        'text': null,
        'files': [
          {'path': 'null', 'name': 'x'},
          'harita-degil',
          {'path': '/cache/ok.txt', 'name': 'ok.txt'},
        ],
      });
      expect(items.files, hasLength(1));
      expect(items.files.single.path, '/cache/ok.txt');
    });

    test('boş metin null sayılır', () {
      final items = SharedItems.fromMap({'text': '   ', 'files': []});
      expect(items.text, isNull);
      expect(items.isEmpty, isTrue);
    });
  });

  group('ShareIntentService', () {
    test('uygulama kapalıyken gelen paylaşım start ile alınır', () async {
      final platform = FakeShareIntentPlatform()
        ..initial = {
          'text': 'selam',
          'files': [
            {'path': '/cache/x', 'name': 'x'},
          ],
        };
      final service = ShareIntentService(platform: platform);
      await service.start();
      expect(platform.cleared, isTrue);
      expect(service.pendingCount, 1);
      final items = service.consume();
      expect(items?.text, 'selam');
      expect(items?.files.single.name, 'x');
    });

    test('canlı paylaşım akışla bildirilir ve kuyruğa girer', () async {
      final platform = FakeShareIntentPlatform();
      final service = ShareIntentService(platform: platform);
      await service.start();

      final events = <SharedItems>[];
      final sub = service.shared.listen(events.add);
      platform.onShared?.call({
        'text': 'canlı',
        'files': [],
      });
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1));
      expect(service.pendingCount, 1);
      await sub.cancel();
    });

    test('kuyruk FIFO ile tüketilir; boşken consume null döner', () async {
      final service = ShareIntentService(platform: FakeShareIntentPlatform());
      service.enqueue(const SharedItems(text: 'bir'));
      service.enqueue(const SharedItems(text: 'iki'));
      expect(service.consume()?.text, 'bir');
      expect(service.consume()?.text, 'iki');
      expect(service.consume(), isNull);
    });

    test('boş içerik kuyruğa alınmaz', () async {
      final service = ShareIntentService(platform: FakeShareIntentPlatform());
      service.enqueue(const SharedItems());
      service.enqueue(const SharedItems(files: []));
      expect(service.pendingCount, 0);
    });
  });

  test('StreamController kapanınca hata fırlatmaz (dispose güvenli)', () async {
    final service = ShareIntentService(platform: FakeShareIntentPlatform());
    final sub = service.shared.listen((_) {});
    service.dispose();
    await sub.cancel();
  });
}
