import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BackgroundService {
  static const _channel = MethodChannel('com.virusdownloader/background_service');

  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// Starts the background foreground service on Android.
  Future<bool> startBackgroundService() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final success = await _channel.invokeMethod<bool>('startBackgroundService');
      _isRunning = success ?? false;
      return _isRunning;
    } catch (e) {
      debugPrint('Error starting background service: $e');
      return false;
    }
  }

  /// Stops the background foreground service on Android.
  Future<bool> stopBackgroundService() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final success = await _channel.invokeMethod<bool>('stopBackgroundService');
      _isRunning = !(success ?? false);
      return success ?? false;
    } catch (e) {
      debugPrint('Error stopping background service: $e');
      return false;
    }
  }
}

