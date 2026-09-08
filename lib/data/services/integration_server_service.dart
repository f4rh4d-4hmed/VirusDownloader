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

        var url = (data['url'] as String? ?? '').trim();

        // 1. Check for browser-internal memory URLs (blob / data)
        if (url.startsWith('blob:') || url.startsWith('data:')) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'error':
                'Browser-internal blob stream cannot be downloaded directly. Please select the captured stream from the VirusDownloader toolbar extension.',
          }));
          await request.response.close();
          return;
        }

        // 2. Normalize protocol-relative and missing scheme URLs
        if (url.startsWith('//')) {
          url = 'https:$url';
        } else if (!url.startsWith('http://') && !url.startsWith('https://')) {
          if (url.contains('.') || url.contains('/')) {
            url = 'https://${url.replaceFirst(RegExp(r'^/+'), '')}';
          }
        }

        // Encode any spaces or unsafe characters if raw string was passed
        if (url.contains(' ')) {
          url = Uri.encodeFull(url);
        }

        final parsedUri = Uri.tryParse(url);
        if (url.isEmpty ||
            parsedUri == null ||
            (!url.startsWith('http://') && !url.startsWith('https://')) ||
            parsedUri.host.isEmpty) {
          request.response.statusCode = HttpStatus.badRequest;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'error': 'Invalid URL: "$url". A valid HTTP or HTTPS URL is required.',
          }));
          await request.response.close();
          return;
        }

        var fileName = (data['fileName'] as String? ?? '').trim();
        if (fileName.isEmpty) {
          fileName = AppUtils.extractFileName(url);
        }

        // Parse category:
        // Priority 1: If fileName has a recognizable extension, use its category
        final extCategory = AppUtils.categoryFromExtension(fileName);
        DownloadCategory category = extCategory;

        final catStr = (data['category'] as String?)?.toLowerCase().trim();
        final isExplicitStream = catStr == 'hls_stream' || catStr == 'dash_stream';

        if (isExplicitStream) {
          category = DownloadCategory.videos;
        } else if (category == DownloadCategory.other && catStr != null && catStr.isNotEmpty && catStr != 'other') {
          // Priority 2: If extension was unknown/other, inspect category provided by browser
          if (catStr == 'video' || catStr == 'videos') {
            category = DownloadCategory.videos;
          } else if (catStr == 'audio') {
            category = DownloadCategory.audio;
          } else if (catStr == 'image' || catStr == 'images') {
            category = DownloadCategory.images;
          } else if (catStr == 'document' || catStr == 'documents') {
            category = DownloadCategory.documents;
          } else if (catStr == 'archive' ||
              catStr == 'archives' ||
              catStr == 'compressed') {
            category = DownloadCategory.compressed;
          } else if (catStr == 'program' || catStr == 'programs') {
            category = DownloadCategory.programs;
          } else {
            category = DownloadCategory.values.firstWhere(
              (c) => c.name.toLowerCase() == catStr,
              orElse: () => DownloadCategory.other,
            );
          }
        }

        // Parse custom headers
        Map<String, String>? headers;
        if (data['headers'] != null && data['headers'] is Map) {
          headers = <String, String>{};
          for (final entry in (data['headers'] as Map).entries) {
            final key = entry.key.toString().trim();
            final value = entry.value.toString();
            // Strip any client-side range header so it does not conflict
            // with HttpDownloadService's own Range resumption or trigger CDN 400 Bad Request
            if (key.toLowerCase() == 'range') continue;
            headers[key] = value;
          }
          if (headers.isEmpty) headers = null;
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

