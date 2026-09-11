import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/core/theme.dart';
import 'package:virusdownloader/data/services/ffmpeg_service.dart';
import 'package:virusdownloader/data/services/file_service.dart';
import 'package:virusdownloader/domain/models/download_task.dart';
import 'package:virusdownloader/ui/views/download_complete_dialog.dart';
import 'package:virusdownloader/ui/views/download_tile.dart';

Widget createTileTestWidget({
  required DownloadTask task,
  FfmpegService? ffmpegService,
}) {
  return MaterialApp(
    theme: ThemeData(
      extensions: const [DownloadStatusColors.light],
    ),
    home: Scaffold(
      body: DownloadTile(
        task: task,
        fileService: FileService(),
        ffmpegService: ffmpegService,
        onPause: () {},
        onResume: () {},
        onCancel: () {},
        onRetry: () {},
        onRemove: () {},
        onDeleteFile: () {},
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Thumbnail Preview and Preview Button Removal Tests', () {
    testWidgets('DownloadTile does NOT have a Preview button or menu item for completed video', (tester) async {
      final task = DownloadTask(
        id: 'task-video-1',
        url: 'https://example.com/movie.mp4',
        fileName: 'movie.mp4',
        savePath: '/dummy/movie.mp4',
        totalBytes: 1000000,
        downloadedBytes: 1000000,
        status: DownloadStatus.completed,
        category: DownloadCategory.videos,
        dateAdded: DateTime.now(),
      );

      await tester.pumpWidget(createTileTestWidget(task: task));
      await tester.pumpAndSettle();

      // Ensure no Preview button exists
      expect(find.byTooltip('Preview'), findsNothing);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);
      expect(find.text('Preview'), findsNothing);

      // Open 3-dot options menu
      final moreOptionsFinder = find.byIcon(Icons.more_vert_rounded);
      expect(moreOptionsFinder, findsOneWidget);
      await tester.tap(moreOptionsFinder);
      await tester.pumpAndSettle();

      // In popup menu: 'Preview' item should NOT be present
      expect(find.text('Preview'), findsNothing);
      // Standard completed items should be present
      expect(find.text('Open File'), findsOneWidget);
      expect(find.text('Show in Folder'), findsOneWidget);
    });

    testWidgets('DownloadTile shows default category icon for in-progress video download', (tester) async {
      final task = DownloadTask(
        id: 'task-video-2',
        url: 'https://example.com/clip.mp4',
        fileName: 'clip.mp4',
        savePath: '/dummy/clip.mp4',
        totalBytes: 1000000,
        downloadedBytes: 500000,
        status: DownloadStatus.downloading,
        category: DownloadCategory.videos,
        dateAdded: DateTime.now(),
      );

      await tester.pumpWidget(createTileTestWidget(task: task));
      await tester.pumpAndSettle();

      // Should display the video category icon
      expect(find.byIcon(Icons.movie_outlined), findsOneWidget);
      // Should NOT render an Image
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('DownloadTile updates leading icon with thumbnail when completed and cached', (tester) async {
      final tempDir = Directory.systemTemp.createTempSync('thumb_test_');
      final fakeThumbFile = File('${tempDir.path}/thumb.jpg')..writeAsBytesSync([1, 2, 3, 4]);

      final ffmpeg = FfmpegService();
      ffmpeg.setMockThumbnail('/dummy/clip.mp4', fakeThumbFile.path);

      final task = DownloadTask(
        id: 'task-video-3',
        url: 'https://example.com/clip.mp4',
        fileName: 'clip.mp4',
        savePath: '/dummy/clip.mp4',
        totalBytes: 1000000,
        downloadedBytes: 1000000,
        status: DownloadStatus.completed,
        category: DownloadCategory.videos,
        dateAdded: DateTime.now(),
      );

      await tester.pumpWidget(createTileTestWidget(task: task, ffmpegService: ffmpeg));
      await tester.pumpAndSettle();

      // Should render the thumbnail image in place of default icon
      expect(find.byType(Image), findsOneWidget);

      tempDir.deleteSync(recursive: true);
    });

    testWidgets('DownloadCompleteDialog does NOT contain a Preview button', (tester) async {
      final task = DownloadTask(
        id: 'task-complete-1',
        url: 'https://example.com/video.mp4',
        fileName: 'video.mp4',
        savePath: '/dummy/video.mp4',
        totalBytes: 5000000,
        downloadedBytes: 5000000,
        status: DownloadStatus.completed,
        category: DownloadCategory.videos,
        dateAdded: DateTime.now(),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: const [DownloadStatusColors.light]),
          home: Scaffold(
            body: DownloadCompleteDialog(
              task: task,
              fileService: FileService(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Ensure no Preview button
      expect(find.text('Preview'), findsNothing);
      expect(find.byIcon(Icons.visibility_outlined), findsNothing);

      // Verify legitimate dialog actions exist
      expect(find.text('Dismiss'), findsOneWidget);
      expect(find.text('Open File'), findsOneWidget);
    });

    test('FfmpegService memory cache stores and clears thumbnails correctly', () {
      final ffmpeg = FfmpegService();
      expect(ffmpeg.getCachedThumbnail('/path/to/media.mp4'), isNull);

      ffmpeg.setMockThumbnail('/path/to/media.mp4', '/path/to/thumb.jpg');
      expect(ffmpeg.getCachedThumbnail('/path/to/media.mp4'), equals('/path/to/thumb.jpg'));

      ffmpeg.clearCache();
      expect(ffmpeg.getCachedThumbnail('/path/to/media.mp4'), isNull);
    });
  });
}

