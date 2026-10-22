import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/models/send_selection.dart';
import 'package:sendlyra/core/utils/path_safety.dart';

void main() {
  group('sanitizeSegment', () {
    test('dizin kaçışı girişimlerini nötralize eder', () {
      expect(sanitizeSegment('..'), '_');
      expect(sanitizeSegment('.'), '_');
      expect(sanitizeSegment(''), '_');
      expect(sanitizeSegment('a/b'), 'a_b');
      expect(sanitizeSegment('a\\b'), 'a_b');
      expect(sanitizeSegment('normal.png'), 'normal.png');
    });
  });

  group('safeJoin', () {
    test('klasör yapısını korur', () {
      expect(
        safeJoin('/kaydet', 'fotolar/2026/img.jpg'),
        '/kaydet/fotolar/2026/img.jpg',
      );
    });

    test('dizin kaçışına izin vermez', () {
      expect(
        safeJoin('/kaydet', '../../../etc/passwd'),
        '/kaydet/_/_/_/etc/passwd',
      );
      final joined = safeJoin('/kaydet', '..\\..\\windows\\system32');
      expect(joined.startsWith('/kaydet/'), true);
      expect(joined.contains('..'), false);
    });

    test('sondaki eğik çizgi sorun çıkarmaz', () {
      expect(safeJoin('/kaydet/', 'x.txt'), '/kaydet/x.txt');
    });

    test('boş rel varsayılan adla sonuçlanır', () {
      expect(safeJoin('/kaydet', '  '), '/kaydet/dosya');
    });
  });

  group('SendSelection', () {
    test('tek dosya seçimi kendisiyle açılır', () {
      const selection = SendSelection(path: '/tmp/a.txt', isDirectory: false);
      expect(selection.displayName, 'a.txt');
      final entries = selection.expand();
      expect(entries.length, 1);
      expect(entries.first.relPath, 'a.txt');
    });
  });

  group('expandSelections', () {
    test('aynı göreli yollar tekilleştirilir', () {
      final entries = expandSelections(const [
        SendSelection(path: '/tmp/a.txt', isDirectory: false),
        SendSelection(path: '/x/y/a.txt', isDirectory: false),
      ]);
      // İkisi de 'a.txt' göreli yolunu üretir → tek kayıt kalır.
      expect(entries.length, 1);
    });
  });
}
