import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'adaptive_rate_limiter.dart';
import 'hls_download_service.dart';
import 'http_download_service.dart';

class FfmpegService {
  String? _cachedPath;
  final Map<String, String> _thumbnailCache = {};
  final Map<String, Future<String?>> _inProgressThumbnailGenerations = {};

  /// Synchronously returns cached thumbnail path if available in memory
  String? getCachedThumbnail(String mediaPath) => _thumbnailCache[mediaPath];

  @visibleForTesting
  void setMockThumbnail(String mediaPath, String thumbnailPath) {
    _thumbnailCache[mediaPath] = thumbnailPath;
  }

  @visibleForTesting
  void clearCache() {
    _cachedPath = null;
    _thumbnailCache.clear();
    _inProgressThumbnailGenerations.clear();
  }

  /// Returns 'bundled' if FFmpeg is available via native plugin, or null
  Future<String?> getFfmpegPath() async {
    return _cachedPath ?? 'bundled';
  }

  @visibleForTesting
  void setMockPath(String? path) {
    _cachedPath = path;
  }

  Future<bool> isAvailable() async {
    return true;
  }

  /// Legacy helper kept for backwards compatibility. Bundled via ffmpeg_kit_flutter_new_min.
  Future<String?> downloadLightweightFfmpeg({
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    if (onProgress != null) {
      onProgress(100, 100);
    }
    return 'bundled';
  }

  /// Remuxes a list of local segment files (from concat_list.txt) into a single container
  Future<bool> remuxConcatList({
    required String concatListPath,
    required String outputPath,
  }) async {
    final args = <String>[
      '-y',
      '-f',
      'concat',
      '-safe',
      '0',
      '-i',
      concatListPath,
      '-c',
      'copy',
      '-bsf:a',
      'aac_adtstoasc',
      outputPath,
    ];

    final session = await FFmpegKit.executeWithArguments(args);
    final returnCode = await session.getReturnCode();
    return ReturnCode.isSuccess(returnCode);
  }

  /// Downloads an HLS stream via HlsDownloadService (concurrent HTTP segments + local remux)
  Future<bool> downloadHlsStream({
    required String m3u8Url,
    required String savePath,
    required DownloadProgressCallback onProgress,
    String? taskId,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    void Function(Process process)? onProcessStarted,
    HlsVariantSelector? variantSelector,
    Dio? dio,
    AdaptiveRateLimiter? rateLimiter,
  }) async {
    final hlsService = HlsDownloadService(
      dio: dio,
      ffmpegService: this,
      rateLimiter: rateLimiter,
    );
    return await hlsService.downloadHlsStream(
      m3u8Url: m3u8Url,
      savePath: savePath,
      onProgress: onProgress,
      taskId: taskId,
      headers: headers,
      cancelToken: cancelToken,
      variantSelector: variantSelector,
      rateLimiter: rateLimiter,
    );
  }

  /// Remuxes any media file (or .ts segments) into an MKV container with subtitles
  Future<bool> remuxToMkv({
    required String inputPath,
    required String outputPath,
    String? subtitlePath,
  }) async {
    final args = <String>['-y', '-i', inputPath];
    if (subtitlePath != null && await File(subtitlePath).exists()) {
      args.addAll(['-i', subtitlePath, '-map', '0:v?', '-map', '0:a?', '-map', '1:s?', '-c', 'copy']);
    } else {
      args.addAll(['-map', '0:v?', '-map', '0:a?', '-map', '0:s?', '-c', 'copy']);
    }
    args.add(outputPath);

    final session = await FFmpegKit.executeWithArguments(args);
    final returnCode = await session.getReturnCode();
    return ReturnCode.isSuccess(returnCode);
  }

  /// Generates or retrieves a snapshot thumbnail image from a video or audio file.
  /// Returns the path to the cached thumbnail JPEG, or null if generation fails or no visual stream exists.
  Future<String?> generateThumbnail(String mediaPath) async {
    if (_thumbnailCache.containsKey(mediaPath)) {
      final cached = _thumbnailCache[mediaPath];
      if (cached != null && File(cached).existsSync()) {
        return cached;
      }
      _thumbnailCache.remove(mediaPath);
    }

    if (_inProgressThumbnailGenerations.containsKey(mediaPath)) {
      return await _inProgressThumbnailGenerations[mediaPath];
    }

    final future = _doGenerateThumbnail(mediaPath);
    _inProgressThumbnailGenerations[mediaPath] = future;
    try {
      final result = await future;
      if (result != null) {
        _thumbnailCache[mediaPath] = result;
      }
      return result;
    } finally {
      _inProgressThumbnailGenerations.remove(mediaPath);
    }
  }

  /// Backwards-compatible alias for generateThumbnail
  Future<String?> generateVideoThumbnail(String videoPath) => generateThumbnail(videoPath);

  Future<String?> _doGenerateThumbnail(String mediaPath) async {
    try {
      if (!await File(mediaPath).exists()) return null;

      final tempDir = await getTemporaryDirectory();
      final thumbsDir = Directory(p.join(tempDir.path, 'vdown_thumbs'));
      if (!await thumbsDir.exists()) {
        await thumbsDir.create(recursive: true);
      }

      final hash = md5.convert(utf8.encode(mediaPath)).toString();
      final thumbPath = p.join(thumbsDir.path, '$hash.jpg');
      final thumbFile = File(thumbPath);

      if (await thumbFile.exists() && (await thumbFile.length()) > 0) {
        return thumbPath;
      }

      // First attempt at 1 second (ideal for videos)
      var session = await FFmpegKit.executeWithArguments([
        '-ss',
        '00:00:01',
        '-i',
        mediaPath,
        '-vframes',
        '1',
        '-q:v',
        '3',
        '-y',
        thumbPath,
      ]);
      var returnCode = await session.getReturnCode();

      if (!ReturnCode.isSuccess(returnCode) || !await thumbFile.exists() || (await thumbFile.length()) == 0) {
        // Fallback attempt at 0 second (for short videos or audio embedded cover art)
        session = await FFmpegKit.executeWithArguments([
          '-ss',
          '00:00:00',
          '-i',
          mediaPath,
          '-vframes',
          '1',
          '-q:v',
          '3',
          '-y',
          thumbPath,
        ]);
        returnCode = await session.getReturnCode();
      }

      if (ReturnCode.isSuccess(returnCode) && await thumbFile.exists() && (await thumbFile.length()) > 0) {
        return thumbPath;
      }
    } catch (e) {
      debugPrint('Error generating thumbnail: $e');
    }
    return null;
  }

  /// Extracts basic media information (duration, resolution, codecs) via FFprobeKit
  Future<Map<String, String>> getVideoInfo(String videoPath) async {
    final info = <String, String>{};
    try {
      if (!await File(videoPath).exists()) return info;

      final session = await FFprobeKit.getMediaInformation(videoPath);
      final mediaInfo = session.getMediaInformation();
      if (mediaInfo == null) return info;

      // Duration: format to HH:MM:SS
      final durationStr = mediaInfo.getDuration();
      if (durationStr != null) {
        final sec = double.tryParse(durationStr);
        if (sec != null) {
          final d = Duration(seconds: sec.toInt());
          final hours = d.inHours.toString().padLeft(2, '0');
          final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
          final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
          info['duration'] = '$hours:$minutes:$seconds';
        }
      }

      final streams = mediaInfo.getStreams();
      for (final stream in streams) {
        final type = stream.getType()?.toLowerCase();
        if (type == 'video') {
          if (!info.containsKey('resolution')) {
            final width = stream.getWidth();
            final height = stream.getHeight();
            if (width != null && height != null) {
              info['resolution'] = '${width}x$height';
            }
          }
          if (!info.containsKey('videoCodec')) {
            final codec = stream.getCodec();
            if (codec != null) {
              info['videoCodec'] = codec;
            }
          }
        } else if (type == 'audio') {
          if (!info.containsKey('audioCodec')) {
            final codec = stream.getCodec();
            if (codec != null) {
              info['audioCodec'] = codec;
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error extracting video info: $e');
    }
    return info;
  }
}
