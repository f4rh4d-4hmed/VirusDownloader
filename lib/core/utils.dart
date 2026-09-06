import 'dart:io';
import 'dart:math';
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

  /// Determines DownloadCategory based on file extension or filename
  static DownloadCategory categoryFromExtension(String extensionOrFileName) {
    String cleanExt = extensionOrFileName.toLowerCase().trim();
    if (cleanExt.contains('.')) {
      cleanExt = cleanExt.split('.').last;
    }
    cleanExt = cleanExt.replaceAll('.', '').trim();

    const docExts = {'pdf', 'doc', 'docx', 'txt', 'rtf', 'odt', 'xls', 'xlsx', 'ppt', 'pptx', 'csv', 'md'};
    const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg', 'tiff', 'ico'};
    const videoExts = {'mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v', 'mpg', 'mpeg', '3gp'};
    const audioExts = {'mp3', 'wav', 'aac', 'flac', 'ogg', 'wma', 'm4a', 'opus'};
    const compExts = {'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz', 'iso', 'dmg'};
    const progExts = {'exe', 'msi', 'apk', 'deb', 'rpm', 'appimage', 'sh', 'bat', 'bin'};

    if (docExts.contains(cleanExt)) return DownloadCategory.documents;
    if (imageExts.contains(cleanExt)) return DownloadCategory.images;
    if (videoExts.contains(cleanExt)) return DownloadCategory.videos;
    if (audioExts.contains(cleanExt)) return DownloadCategory.audio;
    if (compExts.contains(cleanExt)) return DownloadCategory.compressed;
    if (progExts.contains(cleanExt)) return DownloadCategory.programs;

    return DownloadCategory.other;
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
}

