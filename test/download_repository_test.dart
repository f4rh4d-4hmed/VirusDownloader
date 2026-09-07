import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/data/repositories/download_repository.dart';
import 'package:virusdownloader/data/repositories/settings_repository.dart';
import 'package:virusdownloader/data/services/file_service.dart';
import 'package:virusdownloader/data/services/http_download_service.dart';
import 'package:virusdownloader/data/services/storage_service.dart';
import 'package:virusdownloader/domain/models/download_task.dart';

class _MockFileService extends FileService {
  bool deleteFileCalled = false;

  @override
  Future<bool> deleteFile(String path) async {
    deleteFileCalled = true;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DownloadRepository downloadRepo;
  late StorageService storageService;
  late SettingsRepository settingsRepo;
  late _MockFileService fileService;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    storageService = StorageService();
    await storageService.init();

    settingsRepo = SettingsRepository(storageService: storageService);
    await settingsRepo.init();

    fileService = _MockFileService();
    downloadRepo = DownloadRepository(
      httpService: HttpDownloadService(),
      storageService: storageService,
      fileService: fileService,
      settingsRepo: settingsRepo,
    );
  });

  group('DownloadRepository state transition guards', () {
    test('pauseDownload does not mutate completed download', () async {
      final completedTask = DownloadTask(
        id: 'comp-1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '/downloads/file.zip',
        totalBytes: 5000,
        downloadedBytes: 5000,
        status: DownloadStatus.completed,
        dateAdded: DateTime.now(),
      );

      await storageService.saveTasks([completedTask]);
      await downloadRepo.init();

      expect(downloadRepo.tasks.first.status, DownloadStatus.completed);

      // Attempt to pause completed task
      await downloadRepo.pauseDownload('comp-1');

      expect(downloadRepo.tasks.first.status, DownloadStatus.completed);
    });

    test('resumeDownload does not mutate completed download', () async {
      final completedTask = DownloadTask(
        id: 'comp-2',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '/downloads/file.zip',
        totalBytes: 5000,
        downloadedBytes: 5000,
        status: DownloadStatus.completed,
        dateAdded: DateTime.now(),
      );

      await storageService.saveTasks([completedTask]);
      await downloadRepo.init();

      // Attempt to resume completed task
      await downloadRepo.resumeDownload('comp-2');

      expect(downloadRepo.tasks.first.status, DownloadStatus.completed);
    });

    test('cancelDownload does not cancel or delete file for completed download', () async {
      final completedTask = DownloadTask(
        id: 'comp-3',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '/downloads/file.zip',
        totalBytes: 5000,
        downloadedBytes: 5000,
        status: DownloadStatus.completed,
        dateAdded: DateTime.now(),
      );

      await storageService.saveTasks([completedTask]);
      await downloadRepo.init();

      // Attempt to cancel completed task
      await downloadRepo.cancelDownload('comp-3');

      expect(downloadRepo.tasks.first.status, DownloadStatus.completed);
      expect(fileService.deleteFileCalled, isFalse);
    });

    test('changeDownloadUrl does not alter URL of completed download', () async {
      final completedTask = DownloadTask(
        id: 'comp-4',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '/downloads/file.zip',
        totalBytes: 5000,
        downloadedBytes: 5000,
        status: DownloadStatus.completed,
        dateAdded: DateTime.now(),
        isResumable: true,
      );

      await storageService.saveTasks([completedTask]);
      await downloadRepo.init();

      // Attempt to change URL of completed task
      await downloadRepo.changeDownloadUrl('comp-4', 'https://newmirror.com/file.zip');

      expect(downloadRepo.tasks.first.url, 'https://example.com/file.zip');
      expect(downloadRepo.tasks.first.status, DownloadStatus.completed);
    });
  });
}
