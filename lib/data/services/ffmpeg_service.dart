import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'http_download_service.dart';

class FfmpegService {
  String? _cachedPath;

  @visibleForTesting
  void clearCache() {
    _cachedPath = null;
  }

  /// Returns the path to the ffmpeg executable if available, or null
  Future<String?> getFfmpegPath() async {
    if (_cachedPath != null && await File(_cachedPath!).exists()) {
      return _cachedPath;
    }

    final isWindows = Platform.isWindows;
    final exeName = isWindows ? 'ffmpeg.exe' : 'ffmpeg';

    // 1. Check extras/ffmpeg in project root or current directory
    final localPath = p.join(Directory.current.path, 'extras', 'ffmpeg', exeName);
    if (await File(localPath).exists()) {
      _cachedPath = localPath;
      return localPath;
    }

    // 2. Check executable directory
    final exeDir = File(Platform.resolvedExecutable).parent;
    final exeLocal = p.join(exeDir.path, 'extras', 'ffmpeg', exeName);
    if (await File(exeLocal).exists()) {
      _cachedPath = exeLocal;
      return exeLocal;
    }

    // 3. Check AppSupport/VirusDownloader/bin
    try {
      final appSupport = await getApplicationSupportDirectory();
      final appSupportBin = p.join(appSupport.path, 'bin', exeName);
      if (await File(appSupportBin).exists()) {
        _cachedPath = appSupportBin;
        return appSupportBin;
      }
    } catch (_) {}

    // 4. Check system PATH
    try {
      final checkCmd = isWindows ? 'where.exe' : 'which';
      final res = await Process.run(checkCmd, [exeName]);
      if (res.exitCode == 0 && res.stdout.toString().trim().isNotEmpty) {
        final found = res.stdout.toString().trim().split(RegExp(r'[\r\n]+')).first;
        if (await File(found).exists()) {
          _cachedPath = found;
          return found;
        }
      }
    } catch (_) {}

    return null;
  }

  Future<bool> isAvailable() async {
    return (await getFfmpegPath()) != null;
  }

  /// Downloads and extracts the lightweight static FFmpeg for the current platform
  Future<String?> downloadLightweightFfmpeg({
    void Function(int receivedBytes, int totalBytes)? onProgress,
  }) async {
    try {
      String platformKey;
      if (Platform.isWindows) {
        platformKey = 'windows-x64';
      } else if (Platform.isMacOS) {
        platformKey = 'macos-x64';
      } else if (Platform.isLinux) {
        platformKey = 'linux-x64';
      } else {
        return null;
      }

      // Read manifest from assets
      final manifestStr = await rootBundle.loadString('assets/bin/ffmpeg_manifest.json');
      final manifest = jsonDecode(manifestStr) as Map<String, dynamic>;
      final platforms = manifest['platforms'] as Map<String, dynamic>?;
      final platConfig = platforms?[platformKey] as Map<String, dynamic>?;
      if (platConfig == null) return null;

      final downloadUrl = platConfig['url'] as String;
      final exeName = platConfig['executable'] as String;

      final appSupport = await getApplicationSupportDirectory();
      final binDir = Directory(p.join(appSupport.path, 'bin'));
      await binDir.create(recursive: true);

      final targetExe = File(p.join(binDir.path, exeName));
      if (await targetExe.exists()) {
        _cachedPath = targetExe.path;
        return targetExe.path;
      }

      final zipFile = File(p.join(binDir.path, 'ffmpeg_download.zip'));

      // Download using HttpClient
      final client = HttpClient();
      final req = await client.getUrl(Uri.parse(downloadUrl));
      final resp = await req.close();
      if (resp.statusCode != 200) {
        client.close(force: true);
        return null;
      }

      final total = resp.contentLength;
      int received = 0;
      final sink = zipFile.openWrite();

      await for (final chunk in resp) {
        sink.add(chunk);
        received += chunk.length;
        if (onProgress != null && total > 0) {
          onProgress(received, total);
        }
      }
      await sink.flush();
      await sink.close();
      client.close();

      // Extract ZIP
      if (Platform.isWindows) {
        await Process.run('tar', ['-xf', zipFile.path, '-C', binDir.path]);
      } else {
        await Process.run('unzip', ['-o', zipFile.path, '-d', binDir.path]);
        await Process.run('chmod', ['+x', targetExe.path]);
      }

      if (await zipFile.exists()) {
        await zipFile.delete();
      }

      if (await targetExe.exists()) {
        _cachedPath = targetExe.path;
        return targetExe.path;
      }
    } catch (e) {
      debugPrint('Failed to download lightweight FFmpeg: $e');
    }
    return null;
  }

