import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/enums.dart';
import '../../core/utils.dart';
import '../../domain/models/download_task.dart';
import '../services/ffmpeg_service.dart';
import '../services/file_service.dart';
import '../services/http_download_service.dart';
import '../services/storage_service.dart';
import 'settings_repository.dart';

class DownloadRepository extends ChangeNotifier {
  final HttpDownloadService httpService;
  final StorageService storageService;
  final FileService fileService;
  final SettingsRepository settingsRepo;
  final FfmpegService? ffmpegService;

  List<DownloadTask> _tasks = [];
  final Map<String, CancelToken> _activeTokens = {};
  final Uuid _uuid = const Uuid();

  DownloadRepository({
    required this.httpService,
    required this.storageService,
    required this.fileService,
    required this.settingsRepo,
    this.ffmpegService,
  });

  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  int get activeDownloadCount =>
      _tasks.where((t) => t.status == DownloadStatus.downloading).length;

  Future<void> init() async {
    _tasks = await storageService.loadTasks();
    notifyListeners();
  }

  /// Adds a new download task and queues it for execution
  Future<DownloadTask> addTask({
    required String url,
    required String fileName,
    required String targetDirectory,
    DownloadCategory? category,
    Map<String, String>? headers,
  }) async {
    String resolvedFileName = fileName.trim();
    final lowerUrl = url.toLowerCase();
    final isStream = lowerUrl.contains('.m3u8') ||
        resolvedFileName.toLowerCase().endsWith('.m3u8') ||
        resolvedFileName.toLowerCase().endsWith('.ts');

    // Convert .m3u8 or .ts stream targets to MKV container with subtitles support
    if (isStream) {
      if (resolvedFileName.toLowerCase().endsWith('.m3u8')) {
        resolvedFileName = resolvedFileName.replaceAll(RegExp(r'\.m3u8$', caseSensitive: false), '.mkv');
      } else if (resolvedFileName.toLowerCase().endsWith('.ts')) {
        resolvedFileName = resolvedFileName.replaceAll(RegExp(r'\.ts$', caseSensitive: false), '.mkv');
      } else if (!resolvedFileName.contains('.')) {
        resolvedFileName = '$resolvedFileName.mkv';
      }
    }

    final uniqueSavePath =
        await fileService.generateUniqueFilePath(targetDirectory, resolvedFileName);
    final detectedCategory = isStream
        ? DownloadCategory.videos
        : (category ?? AppUtils.categoryFromExtension(resolvedFileName));

    final task = DownloadTask(
      id: _uuid.v4(),
      url: url.trim(),
      fileName: resolvedFileName,
      savePath: uniqueSavePath,
      totalBytes: 0,
      downloadedBytes: 0,
      status: DownloadStatus.queued,
      category: detectedCategory,
      speedBytesPerSec: 0.0,
      dateAdded: DateTime.now(),
      headers: headers,
    );

    _tasks.insert(0, task);
    _persistTasks();
    notifyListeners();

    _processQueue();
    return task;
  }

  /// Pauses an active or queued download
  Future<void> pauseDownload(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final token = _activeTokens[id];
    if (token != null && !token.isCancelled) {
      token.cancel('User paused download');
      _activeTokens.remove(id);
    }

    _tasks[index] = _tasks[index].copyWith(
      status: DownloadStatus.paused,
      speedBytesPerSec: 0.0,
    );

    _persistTasks();
    notifyListeners();
    _processQueue();
  }

  /// Resumes a paused or failed download
  Future<void> resumeDownload(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    _tasks[index] = _tasks[index].copyWith(
      status: DownloadStatus.queued,
      speedBytesPerSec: 0.0,
      clearError: true,
    );

    _persistTasks();
    notifyListeners();
    _processQueue();
  }

  /// Cancels a download and deletes any partially downloaded file
  Future<void> cancelDownload(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = _tasks[index];
    final token = _activeTokens[id];
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled download');
      _activeTokens.remove(id);
    }

    // Delete partial file from disk
    await fileService.deleteFile(task.savePath);

    _tasks[index] = task.copyWith(
      status: DownloadStatus.cancelled,
      downloadedBytes: 0,
      speedBytesPerSec: 0.0,
    );

