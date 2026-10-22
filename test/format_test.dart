import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/utils/format.dart';

void main() {
  group('formatBytes', () {
    test('birim dönüşümleri', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1024 * 1024), '1.0 MB');
      expect(formatBytes(5 * 1024 * 1024 * 1024), '5.0 GB');
    });
  });

  group('formatSpeed', () {
    test('saniyelik hız ekler', () {
      expect(formatSpeed(2048), '2.0 KB/sn');
    });
  });

  group('formatDuration', () {
    test('süre birimleri', () {
      expect(formatDuration(const Duration(seconds: 5)), '5 sn');
      expect(formatDuration(const Duration(minutes: 3, seconds: 7)),
          '3 dk 7 sn');
      expect(formatDuration(const Duration(hours: 2, minutes: 11)),
          '2 sa 11 dk');
    });
  });

  group('timeAgo', () {
    test('göreli zaman', () {
      expect(timeAgo(DateTime.now()), 'az önce');
      expect(timeAgo(DateTime.now().subtract(const Duration(minutes: 12))),
          '12 dk önce');
      expect(timeAgo(DateTime.now().subtract(const Duration(hours: 3))),
          '3 sa önce');
      expect(timeAgo(DateTime.now().subtract(const Duration(days: 2))),
          '2 gün önce');
    });
  });
}
