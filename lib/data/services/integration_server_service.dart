import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/enums.dart';
import '../../core/utils.dart';
import '../repositories/download_repository.dart';
import 'file_service.dart';

class IntegrationServerService extends ChangeNotifier {
  final DownloadRepository downloadRepository;
  final FileService fileService;
  final int port;

  HttpServer? _server;
  bool _isRunning = false;
  DateTime? _lastConnectedTime;
  int _receivedTasksCount = 0;

  IntegrationServerService({
    required this.downloadRepository,
    required this.fileService,
    this.port = 9849,
  });

  bool get isRunning => _isRunning;
  DateTime? get lastConnectedTime => _lastConnectedTime;
  int get receivedTasksCount => _receivedTasksCount;
  int get serverPort => _server?.port ?? port;

  /// Starts the local HTTP bridge server
  Future<void> start() async {
    if (_isRunning) return;

    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: true,
      );
      _isRunning = true;
      notifyListeners();

      _server!.listen(
        _handleRequest,
        onError: (e) {
          debugPrint('IntegrationServer error: $e');
        },
      );
      debugPrint('VirusDownloader Integration Server listening on port ${_server!.port}');
    } catch (e) {
      debugPrint('Failed to bind IntegrationServer on port $port: $e');
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Stops the local HTTP bridge server
  Future<void> stop() async {
    if (!_isRunning) return;
    await _server?.close(force: true);
    _server = null;
    _isRunning = false;
    notifyListeners();
  }

  Future<void> _handleRequest(HttpRequest request) async {
    // Add CORS headers to all responses
    request.response.headers.set('Access-Control-Allow-Origin', '*');
    request.response.headers.set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
    request.response.headers.set('Access-Control-Allow-Headers', 'Content-Type, Authorization, *');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    _lastConnectedTime = DateTime.now();
    notifyListeners();

    final path = request.uri.path;

    if (request.method == 'GET' && (path == '/health' || path == '/status')) {
      request.response.headers.contentType = ContentType.json;
      request.response.statusCode = HttpStatus.ok;
      request.response.write(jsonEncode({
        'status': 'ok',
        'app': 'VirusDownloader',
        'version': '1.0.0',
        'port': _server?.port ?? port,
        'uptime': DateTime.now().toIso8601String(),
      }));
      await request.response.close();
      return;
    }

    if (request.method == 'POST' && path == '/add') {
      try {
        final content = await utf8.decoder.bind(request).join();
        final data = jsonDecode(content) as Map<String, dynamic>;

        final url = (data['url'] as String? ?? '').trim();
        if (url.isEmpty || (!url.startsWith('http://') && !url.startsWith('https://'))) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.write(jsonEncode({'error': 'Invalid or missing URL'}));
          await request.response.close();
          return;
        }

        var fileName = (data['fileName'] as String? ?? '').trim();
        if (fileName.isEmpty) {
          fileName = AppUtils.extractFileName(url);
        }

        // Parse category
        DownloadCategory category = DownloadCategory.other;
        final catStr = data['category'] as String?;
        if (catStr != null) {
          category = DownloadCategory.values.firstWhere(
            (c) => c.name.toLowerCase() == catStr.toLowerCase(),
            orElse: () => AppUtils.categoryFromExtension(fileName),
          );
        } else {
          category = AppUtils.categoryFromExtension(fileName);
        }

        // Parse custom headers
        Map<String, String>? headers;
        if (data['headers'] != null && data['headers'] is Map) {
          headers = Map<String, String>.from(
            (data['headers'] as Map).map(
              (k, v) => MapEntry(k.toString(), v.toString()),
            ),
          );
        }

        // Determine save directory
        final targetDir = downloadRepository.settingsRepo.currentSettings.defaultSavePath.isNotEmpty
            ? downloadRepository.settingsRepo.currentSettings.defaultSavePath
            : await fileService.getDefaultDownloadDirectory();

        // Add task to repository
        final task = await downloadRepository.addTask(
          url: url,
          fileName: fileName,
          targetDirectory: targetDir,
          category: category,
          headers: headers,
        );

        _receivedTasksCount++;
        notifyListeners();

        // Bring desktop window to focus
        if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
          try {
            await windowManager.show();
            await windowManager.focus();
          } catch (_) {}
        }

        request.response.headers.contentType = ContentType.json;
        request.response.statusCode = HttpStatus.ok;
        request.response.write(jsonEncode({
          'success': true,
          'taskId': task.id,
          'fileName': task.fileName,
          'savePath': task.savePath,
        }));
        await request.response.close();
      } catch (err) {
        request.response.statusCode = HttpStatus.internalServerError;
        request.response.write(jsonEncode({'error': err.toString()}));
        await request.response.close();
      }
      return;
    }

    // Default 404
    request.response.statusCode = HttpStatus.notFound;
    request.response.write(jsonEncode({'error': 'Endpoint not found'}));
    await request.response.close();
  }
}

