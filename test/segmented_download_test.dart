import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/data/services/segmented_download_service.dart';

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
  });
}

