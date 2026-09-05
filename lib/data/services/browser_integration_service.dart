import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class DetectedBrowser {
  final String name;
  final String executablePath;
  final String extensionsUrl;
  final bool isChromium;

  const DetectedBrowser({
    required this.name,
    required this.executablePath,
    required this.extensionsUrl,
    this.isChromium = true,
  });
}

class BrowserIntegrationService {
  /// Returns the absolute path where extension files reside or are extracted
  Future<String> getExtensionPath() async {
    // 1. Check if extras/extension directory exists relative to current working directory
    final localExtrasDir = Directory(p.join(Directory.current.path, 'extras', 'extension'));
    if (await localExtrasDir.exists() && await File(p.join(localExtrasDir.path, 'manifest.json')).exists()) {
      return localExtrasDir.path;
    }

    // 2. Check executable directory on desktop
    final exeDir = File(Platform.resolvedExecutable).parent;
    final exeExtrasDir = Directory(p.join(exeDir.path, 'extras', 'extension'));
    if (await exeExtrasDir.exists() && await File(p.join(exeExtrasDir.path, 'manifest.json')).exists()) {
      return exeExtrasDir.path;
    }

    // 3. Unpack from Flutter assets into AppSupport/VirusDownloader/extension
    final appSupport = await getApplicationSupportDirectory();
    final targetDir = Directory(p.join(appSupport.path, 'extension'));
    await targetDir.create(recursive: true);

    // List of assets to unpack
    final assetPaths = [
      'extras/extension/manifest.json',
      'extras/extension/background.js',
      'extras/extension/content.js',
      'extras/extension/content.css',
      'extras/extension/popup.html',
      'extras/extension/popup.js',
      'extras/extension/popup.css',
      'extras/extension/options.html',
      'extras/extension/options.js',
      'extras/extension/icons/icon16.png',
      'extras/extension/icons/icon32.png',
      'extras/extension/icons/icon48.png',
      'extras/extension/icons/icon128.png',
    ];

    for (final asset in assetPaths) {
      try {
        final byteData = await rootBundle.load(asset);
        final rel = asset.replaceFirst('extras/extension/', '');
        final outFile = File(p.join(targetDir.path, rel));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(byteData.buffer.asUint8List(), flush: true);
      } catch (e) {
        debugPrint('Failed to unpack asset $asset: $e');
      }
    }

    return targetDir.path;
  }

  /// Scans system for installed web browsers
  Future<List<DetectedBrowser>> detectInstalledBrowsers() async {
    final list = <DetectedBrowser>[];

    if (!Platform.isWindows) {
      // Basic fallback for other platforms
      return list;
    }

    final localApp = Platform.environment['LOCALAPPDATA'] ?? '';
    final progFiles = Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final progFilesX86 = Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';

    // 1. Google Chrome
    final chromePaths = [
      p.join(progFiles, r'Google\Chrome\Application\chrome.exe'),
      p.join(progFilesX86, r'Google\Chrome\Application\chrome.exe'),
      p.join(localApp, r'Google\Chrome\Application\chrome.exe'),
    ];
    for (final cp in chromePaths) {
      if (await File(cp).exists()) {
        list.add(DetectedBrowser(
          name: 'Google Chrome',
          executablePath: cp,
          extensionsUrl: 'chrome://extensions',
          isChromium: true,
        ));
        break;
      }
    }

    // 2. Microsoft Edge
    final edgePaths = [
      p.join(progFilesX86, r'Microsoft\Edge\Application\msedge.exe'),
      p.join(progFiles, r'Microsoft\Edge\Application\msedge.exe'),
    ];
    for (final ep in edgePaths) {
      if (await File(ep).exists()) {
        list.add(DetectedBrowser(
          name: 'Microsoft Edge',
          executablePath: ep,
          extensionsUrl: 'edge://extensions',
          isChromium: true,
        ));
        break;
      }
    }

    // 3. Brave Browser
    final bravePaths = [
      p.join(localApp, r'BraveSoftware\Brave-Browser\Application\brave.exe'),
      p.join(progFiles, r'BraveSoftware\Brave-Browser\Application\brave.exe'),
    ];
    for (final bp in bravePaths) {
      if (await File(bp).exists()) {
        list.add(DetectedBrowser(
          name: 'Brave Browser',
          executablePath: bp,
          extensionsUrl: 'brave://extensions',
          isChromium: true,
        ));
        break;
      }
    }

    // 4. Opera / Opera GX
    final operaPaths = [
      p.join(localApp, r'Programs\Opera\launcher.exe'),
      p.join(localApp, r'Programs\Opera GX\launcher.exe'),
    ];
    for (final op in operaPaths) {
      if (await File(op).exists()) {
        list.add(DetectedBrowser(
          name: op.contains('GX') ? 'Opera GX' : 'Opera',
          executablePath: op,
          extensionsUrl: 'opera://extensions',
          isChromium: true,
        ));
        break;
      }
    }

    // 5. Vivaldi
    final vivaldiPaths = [
      p.join(localApp, r'Vivaldi\Application\vivaldi.exe'),
      p.join(progFiles, r'Vivaldi\Application\vivaldi.exe'),
    ];
    for (final vp in vivaldiPaths) {
      if (await File(vp).exists()) {
        list.add(DetectedBrowser(
          name: 'Vivaldi',
          executablePath: vp,
          extensionsUrl: 'vivaldi://extensions',
          isChromium: true,
        ));
        break;
      }
    }

    return list;
  }

  /// Automatically launches the browser with the extension loaded
  Future<bool> launchBrowserWithExtension(DetectedBrowser browser) async {
    try {
      final extPath = await getExtensionPath();

      // Copy extension path to clipboard for convenient developer mode setup
      await Clipboard.setData(ClipboardData(text: extPath));

      if (browser.isChromium) {
        // Launch with --load-extension flag
        await Process.start(
          browser.executablePath,
          [
            '--load-extension=$extPath',
            browser.extensionsUrl,
          ],
          mode: ProcessStartMode.detached,
        );
        return true;
      } else {
        await Process.start(
          browser.executablePath,
          [browser.extensionsUrl],
          mode: ProcessStartMode.detached,
        );
        return true;
      }
    } catch (e) {
      debugPrint('Failed to launch browser with extension: $e');
      return false;
    }
  }

  /// Opens the extension folder in Windows Explorer or system file manager
  Future<void> openExtensionFolder() async {
    final extPath = await getExtensionPath();
    if (Platform.isWindows) {
      await Process.run('explorer.exe', [extPath]);
    } else if (Platform.isMacOS) {
      await Process.run('open', [extPath]);
    } else if (Platform.isLinux) {
      await Process.run('xdg-open', [extPath]);
    }
  }

  /// Copies extension path to clipboard
  Future<String> copyExtensionPathToClipboard() async {
    final extPath = await getExtensionPath();
    await Clipboard.setData(ClipboardData(text: extPath));
    return extPath;
  }
}

