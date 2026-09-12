import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../core/utils.dart';

class PermissionService {
  /// MethodChannel for native Android permission operations
  static const _permChannel = MethodChannel('com.virusdownloader/permissions');

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

  /// Request storage permission if required.
  /// Handles scoped storage differences across Android versions.
  Future<bool> requestStoragePermission() async {
    if (kIsWeb || !AppUtils.isMobile) {
      return true;
    }

    try {
      if (Platform.isAndroid) {
        // Android 11+ (API 30+): MANAGE_EXTERNAL_STORAGE for full access
        if (await _isManageExternalStorageGranted()) {
          return true;
        }

        // Try legacy storage permission first (works on Android 10 and below)
        if (await Permission.storage.isGranted) {
          return true;
        }
        final result = await Permission.storage.request();
        if (result.isGranted) {
          return true;
        }

        // For Android 11+, if legacy failed, try manage external storage
        return await requestManageExternalStorageIfNeeded();
      }
      return true;
    } catch (e) {
      debugPrint('Error requesting storage permission: $e');
      return false;
    }
  }

  /// Check if MANAGE_EXTERNAL_STORAGE is granted (Android 11+)
  Future<bool> _isManageExternalStorageGranted() async {
    try {
      final result = await _permChannel.invokeMethod<bool>('isManageExternalStorageGranted');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Request MANAGE_EXTERNAL_STORAGE permission (opens system settings)
  Future<bool> requestManageExternalStorageIfNeeded() async {
    if (!Platform.isAndroid) return true;

    try {
      if (await _isManageExternalStorageGranted()) {
        return true;
      }
      await _permChannel.invokeMethod<bool>('requestManageExternalStorage');
      // User must toggle in settings; we can't know the result immediately
      return await _isManageExternalStorageGranted();
    } catch (e) {
      debugPrint('Error requesting manage external storage: $e');
      return false;
    }
  }

  /// Check if battery optimization exemption is granted
  Future<bool> isBatteryOptimizationExempt() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _permChannel.invokeMethod<bool>('isBatteryOptimizationExempt');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Request battery optimization exemption for reliable background downloads
  Future<bool> requestBatteryOptimizationExemption() async {
    if (!Platform.isAndroid) return true;

    try {
      if (await isBatteryOptimizationExempt()) {
        return true;
      }
      await _permChannel.invokeMethod<bool>('requestBatteryOptimizationExemption');
      // Check again after user interaction
      return await isBatteryOptimizationExempt();
    } catch (e) {
      debugPrint('Error requesting battery optimization exemption: $e');
      return false;
    }
  }

  /// Check all core permissions status
  Future<Map<String, bool>> checkAllPermissions() async {
    if (kIsWeb || !AppUtils.isMobile) {
      return {
        'notifications': true,
        'storage': true,
        'batteryOptimization': true,
      };
    }

    final notifGranted = await Permission.notification.isGranted;
    final storageGranted = Platform.isAndroid
        ? (await _isManageExternalStorageGranted() || await Permission.storage.isGranted)
        : true;
    final batteryExempt = await isBatteryOptimizationExempt();

    return {
      'notifications': notifGranted,
      'storage': storageGranted,
      'batteryOptimization': batteryExempt,
    };
  }

  /// Unified permission check and request flow for app startup.
  /// Requests notification and storage permissions in sequence.
  Future<void> checkAndRequestAllPermissions() async {
    if (kIsWeb || !AppUtils.isMobile) return;

    await requestNotificationPermission();
    await requestStoragePermission();
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
