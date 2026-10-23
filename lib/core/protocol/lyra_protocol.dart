/// LyraLink protokolü — sabitler ve türetilmiş değerler.
///
/// Bu protokol SendLyra için sıfırdan tasarlanmıştır.
abstract final class LyraProtocol {
  static const String protocolName = 'LyraLink';
  static const int protocolVersion = 1;

  /// Keşif (multicast) portu.
  static const int discoveryPort = 47801;

  /// Keşif multicast grubu.
  ///
  /// 224.0.0.0/24 altındaki admin-yerel aralık, tüm yaygın platformlarda
  /// (özellikle Android) sorunsuz kabul edilir; daha yüksek grup adresleri
  /// bazı cihazlarda sessizce reddedilebilir.
  static const String multicastGroup = '224.0.0.167';

  /// Transfer (TCP) portu için varsayılan değer.
  static const int defaultTransferPort = 47802;

  /// Cihazların kendini tanıtma aralığı.
  static const Duration beaconInterval = Duration(seconds: 2);

  /// Beacon gelmezse cihaz "çevrimdışı" sayılır.
  static const Duration deviceTimeout = Duration(seconds: 8);

  /// El sıkışma (handshake) zaman aşımı.
  static const Duration handshakeTimeout = Duration(seconds: 10);

  /// Onay beklerken geçerli süre.
  static const Duration approvalTimeout = Duration(seconds: 120);

  /// Dosya akışındaki tek veri karesinin maksimum boyutu.
  static const int chunkSize = 64 * 1024;

  /// Kabul edilen maksimum şifreli kare boyutu.
  static const int maxFrameSize = 256 * 1024;

  /// Cihaz adı uzunluk sınırı.
  static const int maxNameLength = 64;
}
