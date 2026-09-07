import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

typedef DownloadProgressCallback = void Function({
  required int downloadedBytes,
  required int totalBytes,
  required double speedBytesPerSec,
});

class HttpDownloadService {
  final Dio _dio;

  HttpDownloadService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(minutes: 60),
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36',
                },
              ),
            );

  /// Performs a robust file download with resume support and live speed tracking
  Future<void> downloadFile({
    required String url,
    required String savePath,
    required CancelToken cancelToken,
    required DownloadProgressCallback onProgress,
    bool allowResume = true,
    Map<String, String>? headers,
    void Function({required bool isResumable})? onResumableChecked,
  }) async {
    final file = File(savePath);
    int existingBytes = 0;

    if (allowResume && await file.exists()) {
      existingBytes = await file.length();
    }

    final requestHeaders = <String, dynamic>{};
    if (headers != null) {
      requestHeaders.addAll(headers);
    }
    if (existingBytes > 0) {
      requestHeaders['range'] = 'bytes=$existingBytes-';
    }

    Response<ResponseBody> response;
    try {
      response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          headers: requestHeaders,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
        cancelToken: cancelToken,
      );
    } on DioException catch (e) {
      // If 416 Range Not Satisfiable, file might already be complete
      if (e.response?.statusCode == 416) {
        onProgress(
          downloadedBytes: existingBytes,
          totalBytes: existingBytes,
          speedBytesPerSec: 0.0,
        );
        return;
      }
      rethrow;
    }

    final statusCode = response.statusCode ?? 200;
    final isResumed = statusCode == 206;

    // Detect if the server actually supports resuming
    final acceptRanges = response.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase();
    final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);

    bool isResumable = true;
    if (acceptRanges == 'none') {
      isResumable = false;
    } else if (existingBytes > 0 && !isResumed) {
      // Server ignored Range header and served the full body from 0
      isResumable = false;
    } else if (isResumed || acceptRanges == 'bytes' || contentRange != null) {
      isResumable = true;
    }
    onResumableChecked?.call(isResumable: isResumable);

    // Calculate total content length
    int totalBytes = 0;
    final contentLengthHeader = response.headers.value(HttpHeaders.contentLengthHeader);
    if (contentLengthHeader != null) {
      final parsedLength = int.tryParse(contentLengthHeader) ?? 0;
      totalBytes = isResumed ? (existingBytes + parsedLength) : parsedLength;
    }

    // Determine write mode: append if 206 resumed, otherwise start fresh
    final fileMode = isResumed ? FileMode.append : FileMode.write;
    if (!isResumed && existingBytes > 0) {
      existingBytes = 0;
    }

    final sink = file.openWrite(mode: fileMode);

    int currentBytes = existingBytes;
    int lastSampleBytes = currentBytes;
    DateTime lastSampleTime = DateTime.now();
    double currentSpeed = 0.0;

    try {
      final stream = response.data!.stream;

      await for (final chunk in stream) {
        if (cancelToken.isCancelled) {
          break;
        }

        sink.add(chunk);
        currentBytes += chunk.length;

        final now = DateTime.now();
        final elapsedMs = now.difference(lastSampleTime).inMilliseconds;

        // Update speed calculation every ~400ms to keep UI responsive and smooth
        if (elapsedMs >= 400) {
          final bytesDelta = currentBytes - lastSampleBytes;
          currentSpeed = (bytesDelta / elapsedMs) * 1000.0;
          lastSampleBytes = currentBytes;
          lastSampleTime = now;

          onProgress(
            downloadedBytes: currentBytes,
            totalBytes: totalBytes,
            speedBytesPerSec: currentSpeed,
          );
        }
      }

      await sink.flush();
      await sink.close();

      // Final progress notification
      onProgress(
        downloadedBytes: currentBytes,
        totalBytes: totalBytes > 0 ? totalBytes : currentBytes,
        speedBytesPerSec: 0.0,
      );
    } catch (e) {
      await sink.close();
      rethrow;
    }
  }

  /// Probes URL headers to retrieve file name, content length, and resumability without full download
  Future<({String? fileName, int totalBytes, bool isResumable})> probeUrl(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final reqHeaders = <String, dynamic>{
        'range': 'bytes=0-0',
      };
      if (headers != null) {
        reqHeaders.addAll(headers);
      }
      final response = await _dio.head(
        url,
        options: Options(
          headers: reqHeaders,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
      );

      int totalBytes = 0;
      final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
      final contentLength = response.headers.value(HttpHeaders.contentLengthHeader);
      final acceptRanges = response.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase();

      if (contentRange != null) {
        final match = RegExp(r'/(\d+)').firstMatch(contentRange);
        if (match != null) {
          totalBytes = int.tryParse(match.group(1) ?? '') ?? 0;
        }
      } else if (contentLength != null) {
        totalBytes = int.tryParse(contentLength) ?? 0;
      }

      final isResumable = response.statusCode == 206 ||
          acceptRanges == 'bytes' ||
          contentRange != null ||
          (acceptRanges != 'none' && totalBytes > 0);

      String? fileName;
      final contentDisposition = response.headers.value('content-disposition');
      if (contentDisposition != null) {
        final match = RegExp(r'''filename\*?=(?:UTF-8'')?["']?([^;"']+)["']?''')
            .firstMatch(contentDisposition);
        if (match != null && match.group(1) != null) {
          fileName = Uri.decodeComponent(match.group(1)!);
        }
      }

      return (fileName: fileName, totalBytes: totalBytes, isResumable: isResumable);
    } catch (e) {
      debugPrint('Error probing URL headers: $e');
      return (fileName: null, totalBytes: 0, isResumable: true);
    }
  }

  /// Verifies whether a new URL points to the same file as an existing partial file
  /// by downloading a sample (up to 1 MB) and comparing it byte-by-byte with the local file on disk.
  Future<({bool matches, String? reason, int? newTotalBytes})> verifySameFile({
    required String newUrl,
    required String savePath,
    int? expectedTotalBytes,
    Map<String, String>? headers,
    int sampleSizeBytes = 1024 * 1024,
  }) async {
    final file = File(savePath);
    bool exists = false;
    try {
      exists = file.existsSync();
    } catch (_) {}
    if (!exists) {
      return (matches: true, reason: null, newTotalBytes: null);
    }

    final localLength = await file.length();
    if (localLength == 0) {
      return (matches: true, reason: null, newTotalBytes: null);
    }

    final bytesToSample = math.min(localLength, sampleSizeBytes);
    final requestHeaders = <String, dynamic>{
      'range': 'bytes=0-${bytesToSample - 1}',
    };
    if (headers != null) {
      requestHeaders.addAll(headers);
    }

    try {
      final response = await _dio.get<List<int>>(
        newUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: requestHeaders,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
      );

      final statusCode = response.statusCode ?? 200;
      if (statusCode != 206) {
        return (
          matches: false,
          reason: 'The new server returned status $statusCode instead of 206 Partial Content (it may not support resuming).',
          newTotalBytes: null,
        );
      }

      final remoteBytes = response.data;
      if (remoteBytes == null || remoteBytes.length != bytesToSample) {
        return (
          matches: false,
          reason: 'Expected $bytesToSample bytes in sample, but received ${remoteBytes?.length ?? 0} bytes.',
          newTotalBytes: null,
        );
      }

      // Read local bytes to compare
      final raf = await file.open(mode: FileMode.read);
      List<int> localBytes;
      try {
        localBytes = await raf.read(bytesToSample);
      } finally {
        await raf.close();
      }

      if (!listEquals(localBytes, remoteBytes)) {
        return (
          matches: false,
          reason: 'The first sample of data does not match the existing downloaded file.',
          newTotalBytes: null,
        );
      }

      // Check total size if content-range is present
      int? newTotal;
      final contentRange = response.headers.value(HttpHeaders.contentRangeHeader);
      if (contentRange != null) {
        final match = RegExp(r'/(\d+)').firstMatch(contentRange);
        if (match != null) {
          newTotal = int.tryParse(match.group(1) ?? '');
        }
      }

      if (expectedTotalBytes != null && expectedTotalBytes > 0 && newTotal != null && newTotal > 0) {
        if (expectedTotalBytes != newTotal) {
          return (
            matches: false,
            reason: 'File size mismatch: original file was $expectedTotalBytes bytes, but the new link is $newTotal bytes.',
            newTotalBytes: newTotal,
          );
        }
      }

      return (matches: true, reason: null, newTotalBytes: newTotal);
    } on DioException catch (e) {
      return (
        matches: false,
        reason: e.message ?? 'Network error while verifying new link: $e',
        newTotalBytes: null,
      );
    } catch (e) {
      return (
        matches: false,
        reason: 'Error verifying link: $e',
        newTotalBytes: null,
      );
    }
  }
}
