import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/data/repositories/download_repository.dart';
import 'package:virusdownloader/data/repositories/settings_repository.dart';
import 'package:virusdownloader/data/services/ffmpeg_service.dart';
import 'package:virusdownloader/data/services/file_service.dart';
import 'package:virusdownloader/data/services/http_download_service.dart';
import 'package:virusdownloader/data/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FfmpegService ffmpegService;
  late DownloadRepository downloadRepo;
  late StorageService storageService;
  late SettingsRepository settingsRepo;
  late FileService fileService;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    ffmpegService = FfmpegService();
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
      ffmpegService: ffmpegService,
    );
    await downloadRepo.init();
  });

  group('FfmpegService tests', () {
    test('Bundled FFmpeg is reported as available', () async {
      final service = FfmpegService();
      final path = await service.getFfmpegPath();
      expect(path, equals('bundled'));
      expect(await service.isAvailable(), isTrue);

      final dl = await service.downloadLightweightFfmpeg();
      expect(dl, equals('bundled'));
    });

    test('getFfmpegPath supports mock path override for testing', () async {
      final service = FfmpegService();
      service.setMockPath('/custom/ffmpeg');
      expect(await service.getFfmpegPath(), equals('/custom/ffmpeg'));
      service.clearCache();
      expect(await service.getFfmpegPath(), equals('bundled'));
    });

    test('addTask normalizes .m3u8 URLs to .mkv container with video category', () async {
      final task = await downloadRepo.addTask(
        url: 'https://cdn.example.com/anime/slime-s4-ep1/master.m3u8',
        fileName: 'slime_s4_ep1.m3u8',
        targetDirectory: Directory.systemTemp.path,
      );

      expect(task.fileName, 'slime_s4_ep1.mkv');
      expect(task.savePath.endsWith('.mkv'), isTrue);
      expect(task.category, DownloadCategory.videos);
    });

    test('addTask normalizes .ts URLs to .mkv container', () async {
      final task = await downloadRepo.addTask(
        url: 'https://cdn.example.com/anime/stream.ts?token=xyz',
        fileName: 'episode.ts',
        targetDirectory: Directory.systemTemp.path,
      );

      expect(task.fileName, 'episode.mkv');
      expect(task.savePath.endsWith('.mkv'), isTrue);
      expect(task.category, DownloadCategory.videos);
    });

    test('addTask preserves regular non-stream file extensions', () async {
      final task = await downloadRepo.addTask(
        url: 'https://cdn.example.com/files/archive.zip',
        fileName: 'archive.zip',
        targetDirectory: Directory.systemTemp.path,
      );

      expect(task.fileName, 'archive.zip');
      expect(task.savePath.endsWith('.zip'), isTrue);
      expect(task.category, DownloadCategory.compressed);
    });
  });
}

