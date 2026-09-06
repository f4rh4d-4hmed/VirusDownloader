import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

@immutable
class DownloadStatusColors extends ThemeExtension<DownloadStatusColors> {
  final Color downloading;
  final Color paused;
  final Color completed;
  final Color failed;
  final Color queued;

  const DownloadStatusColors({
    required this.downloading,
    required this.paused,
    required this.completed,
    required this.failed,
    required this.queued,
  });

  @override
  DownloadStatusColors copyWith({
    Color? downloading,
    Color? paused,
    Color? completed,
    Color? failed,
    Color? queued,
  }) {
    return DownloadStatusColors(
      downloading: downloading ?? this.downloading,
      paused: paused ?? this.paused,
      completed: completed ?? this.completed,
      failed: failed ?? this.failed,
      queued: queued ?? this.queued,
    );
  }

  @override
  DownloadStatusColors lerp(ThemeExtension<DownloadStatusColors>? other, double t) {
    if (other is! DownloadStatusColors) return this;
    return DownloadStatusColors(
      downloading: Color.lerp(downloading, other.downloading, t)!,
      paused: Color.lerp(paused, other.paused, t)!,
      completed: Color.lerp(completed, other.completed, t)!,
      failed: Color.lerp(failed, other.failed, t)!,
      queued: Color.lerp(queued, other.queued, t)!,
    );
  }

  static const light = DownloadStatusColors(
    downloading: Color(0xFF0D6EFD), // Blue
    paused: Color(0xFFE67E22),      // Orange
    completed: Color(0xFF198754),   // Green
    failed: Color(0xFFDC3545),      // Red
    queued: Color(0xFF6C757D),      // Muted grey
  );

  static const dark = DownloadStatusColors(
    downloading: Color(0xFF388BFD), // Bright blue
    paused: Color(0xFFF39C12),      // Amber
    completed: Color(0xFF2EA043),   // Vivid green
    failed: Color(0xFFF85149),      // Vivid red
    queued: Color(0xFF8B949E),      // Slate grey
  );
}

class AppTheme {
  static const Color _primarySeed = Color(0xFF1976D2); // Modern crisp blue

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _primarySeed,
      brightness: Brightness.light,
    ),
    extensions: const [DownloadStatusColors.light],
    scaffoldBackgroundColor: const Color(0xFFF8F9FA),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
        systemNavigationBarColor: Color(0xFFF8F9FA),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    chipTheme: const ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      side: BorderSide(color: Color(0xFFDEE2E6)),
    ),
    dividerTheme: const DividerThemeData(
      thickness: 1,
      color: Color(0xFFE9ECEF),
      space: 1,
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _primarySeed,
      brightness: Brightness.dark,
      surface: const Color(0xFF1E1E24),
    ),
    extensions: const [DownloadStatusColors.dark],
    scaffoldBackgroundColor: const Color(0xFF141418),
    appBarTheme: const AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFF141418),
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    chipTheme: const ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
      side: BorderSide(color: Color(0xFF30363D)),
    ),
    dividerTheme: const DividerThemeData(
      thickness: 1,
      color: Color(0xFF21262D),
      space: 1,
    ),
  );
}

