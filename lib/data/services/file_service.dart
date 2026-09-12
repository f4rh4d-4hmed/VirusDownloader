import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class FileService {
  Directory? _customBaseTempDir;

  /// MethodChannel for native Android file operations
  static const _fileChannel = MethodChannel('com.virusdownloader/file_open');

  FileService({Directory? customBaseTempDir}) : _customBaseTempDir = customBaseTempDir;

  @visibleForTesting
  void setCustomBaseTempDir(Directory? dir) => _customBaseTempDir = dir;

  /// Gets the default downloads folder for the current operating system.
  /// On Android, returns the public Downloads/VirusDownloader directory.
  Future<String> getDefaultDownloadDirectory() async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final dir = await getDownloadsDirectory();
        if (dir != null && await dir.exists()) {
          return dir.path;
        }
      }

      if (Platform.isAndroid) {
        // Try to get the public Downloads directory via native channel
        try {
          final publicPath = await _fileChannel.invokeMethod<String>('getPublicDownloadPath');
          if (publicPath != null && publicPath.isNotEmpty) {
            final dir = Directory(publicPath);
            if (!await dir.exists()) {
              await dir.create(recursive: true);
            }
            return publicPath;
          }
        } catch (_) {}

        // Fallback: try external storage directories
        final extDirs = await getExternalStorageDirectories();
        if (extDirs != null && extDirs.isNotEmpty) {
          // Navigate up from app-specific external to public Downloads
          // App path is like /storage/emulated/0/Android/data/pkg/files
          // We want /storage/emulated/0/Download/VirusDownloader
          final appExtPath = extDirs.first.path;
          final androidIdx = appExtPath.indexOf('/Android/');
          if (androidIdx > 0) {
            final publicDir = Directory(
              '${appExtPath.substring(0, androidIdx)}/Download/VirusDownloader',
            );
            if (!await publicDir.exists()) {
              try {
                await publicDir.create(recursive: true);
              } catch (_) {}
            }
            if (await publicDir.exists()) {
              return publicDir.path;
            }
          }
        }

        // Last resort: external storage directory (app-specific, but visible via USB)
        final extDir = await getExternalStorageDirectory();
        if (extDir != null && await extDir.exists()) {
          return extDir.path;
        }
      }

      // iOS or absolute fallback
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    } catch (_) {
      try {
        final dir = await getApplicationDocumentsDirectory();
        return dir.path;
      } catch (_) {
        return Directory.current.path;
      }
    }
  }

  /// Ensures a folder exists on disk
  Future<void> ensureDirectoryExists(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// Checks if a file exists at the given path
  Future<bool> fileExists(String filePath) async {
    return File(filePath).exists();
  }

  /// Returns size of file on disk in bytes (or 0 if does not exist)
  Future<int> getFileSize(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        return await file.length();
      }
    } catch (_) {}
    return 0;
  }

  /// Deletes a file from disk
  Future<bool> deleteFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        return true;
      }
    } catch (e) {
      debugPrint('Error deleting file $filePath: $e');
    }
    return false;
  }

  /// Generates a unique file path in [targetDir] if [fileName] already exists
  Future<String> generateUniqueFilePath(String targetDir, String fileName) async {
    await ensureDirectoryExists(targetDir);
    String fullPath = p.join(targetDir, fileName);
    if (!await File(fullPath).exists()) {
      return fullPath;
    }

    final ext = p.extension(fileName);
    final nameWithoutExt = p.basenameWithoutExtension(fileName);
    int counter = 1;

    while (await File(fullPath).exists()) {
      fullPath = p.join(targetDir, '$nameWithoutExt ($counter)$ext');
      counter++;
    }
    return fullPath;
  }

  /// Opens the file using system default program.
  /// On Android, uses native FileProvider + Intent.ACTION_VIEW via MethodChannel.
  Future<bool> openFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      if (Platform.isAndroid) {
        // Use native Android intent via MethodChannel
        try {
          final result = await _fileChannel.invokeMethod<bool>(
            'openFile',
            {'filePath': filePath},
          );
          return result ?? false;
        } catch (e) {
          debugPrint('Native file open failed, trying url_launcher: $e');
          // Fall through to url_launcher
        }
      }

      final uri = Uri.file(filePath);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error opening file: $e');
    }
    return false;
  }

  /// Opens containing folder in file manager (Explorer, Finder, Files).
  /// Not supported on Android — caller should check [AppUtils.isDesktop] before calling.
  Future<bool> openContainingFolder(String filePath) async {
    try {
      if (Platform.isWindows) {
        final file = File(filePath);
        if (await file.exists()) {
          final result = await Process.run('explorer.exe', ['/select,${p.normalize(filePath)}']);
          return result.exitCode == 0;
        } else {
          final parentDir = p.dirname(filePath);
          final dir = Directory(parentDir);
          if (await dir.exists()) {
            final result = await Process.run('explorer.exe', [p.normalize(parentDir)]);
            return result.exitCode == 0;
          }
        }
      } else if (Platform.isMacOS) {
        final file = File(filePath);
        if (await file.exists()) {
          final result = await Process.run('open', ['-R', filePath]);
          return result.exitCode == 0;
        } else {
          final parentDir = p.dirname(filePath);
          final result = await Process.run('open', [parentDir]);
          return result.exitCode == 0;
        }
      } else if (Platform.isLinux) {
        final parentDir = p.dirname(filePath);
        final result = await Process.run('xdg-open', [parentDir]);
        return result.exitCode == 0;
      }
      // Android/iOS: not supported, return false
    } catch (e) {
      debugPrint('Error opening containing folder: $e');
    }
    return false;
  }

  /// Verifies that the given directory is writable by creating and deleting a test file.
  Future<bool> verifyWriteAccess(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final testFile = File(p.join(dirPath, '.vdown_write_test'));
      await testFile.writeAsString('test');
      await testFile.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Verifies a downloaded file exists at the expected path.
  /// Returns the actual path if found, or null if missing.
  Future<String?> verifySavedFileLocation(String expectedPath) async {
    if (await File(expectedPath).exists()) {
      return expectedPath;
    }
    return null;
  }

  /// Renames a file on disk and returns the new full path.
  /// Returns null if the rename fails.
  Future<String?> renameFile(String currentPath, String newFileName) async {
    try {
      final file = File(currentPath);
      if (!await file.exists()) return null;

      final parentDir = p.dirname(currentPath);
      final newPath = await generateUniqueFilePath(parentDir, newFileName);
      final renamed = await file.rename(newPath);
      return renamed.path;
    } catch (e) {
      debugPrint('Error renaming file: $e');
      // Try copy+delete as fallback (cross-volume)
      try {
        final file = File(currentPath);
        final parentDir = p.dirname(currentPath);
        final newPath = await generateUniqueFilePath(parentDir, newFileName);
        await file.copy(newPath);
        await file.delete();
        return newPath;
      } catch (e2) {
        debugPrint('Rename fallback also failed: $e2');
        return null;
      }
    }
  }

  /// Gets the dedicated temporary directory for in-progress downloads
  Future<Directory> getAppTempDirectory() async {
    if (_customBaseTempDir != null) {
      final tempDir = Directory(p.join(_customBaseTempDir!.path, 'temp'));
      if (!await tempDir.exists()) {
        await tempDir.create(recursive: true);
      }
      return tempDir;
    }
    Directory? baseDir;
    try {
      baseDir = await getApplicationSupportDirectory();
    } catch (_) {
      try {
        baseDir = await getTemporaryDirectory();
      } catch (_) {
        baseDir = null;
      }
    }
    baseDir ??= Directory.systemTemp;

    final tempDir = Directory(p.join(baseDir.path, 'VirusDownloader', 'temp'));
    if (!await tempDir.exists()) {
      await tempDir.create(recursive: true);
    }
    return tempDir;
  }

  /// Returns the temporary file path for an in-progress download task.
  /// Uses a task-prefixed filename in the shared app temp directory.
  Future<String> getTaskTempFilePath(String taskId, String fileName) async {
    final tempDir = await getAppTempDirectory();
    final safeName = p.basename(fileName);
    return p.join(tempDir.path, '${taskId}_$safeName');
  }

  /// Cleans up temporary download file and metadata for a specific task.
  /// Strictly deletes only the task's individual files (never the shared temp folder)
  /// so other active downloads remain completely unaffected.
  /// Operates failsafe: if a file does not exist or deletion fails, it ignores errors cleanly.
  Future<void> cleanupTaskFiles({
    required String taskId,
    required String fileName,
    String? savePath,
    bool deleteTargetFile = false,
  }) async {
    try {
      final tempFilePath = await getTaskTempFilePath(taskId, fileName);
      await deleteFile(tempFilePath);
      await deleteFile('$tempFilePath.vdown_meta');
    } catch (_) {}

    if (deleteTargetFile && savePath != null && savePath.isNotEmpty) {
      try {
        await deleteFile(savePath);
        await deleteFile('$savePath.vdown_meta');
      } catch (_) {}
    }
  }

  /// Moves a file from [sourcePath] to [destinationPath].
  /// Tries an atomic rename first, falling back to copy+delete for cross-volume/mount moves.
  /// Failsafe against existing destination files on Windows.
  Future<bool> moveFile(String sourcePath, String destinationPath) async {
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        return false;
      }
      final destFile = File(destinationPath);
      final destDir = destFile.parent;
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      if (await destFile.exists()) {
        try {
          await destFile.delete();
        } catch (_) {}
      }
      try {
        await sourceFile.rename(destinationPath);
        return true;
      } catch (_) {
        await sourceFile.copy(destinationPath);
        try {
          await sourceFile.delete();
        } catch (_) {}
        return true;
      }
    } catch (e) {
      debugPrint('Error moving file from $sourcePath to $destinationPath: $e');
      return false;
    }
  }
}
