import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ffmpeg_service.dart';
import 'http_download_service.dart';

/// Represents a stream quality variant parsed from an HLS Master Playlist.
class HlsVariant {
  final String url;
  final int? bandwidth;
  final String? resolution;
  final String? codecs;
  final String? name;

  const HlsVariant({
    required this.url,
    this.bandwidth,
    this.resolution,
    this.codecs,
    this.name,
  });

  @override
  String toString() =>
      'HlsVariant(bandwidth: $bandwidth, resolution: $resolution, codecs: $codecs, url: $url)';
}

/// Callback definition allowing callers or UI to select a desired quality variant.
typedef HlsVariantSelector = HlsVariant Function(List<HlsVariant> variants);

class HlsDownloadService {
  final Dio _dio;
  final FfmpegService _ffmpegService;

  HlsDownloadService({
    Dio? dio,
    required FfmpegService ffmpegService,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(minutes: 60),
              ),
            ),
        _ffmpegService = ffmpegService;

  /// Default quality selector: picks the variant with the highest bandwidth.
  static HlsVariant selectHighestQuality(List<HlsVariant> variants) {
    if (variants.isEmpty) {
      throw ArgumentError('Cannot select quality from an empty variant list');
    }
    return variants.reduce((best, curr) {
      final bestBw = best.bandwidth ?? 0;
      final currBw = curr.bandwidth ?? 0;
      return currBw > bestBw ? curr : best;
    });
  }

  /// Parses an M3U8 string to determine if it is a Master Playlist.
  /// Returns a list of variants if it is, or an empty list if it's a Media Playlist.
  static List<HlsVariant> parseMasterPlaylist(String content, Uri baseUri) {
    final lines = LineSplitter.split(content).map((l) => l.trim()).toList();
    final variants = <HlsVariant>[];

    int? nextBandwidth;
    String? nextResolution;
    String? nextCodecs;
    String? nextName;

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;

      if (line.startsWith('#EXT-X-STREAM-INF:')) {
        final attrs = line.substring('#EXT-X-STREAM-INF:'.length);
        final bwMatch = RegExp(r'BANDWIDTH=(\d+)', caseSensitive: false).firstMatch(attrs);
        if (bwMatch != null) {
          nextBandwidth = int.tryParse(bwMatch.group(1)!);
        }

        final resMatch = RegExp(r'RESOLUTION=(\d+x\d+)', caseSensitive: false).firstMatch(attrs);
        if (resMatch != null) {
          nextResolution = resMatch.group(1);
        }

        final codecsMatch = RegExp(r'CODECS="([^"]+)"', caseSensitive: false).firstMatch(attrs);
        if (codecsMatch != null) {
          nextCodecs = codecsMatch.group(1);
        }

        final nameMatch = RegExp(r'NAME="([^"]+)"', caseSensitive: false).firstMatch(attrs);
        if (nameMatch != null) {
          nextName = nameMatch.group(1);
        }
      } else if (!line.startsWith('#')) {
        if (nextBandwidth != null || nextResolution != null || nextCodecs != null || nextName != null) {
          final resolvedUrl = baseUri.resolve(line).toString();
          variants.add(
            HlsVariant(
              url: resolvedUrl,
              bandwidth: nextBandwidth,
              resolution: nextResolution,
              codecs: nextCodecs,
              name: nextName,
            ),
          );
          nextBandwidth = null;
          nextResolution = null;
          nextCodecs = null;
          nextName = null;
        }
      }
    }