  /// Downloads an HLS stream directly via FFmpeg into a single MKV or MP4 file
  Future<bool> downloadHlsStream({
    required String m3u8Url,
    required String savePath,
    required DownloadProgressCallback onProgress,
    Map<String, String>? headers,
    CancelToken? cancelToken,
    void Function(Process process)? onProcessStarted,
  }) async {
    final ffmpegPath = await getFfmpegPath() ?? await downloadLightweightFfmpeg();
    if (ffmpegPath == null) {
      throw Exception('FFmpeg is required to process HLS stream into MKV/MP4, but could not be located.');
    }

    // Build headers string: 'Header1: val\r\nHeader2: val\r\n'
    final headerList = <String>[];
    if (headers != null) {
      for (final entry in headers.entries) {
        final k = entry.key.trim();
        final v = entry.value.trim();
        if (k.toLowerCase() == 'range') continue;
        headerList.add('$k: $v\r\n');
      }
    }

    final args = <String>['-y'];
    if (headerList.isNotEmpty) {
      args.addAll(['-headers', headerList.join('')]);
    }
    args.addAll([
      '-i',
      m3u8Url,
      '-map',
      '0:v?',
      '-map',
      '0:a?',
      '-map',
      '0:s?',
      '-c',
      'copy',
      '-bsf:a',
      'aac_adtstoasc',
      savePath,
    ]);

    final process = await Process.start(ffmpegPath, args);
    if (onProcessStarted != null) {
      onProcessStarted(process);
    }

    cancelToken?.whenCancel.then((_) {
      try {
        process.kill(ProcessSignal.sigkill);
      } catch (_) {}
    });

    int downloadedBytes = 0;
    int lastDownloadedBytes = 0;
    double lastSpeed = 0.0;
    DateTime lastProgressTime = DateTime.now();

    final file = File(savePath);

    // FFmpeg logs progress to stderr
    final stderrSub = process.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((line) async {
      // Parse FFmpeg progress: size=   1234kB time=00:01:23.45 bitrate=... speed=...
      final sizeMatch = RegExp(r'size=\s*(\d+)kB').firstMatch(line);
      if (sizeMatch != null) {
        final kb = int.tryParse(sizeMatch.group(1) ?? '0') ?? 0;
        downloadedBytes = kb * 1024;
      } else if (await file.exists()) {
        downloadedBytes = await file.length();
      }

      final now = DateTime.now();
      final elapsedMs = now.difference(lastProgressTime).inMilliseconds;
      if (elapsedMs >= 400) {
        final bytesDelta = downloadedBytes - lastDownloadedBytes;
        if (bytesDelta > 0 && elapsedMs > 0) {
          lastSpeed = (bytesDelta / (elapsedMs / 1000.0));
        }
        lastDownloadedBytes = downloadedBytes;
        lastProgressTime = now;

        onProgress(
          downloadedBytes: downloadedBytes,
          totalBytes: 0, // Streaming/variable length
          speedBytesPerSec: lastSpeed,
        );
      }
    });

    final exitCode = await process.exitCode;
    await stderrSub.cancel();

    if (cancelToken?.isCancelled == true) {
      throw DioException(
        requestOptions: RequestOptions(path: m3u8Url),
        type: DioExceptionType.cancel,
        error: 'Download paused/cancelled',
      );
    }

    if (exitCode == 0 && await file.exists() && (await file.length()) > 0) {
      final finalLength = await file.length();
      onProgress(
        downloadedBytes: finalLength,
        totalBytes: finalLength,
        speedBytesPerSec: 0,
      );
      return true;
    }

    throw Exception('FFmpeg stream download failed with exit code $exitCode.');
  }

  /// Remuxes any media file (or .ts segments) into an MKV container with subtitles
  Future<bool> remuxToMkv({
    required String inputPath,
    required String outputPath,
    String? subtitlePath,
  }) async {
    final ffmpegPath = await getFfmpegPath() ?? await downloadLightweightFfmpeg();
    if (ffmpegPath == null) return false;

    final args = <String>['-y', '-i', inputPath];
    if (subtitlePath != null && await File(subtitlePath).exists()) {
      args.addAll(['-i', subtitlePath, '-map', '0:v?', '-map', '0:a?', '-map', '1:s?', '-c', 'copy']);
    } else {
      args.addAll(['-map', '0:v?', '-map', '0:a?', '-map', '0:s?', '-c', 'copy']);
    }
    args.add(outputPath);

    final result = await Process.run(ffmpegPath, args);
    return result.exitCode == 0;
  }
}
