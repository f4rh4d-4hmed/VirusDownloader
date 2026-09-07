import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/data/repositories/download_repository.dart';
import 'package:virusdownloader/data/repositories/settings_repository.dart';
import 'package:virusdownloader/data/services/file_service.dart';
import 'package:virusdownloader/data/services/http_download_service.dart';
import 'package:virusdownloader/data/services/storage_service.dart';
import 'package:virusdownloader/ui/view_models/downloads_view_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DownloadRepository downloadRepo;
  late DownloadsViewModel downloadsVm;
  late StorageService storageService;
  late SettingsRepository settingsRepo;
  late FileService fileService;

  setUp(() async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    storageService = StorageService();
    await storageService.init();

    settingsRepo = SettingsRepository(storageService: storageService);
    await settingsRepo.init();

    fileService = FileService();
    downloadRepo = DownloadRepository(
      httpService: HttpDownloadService(),
      storageService: storageService,
      fileService: fileService,
      settingsRepo: settingsRepo,
    );
    await downloadRepo.init();

    downloadsVm = DownloadsViewModel(repository: downloadRepo);
  });

  tearDown(() {
    downloadsVm.dispose();
  });

  group('Change download link repository and ViewModel tests', () {
    test('addTask sets isResumable = true for normal files and false for streams', () async {
      final normalTask = await downloadRepo.addTask(
        url: 'https://cdn.example.com/files/archive.zip',
        fileName: 'archive.zip',
        targetDirectory: Directory.systemTemp.path,
      );
      expect(normalTask.isResumable, isTrue);

      final streamTask = await downloadRepo.addTask(
        url: 'https://cdn.example.com/video/master.m3u8',
        fileName: 'video.m3u8',
        targetDirectory: Directory.systemTemp.path,
      );
      expect(streamTask.isResumable, isFalse);
    });

    test('changeDownloadUrl updates URL and optional headers on resumable task', () async {
      final task = await downloadRepo.addTask(
        url: 'https://cdn.example.com/files/bigfile.zip',
        fileName: 'bigfile.zip',
        targetDirectory: Directory.systemTemp.path,
      );

      expect(task.isResumable, isTrue);
      expect(task.url, 'https://cdn.example.com/files/bigfile.zip');

      await downloadsVm.changeDownloadUrl(
        task.id,
        'https://mirror2.example.com/files/bigfile.zip',
        headers: {'Authorization': 'Bearer new_token'},
      );

      final updated = downloadRepo.tasks.firstWhere((t) => t.id == task.id);
      expect(updated.url, 'https://mirror2.example.com/files/bigfile.zip');
      expect(updated.headers?['Authorization'], 'Bearer new_token');
    });

    test('changeDownloadUrl on unresumable task throws StateError', () async {
      final streamTask = await downloadRepo.addTask(
        url: 'https://cdn.example.com/video/stream.m3u8',
        fileName: 'stream.m3u8',
        targetDirectory: Directory.systemTemp.path,
      );

      expect(streamTask.isResumable, isFalse);

      expect(
        () => downloadRepo.changeDownloadUrl(
          streamTask.id,
          'https://cdn2.example.com/video/stream.m3u8',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('paused task remains paused with new URL until resumed', () async {
      final task = await downloadRepo.addTask(
        url: 'https://cdn.example.com/files/data.bin',
        fileName: 'data.bin',
        targetDirectory: Directory.systemTemp.path,
      );

      await downloadRepo.pauseDownload(task.id);
      final pausedTask = downloadRepo.tasks.firstWhere((t) => t.id == task.id);
      expect(pausedTask.status, DownloadStatus.paused);

      await downloadRepo.changeDownloadUrl(
        task.id,
        'https://mirror.example.com/files/data.bin',
      );

      final afterUrlChange = downloadRepo.tasks.firstWhere((t) => t.id == task.id);
      expect(afterUrlChange.url, 'https://mirror.example.com/files/data.bin');
      expect(afterUrlChange.status, DownloadStatus.paused);
    });

    test('changeDownloadUrl with restartFromBeginning deletes file and resets downloadedBytes', () async {
      final tempDir = await Directory.systemTemp.createTemp('vdl_test_restart_');
      try {
        final task = await downloadRepo.addTask(
          url: 'https://cdn.example.com/files/partfile.bin',
          fileName: 'partfile.bin',
          targetDirectory: tempDir.path,
        );

        // Create a local partial file on disk
        final file = File(task.savePath);
        await file.writeAsBytes([1, 2, 3, 4, 5]);
        expect(file.existsSync(), isTrue);

        await downloadRepo.pauseDownload(task.id);

        await downloadsVm.changeDownloadUrl(
          task.id,
          'https://new.example.com/files/partfile.bin',
          restartFromBeginning: true,
        );

        final updatedTask = downloadRepo.tasks.firstWhere((t) => t.id == task.id);
        expect(updatedTask.url, 'https://new.example.com/files/partfile.bin');
        expect(updatedTask.downloadedBytes, 0);
        expect(file.existsSync(), isFalse);
      } finally {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });

  group('HttpDownloadService.verifySameFile tests', () {
    test('verifySameFile returns matches: true when local file does not exist', () async {
      final httpService = HttpDownloadService();
      final result = await httpService.verifySameFile(
        newUrl: 'https://cdn.example.com/file.bin',
        savePath: 'C:\\non_existent_file_path_${DateTime.now().millisecondsSinceEpoch}.bin',
      );
      expect(result.matches, isTrue);
      expect(result.reason, isNull);
    });

    test('verifySameFile returns matches: true when sample bytes and total size match', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sampleBytes = List<int>.generate(32, (i) => i + 1);
      server.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-31/1000');
        request.response.headers.set(HttpHeaders.contentLengthHeader, '${sampleBytes.length}');
        request.response.add(sampleBytes);
        request.response.close();
      });

      final tempDir = await Directory.systemTemp.createTemp('vdl_test_match_');
      try {
        final file = File('${tempDir.path}/test.bin');
        await file.writeAsBytes(sampleBytes);

        final httpService = HttpDownloadService();
        final result = await httpService.verifySameFile(
          newUrl: 'http://127.0.0.1:${server.port}/test.bin',
          savePath: file.path,
          expectedTotalBytes: 1000,
          sampleSizeBytes: 32,
        );

        expect(result.matches, isTrue);
        expect(result.reason, isNull);
        expect(result.newTotalBytes, 1000);
      } finally {
        await server.close();
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('verifySameFile returns matches: false when server returns 200 OK instead of 206', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.ok;
        request.response.add([1, 2, 3]);
        request.response.close();
      });

      final tempDir = await Directory.systemTemp.createTemp('vdl_test_status_');
      try {
        final file = File('${tempDir.path}/test.bin');
        await file.writeAsBytes([1, 2, 3]);

        final httpService = HttpDownloadService();
        final result = await httpService.verifySameFile(
          newUrl: 'http://${server.address.host}:${server.port}/test.bin',
          savePath: file.path,
          sampleSizeBytes: 3,
        );

        expect(result.matches, isFalse);
        expect(result.reason, contains('200 instead of 206'));
      } finally {
        await server.close();
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('verifySameFile returns matches: false when sample bytes mismatch', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-3/100');
        request.response.add([99, 99, 99, 99]);
        request.response.close();
      });

      final tempDir = await Directory.systemTemp.createTemp('vdl_test_mismatch_');
      try {
        final file = File('${tempDir.path}/test.bin');
        await file.writeAsBytes([1, 2, 3, 4]);

        final httpService = HttpDownloadService();
        final result = await httpService.verifySameFile(
          newUrl: 'http://${server.address.host}:${server.port}/test.bin',
          savePath: file.path,
          sampleSizeBytes: 4,
        );

        expect(result.matches, isFalse);
        expect(result.reason, contains('does not match the existing downloaded file'));
      } finally {
        await server.close();
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('verifySameFile returns matches: false when expectedTotalBytes differs from Content-Range', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sample = [1, 2, 3, 4];
      server.listen((HttpRequest request) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(HttpHeaders.contentRangeHeader, 'bytes 0-3/2000');
        request.response.add(sample);
        request.response.close();
      });

      final tempDir = await Directory.systemTemp.createTemp('vdl_test_size_');
      try {
        final file = File('${tempDir.path}/test.bin');
        await file.writeAsBytes(sample);

        final httpService = HttpDownloadService();
        final result = await httpService.verifySameFile(
          newUrl: 'http://${server.address.host}:${server.port}/test.bin',
          savePath: file.path,
          expectedTotalBytes: 1000,
          sampleSizeBytes: 4,
        );

        expect(result.matches, isFalse);
        expect(result.reason, contains('File size mismatch: original file was 1000 bytes, but the new link is 2000 bytes'));
        expect(result.newTotalBytes, 2000);
      } finally {
        await server.close();
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });
  });
}

