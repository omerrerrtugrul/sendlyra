import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/models/send_selection.dart';
import 'package:sendlyra/core/protocol/lyra_message.dart';
import 'package:sendlyra/core/services/discovery_service.dart';
import 'package:sendlyra/core/services/secret_store.dart';
import 'package:sendlyra/core/services/settings_service.dart';
import 'package:sendlyra/core/utils/path_safety.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Denetim v3.0 rezidüel bulguları (R-2, R-4, R-5, R-6) için kapanış testleri.
void main() {
  group('R-5: ad sınırı bayt bazlıdır', () {
    test('çok baytlı karakterlerde UTF-8 baytı 255\'i aşmaz', () {
      // 'ş' = 2 bayt; 200 tanesi 400 bayt eder → kırpılmalı.
      final seg = sanitizeSegment('${'ş' * 200}.txt');
      expect(utf8.encode(seg).length, lessThanOrEqualTo(255));
    });

    test('kesim karakter sınırında yapılır (glif bölünmez)', () {
      // 150 'ş' (300 bayt) + uzantı; kırpmadan sonra da geçerli UTF-8 olmalı
      // ve 'ş' dışında karakter oluşmamalı.
      final seg = sanitizeSegment('ş' * 150);
      expect(utf8.encode(seg).length, lessThanOrEqualTo(255));
      expect(seg, matches(RegExp(r'^ş+$')));
    });

    test('ASCII adlar eski davranışı korur (255 karakter)', () {
      final seg = sanitizeSegment('a' * 300);
      expect(seg.length, 255);
    });
  });

  group('R-4: async seçim açılımında kök öneki doğrudur', () {
    test('farklı köklerden çakışan yollar doğru kök adıyla tekilleştirilir',
        () async {
      final dir = Directory.systemTemp.createTempSync('lyra-sel-async');
      addTearDown(() => dir.deleteSync(recursive: true));

      // İlk seçim farklı adlı bir dosya — eski hata burada öneki bu
      // dosyanın adından alıyordu (R-4).
      final ana = File('${dir.path}/ana.txt')..writeAsStringSync('0');
      final kokA = Directory('${dir.path}/b/kok')..createSync(recursive: true);
      final kokB = Directory('${dir.path}/c/kok')..createSync(recursive: true);
      File('${kokA.path}/x.txt').writeAsStringSync('1');
      File('${kokB.path}/x.txt').writeAsStringSync('2');

      final entries = await expandSelectionsAsync([
        SendSelection(path: ana.path, isDirectory: false),
        SendSelection(path: kokA.path, isDirectory: true),
        SendSelection(path: kokB.path, isDirectory: true),
      ]);
      expect(entries.length, 3);
      final rels = entries.map((e) => e.relPath).toList();
      expect(rels.toSet().length, 3, reason: 'çakışan yollar tekilleştirilmeli');
      // İlk çakışan kayıt adını korur; ikincisi kök öneki alır.
      expect(rels[1], 'kok/x.txt', reason: 'ilk gelen kayıt adını korur');
      // Çakışan ikinci dosya KENDİ kökünün adını almalı (kok), ilk seçimin
      // adını değil (ana.txt) — R-4.
      expect(rels[2], startsWith('kok-'),
          reason: 'R-4: önek kendi kökünden gelmeli');
      expect(rels.any((r) => r.contains('ana.txt-')), isFalse,
          reason: 'R-4: ilk seçimin adı önek olmamalı');
    });

    test('senkron ve async sürüm aynı adlandırma kuralını üretir', () async {
      final dir = Directory.systemTemp.createTempSync('lyra-sel-parity');
      addTearDown(() => dir.deleteSync(recursive: true));

      final one = Directory('${dir.path}/one/kok')..createSync(recursive: true);
      final two = Directory('${dir.path}/two/kok')..createSync(recursive: true);
      File('${one.path}/x.txt').writeAsStringSync('1');
      File('${two.path}/x.txt').writeAsStringSync('2');

      List<SendSelection> sel() => [
            SendSelection(path: one.path, isDirectory: true),
            SendSelection(path: two.path, isDirectory: true),
          ];
      final sync = expandSelections(sel());
      final async = await expandSelectionsAsync(sel());
      expect(async.map((e) => e.relPath), sync.map((e) => e.relPath));
    });
  });

  group('R-2: PIN düz metin okunmaz, kasadan yüklenir', () {
    test('kasa varken kurucu düz metin kopyayı okumaz', () async {
      SharedPreferences.setMockInitialValues({'settings.pin': '9999'});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs, secrets: SecretStore(prefs));
      expect(settings.pin, isNull,
          reason: 'kurucu düz metin kopyaya güvenmemeli');
      await settings.loadSecrets();
      expect(settings.pin, '9999', reason: 'eski kopya loadSecrets ile gelir');
    });

    test('setPin → loadSecrets turu kasada tutarlıdır', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs, secrets: SecretStore(prefs));
      await settings.setPin('4321');
      expect(settings.hasPin, isTrue);

      final reloaded = SettingsService(prefs, secrets: SecretStore(prefs));
      await reloaded.loadSecrets();
      expect(reloaded.pin, '4321');
    });
  });

  group('R-6: protokol limitleri zorlanır', () {
    test('hello adı 64 karakterden uzunsa kabulde kırpılır', () {
      final hello = HelloInfo.fromJson({
        't': 'hello',
        'v': 1,
        'id': 'c1',
        'name': 'a' * 100,
        'os': 'b' * 100,
        'dev': 'desktop',
        'pk': base64Encode(List<int>.filled(32, 1)),
        'fp': 'f',
      });
      expect(hello.name.length, 64);
      expect(hello.os.length, 64);
    });

    test('hello üretiminde de kırpma uygulanır', () {
      final hello = HelloInfo(
        version: 1,
        id: 'c1',
        name: 'n' * 100,
        os: 'linux',
        deviceType: 'desktop',
        publicKey: List<int>.filled(32, 1),
        fingerprint: 'fp',
      );
      expect((hello.toJson()['name'] as String).length, 64);
    });

    test('beacon adı da kırpılır', () {
      final beacon = DiscoveryBeacon.fromJson({
        'id': 'x',
        'name': 'z' * 200,
        'os': 'linux',
        'dev': 'desktop',
        'port': 47802,
        'pk': '',
        'fp': 'abc',
      }, '10.0.0.5', DateTime.now());
      expect(beacon.name.length, 64);
    });
  });
}
