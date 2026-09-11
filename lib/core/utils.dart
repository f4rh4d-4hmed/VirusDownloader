import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'enums.dart';

class AppUtils {
  /// Whether the app is running on a mobile OS (Android, iOS)
  static bool get isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Whether the app is running on a desktop OS (Windows, macOS, Linux)
  static bool get isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);
  /// Formats byte count to human-readable string (e.g. 1.25 MB, 450 KB, 2.1 GB)
  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    final clampedI = i.clamp(0, suffixes.length - 1);
    final size = bytes / pow(1024, clampedI);
    return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${suffixes[clampedI]}';
  }

  /// Alias for formatFileSize
  static String formatBytes(int bytes) => formatFileSize(bytes);

  /// Formats download speed in bytes/sec (e.g. 2.4 MB/s)
  static String formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 B/s';
    const suffixes = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    final i = (log(bytesPerSec) / log(1024)).floor();
    final clampedI = i.clamp(0, suffixes.length - 1);
    final speed = bytesPerSec / pow(1024, clampedI);
    return '${speed.toStringAsFixed(speed >= 100 ? 0 : 1)} ${suffixes[clampedI]}';
  }

  /// Formats ETA Duration to readable string (e.g. 2h 15m or 45s)
  static String formatDuration(Duration duration) {
    if (duration.isNegative || duration.inSeconds <= 0) return '--';
    if (duration.inHours > 0) {
      return '${duration.inHours}h ${duration.inMinutes.remainder(60)}m';
    } else if (duration.inMinutes > 0) {
      return '${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s';
    } else {
      return '${duration.inSeconds}s';
    }
  }

  /// Extracts clean file extension from a filename or URL.
  /// Correctly handles URL query strings (?foo=bar), hash fragments, paths,
  /// numeric copy suffixes like " (1)", and compound extensions (.tar.gz).
  static String extractExtension(String input) {
    if (input.trim().isEmpty) return '';
    String clean = input.trim();

    // Strip URL query parameters and fragments
    final queryIdx = clean.indexOf('?');
    if (queryIdx != -1) clean = clean.substring(0, queryIdx);
    final hashIdx = clean.indexOf('#');
    if (hashIdx != -1) clean = clean.substring(0, hashIdx);

    // Extract filename from path or URL
    if (clean.contains('/') || clean.contains(r'\')) {
      final segments = clean.split(RegExp(r'[/\\]')).where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty) {
        clean = segments.last;
      }
    }

    // Strip trailing parenthesis noise like "file (1).rar" -> "file.rar"
    clean = clean.replaceAll(RegExp(r'\s*\(\d+\)$'), '');
    clean = clean.toLowerCase().trim();

    // Check compound extensions first
    const compoundExts = ['tar.gz', 'tar.bz2', 'tar.xz', 'tar.zst', 'user.js'];
    for (final compound in compoundExts) {
      if (clean.endsWith('.$compound')) {
        return compound;
      }
    }

    if (clean.contains('.')) {
      return clean.split('.').last.trim();
    }
    return '';
  }

  /// Determines DownloadCategory based on file extension or filename
  static DownloadCategory categoryFromExtension(String extensionOrFileName) {
    String cleanExt = extractExtension(extensionOrFileName);
    if (cleanExt.isEmpty) {
      // In case a bare extension string was passed (e.g. "pdf", "mp4", ".rar")
      cleanExt = extensionOrFileName.trim().toLowerCase().replaceAll('.', '');
    }
    if (cleanExt.isEmpty) return DownloadCategory.other;

    // 1. Videos
    const videoExts = {
      // Standard containers
      'mp4', 'm4v', 'mkv', 'webm', 'avi', 'mov', 'qt', 'wmv', 'flv', 'f4v', 'swf',
      // MPEG & Broadcast
      'mpg', 'mpeg', 'mpe', 'mpv', 'm2v', 'm4p', 'ts', 'mts', 'm2ts', 'vob', 'ogv',
      // Mobile & Legacy
      '3gp', '3g2', 'rm', 'rmvb', 'asf', 'divx', 'amv', 'yuv',
      // Streams
      'm3u8', 'mpd',
    };

    // 2. Audio
    const audioExts = {
      // Lossy
      'mp3', 'aac', 'm4a', 'ogg', 'oga', 'wma', 'opus', 'amr', 'ac3', 'eac3', 'dts', 'ra',
      // Lossless
      'wav', 'wave', 'flac', 'alac', 'aiff', 'aif', 'aifc', 'ape', 'mka', 'wv', 'tta',
      // Tracker & MIDI
      'mid', 'midi', 'kar', 'mod', 'xm', 's3m', 'it',
    };

    // 3. Images & Graphics
    const imageExts = {
      // Standard Web & Raster
      'jpg', 'jpeg', 'jpe', 'jif', 'jfif', 'jfi', 'png', 'gif', 'webp', 'bmp', 'dib', 'tiff', 'tif', 'ico', 'cur', 'svg', 'svgz',
      // Modern / High-Efficiency
      'heic', 'heif', 'avif', 'jxl',
      // Camera RAW
      'raw', 'cr2', 'cr3', 'nef', 'arw', 'dng', 'orf', 'rw2', 'pef', 'raf',
      // Design & Vector
      'psd', 'psb', 'ai', 'eps', 'cdr', 'xcf', 'sketch', 'fig', 'icns',
    };

    // 4. Compressed & Archives
    const compExts = {
      // Standard Archives
      'zip', 'rar', '7z', 'tar', 'gz', 'gzip', 'bz2', 'bzip2', 'xz', 'zst', 'lz', 'lzma', 'lzo', 'z',
      // Disk Images & Backups
      'iso', 'img', 'dmg', 'vhd', 'vhdx', 'vmdk', 'bin', 'cue', 'nrg', 'mdf',
      // Compound Tarballs
      'tar.gz', 'tar.bz2', 'tar.xz', 'tar.zst', 'tgz', 'tbz', 'tbz2', 'txz',
      // Legacy & Packages
      'cab', 'arj', 'lzh', 'lha', 'ace', 'uue', 'cpio', 'shar', 'arc', 'pak',
    };

    // 5. Programs & Executables
    const progExts = {
      // Windows
      'exe', 'msi', 'msix', 'msixbundle', 'appx', 'appxbundle', 'bat', 'cmd', 'com', 'scr', 'reg', 'vbs', 'wsf', 'ps1', 'gadget',
      // Mobile
      'apk', 'xapk', 'apks', 'aab',
      // Linux & Unix
      'deb', 'rpm', 'appimage', 'flatpak', 'snap', 'run', 'bin', 'sh', 'bash', 'elf',
      // macOS
      'pkg', 'mpkg', 'app',
      // Bytecode / Runtime
      'jar', 'war', 'ear',
    };

    // 6. Documents & Code
    const docExts = {
      // Office & Text
      'pdf', 'doc', 'docx', 'docm', 'dot', 'dotx', 'rtf', 'txt', 'text', 'odt', 'ott', 'fodt', 'pages', 'wps', 'wpd',
      // Spreadsheets
      'xls', 'xlsx', 'xlsm', 'xlsb', 'xlt', 'xltx', 'csv', 'tsv', 'ods', 'ots', 'fods', 'numbers',
      // Presentations
      'ppt', 'pptx', 'pptm', 'pot', 'potx', 'pps', 'ppsx', 'odp', 'otp', 'fodp', 'key', 'keynote',
      // eBooks & Publications
      'epub', 'mobi', 'azw', 'azw3', 'fb2', 'ibooks', 'djvu', 'cbr', 'cbz',
      // Markup & Notes
      'md', 'markdown', 'tex', 'latex', 'rst', 'adoc', 'asciidoc',
      // Web & Data Formats
      'html', 'htm', 'xhtml', 'xml', 'json', 'jsonc', 'yaml', 'yml', 'toml', 'sql', 'log', 'cfg', 'conf', 'ini', 'env',
      // Programming Languages
      'c', 'cpp', 'cc', 'cxx', 'h', 'hpp', 'cs', 'java', 'kt', 'kts', 'py', 'pyw', 'rb', 'php',
      'js', 'jsx', 'tsx', 'dart', 'swift', 'go', 'rs', 'lua', 'r', 'scala', 'pl', 'pm',
    };

    if (videoExts.contains(cleanExt)) return DownloadCategory.videos;
    if (audioExts.contains(cleanExt)) return DownloadCategory.audio;
    if (imageExts.contains(cleanExt)) return DownloadCategory.images;
    if (compExts.contains(cleanExt)) return DownloadCategory.compressed;
    if (progExts.contains(cleanExt)) return DownloadCategory.programs;
    if (docExts.contains(cleanExt)) return DownloadCategory.documents;

    return DownloadCategory.other;
  }

  /// Returns true if the file format can be previewed as an image
  static bool isImageFormat(String pathOrName) {
    final ext = extractExtension(pathOrName);
    return {'jpg', 'jpeg', 'jpe', 'jfif', 'png', 'gif', 'webp', 'bmp', 'ico'}.contains(ext);
  }

  /// Returns true if the file format is an audio/music format
  static bool isAudioFormat(String pathOrName) {
    final ext = extractExtension(pathOrName);
    return {'mp3', 'wav', 'wave', 'aac', 'flac', 'ogg', 'oga', 'm4a', 'opus', 'wma', 'aiff', 'aif', 'mid', 'midi'}.contains(ext);
  }

  /// Returns true if the file format is a video format
  static bool isVideoFormat(String pathOrName) {
    final ext = extractExtension(pathOrName);
    return {'mp4', 'm4v', 'mkv', 'webm', 'avi', 'mov', 'wmv', 'flv', 'mpg', 'mpeg', '3gp', 'ts', 'mts', 'vob', 'ogv'}.contains(ext);
  }

  /// Returns true if the file format is a readable text or source document
  static bool isTextFormat(String pathOrName) {
    final ext = extractExtension(pathOrName);
    return {
      'txt', 'text', 'log', 'md', 'markdown', 'json', 'jsonc', 'yaml', 'yml', 'toml',
      'xml', 'html', 'htm', 'xhtml', 'csv', 'tsv', 'sql', 'cfg', 'conf', 'ini', 'env',
      'dart', 'js', 'jsx', 'ts', 'tsx', 'py', 'c', 'cpp', 'h', 'hpp', 'cs', 'java',
      'kt', 'rb', 'php', 'sh', 'bat', 'ps1', 'rs', 'go', 'swift',
    }.contains(ext);
  }

  /// Returns true if the file format can be previewed in the app
  static bool canPreview(String pathOrName) {
    return isImageFormat(pathOrName) ||
        isAudioFormat(pathOrName) ||
        isVideoFormat(pathOrName) ||
        isTextFormat(pathOrName);
  }

  /// Extracts clean filename from a URL
  static String extractFileName(String url) {
    try {
      final uri = Uri.parse(url.trim());
      final pathSegments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (pathSegments.isNotEmpty) {
        final lastSegment = pathSegments.last;
        // Strip query params if any stuck in segment
        final decoded = Uri.decodeComponent(lastSegment);
        if (decoded.trim().isNotEmpty) {
          return decoded;
        }
      }
    } catch (_) {}
    return 'download_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// Returns an appropriate Material Icon for a category
  static IconData getCategoryIcon(DownloadCategory category) {
    switch (category) {
      case DownloadCategory.all:
        return Icons.all_inbox_outlined;
      case DownloadCategory.documents:
        return Icons.description_outlined;
      case DownloadCategory.images:
        return Icons.image_outlined;
      case DownloadCategory.videos:
        return Icons.movie_outlined;
      case DownloadCategory.audio:
        return Icons.audiotrack_outlined;
      case DownloadCategory.compressed:
        return Icons.folder_zip_outlined;
      case DownloadCategory.programs:
        return Icons.laptop_windows_outlined;
      case DownloadCategory.other:
        return Icons.insert_drive_file_outlined;
    }
  }

  /// Returns user-friendly category title
  static String getCategoryLabel(DownloadCategory category) {
    switch (category) {
      case DownloadCategory.all:
        return 'All';
      case DownloadCategory.documents:
        return 'Documents';
      case DownloadCategory.images:
        return 'Images';
      case DownloadCategory.videos:
        return 'Videos';
      case DownloadCategory.audio:
        return 'Audio';
      case DownloadCategory.compressed:
        return 'Archives';
      case DownloadCategory.programs:
        return 'Programs';
      case DownloadCategory.other:
        return 'Other';
    }
  }

  /// Converts raw exceptions or HTTP errors into concise, user-friendly messages
  static String getHumanReadableError(dynamic error) {
    if (error == null) return 'Download failed.';

    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      final headers = error.response?.headers;
      final serverHeader = headers?.value('server')?.toLowerCase() ?? '';
      final cfMitigated = headers?.value('cf-mitigated')?.toLowerCase() ?? '';
      final respData = error.response?.data?.toString().toLowerCase() ?? '';

      // Check for Cloudflare / anti-bot challenges
      final isCloudflareChallenge = cfMitigated == 'challenge' ||
          respData.contains('challenges.cloudflare.com') ||
          respData.contains('just a moment...') ||
          (serverHeader.contains('cloudflare') && statusCode == 403);

      if (isCloudflareChallenge) {
        return 'Cloudflare bot check required. Open link in browser.';
      }

      if (statusCode != null) {
        switch (statusCode) {
          case 400:
            return 'Bad request (400). Invalid download link.';
          case 401:
            return 'Login required (401). Access unauthorized.';
          case 403:
            return 'Access denied (403). Link expired or login required.';
          case 404:
            return 'File not found on server (404).';
          case 405:
            return 'Method not allowed (405). Server rejected request.';
          case 408:
            return 'Request timed out (408). Server was slow.';
          case 410:
            return 'File permanently removed (410).';
          case 416:
            return 'Resume not supported from this position (416).';
          case 429:
            return 'Too many requests (429). Rate limit reached.';
          case 500:
            return 'Server internal error (500). Try again later.';
          case 502:
            return 'Bad gateway (502). Server is unreachable.';
          case 503:
            return 'Service temporarily unavailable (503).';
          case 504:
            return 'Gateway timed out (504). Server took too long.';
          default:
            if (statusCode >= 400 && statusCode < 500) {
              return 'Client error ($statusCode).';
            } else if (statusCode >= 500) {
              return 'Server error ($statusCode).';
            }
        }
      }

      switch (error.type) {
        case DioExceptionType.connectionTimeout:
          return 'Connection timed out. Check your internet.';
        case DioExceptionType.sendTimeout:
          return 'Send timed out. Request took too long.';
        case DioExceptionType.receiveTimeout:
          return 'Server stopped responding (receive timeout).';
        case DioExceptionType.badCertificate:
          return 'Security certificate invalid (SSL/TLS error).';
        case DioExceptionType.cancel:
          return 'Download was cancelled.';
        case DioExceptionType.connectionError:
          return _parseSocketOrNetworkError(error.error ?? error.message);
        case DioExceptionType.unknown:
          if (error.error != null) {
            return _parseSocketOrNetworkError(error.error);
          }
          break;
        default:
          break;
      }
    }

    // Handle FileSystemException (Storage / Permissions)
    if (error is FileSystemException) {
      final msg = error.message.toLowerCase();
      final osMsg = error.osError?.message.toLowerCase() ?? '';
      if (msg.contains('no space') || osMsg.contains('no space')) {
        return 'Storage full. Free up device space.';
      }
      if (msg.contains('permission') || osMsg.contains('permission')) {
        return 'Storage permission denied. Choose another folder.';
      }
      return 'Storage error: ${error.message}';
    }

    if (error is SocketException) {
      return _parseSocketOrNetworkError(error);
    }
    if (error is TimeoutException) {
      return 'Connection timed out.';
    }

    return _parseSocketOrNetworkError(error.toString());
  }

  static String _parseSocketOrNetworkError(dynamic raw) {
    final str = raw.toString().toLowerCase();

    if (str.contains('cf-mitigated') || str.contains('challenges.cloudflare.com')) {
      return 'Cloudflare bot check required. Open link in browser.';
    }
    if (str.contains('403') || str.contains('forbidden')) {
      return 'Access denied (403). Link expired or login required.';
    }
    if (str.contains('404') || str.contains('not found')) {
      return 'File not found on server (404).';
    }
    if (str.contains('401') || str.contains('unauthorized')) {
      return 'Login required (401). Access unauthorized.';
    }
    if (str.contains('429') || str.contains('too many requests')) {
      return 'Too many requests (429). Rate limit reached.';
    }
    if (str.contains('500') || str.contains('internal server error')) {
      return 'Server internal error (500). Try again later.';
    }
    if (str.contains('502') || str.contains('bad gateway')) {
      return 'Bad gateway (502). Server is unreachable.';
    }
    if (str.contains('503') || str.contains('service unavailable')) {
      return 'Service temporarily unavailable (503).';
    }
    if (str.contains('504') || str.contains('gateway timeout')) {
      return 'Gateway timed out (504). Server took too long.';
    }
    if (str.contains('cleartext http traffic') || str.contains('not permitted')) {
      return 'Cleartext HTTP not allowed. Use HTTPS.';
    }
    if (str.contains('failed host lookup') || str.contains('no address associated')) {
      return 'Cannot reach server. Check internet connection.';
    }
    if (str.contains('connection refused')) {
      return 'Server refused connection. Host may be down.';
    }
    if (str.contains('connection reset') || str.contains('broken pipe')) {
      return 'Connection lost. Server closed connection.';
    }
    if (str.contains('network is unreachable')) {
      return 'No internet connection available.';
    }
    if (str.contains('handshake') || str.contains('certificate')) {
      return 'Security certificate invalid (SSL/TLS error).';
    }
    if (str.contains('timed out') || str.contains('timeout')) {
      return 'Connection timed out. Check your internet.';
    }
    if (str.contains('validatestatus was configured to throw')) {
      return 'Server rejected request. Please check URL.';
    }
    if (str.contains('proxy pool exhausted')) {
      return 'All proxies failed to connect.';
    }
    if (str.contains('speed too slow')) {
      return 'Connection speed too slow.';
    }

    return 'Download failed. Check connection or link.';
  }
}