    return variants;
  }

  /// Parses an M3U8 Media Playlist string and returns absolute segment URLs.
  static List<String> parseMediaPlaylist(String content, Uri baseUri) {
    final lines = LineSplitter.split(content).map((l) => l.trim()).toList();
    final segments = <String>[];

    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isEmpty) continue;

      if (line.startsWith('#EXTINF:')) {
        // Look ahead for the URI line
        for (int j = i + 1; j < lines.length; j++) {
          final nextLine = lines[j];
          if (nextLine.isEmpty) continue;
          if (nextLine.startsWith('#')) continue; // skip secondary tags
          final resolvedUri = baseUri.resolve(nextLine).toString();
          segments.add(resolvedUri);
          i = j; // skip forward
          break;
        }
      }
    }

    return segments;
  }

  /// Downloads an HLS stream into [savePath].
  /// Downloads segments concurrently via HTTP, then remuxes locally via FFmpeg.
  Future<bool> downloadHlsStream({
    required String m3u8Url,
    required String savePath,
    required DownloadProgressCallback onProgress,
    String? taskId,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    int concurrency = 5,
    HlsVariantSelector? variantSelector,
    Directory? tempDirectory,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw DioException(
        requestOptions: RequestOptions(path: m3u8Url),
        type: DioExceptionType.cancel,
        error: 'Download cancelled',
      );
    }

    final reqHeaders = <String, dynamic>{};
    if (headers != null) {
      reqHeaders.addAll(headers);
    }

    // 1. Fetch playlist content
    final playlistUri = Uri.parse(m3u8Url);
    final response = await _dio.get<String>(
      m3u8Url,
      options: Options(
        responseType: ResponseType.plain,
        headers: reqHeaders,
      ),
      cancelToken: cancelToken,
    );

    final playlistText = response.data ?? '';
    var targetPlaylistUrl = m3u8Url;
    var targetPlaylistText = playlistText;

    // 2. Handle Master Playlist if present
    final variants = parseMasterPlaylist(playlistText, playlistUri);
    if (variants.isNotEmpty) {
      final selector = variantSelector ?? selectHighestQuality;
      final selectedVariant = selector(variants);
      targetPlaylistUrl = selectedVariant.url;

      final variantResp = await _dio.get<String>(
        targetPlaylistUrl,
        options: Options(
          responseType: ResponseType.plain,
          headers: reqHeaders,
        ),
        cancelToken: cancelToken,
      );
      targetPlaylistText = variantResp.data ?? '';
    }

    // 3. Extract segment URLs
    final segmentUrls = parseMediaPlaylist(
      targetPlaylistText,
      Uri.parse(targetPlaylistUrl),
    );

    if (segmentUrls.isEmpty) {
      throw Exception('No playable segments found in HLS playlist at $m3u8Url');
    }

    // 4. Setup temporary directory for segments
    final idPart = taskId ?? md5.convert(utf8.encode(m3u8Url)).toString();
    final tempDir = tempDirectory ?? await getTemporaryDirectory();
    final hlsDir = Directory(p.join(tempDir.path, 'hls_$idPart'));
    if (!await hlsDir.exists()) {
      await hlsDir.create(recursive: true);
    }

    final totalSegments = segmentUrls.length;
    final segmentFiles = List<File>.generate(
      totalSegments,
      (i) => File(p.join(hlsDir.path, 'seg_${i.toString().padLeft(5, '0')}.ts')),
    );

    // 5. Check already downloaded segments (for instant resume)
    int totalDownloadedBytes = 0;
    final pendingIndices = <int>[];

    for (int i = 0; i < totalSegments; i++) {
      final file = segmentFiles[i];
      if (await file.exists() && (await file.length()) > 0) {
        totalDownloadedBytes += await file.length();
      } else {
        pendingIndices.add(i);
      }
    }

    int lastBytes = totalDownloadedBytes;
    double lastSpeed = 0.0;
    DateTime lastProgressTime = DateTime.now();

    void emitProgress() {
      final now = DateTime.now();
      final elapsedMs = now.difference(lastProgressTime).inMilliseconds;
      if (elapsedMs >= 300) {
        final delta = totalDownloadedBytes - lastBytes;
        if (delta > 0 && elapsedMs > 0) {
          lastSpeed = delta / (elapsedMs / 1000.0);
        }
        lastBytes = totalDownloadedBytes;
        lastProgressTime = now;

        onProgress(
          downloadedBytes: totalDownloadedBytes,
          totalBytes: 0, // Stream has variable segment lengths
          speedBytesPerSec: lastSpeed,
        );
      }
    }

    // Initial progress report
    onProgress(
      downloadedBytes: totalDownloadedBytes,
      totalBytes: 0,
      speedBytesPerSec: 0,
    );

    // 6. Concurrently download pending segments
    if (pendingIndices.isNotEmpty) {
      int nextQueueIdx = 0;
      final workerCount = math.min(concurrency, pendingIndices.length);

      Future<void> worker() async {
        while (true) {
          if (cancelToken?.isCancelled == true) {
            throw DioException(
              requestOptions: RequestOptions(path: m3u8Url),
              type: DioExceptionType.cancel,
              error: 'Download cancelled',
            );
          }

          int segIdx;
          if (nextQueueIdx >= pendingIndices.length) {
            return;
          }
          segIdx = pendingIndices[nextQueueIdx++];

          final segUrl = segmentUrls[segIdx];
          final targetFile = segmentFiles[segIdx];
          final partFile = File('${targetFile.path}.part');

          // Download segment with retry (up to 3 attempts)
          bool success = false;
          Exception? lastEx;
          for (int attempt = 0; attempt < 3; attempt++) {
            if (cancelToken?.isCancelled == true) {
              throw DioException(
                requestOptions: RequestOptions(path: segUrl),
                type: DioExceptionType.cancel,
                error: 'Download cancelled',
              );
            }

            try {
              final segResp = await _dio.get<List<int>>(
                segUrl,
                options: Options(
                  responseType: ResponseType.bytes,
                  headers: reqHeaders,
                ),
                cancelToken: cancelToken,
              );

              final bytes = segResp.data;
              if (bytes != null && bytes.isNotEmpty) {
                await partFile.writeAsBytes(bytes, flush: true);
                if (await targetFile.exists()) {
                  await targetFile.delete();
                }
                await partFile.rename(targetFile.path);

                totalDownloadedBytes += bytes.length;
                emitProgress();
                success = true;
                break;
              }
            } catch (e) {
              lastEx = Exception('Failed to download segment $segIdx ($segUrl): $e');
              if (cancelToken?.isCancelled == true) rethrow;
              await Future.delayed(Duration(milliseconds: 200 * (attempt + 1)));
            }
          }

          if (!success) {
            throw lastEx ?? Exception('Failed to download segment $segIdx after retries');
          }
        }
      }

      await Future.wait(List.generate(workerCount, (_) => worker()));
    }

    if (cancelToken?.isCancelled == true) {
      throw DioException(
        requestOptions: RequestOptions(path: m3u8Url),
        type: DioExceptionType.cancel,
        error: 'Download cancelled',
      );
    }

    // 7. Generate concat_list.txt for local FFmpeg remuxing
    final concatListFile = File(p.join(hlsDir.path, 'concat_list.txt'));
    final concatContent = StringBuffer();
    for (final segFile in segmentFiles) {
      final normalizedPath = segFile.path.replaceAll('\\', '/');
      concatContent.writeln("file '$normalizedPath'");
    }
    await concatListFile.writeAsString(concatContent.toString());

    // 8. Remux locally with FFmpeg
    final remuxSuccess = await _ffmpegService.remuxConcatList(
      concatListPath: concatListFile.path,
      outputPath: savePath,
    );

    if (!remuxSuccess) {
      throw Exception('FFmpeg local remux failed to generate output file.');
    }

    // 9. Clean up temporary segment files
    try {
      if (await hlsDir.exists()) {
        await hlsDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Warning: Failed to delete temporary HLS folder: $e');
    }

    final finalFile = File(savePath);
    final finalLength = await finalFile.exists() ? await finalFile.length() : totalDownloadedBytes;
    onProgress(
      downloadedBytes: finalLength,
      totalBytes: finalLength,
      speedBytesPerSec: 0,
    );

    return true;
  }
}
