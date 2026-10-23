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

    test('Windows sürücü-göreli referansları temizler', () {
      expect(sanitizeSegment('C:evil.txt'), 'C_evil.txt');
      expect(sanitizeSegment('c:..\\x'), 'c_.._x');
      expect(sanitizeSegment('\\\\?\\C:\\x'), '____C__x');
    });

    test('Windows yedeklenmiş aygıt adlarını nötralize eder', () {
      expect(sanitizeSegment('CON'), '_CON');
      expect(sanitizeSegment('nul.txt'), '_nul.txt');
      expect(sanitizeSegment('COM1.tar.gz'), '_COM1.tar.gz');
      expect(sanitizeSegment('LPT9'), '_LPT9');
      expect(sanitizeSegment('console.png'), 'console.png');
    });

    test('Windows için geçersiz karakterleri temizler', () {
      expect(sanitizeSegment('a:b*c?d"e<f>g|h'), 'a_b_c_d_e_f_g_h');
      expect(sanitizeSegment('ad\u0000.png'), 'ad_.png');
    });

    test('sondaki nokta ve boşlukları atar', () {
      expect(sanitizeSegment('gizli.txt...'), 'gizli.txt');
      expect(sanitizeSegment('ad  '), 'ad');
    });

    test('aşırı uzun adları kırpar', () {
      final long = 'a' * 300;
      expect(sanitizeSegment(long).length <= 255, isTrue);
    });
  });

  group('uniqueName', () {
    test('çakışma yoksa adı aynen korur', () {
      expect(uniqueName('ad.pdf', (_) => false), 'ad.pdf');
    });

    test('çakışmada dosya (2).pdf üretilir', () {
      final taken = {'ad.pdf', 'ad (2).pdf'};
      expect(uniqueName('ad.pdf', taken.contains), 'ad (3).pdf');
    });

    test('uzantısız adlarda da çalışır', () {
      expect(uniqueName('klasor', (n) => n == 'klasor'), 'klasor (2)');
    });
  });

  group('isInsideRoot', () {
    test('kök altındaki yolları kabul eder', () {
      expect(isInsideRoot('/kaydet', '/kaydet/a/b.txt'), isTrue);
      expect(isInsideRoot('/kaydet', '/kaydet'), isTrue);
    });

    test('kök dışındaki yolları reddeder', () {
      expect(isInsideRoot('/kaydet', '/kaydet/../etc/passwd'), isFalse);
      expect(isInsideRoot('/kaydet', '/etc/passwd'), isFalse);
      expect(isInsideRoot('/kaydet', '/kaydet2/x'), isFalse);
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
