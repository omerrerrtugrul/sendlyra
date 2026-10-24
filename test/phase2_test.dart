import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/models/send_selection.dart';
import 'package:sendlyra/core/models/transfer_job.dart';
import 'package:sendlyra/core/services/discovery_service.dart';
import 'package:sendlyra/core/services/history_service.dart';
import 'package:sendlyra/core/services/secret_store.dart';
import 'package:sendlyra/core/services/settings_service.dart';
import 'package:sendlyra/ui/strings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('SecretStore (O-13)', () {
    test('yaz-ok-sil turu çalışır (kasaya düşerse prefs temizlenir)', () async {
      SharedPreferences.setMockInitialValues({'gizli': 'eski-deger'});
      final prefs = await SharedPreferences.getInstance();
      final store = SecretStore(prefs);

      final migrated = await store.read('gizli');
      expect(migrated, 'eski-deger');

      await store.write('gizli', 'yeni-deger');
      expect(await store.read('gizli'), 'yeni-deger');

      await store.delete('gizli');
      expect(await store.read('gizli'), isNull);
    });

    test('PIN güvenli saklanır (loadSecrets turu)', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs, secrets: SecretStore(prefs));

      await settings.setPin('1234');
      expect(settings.hasPin, isTrue);

      final reloaded = SettingsService(prefs, secrets: SecretStore(prefs));
      await reloaded.loadSecrets();
      expect(reloaded.pin, '1234');

      await reloaded.setPin(null);
      expect(reloaded.hasPin, isFalse);
    });
  });

  group('hata kodu yerelleştirmesi (O-20)', () {
    test('kodlar iki dilde de çevrilir', () {
      const tr = AppStrings('tr');
      const en = AppStrings('en');
      expect(tr.errorText('err.pinWrong'), 'PIN hatalı');
      expect(en.errorText('err.pinWrong'), 'Wrong PIN');
      expect(tr.errorText('err.hashMismatch'), isNotEmpty);
      expect(en.errorText('err.busy'), isNotEmpty);
    });

    test('bilinmeyen değerler olduğu gibi döner', () {
      const tr = AppStrings('tr');
      expect(tr.errorText('beklenmeyen metin'), 'beklenmeyen metin');
      expect(tr.errorText(null), '');
    });
  });

  group('geçmiş (D-35)', () {
    test('kayıt silinebilir ve detay alanları korunur', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final history = HistoryService(prefs);

      final job = TransferJob(
        id: 'job-1',
        direction: JobDirection.receive,
        peerId: 'p',
        peerName: 'dost',
        peerAddress: '10.0.0.2',
        files: [
          FileTransfer(
              id: 'f0', name: 'a.txt', size: 3, relPath: 'a.txt', savedPath: '/tmp/a.txt'),
        ],
        text: 'merhaba',
        createdAt: DateTime.now(),
      )
        ..state = JobState.failed
        ..error = 'err.hashMismatch'
        ..transferred = 3
        ..textSavedPath = '/tmp/mesaj.txt';

      await history.add(job);
      expect(history.entries.length, 1);
      final entry = history.entries.first;
      expect(entry.error, 'err.hashMismatch');
      expect(entry.text, 'merhaba');
      expect(entry.savedPaths, containsAll(['/tmp/mesaj.txt', '/tmp/a.txt']));

      await history.remove('job-1');
      expect(history.entries, isEmpty);
    });
  });

  group('displayName (D-21)', () {
    test('çok dosyalı kayıt anlaşılır gösterilir', () {
      final job = TransferJob(
        id: 'j',
        direction: JobDirection.send,
        peerId: 'p',
        peerName: 'n',
        peerAddress: '1.1.1.1',
        files: [
          FileTransfer(id: 'f0', name: 'img.jpg', size: 1),
          FileTransfer(id: 'f1', name: 'b.txt', size: 1),
          FileTransfer(id: 'f2', name: 'c.txt', size: 1),
        ],
        createdAt: DateTime.now(),
      );
      expect(job.displayName, 'img.jpg (+2)');
    });
  });

  group('expandSelections (O-31)', () {
    test('çakışan göreli yollar sessizce atılmaz, önek eklenir', () {
      final dir = Directory.systemTemp.createTempSync('lyra-sel-test');
      addTearDown(() => dir.deleteSync(recursive: true));

      final a = Directory('${dir.path}/a/kok')..createSync(recursive: true);
      final b = Directory('${dir.path}/b/kok')..createSync(recursive: true);
      File('${a.path}/x.txt').writeAsStringSync('1');
      File('${b.path}/x.txt').writeAsStringSync('2');

      // Aynı göreli yola (kok/x.txt) sahip iki farklı kök.
      final entries = expandSelections([
        SendSelection(path: a.path, isDirectory: true),
        SendSelection(path: b.path, isDirectory: true),
      ]);
      expect(entries.length, 2);
      final rels = entries.map((e) => e.relPath).toSet();
      expect(rels.length, 2, reason: 'çakışan yollar tekilleştirilmeli');
    });
  });

  group('meşgul durumu (beacon)', () {
    test('busy alanı beacon turunu korur', () {
      final beacon = DiscoveryBeacon.fromJson({
        'id': 'x',
        'name': 'n',
        'os': 'linux',
        'dev': 'desktop',
        'port': 47802,
        'pk': '',
        'fp': 'abc',
        'busy': true,
      }, '10.0.0.5', DateTime.now());
      expect(beacon.busy, isTrue);

      final busyless = DiscoveryBeacon.fromJson({
        'id': 'y',
        'name': 'n',
        'os': 'linux',
        'dev': 'desktop',
        'port': 47802,
        'pk': '',
        'fp': 'abc',
      }, '10.0.0.6', DateTime.now());
      expect(busyless.busy, isFalse);
    });
  });
}
