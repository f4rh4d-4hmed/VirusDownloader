import 'dart:async';
import 'dart:io';
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

  /// Probes URL headers to retrieve file name and content length without full download
  Future<({String? fileName, int totalBytes})> probeUrl(
    String url, {
    Map<String, String>? headers,
  }) async {
    try {
      final reqHeaders = <String, dynamic>{};
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
      final contentLength = response.headers.value(HttpHeaders.contentLengthHeader);
      if (contentLength != null) {
        totalBytes = int.tryParse(contentLength) ?? 0;
      }

      String? fileName;
      final contentDisposition = response.headers.value('content-disposition');
      if (contentDisposition != null) {
        final match = RegExp(r'''filename\*?=(?:UTF-8'')?["']?([^;"']+)["']?''')
            .firstMatch(contentDisposition);
        if (match != null && match.group(1) != null) {
          fileName = Uri.decodeComponent(match.group(1)!);
        }
      }

      return (fileName: fileName, totalBytes: totalBytes);
    } catch (e) {
      debugPrint('Error probing URL headers: $e');
      return (fileName: null, totalBytes: 0);
    }
  }
}