    _persistTasks();
    notifyListeners();
    _processQueue();
  }

  /// Retries a failed or cancelled task
  Future<void> retryDownload(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    _tasks[index] = _tasks[index].copyWith(
      status: DownloadStatus.queued,
      speedBytesPerSec: 0.0,
      clearError: true,
    );

    _persistTasks();
    notifyListeners();
    _processQueue();
  }

  /// Removes task from the list and optionally deletes file on disk
  Future<void> removeTask(String id, {bool deleteFileOnDisk = false}) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = _tasks[index];
    final token = _activeTokens[id];
    if (token != null && !token.isCancelled) {
      token.cancel('Task removed');
      _activeTokens.remove(id);
    }

    if (deleteFileOnDisk) {
      await fileService.deleteFile(task.savePath);
    }

    _tasks.removeAt(index);
    _persistTasks();
    notifyListeners();
    _processQueue();
  }

  /// Pauses all currently active and queued downloads
  Future<void> pauseAll() async {
    for (final task in List.of(_tasks)) {
      if (task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.queued) {
        await pauseDownload(task.id);
      }
    }
  }

  /// Resumes all paused downloads
  Future<void> resumeAll() async {
    for (final task in List.of(_tasks)) {
      if (task.status == DownloadStatus.paused ||
          task.status == DownloadStatus.failed) {
        await resumeDownload(task.id);
      }
    }
  }

  /// Cancels all active, queued, and paused downloads
  Future<void> cancelAllActive() async {
    for (final task in List.of(_tasks)) {
      if (task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.queued ||
          task.status == DownloadStatus.paused) {
        await cancelDownload(task.id);
      }
    }
  }

  /// Checks the queue and launches tasks up to the concurrent limit
  void _processQueue() {
    final maxConcurrent = settingsRepo.currentSettings.maxConcurrentDownloads;
    final currentRunning = activeDownloadCount;
    final availableSlots = maxConcurrent - currentRunning;

    if (availableSlots <= 0) return;

    final queuedTasks =
        _tasks.where((t) => t.status == DownloadStatus.queued).take(availableSlots);

    for (final task in queuedTasks) {
      _executeDownload(task);
    }
  }

  Future<void> _executeDownload(DownloadTask task) async {
    final taskId = task.id;
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) return;

    final cancelToken = CancelToken();
    _activeTokens[taskId] = cancelToken;

    _tasks[index] = _tasks[index].copyWith(
      status: DownloadStatus.downloading,
      clearError: true,
    );
    notifyListeners();

    final isStream = task.url.toLowerCase().contains('.m3u8') ||
        task.fileName.toLowerCase().endsWith('.m3u8') ||
        (task.savePath.toLowerCase().endsWith('.mkv') && task.url.toLowerCase().contains('.m3u8'));

    try {
      if (isStream && ffmpegService != null) {
        await ffmpegService!.downloadHlsStream(
          m3u8Url: task.url,
          savePath: task.savePath,
          cancelToken: cancelToken,
          headers: task.headers,
          onProgress: ({
            required int downloadedBytes,
            required int totalBytes,
            required double speedBytesPerSec,
          }) {
            final idx = _tasks.indexWhere((t) => t.id == taskId);
            if (idx == -1) return;

            _tasks[idx] = _tasks[idx].copyWith(
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes > 0 ? totalBytes : _tasks[idx].totalBytes,
              speedBytesPerSec: speedBytesPerSec,
              status: DownloadStatus.downloading,
            );
            notifyListeners();
          },
        );
      } else {
        await httpService.downloadFile(
          url: task.url,
          savePath: task.savePath,
          cancelToken: cancelToken,
          headers: task.headers,
          onProgress: ({
            required int downloadedBytes,
            required int totalBytes,
            required double speedBytesPerSec,
          }) {
            final idx = _tasks.indexWhere((t) => t.id == taskId);
            if (idx == -1) return;

            _tasks[idx] = _tasks[idx].copyWith(
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes > 0 ? totalBytes : _tasks[idx].totalBytes,
              speedBytesPerSec: speedBytesPerSec,
              status: DownloadStatus.downloading,
            );
            notifyListeners();
          },
        );
      }

      // Successfully completed
      final completedIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (completedIndex != -1 && !cancelToken.isCancelled) {
        final current = _tasks[completedIndex];
        final finalSize = await fileService.getFileSize(current.savePath);
        _tasks[completedIndex] = current.copyWith(
          status: DownloadStatus.completed,
          downloadedBytes: finalSize > 0 ? finalSize : current.downloadedBytes,
          totalBytes: finalSize > 0 ? finalSize : current.totalBytes,
          speedBytesPerSec: 0.0,
          dateCompleted: DateTime.now(),
        );
        _persistTasks();
        notifyListeners();
      }
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        // Cancellation handled by pause/cancel methods
      } else {
        final errIndex = _tasks.indexWhere((t) => t.id == taskId);
        if (errIndex != -1) {
          _tasks[errIndex] = _tasks[errIndex].copyWith(
            status: DownloadStatus.failed,
            speedBytesPerSec: 0.0,
            errorMessage: e.message ?? 'Network error occurred',
          );
          _persistTasks();
          notifyListeners();
        }
      }
    } catch (e) {
      final errIndex = _tasks.indexWhere((t) => t.id == taskId);
      if (errIndex != -1) {
        _tasks[errIndex] = _tasks[errIndex].copyWith(
          status: DownloadStatus.failed,
          speedBytesPerSec: 0.0,
          errorMessage: e.toString(),
        );
        _persistTasks();
        notifyListeners();
      }
    } finally {
      _activeTokens.remove(taskId);
      _processQueue();
    }
  }

  void _persistTasks() {
    storageService.saveTasks(_tasks);
  }
}

