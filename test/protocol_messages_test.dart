import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sendlyra/core/models/transfer_job.dart';
import 'package:sendlyra/core/protocol/lyra_message.dart';

void main() {
  group('HelloInfo', () {
    test('JSON turu korunur', () {
      final hello = HelloInfo(
        version: 1,
        id: 'abc123',
        name: 'Dizüstü',
        os: 'linux',
        deviceType: 'desktop',
        publicKey: utf8.encode('public-key-bytes'),
        fingerprint: 'deadbeef',
      );

      final json = hello.toJson();
      final restored = HelloInfo.fromJson(json);
      expect(restored.id, 'abc123');
      expect(restored.name, 'Dizüstü');
      expect(restored.os, 'linux');
      expect(restored.publicKey, utf8.encode('public-key-bytes'));
      expect(restored.fingerprint, 'deadbeef');
    });

    test('bozuk paket fırlatır', () {
      expect(
        () => HelloInfo.fromJson(const {'t': 'hello'}),
        throwsA(isA<LyraProtocolException>()),
      );
    });
  });

  group('IncomingOffer', () {
    test('dosya listesi ayrıştırılır', () {
      final offer = IncomingOffer.fromJson(const {
        'job': 'j1',
        'files': [
          {'id': 'f0', 'name': 'foto.jpg', 'size': 1234, 'mime': 'image/jpeg'},
          {'id': 'f1', 'name': 'not.txt', 'size': 42},
        ],
        'text': 'selam',
      });
      expect(offer.jobId, 'j1');
      expect(offer.files.length, 2);
      expect(offer.files.first.name, 'foto.jpg');
      expect(offer.files.last.size, 42);
      expect(offer.text, 'selam');
    });
  });

  group('HistoryEntry', () {
    test('JSON turu korunur', () {
      final entry = HistoryEntry(
        id: 'h1',
        direction: JobDirection.send,
        peerName: 'Telefon',
        title: 'foto.jpg',
        bytes: 2048,
        time: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        success: true,
      );
      final json = jsonEncode([entry.toJson()]);
      final list = HistoryEntry.listFromJson(json);
      expect(list.length, 1);
      expect(list.first.title, 'foto.jpg');
      expect(list.first.success, true);
      expect(list.first.direction, JobDirection.send);
    });
  });

  group('TransferJob', () {
    test('ilerleme ve görünüm hesapları', () {
      final job = TransferJob(
        id: 'j1',
        direction: JobDirection.send,
        peerId: 'p1',
        peerName: 'Telefon',
        peerAddress: '192.168.1.5',
        files: [
          FileTransfer(id: 'f0', name: 'a.bin', size: 100),
          FileTransfer(id: 'f1', name: 'b.bin', size: 100),
        ],
        createdAt: DateTime.now(),
      );
      expect(job.totalBytes, 200);
      job.transferred = 50;
      expect(job.progress, closeTo(0.25, 0.001));
      job.files.first.done = 100;
      job.files.first.completed = true;
      expect(job.displayName, 'a.bin +1');
      expect(job.isFinished, false);
      job.state = JobState.completed;
      expect(job.isFinished, true);
    });
  });
}
