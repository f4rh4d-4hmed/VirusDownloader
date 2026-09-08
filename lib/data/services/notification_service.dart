import 'dart:async';
import 'package:awesome_notifications/awesome_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../core/utils.dart';

typedef NotificationActionHandler = void Function(String action, String taskId);

class NotificationService {
  static const String channelProgress = 'download_progress';
  static const String channelComplete = 'download_complete';

  static NotificationActionHandler? onActionReceived;

  bool _isInitialized = false;
  final Map<String, DateTime> _lastProgressUpdate = {};

  Future<void> init() async {
    if (kIsWeb || !AppUtils.isMobile) return;

    try {
      await AwesomeNotifications().initialize(
        null, // Default app icon
        [
          NotificationChannel(
            channelKey: channelProgress,
            channelName: 'Download Progress',
            channelDescription: 'Notifications for active and paused downloads',
            defaultColor: const Color(0xFF1976D2),
            ledColor: Colors.white,
            importance: NotificationImportance.Low,
            enableVibration: false,
            playSound: false,
            onlyAlertOnce: true,
          ),
          NotificationChannel(
            channelKey: channelComplete,
            channelName: 'Download Complete',
            channelDescription: 'Notifications when downloads finish or fail',
            defaultColor: const Color(0xFF1976D2),
            ledColor: Colors.green,
            importance: NotificationImportance.High,
            enableVibration: true,
            playSound: true,
          ),
        ],
        debug: kDebugMode,
      );

      await AwesomeNotifications().setListeners(
        onActionReceivedMethod: onActionReceivedMethod,
      );

      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing AwesomeNotifications: $e');
    }
  }

  @pragma("vm:entry-point")
  static Future<void> onActionReceivedMethod(ReceivedAction receivedAction) async {
    final key = receivedAction.buttonKeyPressed;
    if (key.isEmpty) {
      // User tapped the notification body
      final payloadTaskId = receivedAction.payload?['taskId'];
      if (payloadTaskId != null && onActionReceived != null) {
        onActionReceived!('OPEN_FILE', payloadTaskId);
      }
      return;
    }

    if (key.startsWith('PAUSE_')) {
      final taskId = key.substring('PAUSE_'.length);
      onActionReceived?.call('PAUSE', taskId);
    } else if (key.startsWith('RESUME_')) {
      final taskId = key.substring('RESUME_'.length);
      onActionReceived?.call('RESUME', taskId);
    } else if (key.startsWith('CANCEL_')) {
      final taskId = key.substring('CANCEL_'.length);
      onActionReceived?.call('CANCEL', taskId);
    } else if (key.startsWith('RETRY_')) {
      final taskId = key.substring('RETRY_'.length);
      onActionReceived?.call('RETRY', taskId);
    } else if (key.startsWith('OPEN_')) {
      final taskId = key.substring('OPEN_'.length);
      onActionReceived?.call('OPEN_FILE', taskId);
    }
  }

  int _getNotificationId(String taskId) {
    return taskId.hashCode.abs() % 100000;
  }

