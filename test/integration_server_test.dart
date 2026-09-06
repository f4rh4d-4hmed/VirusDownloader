import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/data/repositories/download_repository.dart';
import 'package:virusdownloader/data/repositories/settings_repository.dart';
import 'package:virusdownloader/data/services/file_service.dart';
import 'package:virusdownloader/data/services/http_download_service.dart';
import 'package:virusdownloader/data/services/integration_server_service.dart';
import 'package:virusdownloader/data/services/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storageService;
  late SettingsRepository settingsRepo;
  late DownloadRepository downloadRepo;
  late IntegrationServerService server;
  late HttpClient httpClient;

  setUp(() async {
    HttpOverrides.global = null;
    httpClient = HttpClient();
    SharedPreferences.setMockInitialValues({});
    storageService = StorageService();
    await storageService.init();

    settingsRepo = SettingsRepository(storageService: storageService);
    await settingsRepo.init();

    final fileService = FileService();
    final httpService = HttpDownloadService();

    downloadRepo = DownloadRepository(
      httpService: httpService,
      storageService: storageService,
      fileService: fileService,
      settingsRepo: settingsRepo,
    );
    await downloadRepo.init();

    // Use test port to avoid collision
    server = IntegrationServerService(
      downloadRepository: downloadRepo,
      fileService: fileService,
      port: 9890,
    );
    await server.start();
  });

  tearDown(() async {
    await server.stop();
    httpClient.close(force: true);
  });

  test('Integration server responds to GET /health with CORS headers', () async {
    final request = await httpClient.getUrl(Uri.parse('http://127.0.0.1:9890/health'));
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    expect(response.headers.value('access-control-allow-origin'), '*');

    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    expect(json['status'], 'ok');
    expect(json['app'], 'VirusDownloader');
  });

  test('Integration server handles POST /add and queues task with custom headers', () async {
    final request = await httpClient.postUrl(Uri.parse('http://127.0.0.1:9890/add'));
    request.headers.contentType = ContentType.json;

    final payload = {
      'url': 'https://example.com/stream/video.m3u8',
      'fileName': 'custom_video.m3u8',
      'category': 'video',
      'headers': {
        'Referer': 'https://example.com/watch?v=123',
        'User-Agent': 'CustomBrowser/1.0',
        'Cookie': 'auth=token999',
      },
    };

    request.write(jsonEncode(payload));
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;

    expect(json['success'], isTrue);
    expect(json['taskId'], isNotNull);

    // Verify task in repository
    expect(downloadRepo.tasks.length, 1);
    final task = downloadRepo.tasks.first;
    expect(task.url, 'https://example.com/stream/video.m3u8');
    expect(task.fileName, 'custom_video.mkv');
    expect(task.category, DownloadCategory.videos);
    expect(task.headers?['Referer'], 'https://example.com/watch?v=123');
    expect(task.headers?['Cookie'], 'auth=token999');
    expect(task.headers?['User-Agent'], 'CustomBrowser/1.0');
  });

  test('Integration server strips Range header and normalizes category for videos', () async {
    final request = await httpClient.postUrl(Uri.parse('http://127.0.0.1:9890/add'));
    request.headers.contentType = ContentType.json;

    final payload = {
      'url': '//example.com/video.mp4?query=sample video',
      'fileName': 'video.mp4',
      'category': 'video',
      'headers': {
        'Referer': 'https://example.com/page',
        'Range': 'bytes=0-1048576',
        'range': 'bytes=0-1048576',
      },
    };

    request.write(jsonEncode(payload));
    final response = await request.close();

    expect(response.statusCode, HttpStatus.ok);
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    expect(json['success'], isTrue);

    final task = downloadRepo.tasks.first;
    expect(task.url.startsWith('https://example.com/video.mp4'), isTrue);
    expect(task.headers?.containsKey('Range'), isFalse);
    expect(task.headers?.containsKey('range'), isFalse);
    expect(task.headers?['Referer'], 'https://example.com/page');
  });

  test('Integration server rejects blob URLs with 400 and clear error message', () async {
    final request = await httpClient.postUrl(Uri.parse('http://127.0.0.1:9890/add'));
    request.headers.contentType = ContentType.json;

    final payload = {
      'url': 'blob:https://example.com/123-456',
      'fileName': 'blob_video.mp4',
    };

    request.write(jsonEncode(payload));
    final response = await request.close();

    expect(response.statusCode, HttpStatus.badRequest);
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    expect(json['error'], contains('Browser-internal blob stream cannot be downloaded directly'));
  });
}
