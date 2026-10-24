import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/models/transfer_job.dart';
import 'package:sendlyra/core/services/history_service.dart';
import 'package:sendlyra/core/services/settings_service.dart';
import 'package:sendlyra/core/services/web_share_service.dart';
import 'package:sendlyra/core/web/zip_writer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('W-05: yerel aralık filtresi', () {
    test('özel/loopback adresler kabul edilir', () {
      for (final ip in [
        '127.0.0.1',
        '127.4.5.6',
        '10.0.0.7',
        '192.168.1.20',
        '172.16.0.1',
        '172.31.255.255',
        '169.254.3.3',
        '::1',
        'fe80::1',
        'fd12::9',
        '::ffff:192.168.0.5',
        'localhost',
      ]) {
        expect(WebShareService.isPrivateAddress(ip), isTrue, reason: ip);
      }
    });

    test('genel adresler reddedilir', () {
      for (final ip in [
        '8.8.8.8',
        '1.2.3.4',
        '172.32.0.1',
        '172.15.0.1',
        '192.169.1.1',
        '2001:4860:4860::8888',
        '',
      ]) {
        expect(WebShareService.isPrivateAddress(ip), isFalse, reason: ip);
      }
    });
  });

  group('ZIP üretici (W-02)', () {
    test('geçerli ZIP yapısı ve CRC üretir', () async {
      final out = StreamController<List<int>>();
      final collected = <int>[];
      final consumed = out.stream.forEach(collected.addAll);
      final zip = ZipWriter(out);
      await zip.addFile(
        name: 'a.txt',
        data: Stream.fromIterable([
          [0x61, 0x62, 0x63], // 'abc'
        ]),
        size: 3,
      );
      await zip.addFile(
        name: 'klasor/b.txt',
        data: Stream.fromIterable([
          [0x78], // 'x'
        ]),
        size: 1,
      );
      await zip.close();
      await consumed;

      final bytes = Uint8List.fromList(collected);
      // Harici doğrulama için isteğe bağlı çıktı (LYRA_ZIP_OUT).
      final outPath = Platform.environment['LYRA_ZIP_OUT'];
      if (outPath != null && outPath.isNotEmpty) {
        File(outPath).writeAsBytesSync(bytes);
      }
      // Yerel başlık imzası
      expect(bytes.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
      // İsimler görünür
      expect(String.fromCharCodes(bytes), contains('a.txt'));
      expect(String.fromCharCodes(bytes), contains('klasor/b.txt'));
      // EOCD imzası son 22 baytta
      final eocd = bytes.length - 22;
      expect(bytes.sublist(eocd, eocd + 4), [0x50, 0x4b, 0x05, 0x06]);

      // EOCD: giriş sayısı
      final bd = ByteData.sublistView(bytes);
      expect(bd.getUint16(eocd + 10, Endian.little), 2); // merkez dizin sayısı
      final cdSize = bd.getUint32(eocd + 12, Endian.little);
      final cdOffset = bd.getUint32(eocd + 16, Endian.little);
      expect(cdOffset + cdSize, lessThanOrEqualTo(eocd));

      // Merkez dizin: 'a.txt' girişi — CRC-32('abc') = 0x352441C2
      var pos = cdOffset;
      var foundCrc = 0;
      for (var i = 0; i < 2; i++) {
        expect(bytes.sublist(pos, pos + 4), [0x50, 0x4b, 0x01, 0x02]);
        final nameLen = bd.getUint16(pos + 28, Endian.little);
        final name = String.fromCharCodes(
            bytes.sublist(pos + 46, pos + 46 + nameLen));
        if (name == 'a.txt') foundCrc = bd.getUint32(pos + 16, Endian.little);
        pos += 46 + nameLen;
      }
      expect(foundCrc, 0x352441C2, reason: "CRC-32('abc')");
    });
  });

  group('Web paylaşım sunucusu (W-01…W-04)', () {
    late Directory saveDir;
    late Directory shareDir;
    late WebShareService web;
    late HistoryService history;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final settings = SettingsService(prefs);
      history = HistoryService(prefs);
      saveDir = Directory.systemTemp.createTempSync('lyra-web-save');
      shareDir = Directory.systemTemp.createTempSync('lyra-web-share');
      web = WebShareService(
        settings: settings,
        history: history,
        saveDirResolver: () async => saveDir.path,
      );
      await settings.setWebPort(0); // test: ephemeral port
    });

    tearDown(() async {
      await web.stop();
      web.dispose();
      saveDir.deleteSync(recursive: true);
      shareDir.deleteSync(recursive: true);
    });

    HttpClient makeClient() => HttpClient()
      ..connectionTimeout = const Duration(seconds: 5);

    Future<HttpClientResponse> httpGet(String path, {String? cookie}) async {
      final client = makeClient();
      addTearDown(client.close);
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:${web.actualPort}$path'));
      req.followRedirects = false;
      if (cookie != null) req.headers.set(HttpHeaders.cookieHeader, cookie);
      return req.close();
    }

    File shareFile(String name, String content) {
      final f = File('${shareDir.path}/$name')..writeAsStringSync(content);
      return f;
    }

    test('health, index ve tekil indirme (W-02)', () async {
      final f = shareFile('merhaba.txt', 'selam dunya');
      web.addPaths([f.path]);
      await web.start();

      final health = await httpGet('/health');
      expect(health.statusCode, HttpStatus.ok);

      final index = await httpGet('/');
      final html = await _transform(index);
      expect(index.statusCode, HttpStatus.ok);
      expect(html, contains('merhaba.txt'));
      expect(html, contains('/all.zip'));

      final dl = await httpGet('/files/0');
      final body = await _transform(dl);
      expect(dl.statusCode, HttpStatus.ok);
      expect(body, 'selam dunya');
      expect(
        dl.headers.value('content-disposition'),
        contains('attachment'),
      );
    });

    test('zip toplu indirme (W-02)', () async {
      web.addPaths([
        shareFile('bir.txt', 'BIR').path,
        shareFile('iki.txt', 'IKI').path,
      ]);
      await web.start();

      final res = await httpGet('/all.zip');
      expect(res.statusCode, HttpStatus.ok);
      expect(res.headers.contentType?.mimeType, 'application/zip');
      final bytes = await res.fold<BytesBuilder>(
          BytesBuilder(), (b, chunk) => b..add(chunk));
      final zip = bytes.takeBytes();
      expect(zip.sublist(0, 4), [0x50, 0x4b, 0x03, 0x04]);
      expect(String.fromCharCodes(zip), contains('bir.txt'));
      expect(String.fromCharCodes(zip), contains('iki.txt'));
    });

    test('tarayıcıdan yükleme: kayıt + çakışma adı + geçmiş (W-03)', () async {
      await web.start();
      final client = makeClient();
      addTearDown(client.close);

      Future<void> upload(String name, String content) async {
        final req = await client.postUrl(Uri.parse(
            'http://127.0.0.1:${web.actualPort}/upload?name=${Uri.encodeQueryComponent(name)}'));
        req.followRedirects = false;
        req.write(content);
        final res = await req.close();
        expect(res.statusCode, HttpStatus.ok);
        await res.drain();
      }

      await upload('rapor.txt', 'bir');
      await upload('rapor.txt', 'iki');

      final files = saveDir.listSync().whereType<File>().toList()
        ..sort((a, b) => a.path.compareTo(b.path));
      expect(files.length, 2);
      expect(files.any((f) => f.path.endsWith('rapor.txt')), isTrue);
      expect(files.any((f) => f.path.endsWith('rapor (2).txt')), isTrue);
      expect(web.uploads, isNotEmpty);

      // Yüklemeler geçmişe "alınan" kayıt olarak geçer.
      expect(history.entries, isNotEmpty);
      expect(history.entries.first.direction, JobDirection.receive);
    });

    test('W-04: PIN koruması ve oturum akışı', () async {
      await web.settings.setWebPin('9999');
      web.addPaths([shareFile('gizli.txt', 'gizli').path]);
      await web.start();

      // PIN'siz istek giriş sayfasına düşer, dosyayı vermez.
      final blocked = await httpGet('/');
      final loginPage = await _transform(blocked);
      expect(loginPage, contains('/login'));
      final denied = await httpGet('/files/0');
      expect(denied.statusCode, HttpStatus.unauthorized);
      await denied.drain();

      // Yanlış PIN → 403
      final client = makeClient();
      addTearDown(client.close);
      final bad = await client.postUrl(
          Uri.parse('http://127.0.0.1:${web.actualPort}/login'));
      bad.followRedirects = false;
      bad.write('pin=0000');
      final badRes = await bad.close();
      expect(badRes.statusCode, HttpStatus.forbidden);
      await badRes.drain();

      // Doğru PIN → oturum çerezi
      final good = await client.postUrl(
          Uri.parse('http://127.0.0.1:${web.actualPort}/login'));
      good.followRedirects = false;
      good.write('pin=9999');
      final goodRes = await good.close();
      expect(goodRes.statusCode, HttpStatus.seeOther);
      final setCookie = goodRes.headers.value(HttpHeaders.setCookieHeader) ?? '';
      expect(setCookie, contains('lyra_sess='));
      await goodRes.drain();
      final cookie =
          setCookie.split(';').first.trim(); // lyra_sess=<token>

      // Oturumlu istek sayfayı ve dosyayı alır.
      final ok = await httpGet('/', cookie: cookie);
      final page = await _transform(ok);
      expect(page, contains('gizli.txt'));
      final file = await httpGet('/files/0', cookie: cookie);
      expect(await _transform(file), 'gizli');
    });

    test('W-05: HTTP uyarısı sayfada görünür', () async {
      await web.start();
      final index = await httpGet('/');
      final html = await _transform(index);
      expect(html, contains('HTTP'));
    });
  });
}

Future<String> _transform(Stream<List<int>> stream) async {
  final bytes = await stream.fold<BytesBuilder>(
      BytesBuilder(), (b, chunk) => b..add(chunk));
  return String.fromCharCodes(bytes.takeBytes());
}
