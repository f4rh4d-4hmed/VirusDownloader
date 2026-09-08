import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/enums.dart';
import '../../core/utils.dart';
import '../../domain/models/proxy_config.dart';
import 'file_service.dart';
import 'http_download_service.dart';
import 'proxy_service.dart';

class SegmentWorkerState {
  final int index;
  final int startByte;
  final int endByte;
  int downloadedBytes;
  final ProxyConfig? proxy; // null = direct connection

  SegmentWorkerState({
    required this.index,
    required this.startByte,
    required this.endByte,
    this.downloadedBytes = 0,
    this.proxy,
  });

  int get totalSegmentBytes => (endByte - startByte) + 1;
  int get currentOffset => startByte + downloadedBytes;
  bool get isFinished => downloadedBytes >= totalSegmentBytes;

  Map<String, dynamic> toJson() => {
        'index': index,
        'startByte': startByte,
        'endByte': endByte,
        'downloadedBytes': downloadedBytes,
      };

  factory SegmentWorkerState.fromJson(Map<String, dynamic> json) =>
      SegmentWorkerState(
        index: json['index'] as int,
        startByte: json['startByte'] as int,
        endByte: json['endByte'] as int,
        downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      );
}

/// Dynamic proxy pool for Rocket Mode.
/// Dispenses candidate proxies, tracks dead or slow proxies, and rotates dynamically.
class DynamicProxyPool {
  final List<ProxyConfig> _candidates;
  final Set<String> _deadOrSlowProxies = {};
  int _nextIndex = 0;

  DynamicProxyPool(List<ProxyConfig> proxies)
      : _candidates = List.of(proxies) {
    // Sort candidates: proxies with verified positive benchmark speed come first
    _candidates.sort((a, b) {
      final sA = a.lastBenchmarkSpeed ?? 0.0;
      final sB = b.lastBenchmarkSpeed ?? 0.0;
      return sB.compareTo(sA);
    });
  }

  bool get isEmpty => _candidates.isEmpty;
  int get candidateCount => _candidates.length;
  int get deadOrSlowCount => _deadOrSlowProxies.length;

  /// Acquires the next available candidate proxy that has not been marked slow or dead.
  ProxyConfig? acquireNext() {
    while (_nextIndex < _candidates.length) {
      final p = _candidates[_nextIndex++];
      if (!_deadOrSlowProxies.contains(p.originalUrl) &&
          !_deadOrSlowProxies.contains(p.displayUrl)) {
        return p;
      }
    }
    return null;
  }

  /// Marks a proxy as slow, stalled, or dead so it won't be reused.
  void markSlowOrDead(ProxyConfig proxy, {String? reason}) {
    _deadOrSlowProxies.add(proxy.originalUrl);
    _deadOrSlowProxies.add(proxy.displayUrl);
  }
}

class SegmentedDownloadService {
  final ProxyService proxyService;
  final FileService fileService;

  SegmentedDownloadService({
    required this.proxyService,
    required this.fileService,
  });

