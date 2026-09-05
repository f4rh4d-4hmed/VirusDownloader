import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

class FileService {
  /// Gets the default downloads folder for the current operating system
  Future<String> getDefaultDownloadDirectory() async {
    try {
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        final dir = await getDownloadsDirectory();
        if (dir != null && await dir.exists()) {
          return dir.path;
        }
      }
      // Mobile or fallback
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

  /// Opens the file using system default program
  Future<bool> openFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;

      final uri = Uri.file(filePath);
      if (await canLaunchUrl(uri)) {
        return await launchUrl(uri);
      }
    } catch (e) {
      debugPrint('Error opening file: $e');
    }
    return false;
  }

  /// Opens containing folder in file manager (Explorer, Finder, Files)
  Future<bool> openContainingFolder(String filePath) async {
    try {
      if (Platform.isWindows) {
        final result = await Process.run('explorer.exe', ['/select,', p.normalize(filePath)]);
        return result.exitCode == 0;
      } else if (Platform.isMacOS) {
        final result = await Process.run('open', ['-R', filePath]);
        return result.exitCode == 0;
      } else if (Platform.isLinux) {
        final parentDir = p.dirname(filePath);
        final result = await Process.run('xdg-open', [parentDir]);
        return result.exitCode == 0;
      } else {
        // Mobile fallback
        final uri = Uri.file(p.dirname(filePath));
        if (await canLaunchUrl(uri)) {
          return await launchUrl(uri);
        }
      }
    } catch (e) {
      debugPrint('Error opening containing folder: $e');
    }
    return false;
  }
}

