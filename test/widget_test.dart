import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/core/utils.dart';
import 'package:virusdownloader/data/models/download_task_model.dart';
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

    test('isMobile and isDesktop properties return boolean flags', () {
      expect(AppUtils.isMobile, isA<bool>());
      expect(AppUtils.isDesktop, isA<bool>());
      // On Windows test environment, isDesktop should be true and isMobile should be false
      expect(AppUtils.isDesktop, isTrue);
      expect(AppUtils.isMobile, isFalse);
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

    test('Preserves headers across copyWith', () {
      final task = DownloadTask(
        id: 'h-1',
        url: 'https://example.com/vid.mp4',
        fileName: 'vid.mp4',
        savePath: '/tmp/vid.mp4',
        dateAdded: DateTime.now(),
        headers: const {'Referer': 'https://example.com'},
      );

      expect(task.headers?['Referer'], 'https://example.com');
      final updated = task.copyWith(downloadedBytes: 100);
      expect(updated.headers?['Referer'], 'https://example.com');
    });
  });

  group('DownloadTaskModel Serialization Tests', () {
    test('Serializes and deserializes headers correctly', () {
      final now = DateTime.now();
      final task = DownloadTask(
        id: 'header-task-1',
        url: 'https://example.com/protected/video.mp4',
        fileName: 'video.mp4',
        savePath: '/downloads/video.mp4',
        totalBytes: 5000,
        downloadedBytes: 1000,
        status: DownloadStatus.downloading,
        dateAdded: now,
        headers: {
          'Referer': 'https://example.com/player',
          'User-Agent': 'CustomUA/1.0',
          'Cookie': 'auth_token=secret_123',
        },
      );

      final json = DownloadTaskModel.toJson(task);
      expect(json['headers'], isNotNull);
      expect(json['headers']['Referer'], 'https://example.com/player');
      expect(json['headers']['Cookie'], 'auth_token=secret_123');

      final deserialized = DownloadTaskModel.fromJson(json);
      expect(deserialized.id, task.id);
      expect(deserialized.headers?['Referer'], 'https://example.com/player');
      expect(deserialized.headers?['User-Agent'], 'CustomUA/1.0');
      expect(deserialized.headers?['Cookie'], 'auth_token=secret_123');
    });

    test('Serializes and deserializes isResumable flag correctly', () {
      final taskResumable = DownloadTask(
        id: 'resumable-1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '/downloads/file.zip',
        dateAdded: DateTime.now(),
        isResumable: true,
      );
      final jsonResumable = DownloadTaskModel.toJson(taskResumable);
      expect(jsonResumable['isResumable'], isTrue);
      expect(DownloadTaskModel.fromJson(jsonResumable).isResumable, isTrue);

      final taskUnresumable = taskResumable.copyWith(isResumable: false);
      final jsonUnresumable = DownloadTaskModel.toJson(taskUnresumable);
      expect(jsonUnresumable['isResumable'], isFalse);
      expect(DownloadTaskModel.fromJson(jsonUnresumable).isResumable, isFalse);

      // Backwards compatibility: defaults to true if missing in json
      final jsonLegacy = {
        'id': 'legacy-1',
        'url': 'https://example.com/legacy.zip',
        'fileName': 'legacy.zip',
        'savePath': '/downloads/legacy.zip',
      };
      expect(DownloadTaskModel.fromJson(jsonLegacy).isResumable, isTrue);
    });
  });
}
