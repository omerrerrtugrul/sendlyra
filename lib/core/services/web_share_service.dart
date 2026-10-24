import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/send_selection.dart';
import '../models/transfer_job.dart';
import '../protocol/lyra_crypto.dart';
import '../utils/path_safety.dart';
import '../web/web_pages.dart';
import '../web/zip_writer.dart';
import 'history_service.dart';
import 'settings_service.dart';

/// W-01…W-05: uygulama içinden başlatılan web paylaşım sunucusu.
///
/// Tarayıcıdan dosya indirme (W-02), dosya yükleme (W-03), PIN korumalı
/// oturum (W-04) ve yalnız yerel ağ erişimi + HTTP uyarısı (W-05).
/// LyraLink'ten bağımsızdır; `dart:io HttpServer` kullanır.
class WebShareService extends ChangeNotifier {
  WebShareService({
    required this.settings,
    required this.history,
    this.saveDirResolver,
  });

  final SettingsService settings;
  final HistoryService history;

  /// Yüklemelerin kaydedileceği klasörü çözer (TransferService ile aynı).
  final Future<String> Function()? saveDirResolver;

  HttpServer? _server;

  /// Paylaşılan dosyalar (tarayıcıya listelenir).
  final List<WebShareEntry> shared = [];

  /// Son yüklenen dosya adları (UI'da gösterim).
  final List<String> uploads = [];

  /// W-04: IP başına oturum — token → IP eşlemesi.
  final Map<String, String> _sessions = {};

  bool get running => _server != null;
  int? get actualPort => _server?.port;
  bool get tlsEnabled =>
      settings.webTlsCert.isNotEmpty && settings.webTlsKey.isNotEmpty;

  /// [start] sırasında çözülen LAN adresi (link/QR için).
  String _lanIp = '127.0.0.1';

  /// LAN IP'si + port ile erişim linki (QR için de kullanılır).
  String get url {
    final port = actualPort ?? settings.webPort;
    final scheme = tlsEnabled ? 'https' : 'http';
    return '$scheme://$_lanIp:$port/';
  }

  // ---------- Paylaşım listesi ----------

  /// Dosya/klasör yollarını paylaşım listesine ekler (klasörler açılır).
  void addPaths(List<String> paths) {
    for (final path in paths) {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      final selection = type == FileSystemEntityType.directory
          ? SendSelection(path: path, isDirectory: true)
          : type == FileSystemEntityType.file
              ? SendSelection(path: path, isDirectory: false)
              : null;
      if (selection == null) continue;
      for (final entry in selection.expand()) {
        if (shared.any((s) => s.path == entry.file.path)) continue;
        shared.add(WebShareEntry(
          path: entry.file.path,
          name: entry.relPath,
          size: entry.sizeBytes,
        ));
      }
    }
    notifyListeners();
  }

  void removeShared(WebShareEntry entry) {
    shared.remove(entry);
    notifyListeners();
  }

  void clearShared() {
    shared.clear();
    notifyListeners();
  }

  // ---------- Sunucu ----------

