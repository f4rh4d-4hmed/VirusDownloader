import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../core/enums.dart';
import '../../core/utils.dart';
import '../../domain/models/download_task.dart';
import '../services/ffmpeg_service.dart';
import '../services/file_service.dart';
import '../services/http_download_service.dart';
import '../services/integrity_service.dart';
import '../services/notification_service.dart';
import '../services/segmented_download_service.dart';
import '../services/storage_service.dart';
import 'settings_repository.dart';

class DownloadRepository extends ChangeNotifier {
  final HttpDownloadService httpService;
  final SegmentedDownloadService? segmentedService;
  final StorageService storageService;
  final FileService fileService;
  final SettingsRepository settingsRepo;
  final FfmpegService? ffmpegService;
  final NotificationService? notificationService;
  final IntegrityService? integrityService;

  List<DownloadTask> _tasks = [];
  final Map<String, CancelToken> _activeTokens = {};
  final Uuid _uuid = const Uuid();

  DownloadRepository({
    required this.httpService,
    this.segmentedService,
    required this.storageService,
    required this.fileService,
    required this.settingsRepo,
    this.ffmpegService,
    this.notificationService,
    this.integrityService,
  }) {
    NotificationService.onActionReceived = _handleNotificationAction;
  }

  void _handleNotificationAction(String action, String taskId) {
    switch (action) {
      case 'PAUSE':
        pauseDownload(taskId);
        break;
      case 'RESUME':
        resumeDownload(taskId);
        break;
      case 'CANCEL':
        cancelDownload(taskId);
        break;
      case 'RETRY':
        retryDownload(taskId);
        break;
      case 'OPEN_FILE':
        final task = _tasks.where((t) => t.id == taskId).firstOrNull;
        if (task != null && task.status == DownloadStatus.completed) {
          fileService.openFile(task.savePath);
        }
        break;
    }
  }

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
    bool? isResumable,
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
      isResumable: isStream ? false : (isResumable ?? true),
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

    final task = _tasks[index];
    if (task.status != DownloadStatus.downloading &&
        task.status != DownloadStatus.queued) {
      return;
    }

    final token = _activeTokens[id];
    if (token != null && !token.isCancelled) {
      token.cancel('User paused download');
      _activeTokens.remove(id);
    }

    _tasks[index] = task.copyWith(
      status: DownloadStatus.paused,
      speedBytesPerSec: 0.0,
    );

    notificationService?.showDownloadPaused(
      taskId: task.id,
      fileName: task.fileName,
      progress: task.progress,
    );

