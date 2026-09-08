enum DownloadStatus {
  queued,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}

enum DownloadCategory {
  all,
  documents,
  images,
  videos,
  audio,
  compressed,
  programs,
  other,
}

enum SortOrder {
  dateAdded,
  name,
  size,
}

enum HashAlgorithm {
  md5,
  sha1,
  sha256,
  sha512,
  crc32,
}

enum SpeedLimitMode {
  rabbit, // 250 KB/s
  turtle, // 1 MB/s
  unlimited, // Unlimited (default)
  rocket, // Rocket mode (multi-proxy)
}

extension SpeedLimitModeExt on SpeedLimitMode {
  String get label {
    switch (this) {
      case SpeedLimitMode.rabbit:
        return 'Rabbit (250 KB/s)';
      case SpeedLimitMode.turtle:
        return 'Turtle (1 MB/s)';
      case SpeedLimitMode.unlimited:
        return 'Default (Unlimited)';
      case SpeedLimitMode.rocket:
        return 'Rocket (Multi-Proxy)';
    }
  }

  /// Short description explaining the speed limit behavior
  String get description {
    switch (this) {
      case SpeedLimitMode.rabbit:
        return 'Throttle to 250 KB/s per task';
      case SpeedLimitMode.turtle:
        return 'Cap bandwidth at 1 MB/s per task';
      case SpeedLimitMode.unlimited:
        return 'Uncapped maximum download speed';
      case SpeedLimitMode.rocket:
        return 'Accelerate via proxy servers';
    }
  }

  /// Returns max bytes per second, or 0 if unlimited / rocket mode handled separately
  int get maxBytesPerSecond {
    switch (this) {
      case SpeedLimitMode.rabbit:
        return 250 * 1024;
      case SpeedLimitMode.turtle:
        return 1024 * 1024;
      case SpeedLimitMode.unlimited:
      case SpeedLimitMode.rocket:
        return 0;
    }
  }
}