  /// Show or throttle-update download progress notification
  Future<void> showDownloadProgress({
    required String taskId,
    required String fileName,
    required double progress,
    required double speedBytesPerSec,
  }) async {
    if (!_isInitialized) return;

    final now = DateTime.now();
    final lastUpdate = _lastProgressUpdate[taskId];
    if (lastUpdate != null && now.difference(lastUpdate).inMilliseconds < 1000) {
      return; // Throttle to 1 update per second
    }
    _lastProgressUpdate[taskId] = now;

    final notifId = _getNotificationId(taskId);
    final percent = (progress * 100).clamp(0.0, 100.0);
    final percentText = percent.toStringAsFixed(0);
    final speedText = AppUtils.formatSpeed(speedBytesPerSec);

    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: notifId,
          channelKey: channelProgress,
          title: fileName,
          body: '$percentText% • $speedText',
          notificationLayout: NotificationLayout.ProgressBar,
          progress: percent,
          locked: true,
          autoDismissible: false,
          payload: {'taskId': taskId},
        ),
        actionButtons: [
          NotificationActionButton(
            key: 'PAUSE_$taskId',
            label: 'Pause',
            autoDismissible: false,
          ),
          NotificationActionButton(
            key: 'CANCEL_$taskId',
            label: 'Cancel',
            autoDismissible: true,
            isDangerousOption: true,
          ),
        ],
      );
    } catch (e) {
      debugPrint('Error showing download progress notification: $e');
    }
  }

  /// Show paused notification with resume option
  Future<void> showDownloadPaused({
    required String taskId,
    required String fileName,
    required double progress,
  }) async {
    if (!_isInitialized) return;

    final notifId = _getNotificationId(taskId);
    final percent = (progress * 100).clamp(0.0, 100.0);

    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: notifId,
          channelKey: channelProgress,
          title: fileName,
          body: 'Paused (${percent.toStringAsFixed(0)}%)',
          notificationLayout: NotificationLayout.ProgressBar,
          progress: percent,
          locked: false,
          autoDismissible: false,
          payload: {'taskId': taskId},
        ),
        actionButtons: [
          NotificationActionButton(
            key: 'RESUME_$taskId',
            label: 'Resume',
            autoDismissible: false,
          ),
          NotificationActionButton(
            key: 'CANCEL_$taskId',
            label: 'Cancel',
            autoDismissible: true,
            isDangerousOption: true,
          ),
        ],
      );
    } catch (e) {
      debugPrint('Error showing paused notification: $e');
    }
  }

  /// Show completion notification
  Future<void> showDownloadComplete({
    required String taskId,
    required String fileName,
    required String savePath,
  }) async {
    if (!_isInitialized) return;

    _lastProgressUpdate.remove(taskId);
    final notifId = _getNotificationId(taskId);

    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: notifId,
          channelKey: channelComplete,
          title: 'Download Complete',
          body: fileName,
          notificationLayout: NotificationLayout.Default,
          locked: false,
          autoDismissible: true,
          payload: {'taskId': taskId, 'savePath': savePath},
        ),
        actionButtons: [
          NotificationActionButton(
            key: 'OPEN_$taskId',
            label: 'Open File',
            autoDismissible: true,
          ),
        ],
      );
    } catch (e) {
      debugPrint('Error showing completion notification: $e');
    }
  }

  /// Show failure notification
  Future<void> showDownloadFailed({
    required String taskId,
    required String fileName,
    required String error,
  }) async {
    if (!_isInitialized) return;

    _lastProgressUpdate.remove(taskId);
    final notifId = _getNotificationId(taskId);

    try {
      await AwesomeNotifications().createNotification(
        content: NotificationContent(
          id: notifId,
          channelKey: channelComplete,
          title: 'Download Failed',
          body: '$fileName: $error',
          notificationLayout: NotificationLayout.Default,
          locked: false,
          autoDismissible: true,
          payload: {'taskId': taskId},
        ),
        actionButtons: [
          NotificationActionButton(
            key: 'RETRY_$taskId',
            label: 'Retry',
            autoDismissible: true,
          ),
        ],
      );
    } catch (e) {
      debugPrint('Error showing failed notification: $e');
    }
  }

  /// Cancel notification for a task
  Future<void> cancelNotification(String taskId) async {
    if (!_isInitialized) return;
    _lastProgressUpdate.remove(taskId);
    final notifId = _getNotificationId(taskId);
    try {
      await AwesomeNotifications().cancel(notifId);
    } catch (e) {
      debugPrint('Error cancelling notification: $e');
    }
  }

  /// Cancel all active notifications
  Future<void> cancelAllNotifications() async {
    if (!_isInitialized) return;
    _lastProgressUpdate.clear();
    try {
      await AwesomeNotifications().cancelAll();
    } catch (e) {
      debugPrint('Error cancelling all notifications: $e');
    }
  }
}