  /// Download a file using multiple parallel segment workers, with optional
  /// placeholder allocation, Rocket Mode proxy distribution, and speed limiting.
  Future<void> downloadFileSegmented({
    required String url,
    required String savePath,
    required int workerCount,
    required CancelToken cancelToken,
    required DownloadProgressCallback onProgress,
    bool usePlaceholderMode = false,
    SpeedLimitMode speedLimitMode = SpeedLimitMode.unlimited,
    List<ProxyConfig> availableProxies = const [],
    Map<String, String>? headers,
    void Function({required bool isResumable})? onResumableChecked,
    void Function(String message)? onStatusMessage,
  }) async {
    // 1. Probe the remote server to check resumability and total file size
    final probeDio = proxyService.createDioWithProxy(null);
    final probeHeaders = <String, dynamic>{'range': 'bytes=0-0'};
    if (headers != null) probeHeaders.addAll(headers);

    Response probeResp;
    try {
      probeResp = await probeDio.head(
        url,
        options: Options(
          headers: probeHeaders,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
        cancelToken: cancelToken,
      );
    } catch (e) {
      // If HEAD fails, attempt GET 0-0
      probeResp = await probeDio.get(
        url,
        options: Options(
          headers: probeHeaders,
          validateStatus: (s) => s != null && s >= 200 && s < 400,
        ),
        cancelToken: cancelToken,
      );
    }

    final acceptRanges = probeResp.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase();
    final contentRange = probeResp.headers.value(HttpHeaders.contentRangeHeader);
    int totalBytes = 0;

    if (contentRange != null) {
      final match = RegExp(r'/(\d+)').firstMatch(contentRange);
      if (match != null) {
        totalBytes = int.tryParse(match.group(1) ?? '') ?? 0;
      }
    } else {
      final cl = probeResp.headers.value(HttpHeaders.contentLengthHeader);
      if (cl != null) totalBytes = int.tryParse(cl) ?? 0;
    }

    final isResumable = probeResp.statusCode == 206 ||
        acceptRanges == 'bytes' ||
        contentRange != null;

    onResumableChecked?.call(isResumable: isResumable);

    // If server does not support byte ranges or size is unknown, fallback to single stream
    if (!isResumable || totalBytes <= 0 || (workerCount <= 1 && speedLimitMode != SpeedLimitMode.rocket)) {
      final singleService = HttpDownloadService();
      await singleService.downloadFile(
        url: url,
        savePath: savePath,
        cancelToken: cancelToken,
        onProgress: onProgress,
        allowResume: isResumable,
        headers: headers,
        onResumableChecked: onResumableChecked,
      );
      return;
    }

    // 2. Storage Strategy for Android
    // On Android, if placeholder mode is enabled, use private storage if file fits,
    // otherwise fallback to direct-write to public storage.
    String activeFilePath = savePath;
    bool usingPrivateTemp = false;

    if (AppUtils.isMobile && Platform.isAndroid && usePlaceholderMode) {
      try {
        final tempDir = await getApplicationSupportDirectory();
        final fileName = savePath.split(Platform.pathSeparator).last;
        final privatePath = '${tempDir.path}${Platform.pathSeparator}$fileName';

        // Check if private storage can hold file
        activeFilePath = privatePath;
        usingPrivateTemp = true;
      } catch (_) {
        activeFilePath = savePath;
        usingPrivateTemp = false;
      }
    }

    // 3. Worker Distribution & Dynamic Proxy Pool for Rocket Mode
    final clampedWorkers = (speedLimitMode == SpeedLimitMode.rocket && availableProxies.isNotEmpty)
        ? math.max(4, workerCount).clamp(1, 16)
        : workerCount.clamp(1, 16);
    final workerList = <SegmentWorkerState>[];
    final proxyPool = DynamicProxyPool(availableProxies);

    if (speedLimitMode == SpeedLimitMode.rocket && availableProxies.isNotEmpty) {
      onStatusMessage?.call(
        'Rocket mode: Active with ${availableProxies.length} proxies (in-flight testing & auto-handover enabled).',
      );
    }

    // Check for existing metadata (resuming segmented download)
    final metaFile = File('$activeFilePath.vdown_meta');
    bool metaRestored = false;

    if (await metaFile.exists()) {
      try {
        final metaContent = await metaFile.readAsString();
        final List<dynamic> jsonList = jsonDecode(metaContent);
        final restored = jsonList
            .whereType<Map<String, dynamic>>()
            .map(SegmentWorkerState.fromJson)
            .toList();

        if (restored.length == clampedWorkers &&
            restored.last.endByte == totalBytes - 1) {
          workerList.addAll(restored);
          metaRestored = true;
        }
      } catch (e) {
        debugPrint('Error restoring segment metadata: $e');
      }
    }

    if (!metaRestored) {
      workerList.clear();
      final blockSize = (totalBytes / clampedWorkers).ceil();
      for (int i = 0; i < clampedWorkers; i++) {
        final start = i * blockSize;
        final end = math.min((i + 1) * blockSize - 1, totalBytes - 1);
        if (start > totalBytes - 1) break;

        ProxyConfig? assignedProxy;
        if (speedLimitMode == SpeedLimitMode.rocket && availableProxies.isNotEmpty) {
          // Worker 0 is always direct connection for maximum stability and baseline throughput.
          // Remaining workers acquire candidate proxies from the pool.
          if (i >= 1) {
            assignedProxy = proxyPool.acquireNext();
          }
        }

        workerList.add(
          SegmentWorkerState(
            index: i,
            startByte: start,
            endByte: end,
            downloadedBytes: 0,
            proxy: assignedProxy,
          ),
        );
      }
    }

    // 4. File Initialization / Placeholder Mode
    final targetFile = File(activeFilePath);
    if (!await targetFile.exists() || !metaRestored) {
      final parentDir = targetFile.parent;
      if (!await parentDir.exists()) {
        await parentDir.create(recursive: true);
      }

      if (usePlaceholderMode) {
        onStatusMessage?.call('Pre-allocating placeholder file...');
        final raf = await targetFile.open(mode: FileMode.write);
        try {
          await raf.truncate(totalBytes);
        } catch (_) {
          // If fast truncate fails, write initial zero
          await raf.writeByte(0);
        } finally {
          await raf.close();
        }
      } else {
        await targetFile.create(recursive: true);
      }
    }

    // Persist initial metadata
    await _saveMeta(metaFile, workerList);

    // 5. Execution: Stream chunks and write concurrently
    final raf = await targetFile.open(mode: FileMode.append);
    int totalDownloaded = workerList.fold(0, (sum, w) => sum + w.downloadedBytes);

    int lastSampleBytes = totalDownloaded;
    DateTime lastSampleTime = DateTime.now();
    double currentSpeed = 0.0;
    final maxSpeed = speedLimitMode.maxBytesPerSecond;

    // Mutex write queue for safe sequential writes to file
    Future<void> writeQueue = Future.value();
    Future<void> writeChunk(int writeOffset, List<int> chunk) {
      final completer = Completer<void>();
      writeQueue = writeQueue.then((_) async {
        try {
          await raf.setPosition(writeOffset);
          await raf.writeFrom(chunk);
          completer.complete();
        } catch (e, st) {
          completer.completeError(e, st);
        }
      });
      return completer.future;
    }

    // Launch all workers
    final workerFutures = <Future<void>>[];

    for (final worker in workerList) {
      if (worker.isFinished) continue;

      workerFutures.add(() async {
        ProxyConfig? currentProxy = worker.proxy;
        if (currentProxy == null &&
            speedLimitMode == SpeedLimitMode.rocket &&
            availableProxies.isNotEmpty &&
            worker.index >= 1) {
          currentProxy = proxyPool.acquireNext();
        }

        int directRetries = 0;

        while (worker.currentOffset <= worker.endByte && !cancelToken.isCancelled) {
          final startRange = worker.currentOffset;
          final endRange = worker.endByte;
          if (startRange > endRange) break;

          final reqHeaders = <String, dynamic>{
            'range': 'bytes=$startRange-$endRange',
          };
          if (headers != null) reqHeaders.addAll(headers);

          final dio = proxyService.createDioWithProxy(
            currentProxy,
            baseOptions: BaseOptions(
              connectTimeout: currentProxy != null
                  ? const Duration(seconds: 5)
                  : const Duration(seconds: 15),
              receiveTimeout: currentProxy != null
                  ? const Duration(seconds: 12)
                  : const Duration(seconds: 30),
            ),
          );

          final requestCancelToken = CancelToken();
          void onParentCancel() {
            if (!requestCancelToken.isCancelled) {
              requestCancelToken.cancel('Parent cancelled');
            }
          }

          cancelToken.whenCancel.then((_) => onParentCancel());

          bool shouldRotateProxy = false;
          String? failureReason;
          final sessionWatch = Stopwatch()..start();
          int bytesInSession = 0;

          try {
            final resp = await dio.get<ResponseBody>(
              url,
              options: Options(
                responseType: ResponseType.stream,
                headers: reqHeaders,
                validateStatus: (s) => s != null && s >= 200 && s < 400,
              ),
              cancelToken: requestCancelToken,
            );

            final stream = resp.data?.stream;
            if (stream == null) {
              throw Exception('Empty response stream');
            }

            final stallTimeout = currentProxy != null
                ? const Duration(seconds: 6)
                : const Duration(seconds: 15);

            await for (final chunk in stream.timeout(stallTimeout)) {
              if (cancelToken.isCancelled) break;

              final offset = worker.currentOffset;
              await writeChunk(offset, chunk);

              worker.downloadedBytes += chunk.length;
              totalDownloaded += chunk.length;
              bytesInSession += chunk.length;

              // Slowness check for proxy workers in Rocket mode:
              // After warmup (>= 2.5s elapsed and at least 64KB transferred)
              if (currentProxy != null && speedLimitMode == SpeedLimitMode.rocket) {
                final elapsedSec = sessionWatch.elapsedMilliseconds / 1000.0;
                if (elapsedSec >= 2.5 && bytesInSession >= 64 * 1024) {
                  final proxySpeed = bytesInSession / elapsedSec;
                  // If proxy is slower than 80 KB/s, terminate it so next proxy takes over
                  if (proxySpeed < 80 * 1024) {
                    failureReason = 'Speed too slow (${AppUtils.formatSpeed(proxySpeed)})';
                    shouldRotateProxy = true;
                    requestCancelToken.cancel(failureReason);
                    break;
                  }
                }
              }

              // Speed Limiter throttle check
              if (maxSpeed > 0 && currentSpeed > maxSpeed) {
                final overRatio = (currentSpeed - maxSpeed) / maxSpeed;
                final pauseMs = (overRatio * 50).clamp(10, 100).toInt();
                await Future.delayed(Duration(milliseconds: pauseMs));
              }

              // Throttle UI update every ~350ms
              final now = DateTime.now();
              final elapsed = now.difference(lastSampleTime).inMilliseconds;
              if (elapsed >= 350) {
                final delta = totalDownloaded - lastSampleBytes;
                currentSpeed = (delta / elapsed) * 1000.0;
                lastSampleBytes = totalDownloaded;
                lastSampleTime = now;

                onProgress(
                  downloadedBytes: totalDownloaded,
                  totalBytes: totalBytes,
                  speedBytesPerSec: currentSpeed,
                );
              }
            }

            directRetries = 0;
          } catch (e) {
            if (cancelToken.isCancelled) break;
            shouldRotateProxy = true;
            failureReason = e is TimeoutException
                ? 'Proxy stalled (no data for 6s)'
                : (failureReason ?? e.toString());
          }

          if (cancelToken.isCancelled) break;

          if (shouldRotateProxy && currentProxy != null) {
            proxyPool.markSlowOrDead(currentProxy, reason: failureReason);
            final oldProxyUrl = currentProxy.displayUrl;
            final nextProxy = proxyPool.acquireNext();
            currentProxy = nextProxy;

            if (nextProxy != null) {
              onStatusMessage?.call(
                'Worker ${worker.index + 1}: Proxy $oldProxyUrl slow/died ($failureReason). Rotating to ${nextProxy.displayUrl}...',
              );
            } else {
              onStatusMessage?.call(
                'Worker ${worker.index + 1}: Proxy pool exhausted. Resuming remainder with direct connection...',
              );
            }
            await Future.delayed(const Duration(milliseconds: 100));
          } else if (shouldRotateProxy && currentProxy == null) {
            // Direct connection had an issue
            directRetries++;
            if (directRetries > 4) {
              throw Exception('Direct worker connection failed after multiple retries: $failureReason');
            }
            await Future.delayed(Duration(milliseconds: 300 * directRetries));
          }
        }
      }());
    }

    try {
      await Future.wait(workerFutures);
    } finally {
      await raf.flush();
      await raf.close();
      await _saveMeta(metaFile, workerList);
    }

    // 6. Post-Download Cleanup & Storage Finalization
    if (totalDownloaded >= totalBytes && !cancelToken.isCancelled) {
      // Remove metadata file
      try {
        if (await metaFile.exists()) {
          await metaFile.delete();
        }
      } catch (_) {}

      // If downloaded to private temp on Android, move to final designated folder
      if (usingPrivateTemp && activeFilePath != savePath) {
        onStatusMessage?.call('Moving file to destination...');
        final tempF = File(activeFilePath);
        final destF = File(savePath);
        final destDir = destF.parent;
        if (!await destDir.exists()) {
          await destDir.create(recursive: true);
        }
        await tempF.copy(savePath);
        await tempF.delete();
      }

      onProgress(
        downloadedBytes: totalBytes,
        totalBytes: totalBytes,
        speedBytesPerSec: 0.0,
      );
    }
  }

  Future<void> _saveMeta(File metaFile, List<SegmentWorkerState> workers) async {
    try {
      final jsonStr = jsonEncode(workers.map((w) => w.toJson()).toList());
      await metaFile.writeAsString(jsonStr, flush: true);
    } catch (_) {}
  }
}

