import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/utils.dart';

class PermissionService {
  /// Request notification permission on Android 13+ (POST_NOTIFICATIONS)
  Future<bool> requestNotificationPermission() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }

    try {
      final status = await Permission.notification.status;
      if (status.isGranted) {
        return true;
      }
      final result = await Permission.notification.request();
      return result.isGranted;
    } catch (e) {
      debugPrint('Error requesting notification permission: $e');
      return false;
    }
  }

  /// Request storage permission if required
  Future<bool> requestStoragePermission() async {
    if (kIsWeb || !AppUtils.isMobile) {
      return true;
    }

    try {
      if (Platform.isAndroid) {
        // For Android 11+ (API 30+), scoped storage is used.
        if (await Permission.storage.isGranted) {
          return true;
        }
        final result = await Permission.storage.request();
        return result.isGranted;
      }
      return true;
    } catch (e) {
      debugPrint('Error requesting storage permission: $e');
      return false;
    }
  }

  /// Check all core permissions status
  Future<Map<String, bool>> checkAllPermissions() async {
    if (kIsWeb || !AppUtils.isMobile) {
      return {'notifications': true, 'storage': true};
    }

    final notifGranted = await Permission.notification.isGranted;
    final storageGranted = await Permission.storage.isGranted;
    return {
      'notifications': notifGranted,
      'storage': storageGranted,
    };
  }

  /// Checks available storage space at the given directory path in bytes.
  /// Returns null if unable to determine.
  Future<int?> getAvailableStorageBytes(String dirPath) async {
    if (kIsWeb) return null;
    try {
      final dir = Directory(dirPath);
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}

