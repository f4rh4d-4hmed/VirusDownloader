import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/data/services/segmented_download_service.dart';
import 'package:virusdownloader/domain/models/proxy_config.dart';

void main() {
  group('Segmented Download & Worker State Tests', () {
    test('SegmentWorkerState calculates offsets and progress correctly', () {
      final worker = SegmentWorkerState(
        index: 0,
        startByte: 0,
        endByte: 999,
        downloadedBytes: 500,
      );

      expect(worker.totalSegmentBytes, 1000);
      expect(worker.currentOffset, 500);
      expect(worker.isFinished, isFalse);

      worker.downloadedBytes = 1000;
      expect(worker.isFinished, isTrue);
    });

    test('SegmentWorkerState serializes and deserializes to JSON', () {
      final worker = SegmentWorkerState(
        index: 2,
        startByte: 2000,
        endByte: 2999,
        downloadedBytes: 450,
      );

      final json = worker.toJson();
      final restored = SegmentWorkerState.fromJson(json);

      expect(restored.index, 2);
      expect(restored.startByte, 2000);
      expect(restored.endByte, 2999);
      expect(restored.downloadedBytes, 450);
      expect(restored.currentOffset, 2450);
    });

    test('SpeedLimitMode extension returns correct byte rates', () {
      expect(SpeedLimitMode.rabbit.maxBytesPerSecond, 250 * 1024);
      expect(SpeedLimitMode.turtle.maxBytesPerSecond, 1024 * 1024);
      expect(SpeedLimitMode.unlimited.maxBytesPerSecond, 0);
      expect(SpeedLimitMode.rocket.maxBytesPerSecond, 0);
    });

    test('DynamicProxyPool prioritizes fast proxies and rotates on slow/dead', () {
      final p1 = ProxyConfig.tryParse('http://1.1.1.1:8080')!;
      final p2 = ProxyConfig.tryParse('http://2.2.2.2:8080')!
          .copyWith(lastBenchmarkSpeed: 500000.0);
      final p3 = ProxyConfig.tryParse('http://3.3.3.3:8080')!
          .copyWith(lastBenchmarkSpeed: 1500000.0);

      final pool = DynamicProxyPool([p1, p2, p3]);

      // p3 has highest speed (1.5MB/s), should be dispensed first
      final first = pool.acquireNext();
      expect(first?.host, '3.3.3.3');

      // p2 has second highest speed (500KB/s)
      final second = pool.acquireNext();
      expect(second?.host, '2.2.2.2');

      // p1 has no speed recorded, dispensed third
      final third = pool.acquireNext();
      expect(third?.host, '1.1.1.1');

      // Pool exhausted
      final fourth = pool.acquireNext();
      expect(fourth, isNull);
    });

    test('DynamicProxyPool skips dead or slow marked proxies', () {
      final p1 = ProxyConfig.tryParse('http://10.0.0.1:8080')!;
      final p2 = ProxyConfig.tryParse('http://10.0.0.2:8080')!;
      final p3 = ProxyConfig.tryParse('http://10.0.0.3:8080')!;

      final pool = DynamicProxyPool([p1, p2, p3]);
      pool.markSlowOrDead(p2, reason: 'Test stall');

      final first = pool.acquireNext();
      expect(first?.host, '10.0.0.1');

      // p2 was marked dead, so acquireNext skips directly to p3
      final second = pool.acquireNext();
      expect(second?.host, '10.0.0.3');

      expect(pool.acquireNext(), isNull);
    });
  });
}

