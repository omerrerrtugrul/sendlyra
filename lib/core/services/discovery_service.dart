import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/device.dart';
import '../protocol/lyra_message.dart';
import '../protocol/lyra_protocol.dart';

/// LyraLink keşif katmanı.
///
/// Her cihaz belirli aralıklarla multicast grubuna "beacon" yollar;
/// beacon alan cihazlar eş listesini günceller. Beacon gelmezse cihaz
/// zaman aşımına uğrayıp listeden düşer.
class DiscoveryBeacon {
  final String id;
  final String name;
  final String os;
  final String deviceType;
  final String address;
  final int port;
  final String publicKeyBase64;
  final String fingerprint;
  final bool busy;
  final DateTime receivedAt;

  const DiscoveryBeacon({
    required this.id,
    required this.name,
    required this.os,
    required this.deviceType,
    required this.address,
    required this.port,
    required this.publicKeyBase64,
    required this.fingerprint,
    required this.busy,
    required this.receivedAt,
  });

  factory DiscoveryBeacon.fromJson(
      Map<String, dynamic> json, String address, DateTime now) {
    return DiscoveryBeacon(
      id: json['id'] as String,
      name: clampName((json['name'] as String?) ?? 'bilinmeyen'),
      os: clampName((json['os'] as String?) ?? 'unknown'),
      deviceType: clampName((json['dev'] as String?) ?? 'unknown'),
      address: address,
      port: (json['port'] as num?)?.toInt() ?? LyraProtocol.defaultTransferPort,
      publicKeyBase64: (json['pk'] as String?) ?? '',
      fingerprint: (json['fp'] as String?) ?? '',
      busy: (json['busy'] as bool?) ?? false,
      receivedAt: now,
    );
  }
}

/// Kendi cihaz bilgimiz — beacon yükü.
class BeaconIdentity {
  final String id;
  final String name;
  final String os;
  final String deviceType;
  final int port;
  final String publicKeyBase64;
  final String fingerprint;

  /// Meşgul durumu: cihazda aktif transfer var mı? (beacon'da yayınlanır)
  final bool busy;

  const BeaconIdentity({
    required this.id,
    required this.name,
    required this.os,
    required this.deviceType,
    required this.port,
    required this.publicKeyBase64,
    required this.fingerprint,
    this.busy = false,
  });
}

class DiscoveryService {
  /// Beacon içeriği her zaman güncel değerlerden üretilir (ad değişince tazelenir).
  final BeaconIdentity Function() identity;
  final void Function(LyraDevice device)? onDeviceFound;
  final void Function(String deviceId)? onDeviceLost;

  RawDatagramSocket? _socket;
  Timer? _beaconTimer;
  Timer? _sweepTimer;
  final Map<String, LyraDevice> _devices = {};
  final _controller = StreamController<void>.broadcast();

  DiscoveryService({required this.identity, this.onDeviceFound, this.onDeviceLost});

  Map<String, LyraDevice> get devices =>
      Map<String, LyraDevice>.unmodifiable(_devices);
  Stream<void> get changes => _controller.stream;

  Future<void> start() async {
    if (_socket != null) return;
    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      LyraProtocol.discoveryPort,
      reuseAddress: true,
    );
    socket.broadcastEnabled = true;
    socket.multicastHops = 1;

    // Tüm arayüzlerde multicast grubuna katıl (çok arayüzlü makineler için).
    try {
      socket.joinMulticast(
        InternetAddress(LyraProtocol.multicastGroup),
      );
    } catch (_) {
      // Bazı platformlarda varsayılan arayüz yeterlidir.
    }
    try {
      final interfaces = await NetworkInterface.list(includeLinkLocal: true);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            try {
              socket.joinMulticast(
                InternetAddress(LyraProtocol.multicastGroup),
                iface,
              );
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    socket.listen((event) {
      if (event == RawSocketEvent.read) {
        final datagram = socket.receive();
        if (datagram != null) _handleDatagram(datagram);
      }
    });

    _socket = socket;
    _beaconTimer = Timer.periodic(LyraProtocol.beaconInterval, (_) => announce());
    _sweepTimer = Timer.periodic(const Duration(seconds: 2), (_) => _sweep());
    announce();
  }

  void announce() {
    final socket = _socket;
    if (socket == null) return;
    final self = identity();
    final payload = {
      't': 'beacon',
      'v': LyraProtocol.protocolVersion,
      'id': self.id,
      'name': self.name,
      'os': self.os,
      'dev': self.deviceType,
      'port': self.port,
      'pk': self.publicKeyBase64,
      'fp': self.fingerprint,
      'busy': self.busy,
      'ts': DateTime.now().millisecondsSinceEpoch,
    };
    final bytes = utf8.encode(jsonEncode(payload));
    var outBytes = bytes;
    // R-6: beacon protokol sınırını (512 bayt) aşarsa ad kırpılarak
    // sığdırılır; gönderim asla sınırsız paket üretmez.
    var name = self.name;
    while (outBytes.length > LyraProtocol.maxBeaconBytes && name.isNotEmpty) {
      name = String.fromCharCodes(name.runes.take(name.runes.length - 1));
      payload['name'] = name;
      outBytes = utf8.encode(jsonEncode(payload));
    }
    try {
      socket.send(outBytes, InternetAddress(LyraProtocol.multicastGroup),
          LyraProtocol.discoveryPort);
    } catch (_) {}
  }

  void _handleDatagram(Datagram datagram) {
    try {
      final json = jsonDecode(utf8.decode(datagram.data));
      if (json is! Map<String, dynamic>) return;
      if (json['t'] != 'beacon') return;
      final id = json['id'] as String?;
      if (id == null || id == identity().id) return;

      final beacon = DiscoveryBeacon.fromJson(
        json,
        datagram.address.address,
        DateTime.now(),
      );
      final device = LyraDevice(
        id: beacon.id,
        name: beacon.name,
        os: beacon.os,
        deviceType: beacon.deviceType,
        address: beacon.address,
        port: beacon.port,
        publicKeyBase64: beacon.publicKeyBase64,
        fingerprint: beacon.fingerprint,
        lastSeen: beacon.receivedAt,
        busy: beacon.busy,
      );
      final isNew = !_devices.containsKey(id);
      _devices[id] = device;
      if (isNew) {
        onDeviceFound?.call(device);
      }
      _controller.add(null);
    } catch (_) {
      // Anlamsız paket yok sayılır.
    }
  }

  void _sweep() {
    final now = DateTime.now();
    final expired = _devices.values
        .where((d) => now.difference(d.lastSeen) > LyraProtocol.deviceTimeout)
        .map((d) => d.id)
        .toList();
    for (final id in expired) {
      _devices.remove(id);
      onDeviceLost?.call(id);
    }
    if (expired.isNotEmpty) _controller.add(null);
  }

  Future<void> stop() async {
    _beaconTimer?.cancel();
    _sweepTimer?.cancel();
    _beaconTimer = null;
    _sweepTimer = null;
    _socket?.close();
    _socket = null;
    _devices.clear();
    _controller.add(null);
  }

  void dispose() {
    stop();
    _controller.close();
  }
}
