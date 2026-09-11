class AppConstants {
  static const String appName = 'VirusDownloader';
  
  // Layout breakpoints
  static const double compactWidth = 600.0;
  static const double mediumWidth = 840.0;

  // Defaults
  static const int defaultMaxConcurrentDownloads = 3;
  
  // Storage keys
  static const String storageKeyTasks = 'vdownloader_tasks';
  static const String storageKeySettings = 'vdownloader_settings';

  // Default network headers
  static const String defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36';

  static const Map<String, String> defaultHttpHeaders = {
    'User-Agent': defaultUserAgent,
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Accept-Encoding': 'identity',
  };
}

