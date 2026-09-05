import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/core/utils.dart';
import 'package:virusdownloader/domain/models/download_task.dart';

void main() {
  group('AppUtils Unit Tests', () {
    test('formatFileSize formats bytes correctly', () {
      expect(AppUtils.formatFileSize(0), '0 B');
      expect(AppUtils.formatFileSize(500), '500 B');
      expect(AppUtils.formatFileSize(1024), '1.0 KB');
      expect(AppUtils.formatFileSize(1024 * 1024 * 5), '5.0 MB');
      expect(AppUtils.formatFileSize(1024 * 1024 * 1024 * 2), '2.0 GB');
    });

    test('formatSpeed formats speed correctly', () {
      expect(AppUtils.formatSpeed(0), '0 B/s');
      expect(AppUtils.formatSpeed(1024), '1.0 KB/s');
      expect(AppUtils.formatSpeed(1024 * 1024 * 2.5), '2.5 MB/s');
    });

    test('categoryFromExtension maps extensions to categories', () {
      expect(AppUtils.categoryFromExtension('pdf'), DownloadCategory.documents);
      expect(AppUtils.categoryFromExtension('.docx'), DownloadCategory.documents);
      expect(AppUtils.categoryFromExtension('mp4'), DownloadCategory.videos);
      expect(AppUtils.categoryFromExtension('mp3'), DownloadCategory.audio);
      expect(AppUtils.categoryFromExtension('zip'), DownloadCategory.compressed);
      expect(AppUtils.categoryFromExtension('exe'), DownloadCategory.programs);
      expect(AppUtils.categoryFromExtension('unknown_ext'), DownloadCategory.other);
    });

    test('extractFileName extracts clean filename from URL', () {
      expect(
        AppUtils.extractFileName('https://example.com/downloads/package.zip'),
        'package.zip',
      );
      expect(
        AppUtils.extractFileName('https://cdn.example.org/videos/movie%20trailer.mp4?auth=xyz'),
        'movie trailer.mp4',
      );
    });
  });

  group('DownloadTask Domain Model Tests', () {
    test('Calculates progress and ETA accurately', () {
      final task = DownloadTask(
        id: 'test-1',
        url: 'https://example.com/sample.zip',
        fileName: 'sample.zip',
        savePath: '/downloads/sample.zip',
        totalBytes: 1000,
        downloadedBytes: 500,
        speedBytesPerSec: 100,
        status: DownloadStatus.downloading,
        dateAdded: DateTime.now(),
      );

      expect(task.progress, 0.5);
      expect(task.eta, const Duration(seconds: 5));
      expect(task.formattedEta, '5s');
      expect(task.isIndeterminate, false);

      final completed = task.copyWith(
        status: DownloadStatus.completed,
        downloadedBytes: 1000,
      );
      expect(completed.progress, 1.0);
      expect(completed.eta, isNull);
    });
  });
}
