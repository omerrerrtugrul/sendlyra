import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/services/settings_service.dart';
import 'package:sendlyra/core/utils/fingerprint_matcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// R-1: parmak izi karşılaştırma ve doğrulama kaydı testleri.
void main() {
  group('normalizeFingerprint', () {
    test('gösterim ayraçlarını temizler ve küçük harfe çevirir', () {
      expect(normalizeFingerprint('AB:cd-ef 12'), 'abcdef12');
      expect(normalizeFingerprint('ABCDEF12'), 'abcdef12');
      expect(normalizeFingerprint('  a b c '), 'abc');
    });

    test('boş/yalnız ayraç normalize edilmiş iz boş kalır', () {
      expect(normalizeFingerprint(''), '');
      expect(normalizeFingerprint(' : - '), '');
    });
  });

  group('fingerprintsMatch', () {
    test('aynı iz biçimden bağımsız eşleşir', () {
      expect(fingerprintsMatch('AB CD:EF-12', 'abcdef12'), isTrue);
    });

    test('farklı iz eşleşmez', () {
      expect(fingerprintsMatch('abcdef12', 'abcdef13'), isFalse);
    });

    test('boş değerler hiçbir zaman eşleşmez', () {
      expect(fingerprintsMatch('', ''), isFalse);
      expect(fingerprintsMatch('abcdef12', ''), isFalse);
      expect(fingerprintsMatch('', 'abcdef12'), isFalse);
      // Yalnız ayraç dolu değer de boş sayılır.
      expect(fingerprintsMatch('::: ', 'abcdef12'), isFalse);
    });
  });

  group('groupFingerprint', () {
    test('8’li bloklara böler', () {
      expect(groupFingerprint('abcdef1234567890'),
          'abcdef12 34567890');
    });

    test('kısa iz aynen döner, boş iz boş kalır', () {
      expect(groupFingerprint('abc'), 'abc');
      expect(groupFingerprint(''), '');
    });
  });

  group('SettingsService doğrulama kaydı (R-1)', () {
    late SharedPreferences prefs;
    late SettingsService settings;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      settings = SettingsService(prefs);
    });

    test('doğrulama kaydedilir ve sorgulanır', () async {
      expect(settings.isVerified('fp-1'), isFalse);
      await settings.setVerified('fp-1', true);
      expect(settings.isVerified('fp-1'), isTrue);
      expect(settings.verifiedFingerprints, contains('fp-1'));
    });

    test('doğrulama kaldırılabilir', () async {
      await settings.setVerified('fp-1', true);
      await settings.setVerified('fp-1', false);
      expect(settings.isVerified('fp-1'), isFalse);
      expect(settings.verifiedFingerprints, isEmpty);
    });

    test('aynı iz iki kez eklenmez', () async {
      await settings.setVerified('fp-1', true);
      await settings.setVerified('fp-1', true);
      expect(settings.verifiedFingerprints, ['fp-1']);
    });

    test('doğrulama kalıcıdır (yeniden yüklemede korunur)', () async {
      await settings.setVerified('fp-1', true);
      final reloaded = SettingsService(prefs);
      expect(reloaded.isVerified('fp-1'), isTrue);
    });

    test('doğrulama diğer kayıtlardan bağımsızdır', () async {
      await settings.setTrusted('fp-1', true);
      expect(settings.isVerified('fp-1'), isFalse);
      await settings.setVerified('fp-1', true);
      expect(settings.isTrusted('fp-1'), isTrue);
    });
  });
}
