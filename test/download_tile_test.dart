import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/core/theme.dart';
import 'package:virusdownloader/data/services/file_service.dart';
import 'package:virusdownloader/domain/models/download_task.dart';
import 'package:virusdownloader/ui/views/download_tile.dart';

Widget createTestWidget({
  required DownloadTask task,
  VoidCallback? onPause,
  VoidCallback? onResume,
  VoidCallback? onCancel,
  VoidCallback? onRetry,
  VoidCallback? onRemove,
  VoidCallback? onDeleteFile,
}) {
  return MaterialApp(
    theme: ThemeData(
      extensions: const [DownloadStatusColors.light],
    ),
    home: Scaffold(
      body: DownloadTile(
        task: task,
        fileService: FileService(),
        onPause: onPause ?? () {},
        onResume: onResume ?? () {},
        onCancel: onCancel ?? () {},
        onRetry: onRetry ?? () {},
        onRemove: onRemove ?? () {},
        onDeleteFile: onDeleteFile ?? () {},
      ),
    ),
  );
}

void main() {
  group('DownloadTile 3-dot options menu interaction tests', () {
    final taskDownloading = DownloadTask(
      id: 'task-1',
      url: 'https://example.com/test.mp4',
      fileName: 'test.mp4',
      savePath: '/downloads/test.mp4',
      totalBytes: 10000,
      downloadedBytes: 5000,
      status: DownloadStatus.downloading,
      dateAdded: DateTime.now(),
    );

    testWidgets('Shows 3-dot options menu on right-click (secondary click)', (tester) async {
      await tester.pumpWidget(createTestWidget(task: taskDownloading));

      // Right-click on the download tile
      await tester.tap(find.text('test.mp4'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      // Verify the 3-dot options menu showed up
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Copy Download Link'), findsOneWidget);
      expect(find.text('Restart Download'), findsOneWidget);
      expect(find.text('Remove from List'), findsOneWidget);
      expect(find.text('Delete from Disk'), findsOneWidget);
    });

    testWidgets('Shows 3-dot options menu on hold-click (long press)', (tester) async {
      await tester.pumpWidget(createTestWidget(task: taskDownloading));

      // Hold-click (long press) on the download tile
      await tester.longPress(find.text('test.mp4'));
      await tester.pumpAndSettle();

      // Verify the 3-dot options menu showed up
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Copy Download Link'), findsOneWidget);
      expect(find.text('Remove from List'), findsOneWidget);
      expect(find.text('Delete from Disk'), findsOneWidget);
    });

    testWidgets('Shows 3-dot options menu when tapping 3-dot icon button', (tester) async {
      await tester.pumpWidget(createTestWidget(task: taskDownloading));

      // Tap the 3-dot icon
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      // Verify the 3-dot options menu showed up
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Copy Download Link'), findsOneWidget);
    });

    testWidgets('Triggers pause callback when selecting Pause from menu', (tester) async {
      bool pauseCalled = false;
      await tester.pumpWidget(createTestWidget(
        task: taskDownloading,
        onPause: () => pauseCalled = true,
      ));

      // Right-click to show menu
      await tester.tap(find.text('test.mp4'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      // Tap Pause
      await tester.tap(find.text('Pause'));
      await tester.pumpAndSettle();

      expect(pauseCalled, isTrue);
    });

    testWidgets('Shows completed options for completed downloads', (tester) async {
      final taskCompleted = taskDownloading.copyWith(
        status: DownloadStatus.completed,
        downloadedBytes: 10000,
      );

      await tester.pumpWidget(createTestWidget(task: taskCompleted));

      // Right-click on tile
      await tester.tap(find.text('test.mp4'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      // Verify options for completed download
      expect(find.text('Open File'), findsOneWidget);
      expect(find.text('Show in Folder'), findsOneWidget);
      expect(find.text('Copy Download Link'), findsOneWidget);
      expect(find.text('Remove from List'), findsOneWidget);
      expect(find.text('Delete from Disk'), findsOneWidget);
    });
  });
}

