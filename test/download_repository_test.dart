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
  List<String> deletedPaths = [];
  bool cleanupTaskFilesCalled = false;
  String? cleanedTaskId;
  bool? cleanedDeleteTarget;

  _MockFileService({super.customBaseTempDir});

  @override
  Future<bool> deleteFile(String path) async {
    deleteFileCalled = true;
    deletedPaths.add(path);
    return super.deleteFile(path);
  }

  @override
  Future<void> cleanupTaskFiles({
    required String taskId,
    required String fileName,
    String? savePath,
    bool deleteTargetFile = false,
  }) async {
    cleanupTaskFilesCalled = true;
    cleanedTaskId = taskId;
    cleanedDeleteTarget = deleteTargetFile;
    return super.cleanupTaskFiles(
      taskId: taskId,
      fileName: fileName,
      savePath: savePath,
      deleteTargetFile: deleteTargetFile,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DownloadRepository downloadRepo;
  late StorageService storageService;
  late SettingsRepository settingsRepo;
  late _MockFileService fileService;
  late Directory tempTestDir;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    storageService = StorageService();
    await storageService.init();

    settingsRepo = SettingsRepository(storageService: storageService);
    await settingsRepo.init();

    tempTestDir = await Directory.systemTemp.createTemp('vdown_test_');
    fileService = _MockFileService(customBaseTempDir: tempTestDir);
    downloadRepo = DownloadRepository(
      httpService: HttpDownloadService(),
      storageService: storageService,
      fileService: fileService,
      settingsRepo: settingsRepo,
    );
  });

  tearDown(() async {
    try {
      if (await tempTestDir.exists()) {
        await tempTestDir.delete(recursive: true);
      }
    } catch (_) {}
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

    test('cancelDownload cleans up temp files for active download', () async {
      final activeTask = DownloadTask(
        id: 'active-1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '${tempTestDir.path}/file.zip',
        totalBytes: 5000,
        downloadedBytes: 2500,
        status: DownloadStatus.paused,
        dateAdded: DateTime.now(),
      );

      await storageService.saveTasks([activeTask]);
      await downloadRepo.init();

      await downloadRepo.cancelDownload('active-1');

      expect(downloadRepo.tasks.first.status, DownloadStatus.cancelled);
      expect(fileService.cleanupTaskFilesCalled, isTrue);
      expect(fileService.cleanedTaskId, 'active-1');
      expect(fileService.cleanedDeleteTarget, isTrue);
    });

    test('removeTask cleans up temp files and respects deleteFileOnDisk flag', () async {
      final activeTask = DownloadTask(
        id: 'rem-1',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '${tempTestDir.path}/file.zip',
        totalBytes: 5000,
        downloadedBytes: 2500,
        status: DownloadStatus.paused,
        dateAdded: DateTime.now(),
      );

      await storageService.saveTasks([activeTask]);
      await downloadRepo.init();

      // Remove without deleting file on disk
      await downloadRepo.removeTask('rem-1', deleteFileOnDisk: false);
      expect(fileService.cleanupTaskFilesCalled, isTrue);
      expect(fileService.cleanedTaskId, 'rem-1');
      expect(fileService.cleanedDeleteTarget, isFalse);
    });
  });

  group('FileService temp isolation & failsafe cleanup', () {
    test('cleanupTaskFiles only deletes specific task files and preserves other active tasks and folder', () async {
      final actualService = FileService(customBaseTempDir: tempTestDir);

      final taskAPath = await actualService.getTaskTempFilePath('taskA', 'video.mp4');
      final taskAMeta = '$taskAPath.vdown_meta';
      final taskBPath = await actualService.getTaskTempFilePath('taskB', 'archive.zip');
      final taskBMeta = '$taskBPath.vdown_meta';

      await File(taskAPath).writeAsString('task A data');
      await File(taskAMeta).writeAsString('task A meta');
      await File(taskBPath).writeAsString('task B data');
      await File(taskBMeta).writeAsString('task B meta');

      expect(await File(taskAPath).exists(), isTrue);
      expect(await File(taskAMeta).exists(), isTrue);
      expect(await File(taskBPath).exists(), isTrue);
      expect(await File(taskBMeta).exists(), isTrue);

      // Clean up only task A
      await actualService.cleanupTaskFiles(taskId: 'taskA', fileName: 'video.mp4');

      // Task A files deleted
      expect(await File(taskAPath).exists(), isFalse);
      expect(await File(taskAMeta).exists(), isFalse);

      // Task B files MUST remain intact (not affected by other tasks!)
      expect(await File(taskBPath).exists(), isTrue);
      expect(await File(taskBMeta).exists(), isTrue);

      // Temp directory itself must NOT be deleted
      final tempDir = await actualService.getAppTempDirectory();
      expect(await tempDir.exists(), isTrue);

      // Failsafe: Calling cleanupTaskFiles on non-existent files does not throw or complain
      await actualService.cleanupTaskFiles(taskId: 'non_existent', fileName: 'missing.bin');
    });

    test('moveFile moves file safely and overwrites existing destination', () async {
      final actualService = FileService(customBaseTempDir: tempTestDir);

      final src = '${tempTestDir.path}/src.txt';
      final dst = '${tempTestDir.path}/dst.txt';

      await File(src).writeAsString('fresh content');
      await File(dst).writeAsString('old content to be replaced');

      final success = await actualService.moveFile(src, dst);

      expect(success, isTrue);
      expect(await File(src).exists(), isFalse);
      expect(await File(dst).exists(), isTrue);
      expect(await File(dst).readAsString(), 'fresh content');
    });

    test('generateUniqueFilePath resolves duplicates with (1), (2) suffixes', () async {
      final actualService = FileService(customBaseTempDir: tempTestDir);
      final file1 = '${tempTestDir.path}/example.mkv';
      await File(file1).writeAsString('first');

      final path2 = await actualService.generateUniqueFilePath(tempTestDir.path, 'example.mkv');
      expect(path2.endsWith('example (1).mkv'), isTrue);
    });
  });

  group('DownloadRepository New Features & Bug Fixes', () {
    test('addTask assigns unique basename to fileName when file already exists (Bug D1)', () async {
      // Create existing file in download folder
      final existingFile = File('${tempTestDir.path}/example.mkv');
      await existingFile.writeAsString('existing content');

      await downloadRepo.init();

      // Add a download with the same name
      final task = await downloadRepo.addTask(
        url: 'http://example.com/example.mkv',
        targetDirectory: tempTestDir.path,
        fileName: 'example.mkv',
      );
      await downloadRepo.cancelDownload(task.id);
      await Future.delayed(const Duration(milliseconds: 100));

      expect(task.fileName, 'example (1).mkv');
      expect(task.savePath.endsWith('example (1).mkv'), isTrue);
    });

    test('renameTask renames completed file on disk and updates task model (Feature F3)', () async {
      await downloadRepo.init();

      final completedPath = '${tempTestDir.path}/initial_name.txt';
      await File(completedPath).writeAsString('file content');

      final task = DownloadTask(
        id: 'rename-test-1',
        url: 'http://example.com/initial_name.txt',
        fileName: 'initial_name.txt',
        savePath: completedPath,
        status: DownloadStatus.completed,
        dateAdded: DateTime.now(),
      );

      await storageService.saveTasks([task]);
      await downloadRepo.init();

      await downloadRepo.renameTask('rename-test-1', 'new_name.txt');

      final updatedTask = downloadRepo.tasks.firstWhere((t) => t.id == 'rename-test-1');
      expect(updatedTask.fileName, 'new_name.txt');
      expect(await File('${tempTestDir.path}/new_name.txt').exists(), isTrue);
      expect(await File(completedPath).exists(), isFalse);
    });

    test('Periodic file checker detects missing completed file (Feature F4)', () async {
      await downloadRepo.init();

      final existingPath = '${tempTestDir.path}/will_be_deleted.txt';
      final file = File(existingPath);
      await file.writeAsString('to be deleted');

      final task = DownloadTask(
        id: 'missing-test-1',
        url: 'http://example.com/will_be_deleted.txt',
        fileName: 'will_be_deleted.txt',
        savePath: existingPath,
        status: DownloadStatus.completed,
        dateAdded: DateTime.now(),
        fileMissing: false,
      );

      await storageService.saveTasks([task]);
      await downloadRepo.init();

      expect(downloadRepo.tasks.firstWhere((t) => t.id == 'missing-test-1').fileMissing, isFalse);

      // Now delete file from disk
      await file.delete();

      // Trigger periodic check
      downloadRepo.startPeriodicFileCheck(interval: const Duration(seconds: 1));
      await Future.delayed(const Duration(milliseconds: 100));

      final checkedTask = downloadRepo.tasks.firstWhere((t) => t.id == 'missing-test-1');
      expect(checkedTask.fileMissing, isTrue);

      downloadRepo.stopPeriodicFileCheck();
    });
  });
}

