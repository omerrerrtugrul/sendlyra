import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/transfer_job.dart';

/// Tamamlanan transferlerin kalıcı geçmişi.
class HistoryService extends ChangeNotifier {
  static const _kHistory = 'history.entries';
  static const int maxEntries = 200;

  final SharedPreferences prefs;
  final List<HistoryEntry> entries = [];

  HistoryService(this.prefs) {
    final raw = prefs.getString(_kHistory);
    if (raw != null && raw.isNotEmpty) {
      try {
        entries.addAll(HistoryEntry.listFromJson(raw));
      } catch (_) {
        // Bozuk kayıt yok sayılır.
      }
    }
  }

  Future<void> add(TransferJob job) async {
    entries.insert(
      0,
      HistoryEntry(
        id: job.id,
        direction: job.direction,
        peerName: job.peerName,
        title: job.displayName,
        bytes: job.transferred,
        time: job.finishedAt ?? DateTime.now(),
        success: job.state == JobState.completed,
      ),
    );
    if (entries.length > maxEntries) {
      entries.removeRange(maxEntries, entries.length);
    }
    await _persist();
    notifyListeners();
  }

  Future<void> clear() async {
    entries.clear();
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    final encoded = jsonEncode([for (final e in entries) e.toJson()]);
    await prefs.setString(_kHistory, encoded);
  }
}
