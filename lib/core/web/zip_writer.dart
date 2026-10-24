import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

/// Yayılı (streaming) ZIP üretici — sıkıştırmasız "stored" girişler.
///
/// W-02: tarayıcıdan "tümünü indir" için kullanılır. Dosyaları belleğe
/// almadan, diskten akıtarak yazar; her giriş için veri tanımlayıcısı
/// (data descriptor) kullanılır ki CRC/boyutlar veri akışından sonra
/// yazılabilsin — böylece dosya iki kez okunmaz.
///
/// ZIP biçimindeki tüm sayısal alanlar **little-endian**dır.
class ZipWriter {
  ZipWriter(this._out);

  static const _le = Endian.little;

  final StreamSink<List<int>> _out;
  final _central = <_CentralEntry>[];
  var _offset = 0;
  bool _closed = false;

  /// Bir dosya ekler; [data] tam [size] bayt üretmelidir.
  Future<void> addFile({
    required String name,
    required Stream<List<int>> data,
    required int size,
    DateTime? modified,
  }) async {
    assert(!_closed, 'ZipWriter kapandıktan sonra eklenemez');
    final nameBytes = utf8.encode(name);
    final time = _dosTime(modified ?? DateTime.now());
    final localOffset = _offset;

    // Yerel dosya başlığı — bayrak 0x0008: CRC/boyutlar veri tanımlayıcısında.
    final header = ByteData(30)
      ..setUint32(0, 0x04034b50, _le) // imza
      ..setUint16(4, 20, _le) // gereken sürüm
      ..setUint16(6, 0x0008, _le) // veri tanımlayıcısı bayrağı
      ..setUint16(8, 0, _le) // yöntem: stored
      ..setUint16(10, time.time, _le)
      ..setUint16(12, time.date, _le)
      ..setUint32(14, 0, _le) // crc32 (sonra)
      ..setUint32(18, 0, _le) // sıkıştırılmış boyut (sonra)
      ..setUint32(22, 0, _le) // ham boyut (sonra)
      ..setUint16(26, nameBytes.length, _le)
      ..setUint16(28, 0, _le); // ek alan yok
    _emit(header.buffer.asUint8List());
    _emit(nameBytes);

    final crc = _Crc32();
    var written = 0;
    await for (final chunk in data) {
      crc.add(chunk);
      written += chunk.length;
      _emit(chunk);
    }

    final descriptor = ByteData(16)
      ..setUint32(0, 0x08074b50, _le) // veri tanımlayıcısı imzası
      ..setUint32(4, crc.value, _le)
      ..setUint32(8, written, _le)
      ..setUint32(12, written, _le);
    _emit(descriptor.buffer.asUint8List());

    _central.add(_CentralEntry(
      nameBytes: nameBytes,
      crc: crc.value,
      size: written,
      offset: localOffset,
      time: time,
    ));
  }

  /// Merkez dizini yazar ve akışı kapatır.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final cdOffset = _offset;
    for (final e in _central) {
      final head = ByteData(46)
        ..setUint32(0, 0x02014b50, _le) // imza
        ..setUint16(4, 20, _le) // üreten sürüm
        ..setUint16(6, 20, _le) // gereken sürüm
        ..setUint16(8, 0x0008, _le) // bayraklar
        ..setUint16(10, 0, _le) // yöntem: stored
        ..setUint16(12, e.time.time, _le)
        ..setUint16(14, e.time.date, _le)
        ..setUint32(16, e.crc, _le)
        ..setUint32(20, e.size, _le)
        ..setUint32(24, e.size, _le)
        ..setUint16(28, e.nameBytes.length, _le)
        ..setUint16(30, 0, _le) // ek alan
        ..setUint16(32, 0, _le) // yorum
        ..setUint16(34, 0, _le) // disk no
        ..setUint16(36, 0, _le) // iç öznitelikler
        ..setUint32(38, 0, _le) // dış öznitelikler
        ..setUint32(42, e.offset, _le);
      _emit(head.buffer.asUint8List());
      _emit(e.nameBytes);
    }
    final cdSize = _offset - cdOffset;

    final end = ByteData(22)
      ..setUint32(0, 0x06054b50, _le) // EOCD imzası
      ..setUint16(4, 0, _le)
      ..setUint16(6, 0, _le)
      ..setUint16(8, _central.length, _le)
      ..setUint16(10, _central.length, _le)
      ..setUint32(12, cdSize, _le)
      ..setUint32(16, cdOffset, _le)
      ..setUint16(20, 0, _le); // yorum yok
    _emit(end.buffer.asUint8List());
    await _out.close();
  }

  void _emit(List<int> bytes) {
    _offset += bytes.length;
    _out.add(bytes);
  }

  static ({int time, int date}) _dosTime(DateTime t) {
    final year = t.year < 1980 ? 1980 : t.year;
    final time = (t.hour << 11) | (t.minute << 5) | (t.second ~/ 2);
    final date = ((year - 1980) << 9) | (t.month << 5) | t.day;
    return (time: time, date: date);
  }
}

class _CentralEntry {
  _CentralEntry({
    required this.nameBytes,
    required this.crc,
    required this.size,
    required this.offset,
    required this.time,
  });

  final List<int> nameBytes;
  final int crc;
  final int size;
  final int offset;
  final ({int time, int date}) time;
}

/// Standart CRC-32 (IEEE 802.3) — lazily tablo ile.
class _Crc32 {
  static List<int>? _table;
  int _crc = 0xffffffff;

  static List<int> _buildTable() {
    final table = List<int>.filled(256, 0);
    for (var i = 0; i < 256; i++) {
      var c = i;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xedb88320 ^ (c >> 1) : c >> 1;
      }
      table[i] = c;
    }
    return table;
  }

  void add(List<int> bytes) {
    final table = _table ??= _buildTable();
    var crc = _crc;
    for (final b in bytes) {
      crc = table[(crc ^ b) & 0xff] ^ (crc >> 8);
    }
    _crc = crc;
  }

  int get value => (_crc ^ 0xffffffff) & 0xffffffff;
}
