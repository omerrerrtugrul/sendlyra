import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/transfer_job.dart';

/// E-03: transfer sonucu bildirimleri için soyut arayüz.
///
/// Testlerde [FakeTransferNotifier], üretimde [LocalTransferNotifier]
/// kullanılır; bildirim altyapısının yokluğu transferi etkilemez.
abstract class TransferNotifier {
  Future<void> init();

  /// İş bittiğinde (tamamlandı / başarısız / iptal) çağrılır.
  void notifyJobFinished(TransferJob job);
}

/// Bildirim göndermeyen taklit (test / desteklenmeyen platform).
class FakeTransferNotifier implements TransferNotifier {
  final List<TransferJob> notified = [];

  @override
  Future<void> init() async {}

  @override
  void notifyJobFinished(TransferJob job) {
    notified.add(job);
  }
}

/// E-03: `flutter_local_notifications` tabanlı yerel bildirimler.
///
/// Transfer tamamlandı/başarısız olduğunda sesli + titreşimli bildirim
/// gösterir; Android 8+ için bildirim kanalı açar.
class LocalTransferNotifier implements TransferNotifier {
  LocalTransferNotifier({String Function()? locale})
      : _locale = locale ?? (() => 'tr');

  final String Function() _locale;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static const _android = AndroidNotificationDetails(
    'sendlyra_transfers',
    'Transfer bildirimleri',
    channelDescription: 'Tamamlanan ve başarısız aktarımlar',
    importance: Importance.high,
    priority: Priority.high,
    playSound: true,
    enableVibration: true,
  );

  static const _details = NotificationDetails(
    android: _android,
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
    linux: LinuxNotificationDetails(),
  );

  @override
  Future<void> init() async {
    if (_ready) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
      macOS: DarwinInitializationSettings(),
      linux: LinuxInitializationSettings(defaultActionName: 'open'),
    );
    await _plugin.initialize(settings: settings);
    try {
      // Android 13+ için bildirim izni (sorulur; reddedilirse sessizce devam).
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();
    } catch (_) {
      // İzin akışı yoksa bildirimler sessizce atlanır.
    }
    _ready = true;
  }

  @override
  void notifyJobFinished(TransferJob job) {
    if (!_ready) return;
    final (title, body) = notificationContent(job, locale: _locale());
    _plugin
        .show(
          id: job.id.hashCode & 0x7fffffff,
          title: title,
          body: body,
          notificationDetails: _details,
        )
        .ignore();
  }
}

/// E-03: bildirim başlık/gövdelerini üretir (saf, test edilebilir).
///
/// `locale` yalnızca `en` ise İngilizce; aksi hâlde Türkçe.
(String, String) notificationContent(TransferJob job,
    {String locale = 'tr'}) {
  final tr = locale != 'en';
  final sent = job.direction == JobDirection.send;
  final ok = job.state == JobState.completed;

  final title = switch ((ok, sent)) {
    (true, true) => tr ? 'Gönderim tamamlandı' : 'Transfer completed',
    (true, false) => tr ? 'Alım tamamlandı' : 'Transfer received',
    (false, true) => tr ? 'Gönderim başarısız' : 'Transfer failed',
    (false, false) => tr ? 'Alım başarısız' : 'Receive failed',
  };

  final detail = job.text != null ? _preview(job.text!) : job.displayName;
  final body = (job.error != null && !ok) ? '$detail · ${job.error}' : detail;
  return (title, body);
}

String _preview(String text) {
  final t = text.trim();
  return t.length > 40 ? '${t.substring(0, 40)}…' : t;
}