    _persistTasks();
    notifyListeners();
    _processQueue();
  }

  /// Resumes a paused or failed download
  Future<void> resumeDownload(String id) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = _tasks[index];
    if (task.status != DownloadStatus.paused &&
        task.status != DownloadStatus.failed &&
        task.status != DownloadStatus.cancelled) {
      return;
    }

    _tasks[index] = task.copyWith(
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
    if (task.status == DownloadStatus.completed ||
        task.status == DownloadStatus.cancelled) {
      return;
    }

    final token = _activeTokens[id];
    if (token != null && !token.isCancelled) {
      token.cancel('User cancelled download');
      _activeTokens.remove(id);
    }

    // Properly clean up all temp files, metadata, and partial file failsafe
    await fileService.cleanupTaskFiles(
      taskId: task.id,
      fileName: task.fileName,
      savePath: task.savePath,
      deleteTargetFile: true,
    );
    notificationService?.cancelNotification(task.id);

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

    final task = _tasks[index];
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.queued) {
      return;
    }

    _tasks[index] = task.copyWith(
      status: DownloadStatus.queued,
      speedBytesPerSec: 0.0,
      clearError: true,
    );

    _persistTasks();
    notifyListeners();
    _processQueue();
  }

  /// Changes the download link for an active resumable download task
  Future<void> changeDownloadUrl(
    String id,
    String newUrl, {
    Map<String, String>? headers,
    bool restartFromBeginning = false,
  }) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) return;

    final task = _tasks[index];
    if (task.status == DownloadStatus.completed) {
      return;
    }
    if (!task.isResumable && !restartFromBeginning) {
      throw StateError('Cannot change download link for an unresumable download.');
    }

    final wasDownloading = task.status == DownloadStatus.downloading;
    if (wasDownloading) {
      final token = _activeTokens[id];
      if (token != null && !token.isCancelled) {
        token.cancel('Download link changed');
        _activeTokens.remove(id);
      }
    }

    if (restartFromBeginning) {
      await fileService.cleanupTaskFiles(
        taskId: task.id,
        fileName: task.fileName,
        savePath: task.savePath,
        deleteTargetFile: true,
      );
    }

    _tasks[index] = task.copyWith(
      url: newUrl.trim(),
      headers: headers ?? task.headers,
      downloadedBytes: restartFromBeginning ? 0 : task.downloadedBytes,
      speedBytesPerSec: 0.0,
      clearError: true,
      status: wasDownloading ? DownloadStatus.queued : task.status,
    );

    _persistTasks();
    notifyListeners();

    if (wasDownloading) {
      _processQueue();
    }
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

    notificationService?.cancelNotification(task.id);

    // Failsafe cleanup of this task's individual temp file & meta (and target file if requested).
    // Never deletes the shared temp directory so other active downloads are unaffected.
    await fileService.cleanupTaskFiles(
      taskId: task.id,
      fileName: task.fileName,
      savePath: task.savePath,
      deleteTargetFile: deleteFileOnDisk,
    );

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

  /// Calculates file hash for a completed download
  Future<String> calculateFileHash(
    String id,
    HashAlgorithm algorithm, {
    void Function(double progress)? onProgress,
  }) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) throw StateError('Task not found');
    final task = _tasks[index];

    final service = integrityService ?? IntegrityService();
    final hash = await service.calculateFileHash(
      task.savePath,
      algorithm,
      onProgress: onProgress,
    );

    _tasks[index] = task.copyWith(
      fileHash: hash,
      hashAlgorithm: algorithm,
    );
    _persistTasks();
    notifyListeners();
    return hash;
  }

  /// Performs torrent-style recheck against the remote server
  Future<RecheckResult> recheckTask(
    String id, {
    void Function(double progress, String status)? onProgress,
  }) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) throw StateError('Task not found');
    final task = _tasks[index];

    final service = integrityService ?? IntegrityService();
    final dio = Dio();
    return await service.recheckFile(
      url: task.url,
      localFilePath: task.savePath,
      dio: dio,
      headers: task.headers,
      onProgress: onProgress,
    );
  }

  /// Scans file for zero-filled piece gaps and patches them in-place
  Future<RepairResult> scanAndRepairZeroGaps(
    String id, {
    int pieceSize = 8 * 1024 * 1024,
    void Function(double progress, String status)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) throw StateError('Task not found');
    final task = _tasks[index];

    final service = integrityService ?? IntegrityService();
    final dio = Dio();
    return await service.scanAndRepairZeroGaps(
      url: task.url,
      localFilePath: task.savePath,
      dio: dio,
      pieceSize: pieceSize,
      headers: task.headers,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
  }

  /// Scans for missing zero pieces without downloading
  Future<List<ZeroPiece>> findZeroPieces(
    String id, {
    int pieceSize = 8 * 1024 * 1024,
    void Function(double progress, String status)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final index = _tasks.indexWhere((t) => t.id == id);
    if (index == -1) throw StateError('Task not found');
    final task = _tasks[index];

    final service = integrityService ?? IntegrityService();
    return await service.findZeroPieces(
      task.savePath,
      pieceSize: pieceSize,
      onProgress: onProgress,
      cancelToken: cancelToken,
    );
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

    final settings = settingsRepo.currentSettings;
    final isStream = task.url.toLowerCase().contains('.m3u8') ||
        task.fileName.toLowerCase().endsWith('.m3u8') ||
        (task.savePath.toLowerCase().endsWith('.mkv') && task.url.toLowerCase().contains('.m3u8'));

    final tempFilePath = await fileService.getTaskTempFilePath(taskId, task.fileName);

    try {
      if (isStream && ffmpegService != null) {
        await ffmpegService!.downloadHlsStream(
          m3u8Url: task.url,
          savePath: tempFilePath,
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

            notificationService?.showDownloadProgress(
              taskId: taskId,
              fileName: task.fileName,
              progress: _tasks[idx].progress,
              speedBytesPerSec: speedBytesPerSec,
            );
          },
        );
        if (!cancelToken.isCancelled) {
          final moved = await fileService.moveFile(tempFilePath, task.savePath);
          if (!moved) {
            throw FileSystemException('Failed to move completed file to destination', task.savePath);
          }
          await fileService.deleteFile('$tempFilePath.vdown_meta');
        }
      } else if (segmentedService != null &&
          (settings.defaultWorkerCount > 1 ||
              settings.usePlaceholderMode ||
              settings.speedLimitMode == SpeedLimitMode.rocket)) {
        await segmentedService!.downloadFileSegmented(
          url: task.url,
          savePath: task.savePath,
          tempPath: tempFilePath,
          workerCount: settings.defaultWorkerCount,
          cancelToken: cancelToken,
          usePlaceholderMode: settings.usePlaceholderMode,
          speedLimitMode: settings.speedLimitMode,
          availableProxies: settings.proxyServers,
          headers: task.headers,
          onStatusMessage: (message) {
            debugPrint('[Download $taskId] $message');
          },
          onResumableChecked: ({required bool isResumable}) {
            final idx = _tasks.indexWhere((t) => t.id == taskId);
            if (idx != -1 && _tasks[idx].isResumable != isResumable) {
              _tasks[idx] = _tasks[idx].copyWith(isResumable: isResumable);
              _persistTasks();
              notifyListeners();
            }
          },
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

            notificationService?.showDownloadProgress(
              taskId: taskId,
              fileName: task.fileName,
              progress: _tasks[idx].progress,
              speedBytesPerSec: speedBytesPerSec,
            );
          },
        );
      } else {
        if (!await fileService.fileExists(tempFilePath) && await fileService.fileExists(task.savePath)) {
          await fileService.moveFile(task.savePath, tempFilePath);
        }
        await httpService.downloadFile(
          url: task.url,
          savePath: tempFilePath,
          cancelToken: cancelToken,
          headers: task.headers,
          onResumableChecked: ({required bool isResumable}) {
            final idx = _tasks.indexWhere((t) => t.id == taskId);
            if (idx != -1 && _tasks[idx].isResumable != isResumable) {
              _tasks[idx] = _tasks[idx].copyWith(isResumable: isResumable);
              _persistTasks();
              notifyListeners();
            }
          },
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

            notificationService?.showDownloadProgress(
              taskId: taskId,
              fileName: task.fileName,
              progress: _tasks[idx].progress,
              speedBytesPerSec: speedBytesPerSec,
            );
          },
        );
        if (!cancelToken.isCancelled) {
          final moved = await fileService.moveFile(tempFilePath, task.savePath);
          if (!moved) {
            throw FileSystemException('Failed to move completed file to destination', task.savePath);
          }
        }
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

        notificationService?.showDownloadComplete(
          taskId: taskId,
          fileName: current.fileName,
          savePath: current.savePath,
        );

        if (settings.autoRecheckOnComplete && current.isResumable) {
          recheckTask(taskId);
        }
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

          notificationService?.showDownloadFailed(
            taskId: taskId,
            fileName: task.fileName,
            error: e.message ?? 'Network error',
          );
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

        notificationService?.showDownloadFailed(
          taskId: taskId,
          fileName: task.fileName,
          error: e.toString(),
        );
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
