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
  void Function(String newUrl, [Map<String, String>? headers, bool restartFromBeginning])? onChangeUrl,
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
        onChangeUrl: onChangeUrl,
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
      expect(find.text('Change Download Link'), findsOneWidget);
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
      expect(find.text('Change Download Link'), findsOneWidget);
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
      expect(find.text('Change Download Link'), findsOneWidget);
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

    testWidgets('Shows Change Download Link for paused resumable downloads', (tester) async {
      final taskPaused = taskDownloading.copyWith(
        status: DownloadStatus.paused,
        isResumable: true,
      );

      await tester.pumpWidget(createTestWidget(task: taskPaused));

      await tester.tap(find.text('test.mp4'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Change Download Link'), findsOneWidget);
    });

    testWidgets('Does NOT show Change Download Link for unresumable downloads', (tester) async {
      final taskUnresumable = taskDownloading.copyWith(
        isResumable: false,
      );

      await tester.pumpWidget(createTestWidget(task: taskUnresumable));

      // Tap the 3-dot icon
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      // Verify Change Download Link is NOT present for unresumable download
      expect(find.text('Copy Download Link'), findsOneWidget);
      expect(find.text('Change Download Link'), findsNothing);
    });

    testWidgets('Does NOT show Change Download Link for completed downloads', (tester) async {
      final taskCompleted = taskDownloading.copyWith(
        status: DownloadStatus.completed,
        downloadedBytes: 10000,
        isResumable: true,
      );

      await tester.pumpWidget(createTestWidget(task: taskCompleted));

      // Right-click on tile
      await tester.tap(find.text('test.mp4'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      // Verify options for completed download
      expect(find.text('Open File'), findsOneWidget);
      expect(find.text('Show in Folder'), findsOneWidget);
      expect(find.text('Copy Download Link'), findsOneWidget);
      expect(find.text('Change Download Link'), findsNothing);
      expect(find.text('Remove from List'), findsOneWidget);
      expect(find.text('Delete from Disk'), findsOneWidget);
    });

    testWidgets('Opens Change Download Link dialog and triggers callback with new URL', (tester) async {
      String? changedUrl;
      await tester.pumpWidget(createTestWidget(
        task: taskDownloading,
        onChangeUrl: (newUrl, [headers, restartFromBeginning = false]) {
          changedUrl = newUrl;
        },
      ));

      // Open 3-dot menu
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      // Tap Change Download Link
      await tester.tap(find.text('Change Download Link'));
      await tester.pumpAndSettle();

      // Verify dialog is open
      expect(find.text('Change Download Link'), findsOneWidget);
      expect(find.text('New Download URL'), findsOneWidget);

      // Enter new URL
      final urlField = find.byType(TextFormField).first;
      await tester.enterText(urlField, 'https://mirror.example.com/updated_test.mp4');
      await tester.pumpAndSettle();

      // Click Change Link button
      await tester.tap(find.widgetWithText(FilledButton, 'Change Link'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      // Verify callback received new URL
      expect(changedUrl, 'https://mirror.example.com/updated_test.mp4');
    });

    testWidgets('Context menu automatically dismisses when task status transitions from downloading to completed', (tester) async {
      await tester.pumpWidget(
        _TestStatusChangeHarness(
          initialTask: taskDownloading,
        ),
      );
      final harnessState = tester.state<_TestStatusChangeHarnessState>(find.byType(_TestStatusChangeHarness));

      // Right-click to open options menu
      await tester.tap(find.text('test.mp4'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      // Verify menu is open
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Now update the task status to completed (download ended)
      harnessState.updateTask(taskDownloading.copyWith(
        status: DownloadStatus.completed,
        downloadedBytes: 10000,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      // Verify menu was automatically dismissed
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('3-dot menu automatically dismisses when task status transitions to completed', (tester) async {
      await tester.pumpWidget(
        _TestStatusChangeHarness(
          initialTask: taskDownloading,
        ),
      );
      final harnessState = tester.state<_TestStatusChangeHarnessState>(find.byType(_TestStatusChangeHarness));

      // Tap 3-dot icon to open menu
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();

      // Verify menu is open
      expect(find.text('Pause'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      // Update task to completed
      harnessState.updateTask(taskDownloading.copyWith(
        status: DownloadStatus.completed,
        downloadedBytes: 10000,
      ));
      await tester.pump();
      await tester.pumpAndSettle();

      // Verify menu was automatically dismissed
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('Guards menu actions against invalid task status', (tester) async {
      bool pauseCalled = false;
      bool cancelCalled = false;

      final completedTask = taskDownloading.copyWith(
        status: DownloadStatus.completed,
        downloadedBytes: 10000,
      );

      await tester.pumpWidget(createTestWidget(
        task: completedTask,
        onPause: () => pauseCalled = true,
        onCancel: () => cancelCalled = true,
      ));

      // Right-click to show menu for completed task
      await tester.tap(find.text('test.mp4'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();

      // Ensure completed options are present, and pause/cancel are not present
      expect(find.text('Open File'), findsOneWidget);
      expect(find.text('Show in Folder'), findsOneWidget);
      expect(find.text('Pause'), findsNothing);
      expect(find.text('Cancel'), findsNothing);
      expect(pauseCalled, isFalse);
      expect(cancelCalled, isFalse);
    });
  });
}

class _TestStatusChangeHarness extends StatefulWidget {
  final DownloadTask initialTask;

  const _TestStatusChangeHarness({
    required this.initialTask,
  });

  @override
  State<_TestStatusChangeHarness> createState() => _TestStatusChangeHarnessState();
}

class _TestStatusChangeHarnessState extends State<_TestStatusChangeHarness> {
  late DownloadTask task;

  @override
  void initState() {
    super.initState();
    task = widget.initialTask;
  }

  void updateTask(DownloadTask newTask) {
    setState(() {
      task = newTask;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(
        extensions: const [DownloadStatusColors.light],
      ),
      home: Scaffold(
        body: DownloadTile(
          task: task,
          fileService: FileService(),
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
}