  /// W-01: sunucuyu başlatır (port çakışırsa hata fırlatır).
  Future<void> start() async {
    if (_server != null) return;
    _lanIp = await lanAddress();
    final port = settings.webPort;
    final HttpServer server;
    if (tlsEnabled) {
      final ctx = SecurityContext()
        ..useCertificateChain(settings.webTlsCert)
        ..usePrivateKey(settings.webTlsKey);
      server = await HttpServer.bindSecure(
        InternetAddress.anyIPv4,
        port,
        ctx,
        shared: true,
      );
    } else {
      server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );
    }
    server.listen(_handle, onError: (_) {});
    _server = server;
    notifyListeners();
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _sessions.clear();
    await server?.close(force: true);
    notifyListeners();
  }

  Future<void> restart() async {
    await stop();
    await start();
  }

  @override
  void dispose() {
    final server = _server;
    _server = null;
    _sessions.clear();
    server?.close(force: true);
    super.dispose();
  }

  // ---------- İstek işleme ----------

  Future<void> _handle(HttpRequest req) async {
    try {
      // W-05: yalnız yerel aralık — İnternet'ten gelen istek reddedilir.
      final ip = req.connectionInfo?.remoteAddress.address ?? '';
      if (!isPrivateAddress(ip)) {
        await _send(req, HttpStatus.forbidden,
            body: 'forbidden', type: 'text/plain');
        return;
      }

      final path = req.uri.path;
      if (path == '/health') {
        await _send(req, HttpStatus.ok, body: 'ok', type: 'text/plain');
        return;
      }
      if (path == '/login') {
        await _handleLogin(req, ip);
        return;
      }
      if (path == '/logout') {
        _logout(req, ip);
        await _redirect(req, '/');
        return;
      }

      // W-04: PIN tanımlıysa oturum gerekir.
      if (!_isAuthorized(req, ip)) {
        if (req.method == 'GET' && path == '/') {
          await _send(req, HttpStatus.ok,
              body: webLoginPage(locale: settings.localeCode),
              type: 'text/html; charset=utf-8');
        } else {
          await _send(req, HttpStatus.unauthorized,
              body: 'unauthorized', type: 'text/plain');
        }
        return;
      }

      if (req.method == 'GET' && path == '/') {
        await _send(req, HttpStatus.ok, body: _indexPage(), type: 'text/html; charset=utf-8');
        return;
      }
      if (req.method == 'GET' && path == '/all.zip') {
        await _handleZip(req);
        return;
      }
      if (req.method == 'GET' && path.startsWith('/files/')) {
        await _handleDownload(req, path);
        return;
      }
      if (req.method == 'POST' && path == '/upload') {
        await _handleUpload(req, ip);
        return;
      }
      await _send(req, HttpStatus.notFound,
          body: 'not found', type: 'text/plain');
    } catch (_) {
      try {
        req.response.statusCode = HttpStatus.internalServerError;
        await req.response.close();
      } catch (_) {}
    }
  }

  String _indexPage() => webSharePage(
        locale: settings.localeCode,
        deviceName: 'SendLyra',
        files: [for (final s in shared) WebFileInfo(name: s.name, size: s.size)],
        uploads: uploads.take(10).toList(),
        insecure: !tlsEnabled,
        pinEnabled: settings.hasWebPin,
      );

  Future<void> _handleLogin(HttpRequest req, String ip) async {
    if (req.method != 'POST') {
      await _redirect(req, '/');
      return;
    }
    final raw = await utf8Stream(req);
    final pin = _formValue(raw, 'pin') ?? '';
    final expected = settings.webPin ?? '';
    final ok = expected.isNotEmpty &&
        LyraCryptoIdentity.constantTimeEquals(pin, expected);
    if (!ok) {
      await _send(req, HttpStatus.forbidden,
          body: webLoginPage(
            locale: settings.localeCode,
            error: _t('PIN hatalı', 'Wrong PIN'),
          ),
          type: 'text/html; charset=utf-8');
      return;
    }
    final token = _randomToken();
    _sessions[token] = ip;
    req.response.headers.set(
      HttpHeaders.setCookieHeader,
      'lyra_sess=$token; HttpOnly; Path=/; SameSite=Strict',
    );
    await _redirect(req, '/');
  }

  void _logout(HttpRequest req, String ip) {
    final cookie = req.headers.value(HttpHeaders.cookieHeader) ?? '';
    final token = _cookieValue(cookie, 'lyra_sess');
    if (token != null) _sessions.remove(token);
    _sessions.removeWhere((_, v) => v == ip);
  }

  bool _isAuthorized(HttpRequest req, String ip) {
    if (!settings.hasWebPin) return true;
    final cookie = req.headers.value(HttpHeaders.cookieHeader) ?? '';
    final token = _cookieValue(cookie, 'lyra_sess');
    return token != null && _sessions[token] == ip;
  }

  Future<void> _handleDownload(HttpRequest req, String path) async {
    final index = int.tryParse(path.substring('/files/'.length)) ?? -1;
    if (index < 0 || index >= shared.length) {
      await _send(req, HttpStatus.notFound,
          body: 'not found', type: 'text/plain');
      return;
    }
    final entry = shared[index];
    final file = File(entry.path);
    if (!await file.exists()) {
      await _send(req, HttpStatus.notFound,
          body: 'not found', type: 'text/plain');
      return;
    }
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = ContentType.binary;
    req.response.headers.contentLength = entry.size;
    req.response.headers.set(
      'content-disposition',
      'attachment; filename="${_asciiName(entry.name)}"; '
      "filename*=UTF-8''${Uri.encodeComponent(entry.name)}",
    );
    await req.response.addStream(file.openRead());
    await req.response.close();
  }

  Future<void> _handleZip(HttpRequest req) async {
    req.response.statusCode = HttpStatus.ok;
    req.response.headers.contentType = ContentType('application', 'zip');
    req.response.headers.set(
      'content-disposition',
      'attachment; filename="sendlyra.zip"',
    );
    final zip = ZipWriter(req.response);
    for (final entry in shared) {
      final file = File(entry.path);
      if (!await file.exists()) continue;
      await zip.addFile(
        name: entry.name,
        data: file.openRead(),
        size: entry.size,
      );
    }
    await zip.close();
  }

  Future<void> _handleUpload(HttpRequest req, String ip) async {
    final rawName = req.uri.queryParameters['name'] ?? 'dosya';
    final name = sanitizeFileName(Uri.decodeQueryComponent(rawName));
    final dir = await saveDirResolver?.call() ?? Directory.systemTemp.path;
    final target = await _resolveCollision(dir, name);
    final file = File(target);
    final sink = file.openWrite();
    await sink.addStream(req);
    await sink.close();
    final size = await file.length();

    final base = target.split('/').last;
    uploads.insert(0, base);
    if (uploads.length > 20) uploads.removeRange(20, uploads.length);

    // Yüklemeler geçmişe "alınan" kayıt olarak geçer (O-18 ile aynı yaklaşım).
    final job = TransferJob(
      id: 'web-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
      direction: JobDirection.receive,
      peerId: 'web',
      peerName: 'Web · $ip',
      peerAddress: ip,
      files: [
        FileTransfer(id: 'f0', name: base, size: size, savedPath: target),
      ],
      createdAt: DateTime.now(),
    )
      ..state = JobState.completed
      ..transferred = size
      ..finishedAt = DateTime.now();
    await history.add(job);

    await _send(req, HttpStatus.ok,
        body: 'saved: $base', type: 'text/plain; charset=utf-8');
    notifyListeners();
  }

  Future<String> _resolveCollision(String dir, String name) async {
    final first = safeJoin(dir, name);
    if (!await File(first).exists()) return first;
    final dot = name.lastIndexOf('.');
    final base = dot > 0 ? name.substring(0, dot) : name;
    final ext = dot > 0 ? name.substring(dot) : '';
    for (var i = 2; i < 1000; i++) {
      final next = safeJoin(dir, '$base ($i)$ext');
      if (!await File(next).exists()) return next;
    }
    return first;
  }

  // ---------- Yardımcılar ----------

  Future<void> _send(
    HttpRequest req,
    int status, {
    required String body,
    required String type,
  }) async {
    req.response.statusCode = status;
    req.response.headers.contentType = ContentType.parse(type);
    req.response.write(body);
    await req.response.close();
  }

  Future<void> _redirect(HttpRequest req, String to) async {
    req.response.statusCode = HttpStatus.seeOther;
    req.response.headers.set(HttpHeaders.locationHeader, to);
    await req.response.close();
  }

  String _t(String tr, String en) => settings.localeCode == 'en' ? en : tr;

  static String _asciiName(String name) =>
      name.runes.every((r) => r < 128) ? name : 'download';

  static String? _cookieValue(String cookie, String key) {
    for (final part in cookie.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length == 2 && kv[0] == key) return kv[1];
    }
    return null;
  }

  static String? _formValue(String body, String key) {
    for (final part in body.split('&')) {
      final kv = part.split('=');
      if (kv.length == 2 && kv[0] == key) {
        return Uri.decodeQueryComponent(kv[1]);
      }
    }
    return null;
  }

  static String _randomToken() {
    final rnd = Random.secure();
    final bytes = List<int>.generate(16, (_) => rnd.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Genel IP dışındakilerden gelen istekleri reddetmek için (W-05).
  static bool isPrivateAddress(String ip) {
    if (ip.isEmpty) return false;
    var addr = ip.toLowerCase();
    if (addr.startsWith('::ffff:')) addr = addr.substring(7);
    if (addr == 'localhost' || addr == '::1' || addr == '0:0:0:0:0:0:0:1') {
      return true;
    }
    final v4 = RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')
        .firstMatch(addr);
    if (v4 != null) {
      final a = int.parse(v4.group(1)!);
      final b = int.parse(v4.group(2)!);
      if (a == 0 || a == 10 || a == 127) return true;
      if (a == 192 && b == 168) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      if (a == 169 && b == 254) return true;
      return false;
    }
    // IPv6: link-local (fe80::/10) ve unique-local (fc00::/7).
    if (addr.startsWith('fe8') ||
        addr.startsWith('fe9') ||
        addr.startsWith('fea') ||
        addr.startsWith('feb')) {
      return true;
    }
    return addr.startsWith('fc') || addr.startsWith('fd');
  }

  /// LAN'daki birincil IPv4 adresi (link üretimi için).
  static Future<String> lanAddress() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (isPrivateAddress(addr.address)) return addr.address;
        }
      }
      for (final iface in interfaces) {
        if (iface.addresses.isNotEmpty) return iface.addresses.first.address;
      }
    } catch (_) {}
    return '127.0.0.1';
  }

  Future<String> utf8Stream(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }
}

/// Paylaşılan tek bir dosya.
class WebShareEntry {
  WebShareEntry({required this.path, required this.name, required this.size});

  final String path;
  final String name;
  final int size;
}
